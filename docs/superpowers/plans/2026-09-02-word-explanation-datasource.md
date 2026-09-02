# 단어·표현 해설 데이터소스 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 자막의 단어와 구동사를 클릭하면 한국어 뜻이 뜨게 한다. 무료 위키 덤프 두 종을 빌드 타임에 병합해 만든 정적 사전을 Firebase Hosting에 올리고, service worker가 IndexedDB에 캐시하며 조회한다.

**Architecture:** 런타임에 외부 사전 API를 부르지 않는다. 개발 PC에서 `tools/build-dictionary.js`가 en.wiktionary(kaikki JSONL)와 ko.wiktionary(XML 덤프)를 병합해 알파벳 두 글자 버킷으로 쪼갠 JSON을 만들고, Hosting에 배포한다. 확장은 service worker에서만 사전을 다루며, 클릭한 버킷만 받아 IndexedDB에 영구 캐시한다. 구동사 매칭과 사전 변환 로직은 `chrome.*`도 `fetch`도 쓰지 않는 순수 ESM 모듈로 분리해 `node --test`로 검증한다.

**Tech Stack:** Chrome MV3 (content script는 IIFE 전역, service worker는 ES module), Node 내장 `node --test`, Firebase Hosting, IndexedDB

**Spec:** `docs/superpowers/specs/2026-09-02-word-explanation-datasource-design.md`

## Global Constraints

- **빌드 스텝과 npm 의존성을 도입하지 않는다.** 번들러도 트랜스파일러도 없다. 테스트는 Node 내장 `node --test`만 쓴다. 빌드 스크립트도 Node 표준 라이브러리만 쓴다.
- **`lexicon/*.js`는 service worker에서만 로드한다.** `manifest.json`의 `content_scripts`에 넣지 않는다. content script 파일들은 IIFE 전역 방식이라 ESM을 import할 수 없다.
- **토큰 분할은 언제나 `.split(' ')`.** `core/subtitle-engine.js`의 span 분할과 `scanMwe`의 토큰 인덱스가 반드시 같은 규칙이어야 한다. 정규식 분할로 바꾸지 않는다.
- **토큰 정규화는 `tok.toLowerCase().replace(/[^a-z']/g, '')`.** `core/subtitle-engine.js:240`의 기존 규칙(`replace(/[^a-zA-Z']/g, '')`)과 같은 문자 집합이다.
- **버킷 키는 소문자화한 표제어의 앞 두 글자.** 알파벳 두 글자가 아니면 `_`.
- **sense는 표제어당 최대 4개.**
- **`ko`가 비어 있지 않으면 `en`을 화면에 쓰지 않는다.** 폴백은 `ko`가 빈 경우에만이다.
- UI 문구는 한국어. 기존 톤(`'✓ 문장 저장됨'`, `'정의를 찾을 수 없습니다.'`)을 따른다.
- 커밋 메시지는 기존 규약(`feat:`, `fix:`, `test:`, `chore:`, `docs:`)을 따른다.

---

## Task 1: 다어절 표현 매칭 함수

설계 §8. 자막 문장 토큰에서 구동사·관용구 구간을 찾는 순수 함수다. 사전 데이터가 아직 없어도 인덱스를 인자로 받으므로 지금 만들 수 있고, 이후 모든 작업이 이 함수의 반환 형태에 의존한다.

**Files:**
- Create: `lexicon/mwe-match.js`
- Test: `test/mwe-match.test.js`

**Interfaces:**
- Produces:
  ```js
  export function scanMwe(tokens, index)
  // tokens: string[]  — 원문을 .split(' ')한 결과. 정규화 전 원본 토큰
  // index:  { mwe: string[], inflections: Record<string,string> }
  //   mwe          — 소문자 다어절 표제어 목록 (예: ["give up", "put up with"])
  //   inflections  — 굴절형 → 원형 (예: { "gave": "give", "gives": "give" })
  // 반환: [{ term: string, start: number, end: number }]
  //   start/end 는 tokens 배열의 인덱스이며 end 는 포함(inclusive)이다.
  ```

**매칭 규칙 (설계 §8):**

1. 각 토큰은 `normalize()`를 거친다. 매칭 후보는 정규화형과 그 원형 **둘 다**다.
2. 동사와 불변화사 사이에 끼어드는 토큰을 **총 3개까지** 허용한다 (`look it up`, `gave the whole plan up`).
3. 같은 시작 위치에서는 **토큰 수가 많은 표제어**를 우선한다 (`put up with` > `put up`).
4. 구간은 겹치지 않는다. 매칭이 성립하면 `end` 다음 토큰부터 다시 찾는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/mwe-match.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scanMwe } from '../lexicon/mwe-match.js';

const INDEX = {
  mwe: ['give up', 'look up', 'put up', 'put up with', 'find out'],
  inflections: { gave: 'give', gives: 'give', giving: 'give', looked: 'look', found: 'find' }
};

const scan = (s) => scanMwe(s.split(' '), INDEX);

test('원형 그대로 일치한다', () => {
  assert.deepEqual(scan('I give up now'), [{ term: 'give up', start: 1, end: 2 }]);
});

test('굴절형을 원형으로 되돌려 일치시킨다', () => {
  assert.deepEqual(scan('He gave up'), [{ term: 'give up', start: 1, end: 2 }]);
});

test('문장부호와 대소문자를 무시한다', () => {
  assert.deepEqual(scan('Gave up!'), [{ term: 'give up', start: 0, end: 1 }]);
});

test('사이에 1토큰이 끼어도 일치한다', () => {
  assert.deepEqual(scan('Look it up'), [{ term: 'look up', start: 0, end: 2 }]);
});

test('사이에 3토큰까지 허용한다', () => {
  assert.deepEqual(scan('He gave the whole plan up'),
    [{ term: 'give up', start: 1, end: 5 }]);
});

test('사이에 4토큰이 끼면 일치하지 않는다', () => {
  assert.deepEqual(scan('He gave the whole silly plan up'), []);
});

test('더 긴 표제어를 우선한다', () => {
  assert.deepEqual(scan('I put up with it'), [{ term: 'put up with', start: 1, end: 3 }]);
});

test('구간이 겹치지 않는다', () => {
  assert.deepEqual(scan('give up find out'), [
    { term: 'give up', start: 0, end: 1 },
    { term: 'find out', start: 2, end: 3 }
  ]);
});

test('표제어가 없으면 빈 배열이다', () => {
  assert.deepEqual(scan('nothing here at all'), []);
});

