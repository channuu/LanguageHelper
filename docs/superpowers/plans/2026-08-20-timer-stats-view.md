# 타이머 통계 모드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "통계"(statistics) mode to the Timer screen — toggled by a top-right icon button — showing a period selector, a total/average summary with bar chart, a month calendar heatmap with a tap-to-select day detail, and study-streak/monthly-activity-rate cards, per Claude Design mockup §1e (2026-08-20 update).

**Architecture:** A new `mobile/lib/features/timer/stats/` module: `stats_calculations.dart` holds pure, fully-unit-tested functions (day grouping, streaks, activity rate, calendar dot tiers) with no widget dependencies; `stats_view.dart` is a `StatefulWidget` that loads a wide window of `StudySession`/`Word`/`Sentence` data once and derives every displayed number from the same in-memory dataset via those pure functions. `timer_screen.dart` gains a small toggle that swaps its existing body for `const StatsView()`.

**Tech Stack:** Flutter/Dart, `provider` for `StudyTimerRepository`/`LearningRepository`, plain `DateTime` math for the calendar grid (no new package dependency), `flutter_test` + `sqflite_common_ffi` no-isolate factory + `shared_preferences` mock for widget tests.

## Global Constraints

- No new pubspec dependencies — the calendar grid is hand-rolled with `DateTime` (spec §2, §7).
- `TimerHistoryView` (the existing 주/월/년 + 그래프/숫자 widget in "타이머" mode) is untouched by this plan — the statistics mode's period selector is a separate, new implementation (spec §3.2, §7).
- `LearningRepository.getWords()`/`getSentences()` take no parameters — any date filtering happens client-side (spec §4, and the project-wide constraint already established in earlier plans on this branch).
- "목표 달성률" is defined as **days-with-any-activity ÷ days-elapsed-so-far in the current month** (NOT a weekly-goal-history calculation) — this is a deliberate reinterpretation documented in spec §3.6, matching the mockup's own example text ("이번 달 18/28일").
- Every test that opens a repository against `inMemoryDatabasePath` MUST call `addTearDown(repo.close)` immediately after construction — `sqflite_common_ffi_no_isolate` caches connections by path, and every prior task on this branch that skipped this leaked DB state across tests (see the ledger/prior fix commits on `feature/timer-redesign`). Do not repeat that mistake.
- Use `Color.withValues(alpha: ...)` (not deprecated `withOpacity`) for any color-with-opacity in new code.

---

### Task 1: Pure calculation functions

**Files:**
- Create: `mobile/lib/features/timer/stats/stats_calculations.dart`
- Test: `mobile/test/features/timer/stats/stats_calculations_test.dart`

**Interfaces:**
- Produces: `Map<DateTime, int> groupSessionsByDay(List<StudySession> sessions)`, `Map<DateTime, int> countSessionsByDay(List<StudySession> sessions)`, `Map<DateTime, int> groupSavesByDay(List<Word> words, List<Sentence> sentences)`, `int currentStreakDays(Map<DateTime, int> dayTotals, {DateTime? today})`, `int longestStreakDays(Map<DateTime, int> dayTotals)`, `({int active, int elapsed}) monthActivityCounts(Map<DateTime, int> dayTotals, DateTime monthStart, DateTime throughDay)`, `double monthlyActivityRate(Map<DateTime, int> dayTotals, DateTime monthStart, DateTime throughDay)`, `int calendarDotTier(int daySeconds, int maxSecondsInMonth)`. Tasks 2-4 import and use all of these.

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/timer/stats/stats_calculations_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/study_session.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/timer/stats/stats_calculations.dart';

StudySession _session(DateTime startedAt, {int durationSeconds = 1800}) => StudySession(
      id: 'id-${startedAt.toIso8601String()}-$durationSeconds',
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSeconds)),
      durationSeconds: durationSeconds,
      savedAt: startedAt.toIso8601String(),
    );

Word _word(String savedAt) => Word(
      id: 'w-$savedAt',
      word: 'x',
      platform: 'youtube',
      contentTitle: 't',
      contentId: 'c',
      timestamp: 0,
      savedAt: savedAt,
    );

Sentence _sentence(String savedAt) => Sentence(
      id: 's-$savedAt',
      original: 'x',
      platform: 'youtube',
      contentTitle: 't',
      contentId: 'c',
      timestamp: 0,
      savedAt: savedAt,
    );

