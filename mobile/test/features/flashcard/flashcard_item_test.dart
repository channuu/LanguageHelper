import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/flashcard/flashcard_item.dart';

Word _word() => Word(
      id: 'w1', word: 'ephemeral', definition: 'lasting for a very short time',
      sentence: 'Nothing in life is ephemeral.', translation: '덧없는',
      platform: 'netflix', contentTitle: 'Title', contentId: 'c1',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      reviewLevel: 2, lastReviewedAt: '2026-08-10T00:00:00.000Z',
      updatedAt: '2026-08-02T00:00:00.000Z',
    );

Sentence _sentence() => Sentence(
      id: 's1', original: 'Nothing in life is ephemeral.', translation: '인생에서 덧없지 않은 것은 없다.',
      platform: 'youtube', contentTitle: 'Video', contentId: 'c2',
      timestamp: 1, savedAt: '2026-08-02T00:00:00.000Z',
      updatedAt: '2026-08-02T00:00:00.000Z',
    );

void main() {
  group('FlashcardItem.fromWord', () {
    test('tests 뜻→단어: prompt is translation, answer is the English word', () {
      final item = FlashcardItem.fromWord(_word());
      expect(item.isWord, isTrue);
      expect(item.prompt, '덧없는');
      expect(item.correctAnswer, 'ephemeral');
      expect(item.backHeadline, 'ephemeral');
      expect(item.backSubtext, '덧없는');
      expect(item.backDetail, 'lasting for a very short time');
      expect(item.backExample, 'Nothing in life is ephemeral.');
      expect(item.reviewLevel, 2);
      expect(item.lastReviewedAt, '2026-08-10T00:00:00.000Z');
    });

    test('falls back to definition as prompt when translation is empty', () {
      final word = _word().copyWith();
      final noTranslation = Word(
        id: word.id, word: word.word, definition: word.definition,
        sentence: word.sentence, translation: '', platform: word.platform,
        contentTitle: word.contentTitle, contentId: word.contentId,
        timestamp: word.timestamp, savedAt: word.savedAt,
        updatedAt: word.updatedAt,
      );
      final item = FlashcardItem.fromWord(noTranslation);
      expect(item.prompt, 'lasting for a very short time');
    });
  });

  group('FlashcardItem.fromSentence', () {
    test('tests 번역→원문: prompt is translation, answer is the original', () {
      final item = FlashcardItem.fromSentence(_sentence());
      expect(item.isWord, isFalse);
      expect(item.prompt, '인생에서 덧없지 않은 것은 없다.');
      expect(item.correctAnswer, 'Nothing in life is ephemeral.');
      expect(item.backHeadline, 'Nothing in life is ephemeral.');
      expect(item.backSubtext, '인생에서 덧없지 않은 것은 없다.');
      expect(item.backDetail, '');
      expect(item.backExample, '');
    });
  });
}
