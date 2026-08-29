import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';

void main() {
  group('Sentence', () {
    test('toMap/fromMap round-trips all fields', () {
      final sentence = Sentence(
        id: 's1',
        original: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'netflix',
        contentTitle: 'Stranger Things S1E1',
        contentId: '70301898',
        timestamp: 142.5,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
        reviewCount: 1,
        nextReviewAt: '2026-08-03T00:00:00.000Z',
      );

      final restored = Sentence.fromMap(sentence.toMap());

      expect(restored.id, 's1');
      expect(restored.original, 'Nothing in life is ephemeral.');
      expect(restored.translation, '인생에서 덧없지 않은 것은 없다.');
      expect(restored.platform, 'netflix');
      expect(restored.contentTitle, 'Stranger Things S1E1');
      expect(restored.contentId, '70301898');
      expect(restored.timestamp, 142.5);
      expect(restored.savedAt, '2026-08-02T00:00:00.000Z');
      expect(restored.reviewCount, 1);
      expect(restored.nextReviewAt, '2026-08-03T00:00:00.000Z');
    });

    test('fromMap defaults missing optional fields', () {
      final restored = Sentence.fromMap({
        'id': 's2',
        'original': 'Brief line.',
        'platform': 'youtube',
        'timestamp': 5,
        'saved_at': '2026-08-02T00:00:00.000Z',
      });

      expect(restored.translation, '');
      expect(restored.contentTitle, '');
      expect(restored.contentId, '');
      expect(restored.reviewCount, 0);
      expect(restored.nextReviewAt, isNull);
    });

    test('copyWith updates only reviewCount and nextReviewAt', () {
      final sentence = Sentence(
        id: 's1', original: 'x', platform: 'netflix',
        contentTitle: 'y', contentId: 'z', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = sentence.copyWith(reviewCount: 1, nextReviewAt: '2026-08-03T00:00:00.000Z');

      expect(updated.reviewCount, 1);
      expect(updated.nextReviewAt, '2026-08-03T00:00:00.000Z');
      expect(updated.original, 'x');
    });

    test('toMap/fromMap round-trips reviewLevel and lastReviewedAt', () {
      final sentence = Sentence(
        id: 's1', original: 's-w1', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
        reviewLevel: 3,
        lastReviewedAt: '2026-08-10T00:00:00.000Z',
      );
      final restored = Sentence.fromMap(sentence.toMap());
      expect(restored.reviewLevel, 3);
      expect(restored.lastReviewedAt, '2026-08-10T00:00:00.000Z');
    });

    test('fromMap defaults reviewLevel to 0 and lastReviewedAt to null when missing', () {
      final restored = Sentence.fromMap({
        'id': 's2', 'original': 'brief', 'platform': 'youtube',
        'timestamp': 5, 'saved_at': '2026-08-02T00:00:00.000Z',
      });
      expect(restored.reviewLevel, 0);
      expect(restored.lastReviewedAt, isNull);
    });

    test('copyWith updates reviewLevel and lastReviewedAt', () {
      final sentence = Sentence(
        id: 's1', original: 's-w1', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = sentence.copyWith(reviewLevel: 2, lastReviewedAt: '2026-08-10T00:00:00.000Z');
      expect(updated.reviewLevel, 2);
      expect(updated.lastReviewedAt, '2026-08-10T00:00:00.000Z');
      expect(updated.original, 's-w1');
    });

    test('copyWith can explicitly clear nextReviewAt and lastReviewedAt to null', () {
      final sentence = Sentence(
        id: 's1', original: 's-w1', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
        nextReviewAt: '2026-08-08T00:00:00.000Z',
        lastReviewedAt: '2026-08-01T00:00:00.000Z',
      );
      final cleared = sentence.copyWith(nextReviewAt: null, lastReviewedAt: null);
      expect(cleared.nextReviewAt, isNull);
      expect(cleared.lastReviewedAt, isNull);
    });

    test('copyWith updates original/translation but leaves other fields (including nextReviewAt) untouched', () {
      final sentence = Sentence(
        id: 's1', original: 'Nothing in life is ephemeral.', translation: '덧없는',
        platform: 'netflix', contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
        updatedAt: '2026-08-02T00:00:00.000Z',
        reviewCount: 5, reviewLevel: 3,
        nextReviewAt: '2099-01-01T00:00:00.000Z',
        lastReviewedAt: '2026-08-10T00:00:00.000Z',
      );
      final updated = sentence.copyWith(original: 'New original.');

      expect(updated.original, 'New original.');
      expect(updated.translation, '덧없는');
      expect(updated.reviewCount, 5);
      expect(updated.reviewLevel, 3);
      expect(updated.nextReviewAt, '2099-01-01T00:00:00.000Z');
      expect(updated.lastReviewedAt, '2026-08-10T00:00:00.000Z');
    });
  });
}