test('빈 인덱스에서도 죽지 않는다', () => {
  assert.deepEqual(scanMwe(['give', 'up'], { mwe: [], inflections: {} }), []);
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `node --test test/mwe-match.test.js`
Expected: FAIL — `Cannot find module '.../lexicon/mwe-match.js'`

- [ ] **Step 3: 구현한다**

`lexicon/mwe-match.js`:

```js
// lexicon/mwe-match.js
// 설계 문서 §8의 다어절 표현 매칭 규칙. 순수 함수다 — chrome.*도 fetch도 쓰지 않는다.

const MAX_GAP = 3;

/** 토큰 정규화. core/subtitle-engine.js:240의 규칙과 같은 문자 집합이다. */
function normalize(tok) {
  return String(tok).toLowerCase().replace(/[^a-z']/g, '');
}

/** 표제어 토큰 하나가 문장 토큰 하나와 맞는지. 정규화형과 원형을 모두 본다. */
function tokenMatches(candTok, rawTok, inflections) {
  const n = normalize(rawTok);
  if (!n) return false;
  return n === candTok || inflections[n] === candTok;
}

/**
 * tokens[start]에서 표제어 candTokens가 시작하는지 시도한다.
 * 성공하면 마지막 토큰의 인덱스를, 실패하면 -1을 돌려준다.
 */
function tryMatch(tokens, start, candTokens, inflections) {
  if (!tokenMatches(candTokens[0], tokens[start], inflections)) return -1;

  let ti = start + 1;
  let gap = 0;
  for (let ci = 1; ci < candTokens.length; ci++) {
    while (ti < tokens.length && !tokenMatches(candTokens[ci], tokens[ti], inflections)) {
      gap++;
      if (gap > MAX_GAP) return -1;
      ti++;
    }
    if (ti >= tokens.length) return -1;
    ti++;
  }
  return ti - 1;
}

export function scanMwe(tokens, index) {
  const inflections = (index && index.inflections) || {};
  const terms = ((index && index.mwe) || [])
    .map(t => ({ term: t, parts: t.split(' ') }))
    // 규칙 3 — 같은 시작 위치에서는 토큰 수가 많은 쪽을 먼저 시도한다.
    .sort((a, b) => b.parts.length - a.parts.length);

  const out = [];
  let i = 0;
  while (i < tokens.length) {
    let hit = null;
    for (const { term, parts } of terms) {
      const end = tryMatch(tokens, i, parts, inflections);
      if (end !== -1) { hit = { term, start: i, end }; break; }
    }
    if (hit) {
      out.push(hit);
      i = hit.end + 1;   // 규칙 4 — 구간은 겹치지 않는다.
    } else {
      i++;
    }
  }
  return out;
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `node --test test/mwe-match.test.js`
Expected: 10 tests PASS

- [ ] **Step 5: 커밋한다**

```bash
git add lexicon/mwe-match.js test/mwe-match.test.js
git commit -m "feat: 자막 문장에서 구동사 구간을 찾는 매칭 함수"
```

---

## Task 2: 사전 변환 순수 함수

설계 §5. 두 덤프의 원시 데이터를 확장이 읽을 레코드로 바꾸는 함수들이다. 네트워크도 파일 시스템도 건드리지 않으므로 전부 테스트 대상이다.

**Files:**
- Create: `lexicon/build-transform.js`
- Test: `test/build-transform.test.js`

**Interfaces:**
- Produces:
  ```js
  export function bucketFor(word)          // "give up" → "gi",  "a" → "_",  "3D" → "_"
  export function parseKaikkiLine(line)    // JSONL 한 줄 → { word, pos, en[], ko[], ipa, forms[] } | null
  export function parseKoSection(wikitext) // ko.wiktionary 위키텍스트 → { pos, senses[] } | null
  export function mergeEntry(kaikkiEntries, koEntry)  // → { pos[], ko[], en[], ipa, mwe }
  export function buildInflections(kaikkiEntries)     // → { "gave": "give", ... }
  ```

**레코드 형태 (설계 §5):**

```js
{ pos: ["adj"], ko: ["서투른, 미숙한"], en: ["Lacking dexterity"], ipa: "ˈɔːkwəd", mwe: false }
```

**실제 입력 형태 — 확인된 사실이다:**

kaikki JSONL 한 줄(`give up`, verb)의 관련 필드:
```json
{ "word": "give up", "pos": "verb", "lang_code": "en",
  "senses": [ { "glosses": ["To surrender"], "examples": [...] } ],
  "sounds": [ { "audio": "...", "mp3_url": "..." }, { "ipa": "/ɡɪv ʌp/" } ],
  "forms":  [ { "form": "gives up", "tags": ["present","singular","third-person"] },
              { "form": "gave up",  "tags": ["past"] } ],
  "translations": [ { "code": "ko", "word": "포기하다", "sense": "to surrender" } ] }
```

ko.wiktionary 위키텍스트(`awkward`) 전문:
```
== 영어 ==
[[분류:영어 형용사]]
{{발음 듣기|}}
{{IPA|}}
# [[서투르다|서투른]], [[미숙하다|미숙한]].
:*
# [[어색하다|어색한]], [[자신]]이 없는.
:*
```

`give up`은 `===동사===` 헤딩과 `* 유의어:` 줄이 더 있다.

**파싱 규칙:**
- `== 영어 ==` 부터 다음 `== ` 헤딩(또는 문서 끝)까지가 대상 구간이다.
- 뜻줄은 `#` 로 시작하는 줄뿐이다. `:`, `*`, `{{`, `[[분류:` 로 시작하는 줄은 버린다.
- 위키 링크는 표시 텍스트만 남긴다. `[[서투르다|서투른]]` → `서투른`, `[[자신]]` → `자신`.
- 품사는 `===동사===` 헤딩 또는 `[[분류:영어 형용사]]`에서 얻는다.
  매핑: `명사`→`noun`, `동사`/`동사구`→`verb`, `형용사`→`adj`, `부사`→`adv`. 그 외는 버린다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/build-transform.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bucketFor, parseKaikkiLine, parseKoSection, mergeEntry, buildInflections
} from '../lexicon/build-transform.js';

test('bucketFor: 앞 두 글자를 쓴다', () => {
  assert.equal(bucketFor('awkward'), 'aw');
  assert.equal(bucketFor('give up'), 'gi');
  assert.equal(bucketFor('Give Up'), 'gi');
});

test('bucketFor: 두 글자를 못 채우거나 알파벳이 아니면 _ 이다', () => {
  assert.equal(bucketFor('a'), '_');
  assert.equal(bucketFor('3D'), '_');
  assert.equal(bucketFor("o'clock"), '_');
});

const KAIKKI = JSON.stringify({
  word: 'give up', pos: 'verb', lang_code: 'en',
  senses: [
    { glosses: ['Used other than figuratively or idiomatically: see give, up.'] },
    { glosses: ['To surrender'] }, { glosses: ['To stop trying'] },
    { glosses: ['To relinquish'] }, { glosses: ['To devote'] }, { glosses: ['To despair of'] }
  ],
  sounds: [{ audio: 'x.wav' }, { ipa: '/ɡɪv ʌp/' }],
  forms: [{ form: 'gave up', tags: ['past'] }],
  translations: [{ code: 'ko', word: '포기하다' }, { code: 'ja', word: 'あきらめる' }]
});

test('parseKaikkiLine: 필요한 필드만 뽑는다', () => {
  const e = parseKaikkiLine(KAIKKI);
  assert.equal(e.word, 'give up');
  assert.equal(e.pos, 'verb');
  assert.equal(e.ipa, '/ɡɪv ʌp/');
  assert.deepEqual(e.ko, ['포기하다']);
  assert.deepEqual(e.forms, [{ form: 'gave up', tags: ['past'] }]);
});

test('parseKaikkiLine: 축자적 용법 sense를 버린다', () => {
  const e = parseKaikkiLine(KAIKKI);
  assert.ok(!e.en.some(g => g.startsWith('Used other than figuratively')));
});

test('parseKaikkiLine: sense를 4개로 자른다', () => {
  assert.equal(parseKaikkiLine(KAIKKI).en.length, 4);
});

test('parseKaikkiLine: 영어가 아닌 줄은 null이다', () => {
  assert.equal(parseKaikkiLine(JSON.stringify({ word: '국가', lang_code: 'ko' })), null);
});

const KO_ADJ = [
  '== 영어 ==', '[[분류:영어 형용사]]', '{{발음 듣기|}}', '{{IPA|}}',
  '# [[서투르다|서투른]], [[미숙하다|미숙한]].', ':*',
  '# [[어색하다|어색한]], [[자신]]이 없는.', ':*'
].join('\n');

test('parseKoSection: 뜻줄만 뽑고 링크를 푼다', () => {
  assert.deepEqual(parseKoSection(KO_ADJ), {
    pos: 'adj', senses: ['서투른, 미숙한.', '어색한, 자신이 없는.']
  });
});

const KO_VERB = [
  '== 영어 ==', '*어원: [[give]] + [[up]]', '{{IPA|}}', '===동사===',
  '# [[그만두다]], [[포기하다]].', ':*', '* 유의어: [[surrender]]',
  '# 내주다, 넘겨주다, 양보하다.', '', '[[분류:영어 동사구]]'
].join('\n');

test('parseKoSection: 헤딩에서 품사를 얻고 유의어 줄을 버린다', () => {
  assert.deepEqual(parseKoSection(KO_VERB), {
    pos: 'verb', senses: ['그만두다, 포기하다.', '내주다, 넘겨주다, 양보하다.']
  });
});

test('parseKoSection: 다른 언어 구간을 넘지 않는다', () => {
  const wt = KO_ADJ + '\n== 한국어 ==\n# 넘어오면 안 되는 뜻.';
  assert.equal(parseKoSection(wt).senses.length, 2);
});

test('parseKoSection: 영어 구간이 없으면 null이다', () => {
  assert.equal(parseKoSection('== 한국어 ==\n# 뜻.'), null);
});

test('mergeEntry: ko.wiktionary 뜻이 kaikki 번역보다 우선한다', () => {
  const r = mergeEntry([parseKaikkiLine(KAIKKI)], parseKoSection(KO_VERB));
  assert.deepEqual(r.ko, ['그만두다, 포기하다.', '내주다, 넘겨주다, 양보하다.']);
  assert.equal(r.mwe, true);
  assert.deepEqual(r.pos, ['verb']);
  assert.equal(r.ipa, '/ɡɪv ʌp/');
});

test('mergeEntry: ko.wiktionary가 없으면 kaikki 번역을 쓴다', () => {
  const r = mergeEntry([parseKaikkiLine(KAIKKI)], null);
  assert.deepEqual(r.ko, ['포기하다']);
});

test('mergeEntry: 한국어가 하나도 없으면 ko는 빈 배열이다', () => {
  const bare = parseKaikkiLine(JSON.stringify({
    word: 'blorp', pos: 'noun', lang_code: 'en', senses: [{ glosses: ['A thing'] }]
  }));
  const r = mergeEntry([bare], null);
  assert.deepEqual(r.ko, []);
  assert.deepEqual(r.en, ['A thing']);
  assert.equal(r.mwe, false);
});

test('buildInflections: 단일 단어 표제어의 굴절형만 모은다', () => {
  const give = parseKaikkiLine(JSON.stringify({
    word: 'give', pos: 'verb', lang_code: 'en', senses: [{ glosses: ['x'] }],
    forms: [{ form: 'gave', tags: ['past'] }, { form: 'gives', tags: ['present'] }]
  }));
  const giveUp = parseKaikkiLine(KAIKKI);
  const map = buildInflections([give, giveUp]);
  assert.equal(map.gave, 'give');
  assert.equal(map.gives, 'give');
  // 다어절 표제어의 통짜 굴절형("gave up")은 넣지 않는다 — 토큰 단위로 매칭하기 때문이다.
  assert.equal(map['gave up'], undefined);
});

test('buildInflections: 굴절형이 원형과 같으면 넣지 않는다', () => {
  const cut = parseKaikkiLine(JSON.stringify({
    word: 'cut', pos: 'verb', lang_code: 'en', senses: [{ glosses: ['x'] }],
    forms: [{ form: 'cut', tags: ['past'] }]
  }));
  assert.equal(buildInflections([cut]).cut, undefined);
});

test('buildInflections: 충돌하면 사전순으로 앞선 원형을 쓴다', () => {
  const mk = (word, form) => parseKaikkiLine(JSON.stringify({
    word, pos: 'verb', lang_code: 'en', senses: [{ glosses: ['x'] }],
    forms: [{ form, tags: ['past'] }]
  }));
  assert.equal(buildInflections([mk('see', 'saw'), mk('sew', 'saw')]).saw, 'see');
  assert.equal(buildInflections([mk('sew', 'saw'), mk('see', 'saw')]).saw, 'see');
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `node --test test/build-transform.test.js`
Expected: FAIL — `Cannot find module '.../lexicon/build-transform.js'`

- [ ] **Step 3: 구현한다**

`lexicon/build-transform.js`:

```js
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
  const head = String(word).toLowerCase().slice(0, 2);
  return /^[a-z]{2}$/.test(head) ? head : '_';
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

    if (line.startsWith('#')) {
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
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `node --test test/build-transform.test.js`
Expected: 16 tests PASS

- [ ] **Step 5: 전체 테스트가 여전히 통과하는지 확인한다**

Run: `npm test`
Expected: 기존 테스트 포함 전부 PASS

- [ ] **Step 6: 커밋한다**

```bash
git add lexicon/build-transform.js test/build-transform.test.js
git commit -m "feat: 위키 덤프를 사전 레코드로 바꾸는 변환 함수"
```

---

## Task 3: 사전 빌드 스크립트

설계 §5, §6. Task 2의 순수 함수들을 실제 덤프에 흘려보내 `dist/dict/`를 만든다. 개발 PC에서 수동 실행하며 CI에 넣지 않는다.

**Files:**
- Create: `tools/build-dictionary.js`
- Modify: `.gitignore`
- Modify: `package.json` (scripts)

**Interfaces:**
- Consumes: `lexicon/build-transform.js`의 `bucketFor`, `parseKaikkiLine`, `parseKoSection`, `mergeEntry`, `buildInflections`
- Produces: `dist/dict/` 아래 `version.json`, `mwe-index.json`, `inflections.json`, `b/<bucket>.json`. Task 5의 `lexicon/lookup.js`가 이 파일들을 HTTP로 읽는다.

**출력 파일 형태:**

```
dist/dict/version.json     { "version": "2026-09-02", "buckets": { "aw": "3f2a…", "gi": "9c11…" } }
dist/dict/mwe-index.json   ["give up", "look up", "put up with", ...]
dist/dict/inflections.json { "gave": "give", "gives": "give", ... }
dist/dict/b/aw.json        { "awkward": { pos:["adj"], ko:[...], en:[...], ipa:"…", mwe:false }, ... }
```

**메모리 전략 — 이게 이 작업의 핵심이다.** kaikki 덤프는 3.2GB이고 같은 표제어의 품사별 줄이 파일 안에서 인접해 있다는 보장이 없다. 전부 메모리에 올리면 죽는다. 그래서 2패스로 간다.

1. ko.wiktionary 덤프(47MB)를 먼저 읽어 `Map<표제어, {pos, senses}>`를 만든다. 작아서 메모리에 들어간다.
2. kaikki를 한 줄씩 흘리며 **버킷별 중간 파일**(`work/b/<bucket>.jsonl`)에 나눠 쓴다. 굴절형 맵은 메모리에 모은다.
3. 버킷 중간 파일을 하나씩 읽어(각각 작다) 표제어별로 묶고, ko 맵과 병합해 최종 버킷 JSON을 쓴다.

**덤프는 스크립트가 내려받지 않는다.** 3.2GB를 매번 다시 받게 되기 때문이다. `dumps/`에 미리 받아 둔 파일을 읽고, 없으면 받는 방법을 안내하며 종료한다.

- [ ] **Step 1: `.gitignore`에 산출물 경로를 넣는다**

`.gitignore` 끝에 추가:

```
dist/
dumps/
work/
```

- [ ] **Step 2: 덤프를 내려받는다 (수동, 1회)**

```bash
mkdir -p dumps
curl -L -o dumps/kowiktionary.xml.bz2 \
  https://dumps.wikimedia.org/kowiktionary/latest/kowiktionary-latest-pages-articles.xml.bz2
curl -L -o dumps/kaikki-english.jsonl \
  https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl
```

두 번째 파일은 3.2GB다. 시간이 걸린다. `ls -l dumps/` 로 크기를 확인한 뒤 다음으로 넘어간다.

- [ ] **Step 3: 빌드 스크립트를 쓴다**

`tools/build-dictionary.js`:

```js
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
```

- [ ] **Step 4: `package.json`에 스크립트를 넣는다**

`scripts`에 한 줄 추가한다:

```json
  "scripts": {
    "test": "node --test test/**/*.js",
    "build:dict": "node tools/build-dictionary.js"
  }
```

- [ ] **Step 5: 빌드를 돌린다**

Run: `npm run build:dict`
Expected: 3단계 진행 로그가 나오고 마지막에 버킷 개수와 두 파일 크기가 찍힌다. kaikki 3.2GB를 훑으므로 수 분 걸린다.

- [ ] **Step 6: 산출물을 눈으로 확인한다**

```bash
ls dist/dict/b | head
node -e "const d=require('./dist/dict/b/aw.json'); console.log(JSON.stringify(d.awkward,null,1))"
node -e "const d=require('./dist/dict/b/gi.json'); console.log(JSON.stringify(d['give up'],null,1))"
node -e "const m=require('./dist/dict/mwe-index.json'); console.log(m.length, m.includes('give up'), m.includes('put up with'))"
node -e "const i=require('./dist/dict/inflections.json'); console.log(i.gave, i.gives, i.found)"
```

확인할 것:
- `awkward.ko`에 한국어 뜻이 들어 있다 (`["서투른, 미숙한.", …]`)
- `give up`의 `mwe`가 `true`이고 `ko`가 비어 있지 않다
- `inflections.gave === 'give'`
- **`mwe-index.json`과 `inflections.json`의 크기를 기록해 둔다.** 설계 §14.1의 미결 사항이다. 둘이 합쳐 1MB를 크게 넘으면 Task 5를 시작하기 전에 알린다.

- [ ] **Step 7: 커밋한다**

산출물(`dist/`)은 커밋하지 않는다. 스크립트와 설정만이다.

```bash
git add tools/build-dictionary.js .gitignore package.json
git commit -m "feat: 위키 덤프에서 사전 아티팩트를 만드는 빌드 스크립트"
```

---

## Task 4: Firebase Hosting 배포

설계 §6. 사전을 정적 파일로 올리고 확장이 그 도메인에 접근할 수 있게 한다. Task 5의 조회 계층이 이 URL을 필요로 하므로 먼저 한다.

**Files:**
- Modify: `firebase.json`
- Modify: `manifest.json` (`host_permissions`)
- Create: `lexicon/config.js`

**Interfaces:**
- Produces: `lexicon/config.js`가 `export const DICT_BASE = 'https://<project>.web.app/dict'`를 내보낸다. Task 5가 import한다.

- [ ] **Step 1: `firebase.json`에 hosting을 더한다**

현재 `firestore` 항목만 있다. 다음으로 바꾼다:

```json
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "hosting": {
    "public": "dist",
    "ignore": ["**/.*"],
    "headers": [
      {
        "source": "/dict/b/**",
        "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
      },
      {
        "source": "/dict/version.json",
        "headers": [{ "key": "Cache-Control", "value": "no-cache" }]
      }
    ]
  }
}
```

버킷 파일은 내용이 바뀌면 `version.json`의 해시가 바뀌어 확장이 스스로 무효화하므로 길게 캐시해도 안전하다. `version.json`만 매번 새로 받아야 한다.

- [ ] **Step 2: 배포한다**

Run: `firebase deploy --only hosting`
Expected: `Hosting URL: https://<project>.web.app` 이 출력된다. 이 URL을 적어 둔다.

- [ ] **Step 3: 실제로 받아지는지 확인한다**

```bash
curl -s https://<project>.web.app/dict/version.json | head -c 200
curl -s -o /dev/null -w "%{http_code} %{size_download}\n" https://<project>.web.app/dict/b/aw.json
```

Expected: 첫 줄에 `{"version":"…","buckets":{…`, 둘째 줄에 `200` 과 0이 아닌 크기

- [ ] **Step 4: `lexicon/config.js`를 만든다**

```js
// lexicon/config.js
// 사전 아티팩트가 올라간 곳. tools/build-dictionary.js가 만들고
// firebase deploy --only hosting 이 올린다.

export const DICT_BASE = 'https://<project>.web.app/dict';
```

`<project>`를 Step 2에서 확인한 실제 값으로 바꾼다.

- [ ] **Step 5: `manifest.json`의 host_permissions를 고친다**

`manifest.json:9`의 배열에서 `"https://api.dictionaryapi.dev/*"`를 **지우고** Hosting 도메인을 넣는다:

```json
  "host_permissions": [
    "https://www.youtube.com/*",
    "https://www.netflix.com/*",
    "https://www.disneyplus.com/*",
    "https://*.coupangplay.com/*",
    "https://<project>.web.app/*",
    "https://identitytoolkit.googleapis.com/*",
    "https://securetoken.googleapis.com/*",
    "https://firestore.googleapis.com/*"
  ],
```

사전 API 호출은 Task 7에서 제거하므로 이 시점에는 팝업이 잠시 "정의를 찾을 수 없습니다"를 띄운다. 정상이다.

- [ ] **Step 6: 커밋한다**

```bash
git add firebase.json manifest.json lexicon/config.js
git commit -m "chore: 사전 아티팩트용 Firebase Hosting 설정"
```

---

## Task 5: 사전 조회 계층

설계 §7. IndexedDB 캐시와 Hosting fetch를 담당한다. IndexedDB는 Node에서 테스트할 수 없으므로 **버전 비교 로직만 순수 함수로 떼어내** 테스트하고, 나머지는 Task 6 이후 확장을 실제로 띄워 확인한다.

**Files:**
- Create: `lexicon/cache-plan.js`
- Create: `lexicon/lookup.js`
- Test: `test/cache-plan.test.js`

**Interfaces:**
- Consumes: `lexicon/config.js`의 `DICT_BASE`, `lexicon/mwe-match.js`의 `scanMwe`, `lexicon/build-transform.js`의 `bucketFor`
- Produces:
  ```js
  // lexicon/cache-plan.js
  export function staleBuckets(cachedHashes, remoteVersion)
  // cachedHashes: { aw: "3f2a…" }   remoteVersion: { version, buckets: { aw: "9c11…" } }
  // 반환: 버려야 할 버킷 이름 배열

  // lexicon/lookup.js
  export async function scanText(text)  // → [{ term, start, end }]
  export async function lookup(term)    // → { pos, ko, en, ipa, mwe } | null
  ```

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/cache-plan.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { staleBuckets } from '../lexicon/cache-plan.js';

test('해시가 같으면 버릴 게 없다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', gi: 'b2' },
    { version: '2026-09-02', buckets: { aw: 'a1', gi: 'b2' } }), []);
});

