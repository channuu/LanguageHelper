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
      final ended = started.add(const Duration(minutes: 30));
      await db.insert('study_sessions', {
        'id': 'session-$i',
        'started_at': started.toIso8601String(),
        'ended_at': ended.toIso8601String(),
        'duration_seconds': 1800,
        'saved_at': ended.toIso8601String(),
      });
    }

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.text('RECENT SESSIONS'), findsOneWidget);
    // Capped at 5, and every seeded session is 30 minutes.
    expect(find.text('30분'), findsNWidgets(5));
  });
}
