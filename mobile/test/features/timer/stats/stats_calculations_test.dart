import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/study_session.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/timer/stats/stats_calculations.dart';

StudySession _session(DateTime startedAt, {int durationSeconds = 1800}) => StudySession(
      id: 'id-${startedAt.toIso8601String()}-$durationSeconds',
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSeconds)),
      durationSeconds: durationSeconds,
      savedAt: startedAt.toIso8601String(),
    );

Word _word(String savedAt) => Word(
      id: 'w-$savedAt',
      word: 'x',
      platform: 'youtube',
      contentTitle: 't',
      contentId: 'c',
      timestamp: 0,
      savedAt: savedAt,
      updatedAt: savedAt,
    );

Sentence _sentence(String savedAt) => Sentence(
      id: 's-$savedAt',
      original: 'x',
      platform: 'youtube',
      contentTitle: 't',
      contentId: 'c',
      timestamp: 0,
      savedAt: savedAt,
      updatedAt: savedAt,
    );

void main() {
  group('groupSessionsByDay', () {
    test('sums durations for the same day and keeps different days separate', () {
      final result = groupSessionsByDay([
        _session(DateTime(2026, 8, 10, 9), durationSeconds: 600),
        _session(DateTime(2026, 8, 10, 20), durationSeconds: 300),
        _session(DateTime(2026, 8, 11, 9), durationSeconds: 100),
      ]);
      expect(result[DateTime(2026, 8, 10)], 900);
      expect(result[DateTime(2026, 8, 11)], 100);
      expect(result.length, 2);
    });
  });

  group('countSessionsByDay', () {
    test('counts rows per day, not summed duration', () {
      final result = countSessionsByDay([
        _session(DateTime(2026, 8, 10, 9)),
        _session(DateTime(2026, 8, 10, 20)),
        _session(DateTime(2026, 8, 11, 9)),
      ]);
      expect(result[DateTime(2026, 8, 10)], 2);
      expect(result[DateTime(2026, 8, 11)], 1);
    });
  });

  group('groupSavesByDay', () {
    test('counts words and sentences together per day', () {
      final result = groupSavesByDay(
        [_word('2026-08-10T09:00:00.000Z'), _word('2026-08-10T20:00:00.000Z')],
        [_sentence('2026-08-10T10:00:00.000Z'), _sentence('2026-08-11T10:00:00.000Z')],
      );
      expect(result[DateTime(2026, 8, 10)], 3);
      expect(result[DateTime(2026, 8, 11)], 1);
    });

    test('skips entries with an empty or unparseable savedAt instead of throwing', () {
      final result = groupSavesByDay([_word('')], [_sentence('not-a-date')]);
      expect(result, isEmpty);
    });
  });

  group('currentStreakDays', () {
    test('counts consecutive days ending today', () {
      final today = DateTime(2026, 8, 15);
      final dayTotals = {
        DateTime(2026, 8, 15): 600,
        DateTime(2026, 8, 14): 600,
        DateTime(2026, 8, 13): 600,
        DateTime(2026, 8, 11): 600, // gap at the 12th breaks the streak before this
      };
      expect(currentStreakDays(dayTotals, today: today), 3);
    });

    test('is 0 when today itself has no activity', () {
      final today = DateTime(2026, 8, 15);
      final dayTotals = {DateTime(2026, 8, 14): 600};
      expect(currentStreakDays(dayTotals, today: today), 0);
    });
  });

  group('longestStreakDays', () {
    test('finds the longest run even if it is not the most recent', () {
      final dayTotals = {
        // A 4-day run early in the month...
        DateTime(2026, 8, 1): 600,
        DateTime(2026, 8, 2): 600,
        DateTime(2026, 8, 3): 600,
        DateTime(2026, 8, 4): 600,
        // ...then a gap, then a shorter 2-day run.
        DateTime(2026, 8, 10): 600,
        DateTime(2026, 8, 11): 600,
      };
      expect(longestStreakDays(dayTotals), 4);
    });

    test('is 0 for no activity at all', () {
      expect(longestStreakDays({}), 0);
    });
  });

  group('monthActivityCounts / monthlyActivityRate', () {
    test('counts active vs elapsed days within the given range', () {
      final dayTotals = {
        DateTime(2026, 8, 1): 600,
        DateTime(2026, 8, 3): 600,
        // day 2 and 4-5 have no activity
      };
      final counts = monthActivityCounts(dayTotals, DateTime(2026, 8, 1), DateTime(2026, 8, 5));
      expect(counts.active, 2);
      expect(counts.elapsed, 5);
      expect(monthlyActivityRate(dayTotals, DateTime(2026, 8, 1), DateTime(2026, 8, 5)), 2 / 5);
    });
  });

  group('calendarDotTier', () {
    test('0 seconds is tier 0 (no dot)', () {
      expect(calendarDotTier(0, 1000), 0);
    });

    test('a day with activity but a month with no recorded max is tier 0 (guards div by zero)', () {
      expect(calendarDotTier(100, 0), 0);
    });

    test('just under one third is tier 1', () {
      expect(calendarDotTier(99, 300), 1);
    });

    test('exactly one third is tier 2', () {
      expect(calendarDotTier(100, 300), 2);
    });

    test('exactly two thirds is tier 2', () {
      expect(calendarDotTier(200, 300), 2);
    });

    test('just over two thirds is tier 3', () {
      expect(calendarDotTier(201, 300), 3);
    });

    test('the max day itself is tier 3', () {
      expect(calendarDotTier(300, 300), 3);
    });
  });

  group('sumSecondsInRange', () {
    test('sums only days within [start, end), excluding end', () {
      final dayTotals = {
        DateTime(2026, 8, 10): 600,
        DateTime(2026, 8, 11): 300,
        DateTime(2026, 8, 12): 900,
      };
      expect(
        sumSecondsInRange(dayTotals, DateTime(2026, 8, 10), DateTime(2026, 8, 12)),
        900, // 10th + 11th, not the 12th
      );
    });

    test('is 0 for a range with no recorded activity', () {
      expect(sumSecondsInRange({}, DateTime(2026, 8, 10), DateTime(2026, 8, 17)), 0);
    });
  });

  group('periodDeltaPercent', () {
    test('positive change rounds to the nearest percent', () {
      expect(periodDeltaPercent(1200, 1000), 20);
    });

    test('negative change is negative', () {
      expect(periodDeltaPercent(800, 1000), -20);
    });

    test('is null when the previous total is 0 (no baseline to compare against)', () {
      expect(periodDeltaPercent(600, 0), isNull);
    });
  });
}