test('해시가 달라진 버킷만 버린다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', gi: 'b2' },
    { version: '2026-10-01', buckets: { aw: 'a1', gi: 'ZZ' } }), ['gi']);
});

test('원격에서 사라진 버킷도 버린다', () => {
  assert.deepEqual(staleBuckets({ aw: 'a1', xx: 'c3' },
    { version: '2026-10-01', buckets: { aw: 'a1' } }), ['xx']);
});

test('캐시가 비어 있으면 버릴 게 없다', () => {
  assert.deepEqual(staleBuckets({}, { version: '2026-10-01', buckets: { aw: 'a1' } }), []);
});

test('원격 버전을 못 읽으면 아무것도 버리지 않는다', () => {
  // 갱신 확인 실패가 조회 실패가 되어선 안 된다 (설계 §11)
  assert.deepEqual(staleBuckets({ aw: 'a1' }, null), []);
  assert.deepEqual(staleBuckets({ aw: 'a1' }, {}), []);
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `node --test test/cache-plan.test.js`
Expected: FAIL — `Cannot find module '.../lexicon/cache-plan.js'`

- [ ] **Step 3: `lexicon/cache-plan.js`를 구현한다**

```js
// lexicon/cache-plan.js
// 설계 문서 §6의 버전 비교. 순수 함수다.

/** 캐시된 버킷 중 원격과 해시가 다르거나 원격에서 사라진 것들을 고른다. */
export function staleBuckets(cachedHashes, remoteVersion) {
  const remote = remoteVersion && remoteVersion.buckets;
  if (!remote) return [];                 // 갱신 확인 실패 — 캐시를 그대로 쓴다
  return Object.keys(cachedHashes || {}).filter(b => remote[b] !== cachedHashes[b]);
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `node --test test/cache-plan.test.js`
Expected: 5 tests PASS

- [ ] **Step 5: `lexicon/lookup.js`를 구현한다**

```js
// lexicon/lookup.js
// 설계 문서 §7의 조회 계층. service worker에서만 로드한다 —
// content script는 IIFE 전역 방식이라 이 모듈을 import할 수 없다.

import { DICT_BASE } from './config.js';
import { scanMwe } from './mwe-match.js';
import { staleBuckets } from './cache-plan.js';
// 버킷 배정 규칙은 빌드와 조회가 반드시 같아야 한다 — 한 곳에서 가져온다.
import { bucketFor } from './build-transform.js';

const DB_NAME = 'eh-dict';
const DB_VERSION = 1;

let dbPromise = null;
let indexPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('buckets')) db.createObjectStore('buckets');
      if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta');
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function idb(store, mode, fn) {
  return openDB().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(store, mode);
    const req = fn(tx.objectStore(store));
    tx.oncomplete = () => resolve(req ? req.result : undefined);
    tx.onerror = () => reject(tx.error);
  }));
}

