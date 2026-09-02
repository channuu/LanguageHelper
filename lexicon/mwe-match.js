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

// index 객체별로 정리된 표제어 구조를 기억해둔다 — 매 호출마다
// 72,069개 표제어를 다시 나누고 정렬하지 않기 위함이다 (설계 §8).
// index 객체의 정체성(identity)으로 키를 잡는다: 같은 인덱스가
// 재사용되는 동안은(서비스워커 생애주기 중) 캐시가 유효하다.
const preparedCache = new WeakMap();

function prepare(index) {
  const cached = preparedCache.get(index);
  if (cached) return cached;

  const inflections = (index && index.inflections) || {};
  const terms = ((index && index.mwe) || [])
    .map((t, order) => ({ term: t, parts: t.split(' '), order }))
    // 규칙 3 — 같은 시작 위치에서는 토큰 수가 많은 쪽을 먼저 시도한다.
    // order는 동률일 때 원래 mwe 배열 순서를 보존하기 위한 안정 정렬용 키다.
    .sort((a, b) => b.parts.length - a.parts.length || a.order - b.order);

  // 첫 토큰별로 후보를 묶어서, 한 위치에서는 그 위치의 토큰이
  // 실제로 시작할 수 있는 표제어만 시도하게 한다.
  const byFirstToken = new Map();
  for (const entry of terms) {
    const key = entry.parts[0];
    let list = byFirstToken.get(key);
    if (!list) { list = []; byFirstToken.set(key, list); }
    list.push(entry);
  }

  const prepared = { inflections, byFirstToken };
  preparedCache.set(index, prepared);
  return prepared;
}

/** 두 후보 목록(각각 길이 내림차순 + 원 순서 보존)을 같은 순서로 합친다. */
function mergeCandidates(a, b) {
  if (!a.length) return b;
  if (!b.length) return a;
  const out = [];
  let i = 0, j = 0;
  while (i < a.length && j < b.length) {
    const x = a[i], y = b[j];
    const xFirst = x.parts.length > y.parts.length ||
      (x.parts.length === y.parts.length && x.order <= y.order);
    out.push(xFirst ? a[i++] : b[j++]);
  }
  while (i < a.length) out.push(a[i++]);
  while (j < b.length) out.push(b[j++]);
  return out;
}

/** tokens[pos]가 시작 토큰으로 쓰일 수 있는 후보들 — 정규화형과 원형(굴절 복원) 둘 다 본다. */
function candidatesAt(byFirstToken, tokens, pos, inflections) {
  const n = normalize(tokens[pos]);
  if (!n) return [];
  const bySurface = byFirstToken.get(n) || [];
  const lemma = inflections[n];
  if (!lemma || lemma === n) return bySurface;
  const byLemma = byFirstToken.get(lemma) || [];
  return mergeCandidates(bySurface, byLemma);
}

export function scanMwe(tokens, index) {
  const { inflections, byFirstToken } = prepare(index);

  const out = [];
  let i = 0;
  while (i < tokens.length) {
    let hit = null;
    const candidates = candidatesAt(byFirstToken, tokens, i, inflections);
    for (const { term, parts } of candidates) {
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
