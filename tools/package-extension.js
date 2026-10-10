#!/usr/bin/env node
// tools/package-extension.js
//
// Chrome 웹 스토어 제출용 ZIP을 만든다.
//
// 저장소에는 확장과 무관한 것이 많이 섞여 있다 — 사전 원본(dumps/, 수백 MB),
// Flutter 앱(mobile/), 빌드 산출물(dist/), 테스트, 설계 문서. 그대로 압축하면
// 용량도 문제고 심사에도 불리하다.
//
// 파일 목록을 손으로 적지 않고 manifest.json에서 끌어내는 이유는, 손으로 적으면
// 반드시 manifest와 어긋나기 때문이다. manifest가 참조하는 것은 자동으로 들어오고,
// 실행 중에만 열리는 페이지(로그인 창, 인쇄용 페이지)와 서비스워커가 import하는
// 모듈 디렉터리만 EXTRA_DIRS에 따로 적는다.
import { readFileSync, rmSync, mkdirSync, cpSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = join(ROOT, 'build');

// manifest에서 끌어낼 수 없는 것들.
//   cloud, lexicon  — background/service_worker.js가 import하는 모듈
//   auth, export    — chrome.runtime.getURL()로 실행 중에만 열리는 페이지
//   popup           — manifest는 popup.html만 가리키고 css/js는 그 안에서 참조
//   ui/fonts        — web_accessible_resources가 glob이라 경로만 알 수 있음
const EXTRA_DIRS = ['cloud', 'lexicon', 'auth', 'export', 'popup', 'ui/fonts'];

function fromManifest(manifest) {
  const files = new Set(['manifest.json']);
  const add = (p) => { if (typeof p === 'string' && !p.includes('*')) files.add(p); };

  add(manifest.background?.service_worker);
  add(manifest.action?.default_popup);
  Object.values(manifest.action?.default_icon || {}).forEach(add);
  Object.values(manifest.icons || {}).forEach(add);
  for (const cs of manifest.content_scripts || []) {
    (cs.js || []).forEach(add);
    (cs.css || []).forEach(add);
  }
  for (const war of manifest.web_accessible_resources || []) {
    (war.resources || []).forEach(add);
  }
  return [...files];
}

const manifest = JSON.parse(readFileSync(join(ROOT, 'manifest.json'), 'utf8'));
const entries = [...fromManifest(manifest), ...EXTRA_DIRS];

// 없는 파일을 조용히 빠뜨리면 심사에 올라간 뒤에야 깨진 걸 알게 된다.
const missing = entries.filter((e) => !existsSync(join(ROOT, e)));
if (missing.length) {
  console.error('패키징 중단 — 참조된 경로가 없습니다:');
  missing.forEach((m) => console.error('  ' + m));
  process.exit(1);
}

const name = `english-helper-${manifest.version}`;
const stage = join(OUT_DIR, name);
rmSync(stage, { recursive: true, force: true });
mkdirSync(stage, { recursive: true });

for (const entry of entries) {
  const dest = join(stage, entry);
  mkdirSync(dirname(dest), { recursive: true });
  cpSync(join(ROOT, entry), dest, { recursive: true });
}

const zipPath = join(OUT_DIR, `${name}.zip`);
rmSync(zipPath, { force: true });
// -r 재귀, -q 조용히, -X 맥OS 확장 속성 제외(심사용 ZIP에 __MACOSX가 들어가지 않게)
execFileSync('zip', ['-rqX', zipPath, name], { cwd: OUT_DIR });

const { size } = await import('node:fs').then((fs) => fs.statSync(zipPath));
console.log(`${zipPath}`);
console.log(`${entries.length}개 항목 · ${(size / 1024).toFixed(0)} KB`);
