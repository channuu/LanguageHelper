import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/study_session.dart';
import '../../data/study_timer_repository.dart';

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({super.key});

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
        final totalMinutes = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds ~/ 60);

        if (goalMinutes == null) {
          return Card(
            child: ListTile(
              title: const Text('이번 주 목표를 설정해보세요'),
              trailing: TextButton(
                onPressed: () => _showSetGoalDialog(context, repo),
                child: const Text('목표 설정'),
              ),
            ),
          );
        }

        final progress = goalMinutes == 0 ? 0.0 : (totalMinutes / goalMinutes).clamp(0.0, 1.0);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('이번 주 $totalMinutes / $goalMinutes분'),
                    TextButton(
                      onPressed: () => _showSetGoalDialog(context, repo),
                      child: const Text('목표 수정'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
        );
      },
    );
  }
}
