// tools/build-dictionary.js
// 설계 문서 §5의 빌드 파이프라인. 개발 PC에서 수동 실행한다.
//   node tools/build-dictionary.js
// 덤프는 dumps/ 에 미리 받아 둔다 (계획 Task 3 Step 2).
// 변환 규칙 자체는 lexicon/build-transform.js에 있고 그쪽이 테스트 대상이다.

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import {
  bucketFor, parseKaikkiLine, parseKoSection, mergeEntry, buildInflections
} from '../lexicon/build-transform.js';

const DUMPS = 'dumps';
const WORK = 'work/b';
const OUT = 'dist/dict';
const FLUSH_EVERY = 200000;

function requireDump(file, how) {
  if (!fs.existsSync(file)) {
    console.error(`덤프가 없다: ${file}\n${how}`);
    process.exit(1);
  }
}

/** ko.wiktionary XML을 흘리며 영어 구간이 있는 표제어만 모은다. */
async function readKoDump(file) {
  // Node의 zlib은 bzip2를 못 푼다. 시스템 bzip2로 파이프한다.
  const bz = spawn('bzip2', ['-dc', file]);
  const rl = readline.createInterface({ input: bz.stdout, crlfDelay: Infinity });

  const map = new Map();
  let title = null;
  let inText = false;
  let buf = [];

  for await (const line of rl) {
    const t = line.match(/<title>([^<]*)<\/title>/);
    if (t) { title = t[1]; continue; }

    if (!inText) {
      const open = line.match(/<text[^>]*>(.*)$/);
      if (open) { inText = true; buf = [open[1]]; }
      else continue;
    } else {
      buf.push(line);
    }

    const closeAt = buf[buf.length - 1].indexOf('</text>');
    if (closeAt !== -1) {
      buf[buf.length - 1] = buf[buf.length - 1].slice(0, closeAt);
      inText = false;
      if (title && !title.includes(':')) {       // 문서 이름공간만
        const parsed = parseKoSection(buf.join('\n'));
        if (parsed) map.set(title.toLowerCase(), parsed);
      }
      buf = [];
    }
  }
  return map;
}

/** kaikki 3.2GB를 흘리며 버킷별 중간 파일로 나눠 쓴다. 굴절형은 메모리에 모은다. */
async function splitKaikki(file) {
  fs.rmSync(WORK, { recursive: true, force: true });
  fs.mkdirSync(WORK, { recursive: true });

  const rl = readline.createInterface({
    input: fs.createReadStream(file), crlfDelay: Infinity
  });

  const pending = new Map();       // bucket → string[]
  const forEntries = [];           // buildInflections에 넘길 항목
  let n = 0;

  const flush = () => {
    for (const [bucket, lines] of pending) {
      fs.appendFileSync(path.join(WORK, bucket + '.jsonl'), lines.join('\n') + '\n');
    }
    pending.clear();
  };

  for await (const line of rl) {
    const e = parseKaikkiLine(line);
    if (!e) continue;

    const bucket = bucketFor(e.word);
    if (!pending.has(bucket)) pending.set(bucket, []);
    pending.get(bucket).push(JSON.stringify(e));

    if (e.forms.length && !e.word.includes(' ')) {
      forEntries.push({ word: e.word, forms: e.forms });
    }

    if (++n % FLUSH_EVERY === 0) { flush(); console.log(`  ${n.toLocaleString()}줄`); }
  }
  flush();
  console.log(`  총 ${n.toLocaleString()}줄`);
  return buildInflections(forEntries);
}

/** 버킷 중간 파일을 표제어별로 묶고 ko 맵과 병합해 최종 JSON을 쓴다. */
function buildBuckets(koMap) {
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(path.join(OUT, 'b'), { recursive: true });

  const hashes = {};
  const mweIndex = [];

  for (const f of fs.readdirSync(WORK).sort()) {
    const bucket = path.basename(f, '.jsonl');
    const byWord = new Map();

    for (const line of fs.readFileSync(path.join(WORK, f), 'utf8').split('\n')) {
      if (!line) continue;
      const e = JSON.parse(line);
      const key = e.word.toLowerCase();
      if (!byWord.has(key)) byWord.set(key, []);
      byWord.get(key).push(e);
    }

    const out = {};
    for (const [word, entries] of byWord) {
      const rec = mergeEntry(entries, koMap.get(word) || null);
      if (!rec.ko.length && !rec.en.length) continue;   // 보여줄 게 없는 표제어는 버린다
      out[word] = rec;
      if (rec.mwe) mweIndex.push(word);
    }

    const json = JSON.stringify(out);
    fs.writeFileSync(path.join(OUT, 'b', bucket + '.json'), json);
    hashes[bucket] = crypto.createHash('sha256').update(json).digest('hex').slice(0, 12);
  }

  mweIndex.sort();
  return { hashes, mweIndex };
}

async function main() {
  const koFile = path.join(DUMPS, 'kowiktionary.xml.bz2');
  const kaikkiFile = path.join(DUMPS, 'kaikki-english.jsonl');
  requireDump(koFile, '계획 Task 3 Step 2의 curl 명령을 실행한다.');
  requireDump(kaikkiFile, '계획 Task 3 Step 2의 curl 명령을 실행한다.');

  console.log('1/3 ko.wiktionary 덤프를 읽는다');
  const koMap = await readKoDump(koFile);
  console.log(`  영어 표제어 ${koMap.size.toLocaleString()}개`);

  console.log('2/3 kaikki 덤프를 버킷으로 나눈다');
  const inflections = await splitKaikki(kaikkiFile);
  console.log(`  굴절형 ${Object.keys(inflections).length.toLocaleString()}개`);

  console.log('3/3 버킷을 병합해 사전을 쓴다');
  const { hashes, mweIndex } = buildBuckets(koMap);

  const version = new Date().toISOString().slice(0, 10);
  fs.writeFileSync(path.join(OUT, 'version.json'),
    JSON.stringify({ version, buckets: hashes }));
  fs.writeFileSync(path.join(OUT, 'mwe-index.json'), JSON.stringify(mweIndex));
  fs.writeFileSync(path.join(OUT, 'inflections.json'), JSON.stringify(inflections));

  const size = (p) => (fs.statSync(p).size / 1024 / 1024).toFixed(2) + 'MB';
  console.log(`\n완료 — 버킷 ${Object.keys(hashes).length}개`);
  console.log(`  mwe-index.json   ${size(path.join(OUT, 'mwe-index.json'))} (${mweIndex.length}개)`);
  console.log(`  inflections.json ${size(path.join(OUT, 'inflections.json'))}`);
}

main().catch(err => { console.error(err); process.exit(1); });
