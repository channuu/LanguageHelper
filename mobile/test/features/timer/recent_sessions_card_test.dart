import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/recent_sessions_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildCard(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: Scaffold(body: RecentSessionsCard())),
    );
  }

  testWidgets('renders nothing when there are no sessions', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.text('RECENT SESSIONS'), findsNothing);
  });

  testWidgets('shows the most recent sessions first, capped at 5', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);

    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final started = now.subtract(Duration(days: i, hours: 1));
      final durationMinutes = 10 + i * 10; // i=0 (most recent) -> 10, i=6 (oldest) -> 70
      final ended = started.add(Duration(minutes: durationMinutes));
      await db.insert('study_sessions', {
        'id': 'session-$i',
        'started_at': started.toIso8601String(),
        'ended_at': ended.toIso8601String(),
        'duration_seconds': durationMinutes * 60,
        'saved_at': ended.toIso8601String(),
      });
    }

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.text('RECENT SESSIONS'), findsOneWidget);
    // The 5 most recent sessions (i=0..4) must be shown.
    for (final minutes in [10, 20, 30, 40, 50]) {
      expect(find.text('$minutes분'), findsOneWidget);
    }
    // The 2 oldest sessions (i=5,6) must NOT be shown. This is the assertion
    // that actually catches a reversed-order regression (a bug that shows
    // the oldest 5 instead of the newest 5 would make these appear instead
    // of two of the durations above).
    for (final minutes in [60, 70]) {
      expect(find.text('$minutes분'), findsNothing);
    }
  });
}
