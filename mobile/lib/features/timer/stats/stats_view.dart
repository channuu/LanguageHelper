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
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

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
                    Expanded(
                      child: Column(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(child: Text('‹', style: TextStyle(fontSize: 18, color: AppColors.inkTertiary))),
                      ),
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
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(child: Text('›', style: TextStyle(fontSize: 18, color: AppColors.inkTertiary))),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _calendarGrid([
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
                ]),
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
        ],
      ),
    );
  }

  void _prevMonth() {
    setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1, 1));
  }

  void _nextMonth() {
    setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1));
  }

  // A hand-rolled, non-scrollable 7-column grid — GridView (even with
  // NeverScrollableScrollPhysics) still creates a Scrollable that can win
  // the gesture arena for a vertical drag starting inside it, which blocks
  // the ancestor SingleChildScrollView from ever seeing that drag.
  Widget _calendarGrid(List<Widget> items) {
    const columns = 7;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += columns) {
      final rowItems = items.sublist(i, i + columns > items.length ? items.length : i + columns);
      rows.add(
        Row(
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: 5),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: c < rowItems.length ? rowItems[c] : const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 5),
          rows[r],
        ],
      ],
    );
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
          color: selected ? AppColors.accentTint : AppColors.surface,
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
