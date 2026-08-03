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
      );
      final updated = sentence.copyWith(reviewCount: 1, nextReviewAt: '2026-08-03T00:00:00.000Z');

      expect(updated.reviewCount, 1);
      expect(updated.nextReviewAt, '2026-08-03T00:00:00.000Z');
      expect(updated.original, 'x');
    });
  });
}
