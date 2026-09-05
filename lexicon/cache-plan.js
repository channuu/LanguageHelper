// lexicon/cache-plan.js
// 설계 문서 §6의 버전 비교. 순수 함수다.

/** 캐시된 버킷 중 원격과 해시가 다르거나 원격에서 사라진 것들을 고른다. */
export function staleBuckets(cachedHashes, remoteVersion) {
  const remote = remoteVersion && remoteVersion.buckets;
  if (!remote) return [];                 // 갱신 확인 실패 — 캐시를 그대로 쓴다
  return Object.keys(cachedHashes || {}).filter(b => remote[b] !== cachedHashes[b]);
}
