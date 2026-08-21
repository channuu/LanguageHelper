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

  Future<void> _openGoalSheet(
    BuildContext context,
    StudyTimerRepository repo,
    int currentGoalHours,
    int currentTotalSeconds,
  ) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalSheet(
        initialHours: currentGoalHours,
        currentTotalSeconds: currentTotalSeconds,
      ),
    );
    if (result != null) {
      await repo.setWeeklyGoal(result * 60);
    }
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

        final dayTotals = List<int>.filled(7, 0); // seconds, index 0=월..6=일
        for (final s in sessions) {
          dayTotals[s.startedAt.weekday - 1] += s.durationSeconds;
        }
        final totalSeconds = dayTotals.fold<int>(0, (a, b) => a + b);

        if (goalMinutes == null) {
          return GestureDetector(
            onTap: () => _openGoalSheet(context, repo, 5, totalSeconds),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const ListTile(
                title: Text('이번 주 목표를 설정해보세요'),
                trailing: Text(
                  '목표 설정',
                  style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, color: AppColors.accentInk),
                ),
              ),
            ),
          );
        }

        // The goal sheet only sets whole-hour goals (matching the mockup's
        // integer-hour model) — legacy minute-precision goals from the old
        // dialog are truncated down to their whole-hour part for display.
        final goalHours = goalMinutes ~/ 60;
        final goalSeconds = goalHours * 3600;
        final todayIndex = DateTime.now().weekday - 1;

        final perDayGoalSeconds = goalSeconds / 7;
        final chartMaxSeconds = [
          ...dayTotals,
          perDayGoalSeconds.round(),
        ].reduce((a, b) => a > b ? a : b);

        final remaining = goalSeconds - totalSeconds;
        final achieved = remaining <= 0;

        return GestureDetector(
          onTap: () => _openGoalSheet(context, repo, goalHours, totalSeconds),
          child: Container(
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
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('이번 주 목표', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 13.5)),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 14, color: AppColors.inkFaint),
                      ],
                    ),
                    Text(
                      '${_formatHM(totalSeconds)} / $goalHours:00',
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          achieved
                              ? '이번 주 목표를 달성했습니다.'
                              : '주 $goalHours시간 목표까지 ${_formatHoursMinutesKorean(remaining)} 남았습니다.',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.inkQuaternary),
                        ),
                      ),
                      const Text(
                        '목표 변경',
                        style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 11, color: AppColors.accentInk),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GoalSheet extends StatefulWidget {
  final int initialHours;
  final int currentTotalSeconds;
  const GoalSheet({super.key, required this.initialHours, required this.currentTotalSeconds});

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<GoalSheet> {
  static const _tickHours = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 21];
  static const _presetHours = [3, 5, 7, 10];
  static const _minHours = 1;
  static const _maxHours = 21;

  late int _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialHours.clamp(_minHours, _maxHours);
  }

  static String _formatHM(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '$h시간 $m분';
  }

  void _setDraft(int hours) => setState(() => _draft = hours.clamp(_minHours, _maxHours));

  @override
  Widget build(BuildContext context) {
    final perDayMinutes = (_draft * 60 / 7).round();
    final perDayLabel = perDayMinutes ~/ 60 > 0 ? _formatHM(perDayMinutes) : '$perDayMinutes분';

    final currentMinutes = widget.currentTotalSeconds ~/ 60;
    final gapMinutes = _draft * 60 - currentMinutes;
    final gapLabel = gapMinutes <= 0 ? '달성' : _formatHM(gapMinutes);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 30 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFDCE1EA), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text(
            '주간 학습 목표',
            style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 20, letterSpacing: -0.01),
          ),
          const SizedBox(height: 6),
          const Text(
            '한 주에 학습할 시간을 정합니다. 월요일에 초기화됩니다.',
            style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.inkTertiary),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_draft',
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 52,
                  height: 1,
                  letterSpacing: -0.03,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text('시간 / 주', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.inkTertiary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '하루 평균 $perDayLabel',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.inkQuaternary),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StepperButton(label: '−', onTap: () => _setDraft(_draft - 1)),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < _tickHours.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                          child: GestureDetector(
                            onTap: () => _setDraft(_tickHours[i]),
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              height: 34,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: 0.34 + i * 0.06,
                                  widthFactor: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _tickHours[i] <= _draft ? AppColors.accent : const Color(0xFFE3E7EF),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _StepperButton(label: '+', onTap: () => _setDraft(_draft + 1)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < _presetHours.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 7),
                    child: _PresetButton(
                      hours: _presetHours[i],
                      selected: _draft == _presetHours[i],
                      onTap: () => _setDraft(_presetHours[i]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(color: const Color(0xFFF0F2F7), borderRadius: BorderRadius.circular(14)),
            child: Text(
              '현재 진행 ${_formatHM(currentMinutes)} · 새 목표까지 $gapLabel',
              style: const TextStyle(fontSize: 12.5, height: 1.55, color: AppColors.inkSecondary),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFDCE1EA)),
                      foregroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('취소', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('저장', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepperButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: const Color(0xFFDCE1EA)),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 22, color: AppColors.inkSecondary)),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final int hours;
  final bool selected;
  final VoidCallback onTap;
  const _PresetButton({required this.hours, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          border: Border.all(color: selected ? Colors.transparent : const Color(0xFFE3E7EF)),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          '$hours시간',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: selected ? AppColors.ink : AppColors.inkSecondary,
          ),
        ),
      ),
    );
  }
}
