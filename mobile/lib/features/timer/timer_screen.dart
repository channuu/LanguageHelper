// mobile/lib/features/timer/timer_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/active_session_state.dart';
import '../../data/study_timer_repository.dart';
import '../../theme/app_theme.dart';
import 'recent_sessions_card.dart';
import 'stats/stats_view.dart';
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
  bool _statsMode = false;

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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _statsMode ? '통계' : '학습 타이머',
                    style: Theme.of(context).textTheme.headlineLarge,
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
                  : _buildTimerMode(repo, active),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerMode(StudyTimerRepository repo, ActiveSessionState? active) {
    return ListView(
      padding: const EdgeInsets.all(20),
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
          color: statsMode ? AppColors.accent : AppColors.surface,
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
