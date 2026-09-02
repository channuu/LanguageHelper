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
