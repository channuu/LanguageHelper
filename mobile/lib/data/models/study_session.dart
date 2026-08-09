class StudySession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final String savedAt;

  const StudySession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.savedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'saved_at': savedAt,
      };

  factory StudySession.fromMap(Map<String, Object?> map) => StudySession(
        id: map['id'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: DateTime.parse(map['ended_at'] as String),
        durationSeconds: map['duration_seconds'] as int,
        savedAt: map['saved_at'] as String,
      );
}
