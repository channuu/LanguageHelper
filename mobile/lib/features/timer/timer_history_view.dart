import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';
import '../../shared/widgets/empty_state.dart';
import '../../theme/app_theme.dart';

enum TimerPeriod { week, month, year }

enum TimerViewMode { graph, list }

class TimerHistoryView extends StatefulWidget {
  const TimerHistoryView({super.key});

  @override
  State<TimerHistoryView> createState() => _TimerHistoryViewState();
}

class _TimerHistoryViewState extends State<TimerHistoryView> {
  TimerPeriod _period = TimerPeriod.week;
  TimerViewMode _viewMode = TimerViewMode.graph;

  ({DateTime start, DateTime end}) _rangeFor(TimerPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case TimerPeriod.week:
        final start = mondayOf(now);
        return (start: start, end: start.add(const Duration(days: 7)));
      case TimerPeriod.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start: start, end: end);
      case TimerPeriod.year:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);
        return (start: start, end: end);
    }
  }

  Map<DateTime, int> _groupByDay(List<StudySession> sessions) {
    final map = <DateTime, int>{};
    for (final s in sessions) {
      final day = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      map[day] = (map[day] ?? 0) + s.durationSeconds;
    }
    return map;
  }

  Map<DateTime, int> _groupByMonth(List<StudySession> sessions) {
    final map = <DateTime, int>{};
    for (final s in sessions) {
      final month = DateTime(s.startedAt.year, s.startedAt.month, 1);
      map[month] = (map[month] ?? 0) + s.durationSeconds;
    }
    return map;
  }

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

  Widget _buildList(Map<DateTime, int> byDay, {bool isMonthGrouped = false}) {
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      children: [
        for (final day in days)
          ListTile(
            title: Text(isMonthGrouped
                ? '${day.year}-${day.month.toString().padLeft(2, '0')}'
                : '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'),
            trailing: Text('${byDay[day]! ~/ 60}분'),
          ),
      ],
    );
  }
}
