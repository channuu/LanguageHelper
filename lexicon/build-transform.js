// lexicon/build-transform.js
// 설계 문서 §5의 사전 변환 규칙. 순수 함수다 — 파일 시스템도 네트워크도 쓰지 않는다.
// tools/build-dictionary.js가 이 함수들을 덤프 스트림에 흘려보낸다.

const MAX_SENSES = 4;

/** 축자적 용법 sense. 이게 남으면 look up at the stars가 구동사 뜻으로 설명된다. */
const LITERAL_PREFIX = 'Used other than figuratively';

const KO_POS = {
  '명사': 'noun', '동사': 'verb', '동사구': 'verb',
  '형용사': 'adj', '부사': 'adv'
};

export function bucketFor(word) {
  const w = String(word).toLowerCase();
  const head2 = w.slice(0, 2);
  if (!/^[a-z]{2}$/.test(head2)) return '_';
  const head3 = w.slice(0, 3);
  return /^[a-z]{3}$/.test(head3) ? head3 : head2;
}

export function parseKaikkiLine(line) {
  let r;
  try { r = JSON.parse(line); } catch { return null; }
  if (!r || r.lang_code !== 'en' || !r.word) return null;

  const en = (r.senses || [])
    .map(s => (s.glosses || [])[0])
    .filter(g => g && !g.startsWith(LITERAL_PREFIX))
    .slice(0, MAX_SENSES);

  const ipaSound = (r.sounds || []).find(s => s.ipa);

  return {
    word: r.word,
    pos: r.pos || '',
    en,
    ko: (r.translations || []).filter(t => t.code === 'ko').map(t => t.word).filter(Boolean),
    ipa: ipaSound ? ipaSound.ipa : '',
    forms: r.forms || []
  };
}

/** 위키 링크에서 표시 텍스트만 남긴다. [[서투르다|서투른]] → 서투른 */
function unlink(s) {
  return s.replace(/\[\[([^\]|]*\|)?([^\]]*)\]\]/g, '$2');
}

export function parseKoSection(wikitext) {
  const lines = String(wikitext).split('\n');
  const start = lines.findIndex(l => /^==\s*영어\s*==/.test(l));
  if (start === -1) return null;

  let pos = '';
  const senses = [];
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i];
    if (/^==[^=]/.test(line)) break;              // 다음 언어 구간

    const heading = line.match(/^===+\s*([^=]+?)\s*===+/);
    if (heading && KO_POS[heading[1]]) { pos = KO_POS[heading[1]]; continue; }

    const category = line.match(/\[\[분류:영어\s*([^\]]+)\]\]/);
    if (category && !pos && KO_POS[category[1].trim()]) { pos = KO_POS[category[1].trim()]; }

    // '#'는 뜻줄, '#:'/'#*'는 예문·인용문(중첩)이라 뜻으로 치지 않는다.
    if (/^#[^#:*]/.test(line) || line === '#') {
      const text = unlink(line.replace(/^#+\s*/, '')).trim();
      if (text) senses.push(text);
    }
  }
  if (!senses.length) return null;
  return { pos, senses: senses.slice(0, MAX_SENSES) };
}

export function mergeEntry(kaikkiEntries, koEntry) {
  const entries = (kaikkiEntries || []).filter(Boolean);
  const word = entries.length ? entries[0].word : '';

  const ko = koEntry && koEntry.senses.length
    ? koEntry.senses.slice(0, MAX_SENSES)
    : entries.flatMap(e => e.ko).slice(0, MAX_SENSES);

  const pos = [...new Set(entries.map(e => e.pos).filter(Boolean))];
  if (koEntry && koEntry.pos && !pos.includes(koEntry.pos)) pos.push(koEntry.pos);

  const withIpa = entries.find(e => e.ipa);

  return {
    pos,
    ko,
    en: entries.flatMap(e => e.en).slice(0, MAX_SENSES),
    ipa: withIpa ? withIpa.ipa : '',
    mwe: word.includes(' ')
  };
}

export function buildInflections(kaikkiEntries) {
  const map = {};
  for (const e of (kaikkiEntries || []).filter(Boolean)) {
    if (e.word.includes(' ')) continue;   // 다어절은 토큰 단위로 매칭한다
    const lemma = e.word.toLowerCase();
    for (const f of e.forms || []) {
      const form = String(f.form || '').toLowerCase();
      if (!form || form === lemma || form.includes(' ')) continue;
      // 충돌하면 사전순으로 앞선 원형을 쓴다 — 덤프 순서와 무관하게 같은 결과가 나와야 한다.
      if (map[form] === undefined || lemma < map[form]) map[form] = lemma;
    }
  }
  return map;
}
