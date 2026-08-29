/// 설계 문서 §7.3의 병합 규칙. 순수 함수다 — DB도 네트워크도 건드리지 않는다.
/// 확장의 cloud/merge.js와 같은 규칙이며, 두 구현이 갈라지면 기기마다
/// 다른 결과가 나온다.

class SyncRecord {
  final String id;
  final String updatedAt;
  final String? syncedAt;
  final Map<String, Object?> data;

  const SyncRecord({
    required this.id,
    required this.updatedAt,
    required this.syncedAt,
    required this.data,
  });
}

class MergePlan {
  final List<SyncRecord> toWriteLocal;
  final List<String> toDeleteLocal;
  final List<SyncRecord> toPush;

  const MergePlan({
    required this.toWriteLocal,
    required this.toDeleteLocal,
    required this.toPush,
  });
}

MergePlan planMerge({
  required List<SyncRecord> local,
  required List<SyncRecord> remote,
}) {
  final remoteById = {for (final r in remote) r.id: r};
  final localIds = {for (final l in local) l.id};

  final toWriteLocal = <SyncRecord>[];
  final toDeleteLocal = <String>[];
  final toPush = <SyncRecord>[];

  for (final item in local) {
    // 규칙 1 — 아직 안 올라간 항목은 서버에 없는 게 당연하다. 절대 덮지 않는다.
    if (item.syncedAt == null) {
      toPush.add(item);
      continue;
    }
    final server = remoteById[item.id];
    if (server == null) {
      // 규칙 4 — 올린 적 있는데 서버에 없다 = 다른 기기에서 삭제됐다.
      toDeleteLocal.add(item.id);
      continue;
    }
    // 규칙 2 — 늦은 쪽이 이긴다. 동률이면 서버.
    if (item.updatedAt.compareTo(server.updatedAt) > 0) {
      toPush.add(item);
    } else {
      toWriteLocal.add(server);
    }
  }

  // 규칙 3 — 서버에만 있으면 로컬에 넣는다.
  for (final server in remote) {
    if (!localIds.contains(server.id)) toWriteLocal.add(server);
  }

  return MergePlan(
    toWriteLocal: toWriteLocal,
    toDeleteLocal: toDeleteLocal,
    toPush: toPush,
  );
}