void main() {
  group('groupSessionsByDay', () {
    test('sums durations for the same day and keeps different days separate', () {
      final result = groupSessionsByDay([
        _session(DateTime(2026, 8, 10, 9), durationSeconds: 600),
        _session(DateTime(2026, 8, 10, 20), durationSeconds: 300),
        _session(DateTime(2026, 8, 11, 9), durationSeconds: 100),
      ]);
      expect(result[DateTime(2026, 8, 10)], 900);
      expect(result[DateTime(2026, 8, 11)], 100);
      expect(result.length, 2);
    });
  });

  group('countSessionsByDay', () {
    test('counts rows per day, not summed duration', () {
      final result = countSessionsByDay([
        _session(DateTime(2026, 8, 10, 9)),
        _session(DateTime(2026, 8, 10, 20)),
        _session(DateTime(2026, 8, 11, 9)),
      ]);
      expect(result[DateTime(2026, 8, 10)], 2);
      expect(result[DateTime(2026, 8, 11)], 1);
    });
  });

  group('groupSavesByDay', () {
    test('counts words and sentences together per day', () {
      final result = groupSavesByDay(
        [_word('2026-08-10T09:00:00.000Z'), _word('2026-08-10T20:00:00.000Z')],
        [_sentence('2026-08-10T10:00:00.000Z'), _sentence('2026-08-11T10:00:00.000Z')],
      );
      expect(result[DateTime(2026, 8, 10)], 3);
      expect(result[DateTime(2026, 8, 11)], 1);
    });

    test('skips entries with an empty or unparseable savedAt instead of throwing', () {
      final result = groupSavesByDay([_word('')], [_sentence('not-a-date')]);
      expect(result, isEmpty);
    });
  });

  group('currentStreakDays', () {
    test('counts consecutive days ending today', () {
      final today = DateTime(2026, 8, 15);
      final dayTotals = {
        DateTime(2026, 8, 15): 600,
        DateTime(2026, 8, 14): 600,
        DateTime(2026, 8, 13): 600,
        DateTime(2026, 8, 11): 600, // gap at the 12th breaks the streak before this
      };
      expect(currentStreakDays(dayTotals, today: today), 3);
    });

    test('is 0 when today itself has no activity', () {
      final today = DateTime(2026, 8, 15);
      final dayTotals = {DateTime(2026, 8, 14): 600};
      expect(currentStreakDays(dayTotals, today: today), 0);
    });
  });

  group('longestStreakDays', () {
    test('finds the longest run even if it is not the most recent', () {
      final dayTotals = {
        // A 4-day run early in the month...
        DateTime(2026, 8, 1): 600,
        DateTime(2026, 8, 2): 600,
        DateTime(2026, 8, 3): 600,
        DateTime(2026, 8, 4): 600,
        // ...then a gap, then a shorter 2-day run.
        DateTime(2026, 8, 10): 600,
        DateTime(2026, 8, 11): 600,
      };
      expect(longestStreakDays(dayTotals), 4);
    });

    test('is 0 for no activity at all', () {
      expect(longestStreakDays({}), 0);
    });
  });

  group('monthActivityCounts / monthlyActivityRate', () {
    test('counts active vs elapsed days within the given range', () {
      final dayTotals = {
        DateTime(2026, 8, 1): 600,
        DateTime(2026, 8, 3): 600,
        // day 2 and 4-5 have no activity
      };
      final counts = monthActivityCounts(dayTotals, DateTime(2026, 8, 1), DateTime(2026, 8, 5));
      expect(counts.active, 2);
      expect(counts.elapsed, 5);
      expect(monthlyActivityRate(dayTotals, DateTime(2026, 8, 1), DateTime(2026, 8, 5)), 2 / 5);
    });
  });

  group('calendarDotTier', () {
    test('0 seconds is tier 0 (no dot)', () {
      expect(calendarDotTier(0, 1000), 0);
    });

    test('a day with activity but a month with no recorded max is tier 0 (guards div by zero)', () {
      expect(calendarDotTier(100, 0), 0);
    });

    test('just under one third is tier 1', () {
      expect(calendarDotTier(99, 300), 1);
    });

    test('exactly one third is tier 2', () {
      expect(calendarDotTier(100, 300), 2);
    });

    test('exactly two thirds is tier 2', () {
      expect(calendarDotTier(200, 300), 2);
    });

    test('just over two thirds is tier 3', () {
      expect(calendarDotTier(201, 300), 3);
    });

    test('the max day itself is tier 3', () {
      expect(calendarDotTier(300, 300), 3);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/stats/stats_calculations_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/features/timer/stats/stats_calculations.dart'`

- [ ] **Step 3: Write `stats_calculations.dart`**

Create `mobile/lib/features/timer/stats/stats_calculations.dart`:

```dart
import '../../../data/models/sentence.dart';
import '../../../data/models/study_session.dart';
import '../../../data/models/word.dart';

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Sums [StudySession.durationSeconds] per calendar day (local midnight).
Map<DateTime, int> groupSessionsByDay(List<StudySession> sessions) {
  final map = <DateTime, int>{};
  for (final s in sessions) {
    final day = _dateOnly(s.startedAt);
    map[day] = (map[day] ?? 0) + s.durationSeconds;
  }
  return map;
}

/// Counts session rows (not summed duration) per calendar day.
Map<DateTime, int> countSessionsByDay(List<StudySession> sessions) {
  final map = <DateTime, int>{};
  for (final s in sessions) {
    final day = _dateOnly(s.startedAt);
    map[day] = (map[day] ?? 0) + 1;
  }
  return map;
}

/// Counts saved [Word]s and [Sentence]s together per calendar day, keyed by
/// their `savedAt` field. Entries with an empty or unparseable `savedAt`
/// are skipped rather than thrown — `Word.savedAt`/`Sentence.savedAt`
/// default to `''` when the underlying DB column is missing/null, and an
/// empty string is not a valid ISO8601 date.
Map<DateTime, int> groupSavesByDay(List<Word> words, List<Sentence> sentences) {
  final map = <DateTime, int>{};
  void addAll(Iterable<String> savedAts) {
    for (final raw in savedAts) {
      if (raw.isEmpty) continue;
      DateTime parsed;
      try {
        parsed = DateTime.parse(raw);
      } catch (_) {
        continue;
      }
      final day = _dateOnly(parsed);
      map[day] = (map[day] ?? 0) + 1;
    }
  }

  addAll(words.map((w) => w.savedAt));
  addAll(sentences.map((s) => s.savedAt));
  return map;
}

/// Consecutive days (ending at [today], inclusive) present with a positive
/// value in [dayTotals]. 0 if [today] itself has no activity yet.
int currentStreakDays(Map<DateTime, int> dayTotals, {DateTime? today}) {
  final start = _dateOnly(today ?? DateTime.now());
  var streak = 0;
  var day = start;
  while ((dayTotals[day] ?? 0) > 0) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

/// The longest run of consecutive active days found anywhere in
/// [dayTotals] (not necessarily ending today).
int longestStreakDays(Map<DateTime, int> dayTotals) {
  final activeDays = dayTotals.entries.where((e) => e.value > 0).map((e) => e.key).toList()
    ..sort();
  if (activeDays.isEmpty) return 0;
  var longest = 1;
  var current = 1;
  for (var i = 1; i < activeDays.length; i++) {
    final gap = activeDays[i].difference(activeDays[i - 1]).inDays;
    current = gap == 1 ? current + 1 : 1;
    if (current > longest) longest = current;
  }
  return longest;
}

/// Active-vs-elapsed day counts for [monthStart]..[throughDay] (both
/// inclusive, same-month range expected but not enforced).
({int active, int elapsed}) monthActivityCounts(
  Map<DateTime, int> dayTotals,
  DateTime monthStart,
  DateTime throughDay,
) {
  var elapsed = 0;
  var active = 0;
  var day = _dateOnly(monthStart);
  final end = _dateOnly(throughDay);
  while (!day.isAfter(end)) {
    elapsed++;
    if ((dayTotals[day] ?? 0) > 0) active++;
    day = day.add(const Duration(days: 1));
  }
  return (active: active, elapsed: elapsed);
}

/// `active / elapsed` from [monthActivityCounts], or 0 if elapsed is 0.
double monthlyActivityRate(Map<DateTime, int> dayTotals, DateTime monthStart, DateTime throughDay) {
  final counts = monthActivityCounts(dayTotals, monthStart, throughDay);
  if (counts.elapsed == 0) return 0;
  return counts.active / counts.elapsed;
}

/// 0 (no dot) / 1 (small) / 2 (medium) / 3 (large) calendar-cell dot tier
/// for a day with [daySeconds] of activity, relative to [maxSecondsInMonth]
/// (the busiest day in the displayed month). Thresholds: <1/3 → 1,
/// 1/3..2/3 inclusive → 2, >2/3 → 3.
int calendarDotTier(int daySeconds, int maxSecondsInMonth) {
  if (daySeconds <= 0 || maxSecondsInMonth <= 0) return 0;
  final fraction = daySeconds / maxSecondsInMonth;
  if (fraction > 2 / 3) return 3;
  if (fraction >= 1 / 3) return 2;
  return 1;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/features/timer/stats/stats_calculations_test.dart`
Expected: PASS (17 tests)

- [ ] **Step 5: Commit**

```bash
cd mobile
git add lib/features/timer/stats/stats_calculations.dart test/features/timer/stats/stats_calculations_test.dart
git commit -m "feat: add pure calculation functions for timer stats view"
```

---

### Task 2: Mode toggle, period selector, and summary bar chart

**Files:**
- Create: `mobile/lib/features/timer/stats/stats_view.dart`
- Test: `mobile/test/features/timer/stats/stats_view_test.dart`
- Modify: `mobile/lib/features/timer/timer_screen.dart`
- Test: `mobile/test/features/timer/timer_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `groupSessionsByDay`, `countSessionsByDay`, `groupSavesByDay` from `stats_calculations.dart` (Task 1). `StudyTimerRepository.getSessionsBetween`, `mondayOf` from `mobile/lib/data/study_timer_repository.dart` (existing, unchanged). `LearningRepository.getWords`/`getSentences` from `mobile/lib/data/repository.dart` (existing, unchanged). `AppColors`/`AppFonts`.
- Produces: `class StatsView extends StatefulWidget` with a no-arg const constructor (`const StatsView({super.key})`). `enum StatsPeriod { week, month, year }` (top-level in `stats_view.dart`). Task 3 and Task 4 both add more `build()` content and more loaded state to this same `_StatsViewState` class.

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/timer/stats/stats_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/repository.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/stats/stats_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  Widget buildView(LearningRepository learningRepo, StudyTimerRepository timerRepo) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningRepository>.value(value: learningRepo),
        ChangeNotifierProvider<StudyTimerRepository>.value(value: timerRepo),
      ],
      child: const MaterialApp(home: Scaffold(body: StatsView())),
    );
  }

  testWidgets('shows 주간/월간/년간 period selector and defaults to 주간', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('주간'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);
    expect(find.text('년간'), findsOneWidget);
    expect(find.text('이번 주'), findsOneWidget);
  });

  testWidgets('summary total reflects sessions in the selected period', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    // Two sessions on two different days, so total (2:00) and average
    // (1:00, since there are 2 active days) are distinct values — with
    // only a single active day, average always equals total (average =
    // total / activeDays = total / 1), which would make this assertion
    // ambiguous regardless of the chosen duration.
    final monday = mondayOf(DateTime.now());
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 10, minutes: 30)).toIso8601String(),
      'duration_seconds': 5400,
      'saved_at': monday.add(const Duration(hours: 10, minutes: 30)).toIso8601String(),
    });
    await db.insert('study_sessions', {
      'id': 's2',
      'started_at': monday.add(const Duration(days: 1, hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(days: 1, hours: 9, minutes: 30)).toIso8601String(),
      'duration_seconds': 1800,
      'saved_at': monday.add(const Duration(days: 1, hours: 9, minutes: 30)).toIso8601String(),
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('2:00'), findsOneWidget); // total
    expect(find.text('1:00'), findsOneWidget); // average (7200s / 2 active days)
  });

  testWidgets('switching to 월간 changes the scope label', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final timerRepo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(timerRepo.close);

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('월간'));
    await tester.pumpAndSettle();

    expect(find.text('이번 달'), findsOneWidget);
    expect(find.text('이번 주'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/features/timer/stats/stats_view.dart'`

- [ ] **Step 3: Write `stats_view.dart`**

Create `mobile/lib/features/timer/stats/stats_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repository.dart';
import '../../../data/study_timer_repository.dart';
import '../../../theme/app_theme.dart';
import 'stats_calculations.dart';

enum StatsPeriod { week, month, year }

class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  StatsPeriod _period = StatsPeriod.week;
  bool _loaded = false;
  Map<DateTime, int> _dayTotals = {};
  Map<DateTime, int> _sessionCounts = {};
  Map<DateTime, int> _saveDayTotals = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timerRepo = context.read<StudyTimerRepository>();
    final learningRepo = context.read<LearningRepository>();
    final now = DateTime.now();
    // A wide window so streaks/calendar navigation have real history to
    // work with, without querying "all time".
    final start = now.subtract(const Duration(days: 400));
    final end = now.add(const Duration(days: 1));
    final sessions = await timerRepo.getSessionsBetween(start, end);
    final words = await learningRepo.getWords();
    final sentences = await learningRepo.getSentences();
    if (!mounted) return;
    setState(() {
      _dayTotals = groupSessionsByDay(sessions);
      _sessionCounts = countSessionsByDay(sessions);
      _saveDayTotals = groupSavesByDay(words, sentences);
      _loaded = true;
    });
  }

  String _formatHM(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  ({DateTime start, DateTime end, String scopeLabel}) _rangeFor(StatsPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case StatsPeriod.week:
        final start = mondayOf(now);
        return (start: start, end: start.add(const Duration(days: 7)), scopeLabel: '이번 주');
      case StatsPeriod.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start: start, end: end, scopeLabel: '이번 달');
      case StatsPeriod.year:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);
        return (start: start, end: end, scopeLabel: '올해');
    }
  }

  List<({String label, int seconds, bool isCurrent})> _bars(StatsPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case StatsPeriod.week:
        final monday = mondayOf(now);
        const labels = ['월', '화', '수', '목', '금', '토', '일'];
        return [
          for (var i = 0; i < 7; i++)
            (
              label: labels[i],
              seconds: _dayTotals[monday.add(Duration(days: i))] ?? 0,
              isCurrent: monday.add(Duration(days: i)) == today,
            ),
        ];
      case StatsPeriod.month:
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final weekCount = (daysInMonth / 7).ceil();
        final result = <({String label, int seconds, bool isCurrent})>[];
        for (var w = 0; w < weekCount; w++) {
          var total = 0;
          var containsToday = false;
          for (var d = w * 7 + 1; d <= (w + 1) * 7 && d <= daysInMonth; d++) {
            final day = DateTime(now.year, now.month, d);
            total += _dayTotals[day] ?? 0;
            if (day == today) containsToday = true;
          }
          result.add((label: '${w + 1}주', seconds: total, isCurrent: containsToday));
        }
        return result;
      case StatsPeriod.year:
        const labels = ['1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'];
        final result = <({String label, int seconds, bool isCurrent})>[];
        for (var m = 1; m <= 12; m++) {
          var total = 0;
          final daysInM = DateTime(now.year, m + 1, 0).day;
          for (var d = 1; d <= daysInM; d++) {
            total += _dayTotals[DateTime(now.year, m, d)] ?? 0;
          }
          result.add((label: labels[m - 1], seconds: total, isCurrent: m == now.month));
        }
        return result;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final range = _rangeFor(_period);
    final bars = _bars(_period);
    final totalSeconds = bars.fold<int>(0, (sum, b) => sum + b.seconds);
    final counts = monthActivityCounts(_dayTotals, range.start, range.end.subtract(const Duration(days: 1)));
    final avgSeconds = counts.active == 0 ? 0 : totalSeconds ~/ counts.active;
    final maxBarSeconds = bars.fold<int>(0, (m, b) => b.seconds > m ? b.seconds : m);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFFE9ECF3), borderRadius: BorderRadius.circular(11)),
            child: Row(
              children: [
                Expanded(child: _periodSegment('주간', StatsPeriod.week)),
                Expanded(child: _periodSegment('월간', StatsPeriod.month)),
                Expanded(child: _periodSegment('년간', StatsPeriod.year)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          range.scopeLabel,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: AppColors.inkQuaternary,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _formatHM(totalSeconds),
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontWeight: FontWeight.w600,
                            fontSize: 34,
                            letterSpacing: -0.02,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('활동일 평균', style: TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary)),
                        const SizedBox(height: 5),
                        Text(
                          _formatHM(avgSeconds),
                          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13.5, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 104,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < bars.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                            child: _StatsBarColumn(bar: bars[i], maxSeconds: maxBarSeconds),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.only(top: 13),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F2F7)))),
                  child: const Text('최근 구간 기준', style: TextStyle(fontSize: 11.5, color: AppColors.inkTertiary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodSegment(String label, StatsPeriod value) {
    final selected = _period == value;
    return GestureDetector(
      onTap: () => setState(() => _period = value),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            color: selected ? AppColors.ink : AppColors.inkTertiary,
          ),
        ),
      ),
    );
  }
}

class _StatsBarColumn extends StatelessWidget {
  final ({String label, int seconds, bool isCurrent}) bar;
  final int maxSeconds;
  const _StatsBarColumn({required this.bar, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final fraction = maxSeconds == 0 ? 0.0 : (bar.seconds / maxSeconds).clamp(0.0, 1.0);
    final color = bar.seconds == 0
        ? const Color(0xFFF0F2F7)
        : (bar.isCurrent ? AppColors.accent : const Color(0xFFFFBC8F));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 78,
          decoration: BoxDecoration(color: const Color(0xFFF0F2F7), borderRadius: BorderRadius.circular(5)),
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: fraction,
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          bar.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: bar.isCurrent ? AppColors.ink : AppColors.inkQuaternary,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Write the failing test for the mode toggle in `timer_screen.dart`**

Append to `mobile/test/features/timer/timer_screen_test.dart` (before the file's closing `}`):

```dart
  testWidgets('tapping the stats toggle switches from 학습 타이머 to 통계 and back', (tester) async {
    final repo = LocalStudyTimerRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(repo.close);
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    expect(find.text('학습 타이머'), findsOneWidget);
    expect(find.text('통계'), findsNothing);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await settleOnce(tester);
    await settleOnce(tester);

    expect(find.text('통계'), findsOneWidget);
    expect(find.text('학습 타이머'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await settleOnce(tester);

    expect(find.text('학습 타이머'), findsOneWidget);
  });
```

Note: `buildScreen` in this test file only provides a `StudyTimerRepository` (see the file's existing `buildScreen` helper) — but `StatsView` (used once stats mode is on) also needs a `LearningRepository` in its widget tree via `context.read<LearningRepository>()`. Update the file's existing `buildScreen` helper to also provide one:

Find:
```dart
  Widget buildScreen(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: TimerScreen()),
    );
  }
```

Replace with:
```dart
  Widget buildScreen(StudyTimerRepository repo, {LearningRepository? learningRepo}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StudyTimerRepository>.value(value: repo),
        ChangeNotifierProvider<LearningRepository>.value(
          value: learningRepo ?? LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath)),
        ),
      ],
      child: const MaterialApp(home: TimerScreen()),
    );
  }
