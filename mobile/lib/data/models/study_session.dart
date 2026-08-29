class StudySession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String savedAt;
  final String updatedAt;
  final String? syncedAt;

  const StudySession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.savedAt,
    required this.updatedAt,
    this.syncedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'saved_at': savedAt,
        'updated_at': updatedAt,
        'synced_at': syncedAt,
      };

  factory StudySession.fromMap(Map<String, Object?> map) => StudySession(
        id: map['id'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        durationSeconds: map['duration_seconds'] as int,
        savedAt: map['saved_at'] as String,
        // Migration backfills updated_at, but fall back to saved_at for
        // rows that somehow arrive without it (e.g. imported backups).
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
      );

  StudySession copyWith({
    String? updatedAt,
    String? syncedAt,
  }) =>
      StudySession(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        savedAt: savedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncedAt: syncedAt ?? this.syncedAt,
      );
}
