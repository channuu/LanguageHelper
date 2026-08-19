# 타이머 재설계(1e) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Flutter app's Timer screen (status pill, clock, buttons, weekly goal bar chart, history view) to match Claude Design mockup §1e, and add a new "최근 세션" (recent sessions) list — with no repository or schema changes.

**Architecture:** Pure UI layer changes on top of the existing `StudyTimerRepository`/`ActiveSessionState`/`StudySession`/`WeeklyGoal` models (all unchanged). Four independent widget-level tasks: the timer card itself, the weekly-goal card's bar chart, a new recent-sessions card, and a light restyle of the existing history view.

**Tech Stack:** Flutter/Dart, `provider` for `StudyTimerRepository`, `fl_chart` (already a dependency, used by `TimerHistoryView`), `flutter_test` + `sqflite_common_ffi` no-isolate factory + `shared_preferences` mock for widget tests.

## Global Constraints

- No changes to `StudyTimerRepository`, `LocalStudyTimerRepository`, `ActiveSessionState`, `StudySession`, `WeeklyGoal`, or the DB schema — this is a UI-only plan (spec §2, §6).
- Button labels stay exactly `시작`/`일시정지`/`재개`/`종료` (spec §3.3) — existing tests assert these literal strings; do not rename them.
- `TimerHistoryView`'s existing 주간/월간/년간 + 그래프/숫자 toggle functionality must NOT be removed (spec §2, §6) — restyle only.
- `mobile/test/features/timer/timer_screen_test.dart` never calls `tester.pumpAndSettle()` — `TimerScreen` starts a `Timer.periodic` that never stops on its own, so `pumpAndSettle()` hangs. Any new test in that file must reuse the file's existing bounded `settleOnce()` helper instead (see Task 1 for the exact helper).
- Use `Color.withValues(alpha: ...)` (not deprecated `withOpacity`) for any color-with-opacity in new code.

---

### Task 1: Timer card restyle

