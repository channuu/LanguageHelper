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
