// cloud/merge.js
// 설계 문서 §7.3의 병합 규칙. 순수 함수다 — chrome.*도 fetch도 쓰지 않는다.
// 앱의 sync_service.dart가 같은 규칙을 Dart로 구현한다.

/**
 * @param {Array<{id: string, updated_at: string, synced_at: ?string}>} local
 * @param {Array<{id: string, updated_at: string}>} remote
 */
export function planMerge(local, remote) {
  const remoteById = new Map(remote.map(r => [r.id, r]));
  const localById = new Map(local.map(l => [l.id, l]));

  const toWriteLocal = [];
  const toDeleteLocal = [];
  const toPush = [];

  for (const item of local) {
    // 규칙 1 — 아직 안 올라간 항목은 서버에 없는 게 당연하다. 절대 덮지 않는다.
    if (item.synced_at == null) {
      toPush.push(item);
      continue;
    }
    const server = remoteById.get(item.id);
    if (!server) {
      // 규칙 4 — 올린 적 있는데 서버에 없다 = 다른 기기에서 삭제됐다.
      toDeleteLocal.push(item.id);
      continue;
    }
    // 규칙 2 — 늦은 쪽이 이긴다. 동률이면 서버.
    if (item.updated_at > server.updated_at) {
      toPush.push(item);
    } else {
      toWriteLocal.push(server);
    }
  }

  // 규칙 3 — 서버에만 있으면 로컬에 넣는다.
  for (const server of remote) {
    if (!localById.has(server.id)) toWriteLocal.push(server);
  }

  return { toWriteLocal, toDeleteLocal, toPush };
}
