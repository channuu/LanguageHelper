import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/word.dart';

void main() {
  group('Word', () {
    test('toMap/fromMap round-trips all fields', () {
      final word = Word(
        id: 'w1',
        word: 'ephemeral',
        definition: 'lasting for a very short time',
        sentence: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'netflix',
        contentTitle: 'Stranger Things S1E1',
        contentId: '70301898',
        timestamp: 142.5,
        savedAt: '2026-08-02T00:00:00.000Z',
        reviewCount: 2,
        nextReviewAt: '2026-08-03T00:00:00.000Z',
      );

      final restored = Word.fromMap(word.toMap());

      expect(restored.id, 'w1');
      expect(restored.word, 'ephemeral');
      expect(restored.definition, 'lasting for a very short time');
      expect(restored.sentence, 'Nothing in life is ephemeral.');
      expect(restored.translation, '인생에서 덧없지 않은 것은 없다.');
      expect(restored.platform, 'netflix');
      expect(restored.contentTitle, 'Stranger Things S1E1');
      expect(restored.contentId, '70301898');
      expect(restored.timestamp, 142.5);
      expect(restored.savedAt, '2026-08-02T00:00:00.000Z');
      expect(restored.reviewCount, 2);
      expect(restored.nextReviewAt, '2026-08-03T00:00:00.000Z');
    });

    test('fromMap defaults missing optional fields', () {
      final restored = Word.fromMap({
        'id': 'w2',
        'word': 'brief',
        'platform': 'youtube',
        'timestamp': 10,
        'saved_at': '2026-08-02T00:00:00.000Z',
      });

      expect(restored.definition, '');
      expect(restored.sentence, '');
      expect(restored.translation, '');
      expect(restored.contentTitle, '');
      expect(restored.contentId, '');
      expect(restored.reviewCount, 0);
      expect(restored.nextReviewAt, isNull);
    });

    test('copyWith updates only reviewCount and nextReviewAt', () {
      final word = Word(
        id: 'w1', word: 'ephemeral', platform: 'netflix',
        contentTitle: 'x', contentId: 'y', timestamp: 1,
        savedAt: '2026-08-02T00:00:00.000Z',
      );
      final updated = word.copyWith(reviewCount: 1, nextReviewAt: '2026-08-03T00:00:00.000Z');

      expect(updated.reviewCount, 1);
      expect(updated.nextReviewAt, '2026-08-03T00:00:00.000Z');
      expect(updated.word, 'ephemeral');
      expect(updated.id, 'w1');
    });
  });
}