const idbGet = (store, key) => idb(store, 'readonly', s => s.get(key));
const idbPut = (store, key, value) =>
  // 캐시 쓰기 실패는 조회 실패가 아니다 (설계 §11).
  idb(store, 'readwrite', s => s.put(value, key)).catch(err => {
    console.warn('[EH dict] 캐시 쓰기 실패', err);
  });
const idbDel = (store, key) => idb(store, 'readwrite', s => s.delete(key)).catch(() => {});

async function fetchJson(pathname) {
  const res = await fetch(`${DICT_BASE}/${pathname}`, { cache: 'no-store' });
  if (!res.ok) throw new Error(`dict fetch ${pathname}: ${res.status}`);
  return res.json();
}

/** 해시가 달라진 버킷을 버린다. 실패하면 조용히 넘어간다 — 캐시는 그대로 쓴다. */
async function refreshVersion() {
  let remote = null;
  try { remote = await fetchJson('version.json'); } catch (e) {
    console.warn('[EH dict] version.json 조회 실패', e);
    return;
  }
  const cached = (await idbGet('meta', 'hashes')) || {};
  const stale = staleBuckets(cached, remote);
  for (const b of stale) {
    await idbDel('buckets', b);
    delete cached[b];
  }
  if (stale.length) await idbPut('meta', 'hashes', cached);
  await idbPut('meta', 'version', remote);
}

