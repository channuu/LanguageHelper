import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/weekly_goal.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final goal = WeeklyGoal(
      id: 'goal1',
      targetMinutes: 300,
      effectiveFrom: DateTime.parse('2026-08-10T00:00:00.000Z'),
      createdAt: '2026-08-10T00:00:00.000Z',
      updatedAt: '2026-08-10T00:00:00.000Z',
      syncedAt: '2026-08-10T00:01:00.000Z',
    );

    final restored = WeeklyGoal.fromMap(goal.toMap());

    expect(restored.id, 'goal1');
    expect(restored.targetMinutes, 300);
    expect(restored.effectiveFrom, DateTime.parse('2026-08-10T00:00:00.000Z'));
    expect(restored.createdAt, '2026-08-10T00:00:00.000Z');
    expect(restored.updatedAt, '2026-08-10T00:00:00.000Z');
    expect(restored.syncedAt, '2026-08-10T00:01:00.000Z');
  });

  test('toMap uses snake_case keys matching the SQL schema', () {
    final goal = WeeklyGoal(
      id: 'goal1',
      targetMinutes: 300,
      effectiveFrom: DateTime.parse('2026-08-10T00:00:00.000Z'),
      createdAt: '2026-08-10T00:00:00.000Z',
      updatedAt: '2026-08-10T00:00:00.000Z',
    );

    expect(goal.toMap().keys.toSet(), {
      'id', 'target_minutes', 'effective_from', 'created_at',
      'updated_at', 'synced_at',
    });
  });
}
