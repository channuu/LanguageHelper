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
