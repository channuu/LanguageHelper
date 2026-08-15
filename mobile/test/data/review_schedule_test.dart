import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/review_schedule.dart';

void main() {
  group('nextReviewAtForLevel', () {
    test('level 0 has no schedule (returns null)', () {
      expect(nextReviewAtForLevel(0, DateTime(2026, 8, 15)), isNull);
    });

    test('level 1 is 1 day out', () {
      expect(
        nextReviewAtForLevel(1, DateTime(2026, 8, 15)),
        DateTime(2026, 8, 16).toIso8601String(),
      );
    });

    test('level 2 is 7 days out', () {
      expect(
        nextReviewAtForLevel(2, DateTime(2026, 8, 15)),
        DateTime(2026, 8, 22).toIso8601String(),
      );
    });

    test('level 3 is 30 days out', () {
      expect(
        nextReviewAtForLevel(3, DateTime(2026, 8, 15)),
        DateTime(2026, 9, 14).toIso8601String(),
      );
    });

    test('level 4 is 90 days out', () {
      expect(
        nextReviewAtForLevel(4, DateTime(2026, 8, 15)),
        DateTime(2026, 11, 13).toIso8601String(),
      );
    });
  });

  group('isDueForReview', () {
    test('level 0 is always due, regardless of nextReviewAt', () {
      expect(isDueForReview(0, null), isTrue);
      expect(isDueForReview(0, DateTime(2099, 1, 1).toIso8601String()), isTrue);
    });

    test('a level with no nextReviewAt is due (safety net)', () {
      expect(isDueForReview(2, null), isTrue);
    });

    test('a future nextReviewAt is not due', () {
      final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
      expect(isDueForReview(2, future), isFalse);
    });

    test('a past nextReviewAt is due', () {
      final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      expect(isDueForReview(2, past), isTrue);
    });
  });

  test('kReviewLevelNames has one name per level 0-4', () {
    expect(kReviewLevelNames, hasLength(5));
  });

  test('kReviewIntervalDays has one entry per level 0-4', () {
    expect(kReviewIntervalDays, hasLength(5));
  });
}