```

Add the missing import at the top of the file:

```dart
import 'package:english_helper_app/data/repository.dart';
```

(`MultiProvider` comes from `package:provider/provider.dart`, already imported in this file.)

- [ ] **Step 6: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/timer_screen_test.dart`
Expected: FAIL — no stats toggle icon exists yet in `timer_screen.dart`.

- [ ] **Step 7: Wire the toggle into `timer_screen.dart`**

In `mobile/lib/features/timer/timer_screen.dart`, add imports at the top:

```dart
import 'stats/stats_view.dart';
```

Add a new state field to `_TimerScreenState` (alongside the existing fields):

```dart
  bool _statsMode = false;
```

Replace the `build` method's `return Scaffold(...)` (everything from `return Scaffold(` to the matching closing `);` before the class's closing `}`) with:

```dart
    return Scaffold(
      appBar: AppBar(title: const Text('타이머')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _statsMode ? '통계' : '학습 타이머',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                _StatsToggleButton(
                  statsMode: _statsMode,
                  onTap: () => setState(() => _statsMode = !_statsMode),
                ),
              ],
            ),
          ),
          Expanded(
            child: _statsMode
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: StatsView(),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            if (active != null) ...[
                              _StatusPill(isPaused: active.isPaused),
                              const SizedBox(height: 14),
                            ],
                            Text(
                              _format(active?.elapsedSeconds() ?? _displaySeconds),
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
                                fontWeight: FontWeight.w600,
                                fontSize: 56,
                                letterSpacing: -0.02,
                                color: AppColors.ink,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '오늘 누적 ${_formatHoursMinutesKorean(_todayTotalSeconds)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.inkQuaternary),
                            ),
                            const SizedBox(height: 22),
                            Row(children: _buildButtons(repo, active)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const WeeklyGoalCard(),
                      const SizedBox(height: 14),
                      const RecentSessionsCard(),
                      const SizedBox(height: 24),
                      const TimerHistoryView(),
                    ],
                  ),
          ),
        ],
      ),
    );
```

