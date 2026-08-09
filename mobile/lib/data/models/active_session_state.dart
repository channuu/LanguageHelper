class ActiveSessionState {
  final DateTime startedAt;
  final DateTime? pausedAt;
  final int accumulatedPausedSeconds;

  const ActiveSessionState({
    required this.startedAt,
    this.pausedAt,
    this.accumulatedPausedSeconds = 0,
  });

  bool get isPaused => pausedAt != null;

  /// Seconds of actual focus time so far, excluding paused time.
  /// While paused, uses [pausedAt] as the reference point (not [now]) so the
  /// displayed time freezes during a pause.
  int elapsedSeconds({DateTime? now}) {
    final reference = pausedAt ?? (now ?? DateTime.now());
    return reference.difference(startedAt).inSeconds - accumulatedPausedSeconds;
  }

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'pausedAt': pausedAt?.toIso8601String(),
        'accumulatedPausedSeconds': accumulatedPausedSeconds,
      };

  factory ActiveSessionState.fromJson(Map<String, Object?> json) => ActiveSessionState(
        startedAt: DateTime.parse(json['startedAt'] as String),
        pausedAt: json['pausedAt'] != null
            ? DateTime.parse(json['pausedAt'] as String)
            : null,
        accumulatedPausedSeconds: json['accumulatedPausedSeconds'] as int? ?? 0,
      );

  ActiveSessionState copyWith({
    DateTime? pausedAt,
    bool clearPausedAt = false,
    int? accumulatedPausedSeconds,
  }) =>
      ActiveSessionState(
        startedAt: startedAt,
        pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
        accumulatedPausedSeconds: accumulatedPausedSeconds ?? this.accumulatedPausedSeconds,
      );
}
