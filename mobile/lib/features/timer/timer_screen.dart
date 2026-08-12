// mobile/lib/features/timer/timer_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/active_session_state.dart';
import '../../data/study_timer_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _init();
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
  }

  void _tick() {
    if (!mounted) return;
    final active = context.read<StudyTimerRepository>().activeSession;
    setState(() => _displaySeconds = active?.elapsedSeconds() ?? 0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildButtons(StudyTimerRepository repo, ActiveSessionState? active) {
    if (active == null) {
      return [
        ElevatedButton(onPressed: () => repo.startSession(), child: const Text('시작')),
      ];
    }
    if (active.isPaused) {
      return [
        ElevatedButton(onPressed: () => repo.resumeSession(), child: const Text('재개')),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: () => repo.endSession(), child: const Text('종료')),
      ];
    }
    return [
      ElevatedButton(onPressed: () => repo.pauseSession(), child: const Text('일시정지')),
      const SizedBox(width: 12),
      OutlinedButton(onPressed: () => repo.endSession(), child: const Text('종료')),
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
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              _format(active?.elapsedSeconds() ?? _displaySeconds),
              style: Theme.of(context).textTheme.displayMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildButtons(repo, active),
          ),
          const SizedBox(height: 24),
          const WeeklyGoalCard(),
          const SizedBox(height: 24),
          const TimerHistoryView(),
        ],
      ),
    );
  }
}