**Files:**
- Modify: `mobile/lib/features/timer/timer_screen.dart` (full rewrite)
- Test: `mobile/test/features/timer/timer_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `AppColors`/`AppFonts` from `mobile/lib/theme/app_theme.dart` (already on this branch). `StudyTimerRepository.getSessionsBetween(DateTime, DateTime) -> Future<List<StudySession>>` (existing, unchanged).
- Produces: `TimerScreen` keeps its existing no-arg const constructor — no other file needs to change to keep using `const TimerScreen()` in `app.dart`.

- [ ] **Step 1: Write the failing test**

Append to `mobile/test/features/timer/timer_screen_test.dart` (before the file's closing `}`):

```dart
  testWidgets('shows today\'s accumulated total, excluding the running session', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // A completed session earlier today: 25 minutes.
    await db.insert('study_sessions', {
      'id': 'today-1',
      'started_at': todayStart.add(const Duration(hours: 1)).toIso8601String(),
      'ended_at': todayStart.add(const Duration(hours: 1, minutes: 25)).toIso8601String(),
      'duration_seconds': 1500,
      'saved_at': todayStart.add(const Duration(hours: 1, minutes: 25)).toIso8601String(),
    });
    // A session from yesterday must not count.
    final yesterday = todayStart.subtract(const Duration(days: 1));
    await db.insert('study_sessions', {
      'id': 'yesterday-1',
      'started_at': yesterday.add(const Duration(hours: 1)).toIso8601String(),
      'ended_at': yesterday.add(const Duration(hours: 1, minutes: 40)).toIso8601String(),
      'duration_seconds': 2400,
      'saved_at': yesterday.add(const Duration(hours: 1, minutes: 40)).toIso8601String(),
    });

    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);
    await settleOnce(tester); // second pass: lets the async _loadTodayTotal() land

    expect(find.textContaining('오늘 누적 0시간 25분'), findsOneWidget);
  });

  testWidgets('status pill shows 학습 중 while running and 일시정지 while paused', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    await tester.pumpWidget(buildScreen(repo));
    await settleOnce(tester);

    // No active session: no pill at all.
    expect(find.text('학습 중'), findsNothing);

    await tester.tap(find.text('시작'));
    await settleOnce(tester);
    expect(find.text('학습 중'), findsOneWidget);

    await tester.tap(find.text('일시정지'));
    await settleOnce(tester);
    expect(find.text('학습 중'), findsNothing);
    // The pill's own label reads 일시정지 too (same string as the button),
    // so at least one 일시정지 text now exists in addition to the button.
    expect(find.text('일시정지'), findsWidgets);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/timer_screen_test.dart`
Expected: FAIL — `find.textContaining('오늘 누적 0시간 25분')` finds nothing (current screen shows a hardcoded old format or nothing at all), and the pill assertions fail (no such widget exists yet).

- [ ] **Step 3: Rewrite `timer_screen.dart`**

Replace the full contents of `mobile/lib/features/timer/timer_screen.dart`:

```dart
// mobile/lib/features/timer/timer_screen.dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/active_session_state.dart';
import '../../data/study_timer_repository.dart';
import '../../theme/app_theme.dart';
import 'recent_sessions_card.dart';
import 'timer_history_view.dart';
import 'weekly_goal_card.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _ticker;
  int _displaySeconds = 0;
  bool _loaded = false;
  int _todayTotalSeconds = 0;
  StudyTimerRepository? _repo;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<StudyTimerRepository>();
    if (!identical(repo, _repo)) {
      _repo?.removeListener(_onRepoChanged);
      _repo = repo;
      repo.addListener(_onRepoChanged);
    }
  }

  Future<void> _init() async {
    // load() restores a persisted active session (e.g. the app was killed
    // mid-session) — activeSession is a sync getter and won't do this on
    // its own, so this must run before the first _tick().
    await context.read<StudyTimerRepository>().load();
    if (!mounted) return;
    setState(() => _loaded = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
    await _loadTodayTotal();
  }

  void _onRepoChanged() {
    // A session ending (or starting elsewhere) changes today's total.
    _loadTodayTotal();
  }

  Future<void> _loadTodayTotal() async {
    final repo = context.read<StudyTimerRepository>();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final sessions = await repo.getSessionsBetween(
      todayStart,
      todayStart.add(const Duration(days: 1)),
    );
    final total = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    if (!mounted) return;
    setState(() => _todayTotalSeconds = total);
  }

  void _tick() {
    if (!mounted) return;
    final active = context.read<StudyTimerRepository>().activeSession;
    setState(() => _displaySeconds = active?.elapsedSeconds() ?? 0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _repo?.removeListener(_onRepoChanged);
    super.dispose();
  }

  String _format(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatHoursMinutesKorean(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return '$h시간 $m분';
  }

  List<Widget> _buildButtons(StudyTimerRepository repo, ActiveSessionState? active) {
    if (active == null) {
      return [
        Expanded(
          child: ElevatedButton(
            onPressed: () => repo.startSession(),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('시작'),
          ),
        ),
      ];
    }
    final toggle = active.isPaused
        ? ElevatedButton(
            onPressed: () => repo.resumeSession(),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('재개'),
          )
        : ElevatedButton(
            onPressed: () => repo.pauseSession(),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('일시정지'),
          );
    return [
      Expanded(child: toggle),
      const SizedBox(width: 10),
      SizedBox(
        width: 104,
        height: 50,
        child: OutlinedButton(
          onPressed: () => repo.endSession(),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.borderStrong),
            foregroundColor: AppColors.inkSecondary,
          ),
          child: const Text('종료'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repo = context.watch<StudyTimerRepository>();
    final active = repo.activeSession;

    return Scaffold(
      appBar: AppBar(title: const Text('타이머')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('학습 타이머', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 16),
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
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isPaused;
  const _StatusPill({required this.isPaused});

  @override
  Widget build(BuildContext context) {
    // The mockup's running-state dot color is identical to the pill's own
    // background (both oklch(0.74 0.16 45)), which would render invisible —
    // an apparent mockup oversight. Using ink for the dot keeps it visible
    // while staying on the same "running = accent, paused = neutral" idea.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: isPaused ? const Color(0xFFF0F2F7) : AppColors.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isPaused ? const Color(0xFFBEC5D3) : AppColors.ink,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isPaused ? '일시정지' : '학습 중',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              color: isPaused ? AppColors.inkTertiary : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: this rewrite imports `recent_sessions_card.dart`, which Task 3 creates. If you're executing tasks in order, Task 3 hasn't run yet — that's fine, `RecentSessionsCard` won't exist until Task 3 lands, and this task's own tests don't reference it directly, but **the file won't compile until Task 3 exists**. Implementers: if you hit "`RecentSessionsCard` isn't defined" while working this task in isolation, that's expected — proceed with your task's steps and tests as written; the plan's task order (1 → 2 → 3 → 4) resolves it, or coordinate with whoever is running Task 3.

- [ ] **Step 4: Run tests to verify they pass**

This step requires `RecentSessionsCard` to exist (Task 3). If running strictly in order, come back to this verification after Task 3's Step 3 lands, or implement Task 3 first. Once `recent_sessions_card.dart` exists:

Run: `cd mobile && flutter test test/features/timer/timer_screen_test.dart`
Expected: PASS (all existing tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
cd mobile
git add lib/features/timer/timer_screen.dart test/features/timer/timer_screen_test.dart
git commit -m "feat: redesign timer card (status pill, today's total, restyled buttons)"
```

---

### Task 2: Weekly goal 7-day bar chart

**Files:**
- Modify: `mobile/lib/features/timer/weekly_goal_card.dart` (full rewrite)
- Test: `mobile/test/features/timer/weekly_goal_card_test.dart` (extend/fix)

**Interfaces:**
- Consumes: `AppColors`/`AppFonts`. `StudyTimerRepository.getSessionsBetween`/`.getWeeklyGoalMinutes`/`.setWeeklyGoal` (existing, unchanged). `mondayOf(DateTime) -> DateTime` from `mobile/lib/data/study_timer_repository.dart` (existing, unchanged).
- Produces: `WeeklyGoalCard` keeps its existing no-arg const constructor — `timer_screen.dart` already references `const WeeklyGoalCard()` unchanged.

- [ ] **Step 1: Fix the now-outdated existing test, and add new ones**

The existing test `'shows progress against the goal once one is set'` asserts `find.byType(LinearProgressIndicator)` and `find.textContaining('300')` — both break once the card shows a 7-day bar chart with an `H:MM`-formatted header instead. Replace the full contents of `mobile/test/features/timer/weekly_goal_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:english_helper_app/data/database.dart';
import 'package:english_helper_app/data/study_timer_repository.dart';
import 'package:english_helper_app/features/timer/weekly_goal_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildCard(StudyTimerRepository repo) {
    return ChangeNotifierProvider<StudyTimerRepository>.value(
      value: repo,
      child: const MaterialApp(home: Scaffold(body: WeeklyGoalCard())),
    );
  }

  testWidgets('shows "목표를 설정해보세요" when no goal is set', (tester) async {
    final repo = LocalStudyTimerRepository(
      openDb: () => openAppDatabase(inMemoryDatabasePath),
    );
    addTearDown(repo.close);
    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('목표'), findsWidgets);
  });

  testWidgets('shows a 7-day bar chart with H:MM totals once a goal is set', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);
    await repo.setWeeklyGoal(300); // 5 hours

    final monday = mondayOf(DateTime.now());
    // 1h12m on Monday.
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 10, minutes: 12)).toIso8601String(),
      'duration_seconds': 4320,
      'saved_at': monday.add(const Duration(hours: 10, minutes: 12)).toIso8601String(),
    });

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    // Header shows H:MM total / H:MM goal.
    expect(find.textContaining('1:12'), findsOneWidget);
    expect(find.textContaining('5:00'), findsOneWidget);
    // 7 day-of-week labels.
    for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('shows the achieved message once the goal is met', (tester) async {
    final db = await openAppDatabase(inMemoryDatabasePath);
    final repo = LocalStudyTimerRepository(openDb: () async => db);
    addTearDown(repo.close);
    await repo.setWeeklyGoal(1); // 1 minute — trivially achievable

    final monday = mondayOf(DateTime.now());
    await db.insert('study_sessions', {
      'id': 's1',
      'started_at': monday.add(const Duration(hours: 9)).toIso8601String(),
      'ended_at': monday.add(const Duration(hours: 9, minutes: 5)).toIso8601String(),
      'duration_seconds': 300,
      'saved_at': monday.add(const Duration(hours: 9, minutes: 5)).toIso8601String(),
    });

    await tester.pumpWidget(buildCard(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('달성했어요'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/weekly_goal_card_test.dart`
Expected: FAIL — no day-of-week labels or H:MM header exist yet in the current linear-progress implementation.

- [ ] **Step 3: Rewrite `weekly_goal_card.dart`**

Replace the full contents of `mobile/lib/features/timer/weekly_goal_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';
import '../../theme/app_theme.dart';

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({super.key});

  static const _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  // oklch(0.86 0.11 50) from the mockup — a light peach tint for non-today
  // days that have recorded time, distinct from AppColors.accent (today).
  static const _barTint = Color(0xFFFFBC8F);
  static const _barEmpty = Color(0xFFF0F2F7);
  static const _labelMuted = Color(0xFFA1A9B9);

  Future<void> _showSetGoalDialog(BuildContext context, StudyTimerRepository repo) async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('주간 목표 (분)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await repo.setWeeklyGoal(result);
    }
  }

  static String _formatHM(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  static String _formatHoursMinutesKorean(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    return '$h시간 $m분';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudyTimerRepository>();
    final weekStart = mondayOf(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 7));

    return FutureBuilder<List<Object?>>(
      future: Future.wait([
        repo.getWeeklyGoalMinutes(weekStart),
        repo.getSessionsBetween(weekStart, weekEnd),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final goalMinutes = snapshot.data?[0] as int?;
        final sessions = (snapshot.data?[1] as List<StudySession>?) ?? const [];

        if (goalMinutes == null) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              title: const Text('이번 주 목표를 설정해보세요'),
              trailing: TextButton(
                onPressed: () => _showSetGoalDialog(context, repo),
                child: const Text('목표 설정'),
              ),
            ),
          );
        }

        final dayTotals = List<int>.filled(7, 0); // seconds, index 0=월..6=일
        for (final s in sessions) {
          dayTotals[s.startedAt.weekday - 1] += s.durationSeconds;
        }
        final totalSeconds = dayTotals.fold<int>(0, (a, b) => a + b);
        final goalSeconds = goalMinutes * 60;
        final todayIndex = DateTime.now().weekday - 1;

        final perDayGoalSeconds = goalSeconds / 7;
        final chartMaxSeconds = [
          ...dayTotals,
          perDayGoalSeconds.round(),
        ].reduce((a, b) => a > b ? a : b);

        final remaining = goalSeconds - totalSeconds;
        final achieved = remaining <= 0;

        return Container(
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
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text('이번 주 목표', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  Text(
                    '${_formatHM(totalSeconds)} / ${_formatHM(goalSeconds)}',
                    style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12.5, color: AppColors.inkSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 70,
                                decoration: BoxDecoration(
                                  color: _barEmpty,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: chartMaxSeconds == 0
                                      ? 0
                                      : (dayTotals[i] / chartMaxSeconds).clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: dayTotals[i] == 0
                                          ? _barEmpty
                                          : (i == todayIndex ? AppColors.accent : _barTint),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                _dayLabels[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: i == todayIndex ? AppColors.ink : _labelMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF0F2F7))),
                ),
                child: Text(
                  achieved
                      ? '주간 목표를 달성했어요! 🎉'
                      : '주 ${_formatHoursMinutesKorean(goalSeconds)} 목표까지 ${_formatHoursMinutesKorean(remaining)} 남았습니다.',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/weekly_goal_card_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd mobile
git add lib/features/timer/weekly_goal_card.dart test/features/timer/weekly_goal_card_test.dart
git commit -m "feat: redesign weekly goal card as a 7-day bar chart"
```

---

### Task 3: Recent sessions card (new)

**Files:**
- Create: `mobile/lib/features/timer/recent_sessions_card.dart`
- Test: `mobile/test/features/timer/recent_sessions_card_test.dart` (new)

**Interfaces:**
- Consumes: `AppColors`/`AppFonts`. `StudyTimerRepository.getSessionsBetween` (existing, unchanged).
- Produces: `class RecentSessionsCard extends StatelessWidget` with a no-arg const constructor (`const RecentSessionsCard({super.key})`). Task 1's rewrite of `timer_screen.dart` already references `const RecentSessionsCard()` — this task is what makes that import resolve.

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/features/timer/recent_sessions_card_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/features/timer/recent_sessions_card_test.dart`
Expected: FAIL — `Error: Not found: 'package:english_helper_app/features/timer/recent_sessions_card.dart'`

- [ ] **Step 3: Write `recent_sessions_card.dart`**

Create `mobile/lib/features/timer/recent_sessions_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';
import '../../theme/app_theme.dart';

/// Shows the most recently completed study sessions. Renders nothing when
/// there are none yet — the mockup has no empty-state variant for this
/// section (design.md §3.5).
class RecentSessionsCard extends StatelessWidget {
  const RecentSessionsCard({super.key});

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudyTimerRepository>();
    // A wide-enough window to reliably surface the most recent sessions
    // without querying "all time".
    final end = DateTime.now().add(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 91));

    return FutureBuilder<List<StudySession>>(
      future: repo.getSessionsBetween(start, end),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const [];
        if (sessions.isEmpty) return const SizedBox.shrink();

        // getSessionsBetween orders ascending by started_at; take the tail
        // (most recent) and reverse to show newest first.
        final recent = sessions.reversed.take(_maxShown).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'RECENT SESSIONS',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: AppColors.inkQuaternary,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        border: i < recent.length - 1
                            ? const Border(bottom: BorderSide(color: Color(0xFFF1F3F8)))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _dateLabel(recent[i].startedAt),
                                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _timeRangeLabel(recent[i]),
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _durationLabel(recent[i].durationSeconds),
                            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 13, color: AppColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _dateLabel(DateTime dt) => '${dt.month}월 ${dt.day}일';

  static String _timeRangeLabel(StudySession s) {
    String hm(DateTime dt) {
      final period = dt.hour < 12 ? '오전' : '오후';
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return '$period $hour12:${dt.minute.toString().padLeft(2, '0')}';
    }

    return '${hm(s.startedAt)} - ${hm(s.endedAt)}';
  }

  static String _durationLabel(int totalSeconds) => '${totalSeconds ~/ 60}분';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd mobile && flutter test test/features/timer/recent_sessions_card_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Run Task 1's tests now that `RecentSessionsCard` exists**

Run: `cd mobile && flutter test test/features/timer/timer_screen_test.dart`
Expected: PASS (all tests, including Task 1's 2 new ones — this confirms the import Task 1 added now resolves)

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/timer/recent_sessions_card.dart test/features/timer/recent_sessions_card_test.dart
git commit -m "feat: add recent sessions card to timer screen"
```

---

### Task 4: Restyle `TimerHistoryView` (visual only, no functional change)

**Files:**
- Modify: `mobile/lib/features/timer/timer_history_view.dart`
- Test: `mobile/test/features/timer/timer_history_view_test.dart` (no changes expected — this task must not break it)

**Interfaces:**
- Consumes: `AppColors` from `mobile/lib/theme/app_theme.dart`.
- Produces: no new public API — `TimerHistoryView`'s constructor and behavior (주/월/년, 그래프/숫자) stay identical; only visuals change.

- [ ] **Step 1: Confirm the existing test still passes before touching anything (baseline)**

Run: `cd mobile && flutter test test/features/timer/timer_history_view_test.dart`
Expected: PASS (3 tests) — this is your baseline; re-run the same command after Step 3 and expect the same PASS with no changes to this test file. In particular, `'year period list view aggregates sessions by month, not by day'` asserts `find.byType(ListTile), findsNWidgets(2)` — **do not change the list view's row widget away from `ListTile`**, or this test breaks.

- [ ] **Step 2: N/A (no failing-test step — this task changes styling, not behavior, so there is no new test to write first)**

- [ ] **Step 3: Restyle the wrapping container and bar chart color**

In `mobile/lib/features/timer/timer_history_view.dart`, add the import:

```dart
import '../../theme/app_theme.dart';
```

Wrap the `Column`'s existing children in a styled container. Change the `build` method's `return Column(...)` (the outermost return) to:

```dart
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudyTimerRepository>();
    final range = _rangeFor(_period);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<TimerPeriod>(
            segments: const [
              ButtonSegment(value: TimerPeriod.week, label: Text('주간')),
              ButtonSegment(value: TimerPeriod.month, label: Text('월간')),
              ButtonSegment(value: TimerPeriod.year, label: Text('년간')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TimerViewMode>(
            segments: const [
              ButtonSegment(value: TimerViewMode.graph, label: Text('그래프')),
              ButtonSegment(value: TimerViewMode.list, label: Text('숫자')),
            ],
            selected: {_viewMode},
            onSelectionChanged: (s) => setState(() => _viewMode = s.first),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<StudySession>>(
            future: repo.getSessionsBetween(range.start, range.end),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sessions = snapshot.data ?? const [];
              if (sessions.isEmpty) {
                return const EmptyState(message: '이 기간에 기록된 공부 시간이 없어요');
              }
              final isMonthGrouped = _period == TimerPeriod.year;
              final grouped = isMonthGrouped ? _groupByMonth(sessions) : _groupByDay(sessions);
              return _viewMode == TimerViewMode.graph
                  ? _buildGraph(grouped)
                  : _buildList(grouped, isMonthGrouped: isMonthGrouped);
            },
          ),
        ],
      ),
    );
  }
```

(This is identical in structure to the current method — only the outer `Column` became a `Column` wrapped in a styled `Container`; every child widget, callback, and the `FutureBuilder`'s contents are unchanged verbatim.)

Change `_buildGraph` to color the bars with the app's accent instead of `fl_chart`'s default:

```dart
  Widget _buildGraph(Map<DateTime, int> byDay) {
    final days = byDay.keys.toList()..sort();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: byDay[days[i]]! / 60, color: AppColors.accent),
              ]),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: Run the test again to confirm no regression**

Run: `cd mobile && flutter test test/features/timer/timer_history_view_test.dart`
Expected: PASS (same 3 tests, unchanged file)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd mobile && flutter analyze && flutter test`
Expected: no analyzer issues, full suite passes (this also re-confirms Tasks 1-3 integrate correctly with this task's changes to the same screen).

- [ ] **Step 6: Commit**

```bash
cd mobile
git add lib/features/timer/timer_history_view.dart
git commit -m "style: restyle TimerHistoryView container and bar chart color"
```

---

## Self-Review Notes

- **Spec coverage:** §3.1 (timer card: pill, clock, 오늘 누적, buttons) → Task 1. §3.2 (weekly goal 7-day bar chart) → Task 2. §3.3 (button states confirmed: 시작-only before a session exists, toggle+종료 after) → Task 1. §3.4 (오늘 누적 excludes the running session) → Task 1 (`_loadTodayTotal` only queries completed `study_sessions` rows; the active session is never written there until `endSession()`). §3.5 (recent sessions, no empty state) → Task 3. §4 (goal-met message, no-goal state, recent-sessions-hidden-when-empty) → Tasks 2 and 3. §5 (all listed test cases) → distributed across Tasks 1-3; Task 4 has no new tests since it's styling-only, per its own explicit constraint. §6 (out-of-scope: no new repo methods/schema, `TimerHistoryView` functionality preserved) → confirmed by Task 4's baseline-then-reconfirm test step and by no task touching `study_timer_repository.dart`/`database.dart`.
- **Placeholder scan:** none found — every step has literal code and exact commands.
- **Type consistency:** `RecentSessionsCard()` (no-arg const constructor) matches between Task 3's definition and Task 1's `timer_screen.dart` usage. `_formatHoursMinutesKorean`/`_formatHM` helper names and signatures are local to their own files (`timer_screen.dart` and `weekly_goal_card.dart` each define their own copy — intentionally not shared, since sharing a 3-line formatter across files isn't worth a new utility module per this codebase's established small-duplication convention, e.g. `_generateId()` in Task 5 of the flashcard plan). `mondayOf` import path (`../../data/study_timer_repository.dart`) matches its existing pre-plan location — no change needed since Task 2 doesn't move it.
- **Task ordering dependency:** Task 1 imports `recent_sessions_card.dart` (created in Task 3), so `timer_screen.dart` will not compile between Task 1's commit and Task 3's commit if run out of order. This is explicitly called out inside Task 1's Step 3 and Step 4 — dispatch these tasks in order (1 → 2 → 3 → 4) to avoid a broken intermediate state, or accept that Task 1 alone is red until Task 3 lands.