(This is the same content as before, just moved: the "학습 타이머" title is now in the new header `Row` instead of being the `ListView`'s first child, and the whole prior `ListView` is now the `else` branch of a ternary inside an `Expanded`.)

Add the `_StatsToggleButton` widget at the end of the file (after `_StatusPill`):

```dart
class _StatsToggleButton extends StatelessWidget {
  final bool statsMode;
  final VoidCallback onTap;
  const _StatsToggleButton({required this.statsMode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: statsMode ? AppColors.accent : Colors.white,
          border: Border.all(color: statsMode ? Colors.transparent : AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(
          statsMode ? Icons.close : Icons.calendar_month_outlined,
          size: 19,
          color: statsMode ? AppColors.ink : AppColors.inkSecondary,
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/`
Expected: PASS (all files, including the new toggle test)

- [ ] **Step 9: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 10: Commit**

```bash
cd mobile
git add lib/features/timer/stats/stats_view.dart lib/features/timer/timer_screen.dart \
  test/features/timer/stats/stats_view_test.dart test/features/timer/timer_screen_test.dart
git commit -m "feat: add stats mode toggle with period selector and summary bar chart"
```

---

### Task 3: Calendar heatmap and day-detail panel

**Files:**
- Modify: `mobile/lib/features/timer/stats/stats_view.dart`
- Test: `mobile/test/features/timer/stats/stats_view_test.dart` (extend)

**Interfaces:**
- Consumes: `calendarDotTier(int, int) -> int` from `stats_calculations.dart` (Task 1). `_StatsViewState`'s existing `_dayTotals`/`_sessionCounts`/`_saveDayTotals`/`_load()` (Task 2, this task doesn't change `_load()`'s query, just adds two new local UI-state fields).
- Produces: no new public API — this task only adds to `StatsView`'s rendered content and `_StatsViewState`'s private fields (`_calendarMonth`, `_selectedDay`). Task 4 reads `_dayTotals` the same way this task does.

- [ ] **Step 1: Write the failing tests**

Append to `mobile/test/features/timer/stats/stats_view_test.dart` (before the file's closing `}`):

```dart
  testWidgets('calendar shows a dot only for days with recorded activity', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': today.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': today.add(const Duration(hours: 9, minutes: 30)).toIso8601String(),
      'duration_seconds': 1800,
      'saved_at': today.add(const Duration(hours: 9, minutes: 30)).toIso8601String(),
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('${today.day}'), findsOneWidget);
    // Month navigation header is present.
    expect(find.text('‹'), findsOneWidget);
    expect(find.text('›'), findsOneWidget);
  });

  testWidgets('tapping a calendar day updates the day-detail panel', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    // Pick a day earlier in the month than today, so it's guaranteed to be
    // a distinct, already-elapsed day regardless of what "today" is.
    final targetDay = DateTime(now.year, now.month, 1);
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': targetDay.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
      'duration_seconds': 2700,
      'saved_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
    });
    await db.insert('words', {
      'id': 'w1', 'word': 'ephemeral', 'platform': 'youtube',
      'content_title': 't', 'content_id': 'c', 'timestamp': 0,
      'saved_at': targetDay.add(const Duration(hours: 9, minutes: 45)).toIso8601String(),
      'review_level': 0,
    });

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    expect(find.text('0:45'), findsOneWidget); // 학습 시간
    expect(find.text('1'), findsWidgets); // 세션 count and/or 저장 count both show "1"
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: FAIL — no calendar grid or day-detail panel exists yet.

- [ ] **Step 3: Add the calendar and day-detail sections**

In `mobile/lib/features/timer/stats/stats_view.dart`, add two new fields to `_StatsViewState` (alongside the existing ones):

```dart
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
```

Add two navigation methods and a cell-list builder to `_StatsViewState`:

```dart
  void _prevMonth() {
    setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1));
  }

  void _nextMonth() {
    setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1));
  }

  List<DateTime?> _calendarCells() {
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final leadingBlanks = _calendarMonth.weekday - 1; // Monday=1 -> 0 blanks
    return [
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(_calendarMonth.year, _calendarMonth.month, d),
    ];
  }

  int _maxSecondsInCalendarMonth() {
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    var max = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final seconds = _dayTotals[DateTime(_calendarMonth.year, _calendarMonth.month, d)] ?? 0;
      if (seconds > max) max = seconds;
    }
    return max;
  }
