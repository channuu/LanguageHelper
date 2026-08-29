import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/study_session.dart';

void main() {
  test('toMap/fromMap round-trips all fields', () {
    final session = StudySession(
      id: 'sess1',
      startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
      endedAt: DateTime.parse('2026-08-10T09:30:00.000Z'),
      durationSeconds: 1500,
      savedAt: '2026-08-10T09:30:00.000Z',
      updatedAt: '2026-08-10T09:30:00.000Z',
      syncedAt: '2026-08-10T09:31:00.000Z',
    );

    final restored = StudySession.fromMap(session.toMap());

    expect(restored.id, 'sess1');
    expect(restored.startedAt, DateTime.parse('2026-08-10T09:00:00.000Z'));
    expect(restored.endedAt, DateTime.parse('2026-08-10T09:30:00.000Z'));
    expect(restored.durationSeconds, 1500);
    expect(restored.savedAt, '2026-08-10T09:30:00.000Z');
    expect(restored.updatedAt, '2026-08-10T09:30:00.000Z');
    expect(restored.syncedAt, '2026-08-10T09:31:00.000Z');
  });

  test('toMap uses snake_case keys matching the SQL schema', () {
    final session = StudySession(
      id: 'sess1',
      startedAt: DateTime.parse('2026-08-10T09:00:00.000Z'),
      endedAt: DateTime.parse('2026-08-10T09:30:00.000Z'),
      durationSeconds: 1500,
      savedAt: '2026-08-10T09:30:00.000Z',
      updatedAt: '2026-08-10T09:30:00.000Z',
    );

    final map = session.toMap();

    expect(map.keys.toSet(), {
      'id', 'started_at', 'ended_at', 'duration_seconds', 'saved_at',
      'updated_at', 'synced_at',
    });
  });
}
