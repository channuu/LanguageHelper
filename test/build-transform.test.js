import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bucketFor, parseKaikkiLine, parseKoSection, mergeEntry, buildInflections
} from '../lexicon/build-transform.js';

test('bucketFor: 앞 세 글자가 모두 알파벳이면 세 글자를 쓴다', () => {
  assert.equal(bucketFor('awkward'), 'awk');
  assert.equal(bucketFor('give up'), 'giv');
  assert.equal(bucketFor('Give Up'), 'giv');
});

test('bucketFor: 두 글자짜리 단어는 두 글자를 쓴다', () => {
  assert.equal(bucketFor('go'), 'go');
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

const KO_WITH_EXAMPLES = [
  '== 영어 ==', '===Suffix===',
  "# [[times|Times]]: 배수를 나타내는 접미사.",
  "#* '''1809''', some old quotation citation that runs long:",
  "#*: Her stomach being extremely delicate, an English quotation line.",
  '#: {{예문|en|Example sentence in English.|한국어 번역.}}',
  '# 두 번째 뜻.'
].join('\n');

test('parseKoSection: #:와 #*로 시작하는 예문·인용문 줄은 뜻으로 치지 않는다', () => {
  assert.deepEqual(parseKoSection(KO_WITH_EXAMPLES), {
    pos: '', senses: ['Times: 배수를 나타내는 접미사.', '두 번째 뜻.']
  });
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