```

In `build()`, add the calendar card and day-detail card right after the summary card's closing `),` (i.e., as additional children of the outer `Column` in the `SingleChildScrollView`, after the summary `Container`):

```dart
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _prevMonth,
                      child: const SizedBox(width: 28, height: 28, child: Icon(Icons.chevron_left, size: 18, color: AppColors.inkTertiary)),
                    ),
                    Expanded(
                      child: Text(
                        '${_calendarMonth.year}년 ${_calendarMonth.month}월',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    GestureDetector(
                      onTap: _nextMonth,
                      child: const SizedBox(width: 28, height: 28, child: Icon(Icons.chevron_right, size: 18, color: AppColors.inkTertiary)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  children: [
                    for (final label in const ['월', '화', '수', '목', '금', '토', '일'])
                      Center(
                        child: Text(
                          label,
                          style: const TextStyle(fontFamily: AppFonts.mono, fontWeight: FontWeight.w600, fontSize: 10, color: AppColors.inkFaint),
                        ),
                      ),
                    for (final cell in _calendarCells())
                      cell == null
                          ? const SizedBox.shrink()
                          : _CalendarCell(
                              day: cell,
                              selected: cell == _selectedDay,
                              isToday: cell == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                              dotTier: calendarDotTier(_dayTotals[cell] ?? 0, _maxSecondsInCalendarMonth()),
                              onTap: () => setState(() => _selectedDay = cell),
                            ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.only(top: 13),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F2F7)))),
                  child: const Text('칸을 눌러 그날 기록을 봅니다', style: TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedDay.month}월 ${_selectedDay.day}일',
                  style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: AppColors.inkQuaternary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _DayStat(label: '학습 시간', value: _formatHM(_dayTotals[_selectedDay] ?? 0))),
                    Container(width: 1, height: 36, color: const Color(0xFFF0F2F7)),
                    Expanded(child: _DayStat(label: '세션', value: '${_sessionCounts[_selectedDay] ?? 0}')),
                    Container(width: 1, height: 36, color: const Color(0xFFF0F2F7)),
                    Expanded(child: _DayStat(label: '저장', value: '${_saveDayTotals[_selectedDay] ?? 0}')),
                  ],
                ),
              ],
            ),
          ),