/** mwe-index.json과 inflections.json. 최초 1회만 받는다. */
function getIndex() {
  if (indexPromise) return indexPromise;
  indexPromise = (async () => {
    const cached = await idbGet('meta', 'index');
    if (cached) return cached;
    const [mwe, inflections] = await Promise.all([
      fetchJson('mwe-index.json'), fetchJson('inflections.json')
    ]);
    const index = { mwe, inflections };
    await idbPut('meta', 'index', index);
    return index;
  })().catch(err => {
    indexPromise = null;               // 다음 호출에서 다시 시도한다
    throw err;
  });
  return indexPromise;
}

async function getBucket(name) {
  const cached = await idbGet('buckets', name);
  if (cached) return cached;
  const entries = await fetchJson(`b/${name}.json`);
  await idbPut('buckets', name, entries);
  const version = await idbGet('meta', 'version');
  if (version && version.buckets && version.buckets[name]) {
    const hashes = (await idbGet('meta', 'hashes')) || {};
    hashes[name] = version.buckets[name];
    await idbPut('meta', 'hashes', hashes);
  }
  return entries;
}

export async function scanText(text) {
  const index = await getIndex();
  return scanMwe(String(text).split(' '), index);
}

export async function lookup(term) {
  await refreshVersion();
  const key = String(term).toLowerCase().trim();
  if (!key) return null;

  let entries = await getBucket(bucketFor(key));
  if (entries[key]) return entries[key];

  // 단일 단어라면 굴절형일 수 있다 — 원형으로 한 번 더 본다.
  if (!key.includes(' ')) {
    const { inflections } = await getIndex();
    const lemma = inflections[key];
    if (lemma && lemma !== key) {
      const b = bucketFor(lemma);
      entries = b === bucketFor(key) ? entries : await getBucket(b);
      if (entries[lemma]) return entries[lemma];
    }
  }
  return null;
}
```

`refreshVersion()`을 `lookup()`마다 부르는 게 낭비로 보이지만, MV3 service worker는 유휴 30초쯤에 종료되므로 "시작 시 1회"라는 개념이 없다. `version.json`은 수백 바이트고 `no-cache`라 실제 비용이 작다.

- [ ] **Step 6: 전체 테스트를 돌린다**

Run: `npm test`
Expected: 전부 PASS

- [ ] **Step 7: 커밋한다**

```bash
git add lexicon/cache-plan.js lexicon/lookup.js test/cache-plan.test.js
git commit -m "feat: IndexedDB 캐시를 얹은 사전 조회 계층"
```

---

## Task 6: service worker 메시지 라우팅

설계 §7.2. content script가 사전을 쓸 수 있게 두 메시지 타입을 연다.

**Files:**
- Modify: `background/service_worker.js` (import 블록, `handleMessage`의 switch)

**Interfaces:**
- Consumes: `lexicon/lookup.js`의 `scanText`, `lookup`
- Produces: 메시지 두 종
  ```js
  { type: 'DICT_SCAN',   payload: { text } }  → { success: true, matches: [{term,start,end}] }
  { type: 'DICT_LOOKUP', payload: { term } }  → { success: true, entry: {...} | null }
  ```

- [ ] **Step 1: import를 더한다**

`background/service_worker.js:6` 아래(`cloud/sync.js` import 다음)에 넣는다:

```js
import { scanText, lookup } from '../lexicon/lookup.js';
```

- [ ] **Step 2: switch에 두 케이스를 더한다**

`handleMessage`의 `switch (message.type) {` 안, `case 'FETCH_CAPTIONS'` **앞**에 넣는다. 사전 조회는 로그인과 무관하므로 `AUTH_REQUIRED` 목록(`background/service_worker.js:40`)에는 **넣지 않는다.**

```js
    // 사전 — 로그인과 무관하다. 자막을 보는 것 자체는 계정 없이 되기 때문이다.
    case 'DICT_SCAN': {
      try {
        return { success: true, matches: await scanText(message.payload.text || '') };
      } catch (err) {
        console.warn('[EH BG] dict scan', err);
        return { success: true, matches: [] };   // 사전이 없어도 자막은 나와야 한다
      }
    }

    case 'DICT_LOOKUP': {
      try {
        return { success: true, entry: await lookup(message.payload.term || '') };
      } catch (err) {
        return { success: false, error: err.message };
      }
    }
```

- [ ] **Step 3: 확장을 다시 로드하고 조회가 되는지 확인한다**

1. `chrome://extensions` → 이 확장의 **새로고침** 버튼
2. 같은 카드의 **서비스 워커** 링크를 눌러 DevTools 콘솔을 연다
3. 콘솔에 붙여 넣는다:

```js
await chrome.runtime.sendMessage({ type: 'DICT_LOOKUP', payload: { term: 'awkward' } })
await chrome.runtime.sendMessage({ type: 'DICT_LOOKUP', payload: { term: 'gave' } })
await chrome.runtime.sendMessage({ type: 'DICT_SCAN', payload: { text: 'He gave the plan up' } })
```

Expected:
- 첫 줄 — `entry.ko`에 한국어 뜻이 들어 있다
- 둘째 줄 — 굴절형이 `give`로 되돌아가 `entry`가 나온다
- 셋째 줄 — `matches`가 `[{ term: 'give up', start: 1, end: 4 }]`
- Network 탭에 `version.json`, `mwe-index.json`, `b/aw.json` 요청이 보인다. **같은 명령을 다시 실행하면 버킷 요청이 사라진다** — IndexedDB 캐시가 동작한다는 뜻이다

- [ ] **Step 4: 커밋한다**

```bash
git add background/service_worker.js
git commit -m "feat: 서비스워커에 사전 조회·스캔 메시지 추가"
```

---

## Task 7: 단어 팝업 개편

설계 §9. 한국어 뜻을 보여주고, 다어절 표현을 단일 단어보다 먼저 보여준다. `api.dictionaryapi.dev` 의존을 끊는다.

**Files:**
- Modify: `core/word-popup.js` (전면 개편)
- Modify: `ui/overlay.css:306` 부근 (팝업 스타일 추가)

**Interfaces:**
- Consumes: Task 6의 `DICT_LOOKUP` 메시지
- Produces: `window.EH.WordPopup.show(options)` — **위치 인자에서 옵션 객체로 시그니처가 바뀐다.** 호출부는 `core/subtitle-engine.js:242` 한 곳뿐이며 Task 8에서 고친다.
  ```js
  show({ word, term, sentence, translation, timestamp, x, y })
  // word: 클릭한 단일 단어 (문장부호 제거 후)
  // term: 이 단어를 품은 다어절 표현. 없으면 null
  ```

- [ ] **Step 1: `core/word-popup.js:38-103`의 `fetchDefinition`과 `show`를 갈아치운다**

`fetchDefinition` 함수 전체를 지우고 다음으로 바꾼다:

```js
  async function lookup(term) {
    try {
      const res = await chrome.runtime.sendMessage({
        type: 'DICT_LOOKUP', payload: { term }
      });
      return (res && res.success) ? res.entry : null;
    } catch (e) {
      return null;
    }
  }

  /** 뜻 목록을 저장용 한 줄로 만든다. */
  function flatten(entry) {
    if (!entry) return '';
    return (entry.ko.length ? entry.ko : entry.en).join(' / ');
  }

  function renderBody(entry) {
    if (!entry) {
      return `<div class="eh-popup-def">정의를 찾을 수 없습니다.</div>`;
    }
    const meta = [entry.pos.join(', '), entry.ipa].filter(Boolean).join(' · ');
    const senses = entry.ko.length ? entry.ko : entry.en;
    const noKo = !entry.ko.length && entry.en.length
      ? `<div class="eh-popup-note">한국어 뜻 없음 — 영어 정의를 보여줍니다</div>` : '';
    return `
      ${meta ? `<div class="eh-popup-phonetic">${esc(meta)}</div>` : ''}
      <div class="eh-popup-divider"></div>
      ${noKo}
      ${senses.map(s => `<div class="eh-popup-def">${esc(s)}</div>`).join('')}
    `;
  }
```

`show` 함수 전체를 다음으로 바꾼다:

```js
  async function show({ word, term, sentence, translation, timestamp, x, y }) {
    if (!popupEl) return;

    // 다어절 표현이 있으면 그쪽이 표제어다. find out을 눌렀는데 find가 뜨면
    // 이 기능의 존재 이유가 사라진다 (설계 §9).
    let headword = term || word;

    popupEl.innerHTML = `
      <div class="eh-popup-word">${esc(headword)}</div>
      <div class="eh-popup-loading">불러오는 중...</div>
    `;
    popupEl.classList.add('visible');
    positionPopup(x, y);

    let entry = await lookup(headword);
    render();

    function render() {
      const showWordLink = term && headword === term;
      popupEl.innerHTML = `
        <div class="eh-popup-word">${esc(headword)}</div>
        ${renderBody(entry)}
        ${showWordLink
          ? `<button class="eh-popup-link" id="eh-show-word">"${esc(word)}" 뜻 보기</button>`
          : ''}
        ${sentence ? `<div class="eh-popup-sentence">"${esc(sentence)}"</div>` : ''}
        <div class="eh-popup-actions">
          <button class="eh-popup-btn" id="eh-save-word">${term ? '표현 저장' : '단어 저장'}</button>
          <button class="eh-popup-btn" id="eh-save-sent">문장 저장</button>
        </div>
        <div class="eh-popup-credit">뜻: 위키낱말사전 (CC BY-SA)</div>
      `;
      positionPopup(x, y);
      wire();
    }

    function wire() {
      const link = document.getElementById('eh-show-word');
      if (link) {
        link.addEventListener('click', async (e) => {
          e.stopPropagation();
          headword = word;
          entry = await lookup(word);
          render();
        });
      }

      document.getElementById('eh-save-word').addEventListener('click', () => {
        window.EH.Storage.saveWord({
          word: headword, definition: flatten(entry),
          sentence, translation, timestamp
        }).then((res) => {
          if (window.EH.handleAuthRequired(res)) return;
          window.EH.showToast?.(`✓ "${headword}" 저장됨`);
          document.dispatchEvent(new CustomEvent('eh-item-saved'));
          hide();
        });
      });

      document.getElementById('eh-save-sent').addEventListener('click', () => {
        window.EH.Storage.saveSentence({ original: sentence, translation, timestamp })
          .then((res) => {
            if (window.EH.handleAuthRequired(res)) return;
            window.EH.showToast?.('✓ 문장 저장됨');
            document.dispatchEvent(new CustomEvent('eh-item-saved'));
            hide();
          });
      });
    }
  }
```

- [ ] **Step 2: 새 클래스의 스타일을 더한다**

`ui/overlay.css`의 `.eh-popup-def` 규칙(306행 부근) **다음**에 넣는다:

```css
.eh-popup-note {
  font-size: 11px; color: var(--eh-text-faint);
  margin-bottom: 6px;
}
.eh-popup-link {
  display: block; width: 100%; margin: 6px 0 0;
  padding: 5px 0; font-size: 12px;
  background: none; border: none; cursor: pointer;
  color: rgba(var(--eh-gold-rgb), 0.85);
  text-align: left;
}
.eh-popup-link:hover { color: var(--eh-text); }
.eh-popup-credit {
  margin-top: 10px; font-size: 10px;
  color: var(--eh-text-faint);
}
```

- [ ] **Step 3: 커밋한다**

이 시점에는 `show`의 시그니처가 바뀌었으나 호출부가 아직 옛 방식이라 팝업이 뜨지 않는다. Task 8에서 이어 고친다.

```bash
git add core/word-popup.js ui/overlay.css
git commit -m "feat: 팝업에 한국어 뜻과 다어절 표현 표시"
```

---

## Task 8: 자막 오버레이 연결

설계 §9. 자막에서 구동사 구간을 표시하고, 클릭을 새 팝업 시그니처로 넘긴다. 이 작업이 끝나야 기능이 실제로 동작한다.

**Files:**
- Modify: `core/subtitle-engine.js:229-248` (자막 렌더 블록)
- Modify: `ui/overlay.css:70` 부근 (`.eh-word` 규칙 다음)

**Interfaces:**
- Consumes: Task 6의 `DICT_SCAN`, Task 7의 `WordPopup.show(options)`

- [ ] **Step 1: 렌더 블록을 고친다**

`core/subtitle-engine.js`의 `// 영어 자막: 단어별 span으로 분리 (클릭 가능)` 블록(229–248행)을 다음으로 바꾼다. `split(' ')`는 그대로 둔다 — `scanMwe`가 돌려주는 인덱스와 같은 규칙이어야 한다.

```js
    // 영어 자막: 단어별 span으로 분리 (클릭 가능)
    enLine.innerHTML = '';
    currentMatches = [];
    if (enText) {
      const s = window.EH.settings;
      enLine.style.fontSize = s.enSize + 'px';
      const tokens = enText.split(' ');
      const spans = [];

      tokens.forEach((word, i, arr) => {
        const span = document.createElement('span');
        span.className = 'eh-word';
        span.textContent = word + (i < arr.length - 1 ? ' ' : '');
        span.addEventListener('click', (e) => {
          e.stopPropagation();
          const clean = word.replace(/[^a-zA-Z']/g, '');
          if (!clean || !window.EH.WordPopup) return;
          const hit = currentMatches.find(m => i >= m.start && i <= m.end);
          window.EH.WordPopup.show({
            word: clean,
            term: hit ? hit.term : null,
            sentence: fullEnText,
            translation: nativeText,
            timestamp: window.EH.adapter?.getCurrentTime() || 0,
            x: e.clientX, y: e.clientY
          });
        });
        spans.push(span);
        enLine.appendChild(span);
      });

      // 구동사 구간 표시. 비동기라 cue가 이미 바뀌었으면 버린다.
      const scannedFor = enText;
      chrome.runtime.sendMessage({ type: 'DICT_SCAN', payload: { text: enText } })
        .then((res) => {
          if (!res || !res.success || scannedFor !== currentEnText) return;
          currentMatches = res.matches;
          for (const m of res.matches) {
            for (let i = m.start; i <= m.end && i < spans.length; i++) {
              spans[i].classList.add('eh-mwe');
            }
          }
        })
        .catch(() => {});
    }
```

- [ ] **Step 2: `currentMatches`를 선언한다**

`core/subtitle-engine.js`에서 `currentEnText`가 선언된 줄을 찾아(`let currentEnText`) 그 아래에 넣는다:

```js
  let currentMatches = [];
```

- [ ] **Step 3: 구동사 표시 스타일을 더한다**

`ui/overlay.css`의 `.eh-word:active` 규칙(70행) **다음**에 넣는다:

```css
.eh-word.eh-mwe {
  text-decoration: underline;
  text-decoration-style: dotted;
  text-decoration-color: rgba(var(--eh-gold-rgb), 0.75);
  text-underline-offset: 3px;
}
```

- [ ] **Step 4: 확장을 다시 로드하고 실제 영상에서 확인한다**

1. `chrome://extensions` → 새로고침
2. 영어 자막이 있는 YouTube 영상을 연다
3. 확인할 것:
   - 일반 단어를 클릭하면 **한국어 뜻**이 뜬다
   - 구동사가 나오는 자막에서 해당 구간에 **점선 밑줄**이 보인다
   - 그 구간의 단어를 클릭하면 표제어가 **구동사**로 뜨고, `"단어" 뜻 보기` 버튼으로 단일 단어 뜻으로 넘어갈 수 있다
   - 한국어 뜻이 없는 구동사에서는 영어 정의와 함께 `한국어 뜻 없음` 안내가 뜬다
   - `표현 저장`을 누르면 라이브러리 패널에 그 표현이 한국어 뜻과 함께 들어온다
   - 자막이 빠르게 바뀔 때 이전 cue의 밑줄이 남지 않는다

- [ ] **Step 5: 전체 테스트를 돌린다**

Run: `npm test`
Expected: 전부 PASS

- [ ] **Step 6: 커밋한다**

```bash
git add core/subtitle-engine.js ui/overlay.css
git commit -m "feat: 자막에 구동사 구간 표시와 사전 팝업 연결"
```

---

## 마무리 확인

전체가 끝난 뒤 다음을 확인한다.

- [ ] `grep -rn "dictionaryapi" .` 가 아무것도 찾지 못한다 (`docs/` 제외)
- [ ] `manifest.json`의 `host_permissions`에 `api.dictionaryapi.dev`가 없고 Hosting 도메인이 있다
- [ ] `manifest.json`의 `content_scripts` 어디에도 `lexicon/`이 없다
- [ ] `git status`가 깨끗하고 `dist/`, `dumps/`, `work/`가 추적되지 않는다
- [ ] `npm test` 전부 통과
- [ ] 설계 §14의 미결 사항 세 가지에 대해 실측값을 남긴다 — `mwe-index.json`/`inflections.json` 크기, 가장 큰 버킷의 크기, 그리고 그 값들에 비추어 버킷 두 글자가 적정한지
