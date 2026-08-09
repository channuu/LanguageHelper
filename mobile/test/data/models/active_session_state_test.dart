import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/active_session_state.dart';

void main() {
  group('ActiveSessionState', () {
    test('isPaused is false when pausedAt is null', () {
      final state = ActiveSessionState(startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'));
      expect(state.isPaused, isFalse);
    });

    test('isPaused is true when pausedAt is set', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
      );
      expect(state.isPaused, isTrue);
    });

    test('elapsedSeconds while running subtracts accumulated paused time from now-started', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        accumulatedPausedSeconds: 60,
      );
      final now = DateTime.parse('2026-08-10T09:10:00.000Z'); // 600s since start
      expect(state.elapsedSeconds(now: now), 540); // 600 - 60
    });

    test('elapsedSeconds while paused uses pausedAt, not now', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
        accumulatedPausedSeconds: 0,
      );
      final now = DateTime.parse('2026-08-10T09:30:00.000Z'); // way later, should be ignored
      expect(state.elapsedSeconds(now: now), 300); // 09:05 - 09:00
    });

    test('toJson/fromJson round-trips all fields', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
        accumulatedPausedSeconds: 42,
      );
      final restored = ActiveSessionState.fromJson(state.toJson());

      expect(restored.startedAt, state.startedAt);
      expect(restored.pausedAt, state.pausedAt);
      expect(restored.accumulatedPausedSeconds, 42);
    });

    test('toJson/fromJson round-trips a null pausedAt', () {
      final state = ActiveSessionState(startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'));
      final restored = ActiveSessionState.fromJson(state.toJson());
      expect(restored.pausedAt, isNull);
    });

    test('copyWith(pausedAt: x) sets pausedAt without touching other fields', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        accumulatedPausedSeconds: 10,
      );
      final updated = state.copyWith(pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'));

      expect(updated.pausedAt, DateTime.parse('2026-08-10T09:05:00.000Z'));
      expect(updated.startedAt, state.startedAt);
      expect(updated.accumulatedPausedSeconds, 10);
    });

    test('copyWith(clearPausedAt: true) clears pausedAt even if a new one is also passed', () {
      final state = ActiveSessionState(
        startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
        pausedAt: DateTime.parse('2026-08-10T09:05:00.000Z'),
      );
      final updated = state.copyWith(clearPausedAt: true, accumulatedPausedSeconds: 300);

      expect(updated.pausedAt, isNull);
      expect(updated.accumulatedPausedSeconds, 300);
    });
  });
}
