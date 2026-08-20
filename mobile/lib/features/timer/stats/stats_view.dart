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