```

Add three small widgets at the end of the file:

```dart
class _CalendarCell extends StatelessWidget {
  final DateTime day;
  final bool selected;
  final bool isToday;
  final int dotTier;
  final VoidCallback onTap;

  const _CalendarCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dotTier,
    required this.onTap,
  });

  static const _dotColors = [null, Color(0xFFFACCB7), Color(0xFFFEA47C), Color(0xFFFB864D)];
  static const _dotWidths = [0.0, 11.0, 15.0, 19.0];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTint : Colors.white,
          border: Border.all(color: selected ? AppColors.accent : const Color(0xFFE7EAF1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11.5,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 3,
              width: _dotWidths[dotTier],
              child: dotTier == 0
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(color: _dotColors[dotTier], borderRadius: BorderRadius.circular(2)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayStat extends StatelessWidget {
  final String label;
  final String value;
  const _DayStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 19)),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/timer/stats/stats_view.dart test/features/timer/stats/stats_view_test.dart
git commit -m "feat: add calendar heatmap and day-detail panel to stats view"
```

---

### Task 4: Streak and monthly-activity-rate cards

**Files:**
- Modify: `mobile/lib/features/timer/stats/stats_view.dart`
- Test: `mobile/test/features/timer/stats/stats_view_test.dart` (extend)

**Interfaces:**
- Consumes: `currentStreakDays`, `longestStreakDays`, `monthActivityCounts` from `stats_calculations.dart` (Task 1). `_StatsViewState`'s `_dayTotals` (Task 2).
- Produces: nothing further consumed by other tasks — this is the final task of the plan.

- [ ] **Step 1: Write the failing test**

Append to `mobile/test/features/timer/stats/stats_view_test.dart` (before the file's closing `}`):

```dart
  testWidgets('shows current streak and monthly activity rate', (tester) async {
    final learningRepo = LocalSQLiteRepository(openDb: () => openAppDatabase(inMemoryDatabasePath));
    addTearDown(learningRepo.close);
    final db = await openAppDatabase(inMemoryDatabasePath);
    final timerRepo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(timerRepo.close);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // A 2-day streak: today and yesterday.
    for (final offset in [0, 1]) {
      final day = today.subtract(Duration(days: offset));
      await db.insert('study_sessions', {
        'id': 'streak-$offset',
        'started_at': day.add(const Duration(hours: 9)).toIso8601String(),
        'ended_at': day.add(const Duration(hours: 9, minutes: 10)).toIso8601String(),
        'duration_seconds': 600,
        'saved_at': day.add(const Duration(hours: 9, minutes: 10)).toIso8601String(),
      });
    }

    await tester.pumpWidget(buildView(learningRepo, timerRepo));
    await tester.pumpAndSettle();

    expect(find.text('연속 학습'), findsOneWidget);
    expect(find.text('2일'), findsOneWidget);
    expect(find.text('목표 달성률'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: FAIL — no streak/achievement cards exist yet.

- [ ] **Step 3: Add the streak and achievement-rate cards**

In `mobile/lib/features/timer/stats/stats_view.dart`, add the two cards to `build()` as the last children of the outer `Column`, right after the day-detail `Container` added in Task 3 (before the `SingleChildScrollView`'s closing):

```dart
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: '연속 학습',
                  value: '${currentStreakDays(_dayTotals)}일',
                  footnote: '최장 ${longestStreakDays(_dayTotals)}일',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Builder(builder: (context) {
                  final now = DateTime.now();
                  final counts = monthActivityCounts(
                    _dayTotals,
                    DateTime(now.year, now.month, 1),
                    DateTime(now.year, now.month, now.day),
                  );
                  final rate = counts.elapsed == 0 ? 0 : (counts.active / counts.elapsed * 100).round();
                  return _MetricCard(
                    label: '목표 달성률',
                    value: '$rate%',
                    footnote: '이번 달 ${counts.active}/${counts.elapsed}일',
                  );
                }),
              ),
            ],
          ),
```

Add the `_MetricCard` widget at the end of the file:

```dart
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String footnote;
  const _MetricCard({required this.label, required this.value, required this.footnote});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 22)),
          const SizedBox(height: 4),
          Text(footnote, style: const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/stats/stats_view_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes.

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/timer/stats/stats_view.dart test/features/timer/stats/stats_view_test.dart
git commit -m "feat: add streak and monthly activity-rate cards to stats view"
```

---

## Self-Review Notes

- **Spec coverage:** §3.1 (mode toggle) → Task 2. §3.2 (period selector) → Task 2. §3.3 (summary card: total/average/bar chart) → Task 2. §3.4 (calendar heatmap, 3-tier dots) → Task 3. §3.5 (day detail: time/session/save counts) → Task 3. §3.6 (streak + activity-rate, redefined per spec's own reasoning) → Task 4. §4 (data flow: both repositories via the same `MultiProvider`, client-side aggregation, no repository interface changes) → Task 2's `_load()`. §5 (error handling: zero-activity periods render "0:00"/no dots without crashing) → covered by `calendarDotTier`'s `<= 0` guard (Task 1) and `avgSeconds`'s `counts.active == 0 ? 0 : ...` guard (Task 2). §6 (all listed test cases) → distributed across Tasks 1-4. §7 (out of scope: no new deps, no delta calculation, no weekly-goal-history achievement metric, `TimerHistoryView` untouched) → confirmed: no `pubspec.yaml` changes in any task, no `statDelta`-equivalent implemented, achievement rate uses the day-activity-ratio definition only, no task touches `timer_history_view.dart`.
- **Placeholder scan:** none found — every step has literal code and exact commands.
- **Type consistency:** `Map<DateTime, int>` is the consistent return type for all three grouping functions (`groupSessionsByDay`, `countSessionsByDay`, `groupSavesByDay`) across Task 1's definitions and every call site in Tasks 2-4. `calendarDotTier(int, int) -> int` (0-3) matches between Task 1's definition and Task 3's `_CalendarCell` usage (`_dotColors`/`_dotWidths` arrays are both length 4, indices 0-3). `({int active, int elapsed})` record shape from `monthActivityCounts` is destructured identically (`.active`, `.elapsed`) in both Task 2 (average calculation) and Task 4 (achievement rate) — same field names, no drift.
- **Cross-task file ownership:** `stats_view.dart` is created in Task 2 and extended by Tasks 3 and 4 in sequence — each task's steps assume the previous task's version is already in place (Task 3 inserts new children into `build()`'s existing `Column`; Task 4 does the same). Dispatch these three tasks in strict order (2 → 3 → 4); Task 1 has no dependency on the others and could in principle run in parallel, but this plan dispatches it first since Tasks 2-4 all import from it.
- **DB-isolation discipline:** every new test that opens `inMemoryDatabasePath` (Tasks 2-4's `stats_view_test.dart` additions, and Task 2's `timer_screen_test.dart` addition) calls `addTearDown(repo.close)` on both the `LearningRepository` and `StudyTimerRepository` it constructs — this was a recurring omission on earlier plans on this same branch and is called out explicitly in Global Constraints so it isn't repeated a fourth time.
