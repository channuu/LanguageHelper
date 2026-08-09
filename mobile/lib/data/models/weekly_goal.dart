class WeeklyGoal {
  final String id;
  final int targetMinutes;
  final DateTime effectiveFrom;
  final String createdAt;

  const WeeklyGoal({
    required this.id,
    required this.targetMinutes,
    required this.effectiveFrom,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'target_minutes': targetMinutes,
        'effective_from': effectiveFrom.toIso8601String(),
        'created_at': createdAt,
      };

  factory WeeklyGoal.fromMap(Map<String, Object?> map) => WeeklyGoal(
        id: map['id'] as String,
        targetMinutes: map['target_minutes'] as int,
        effectiveFrom: DateTime.parse(map['effective_from'] as String),
        createdAt: map['created_at'] as String,
      );
}
