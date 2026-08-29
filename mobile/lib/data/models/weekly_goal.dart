class WeeklyGoal {
  final String id;
  final int targetMinutes;
  final DateTime effectiveFrom;
  final String createdAt;
  final String updatedAt;
  final String? syncedAt;

  const WeeklyGoal({
    required this.id,
    required this.targetMinutes,
    required this.effectiveFrom,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'target_minutes': targetMinutes,
        'effective_from': effectiveFrom.toIso8601String(),
        'created_at': createdAt,
        'updated_at': updatedAt,
        'synced_at': syncedAt,
      };

  factory WeeklyGoal.fromMap(Map<String, Object?> map) => WeeklyGoal(
        id: map['id'] as String,
        targetMinutes: map['target_minutes'] as int,
        effectiveFrom: DateTime.parse(map['effective_from'] as String),
        createdAt: map['created_at'] as String,
        // Migration backfills updated_at, but fall back to created_at for
        // rows that somehow arrive without it (e.g. imported backups).
        updatedAt: (map['updated_at'] as String?) ??
            (map['created_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
      );

  WeeklyGoal copyWith({
    String? updatedAt,
    String? syncedAt,
  }) =>
      WeeklyGoal(
        id: id,
        targetMinutes: targetMinutes,
        effectiveFrom: effectiveFrom,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncedAt: syncedAt ?? this.syncedAt,
      );
}
