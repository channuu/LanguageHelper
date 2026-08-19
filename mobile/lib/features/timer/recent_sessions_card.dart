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
