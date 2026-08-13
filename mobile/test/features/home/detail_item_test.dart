// mobile/test/features/home/detail_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/data/models/sentence.dart';
import 'package:english_helper_app/data/models/word.dart';
import 'package:english_helper_app/features/home/detail_item.dart';

void main() {
  group('DetailItem.fromWord', () {
    test('maps word/definition/translation into headline/detail', () {
      final word = Word(
        id: 'w1',
        word: 'ephemeral',
        definition: 'lasting for a very short time',
        translation: '덧없는',
        platform: 'youtube',
        contentTitle: 'Some Video',
        contentId: 'dQw4w9WgXcQ',
        timestamp: 142.5,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromWord(word);

      expect(item.id, 'w1');
      expect(item.headline, 'ephemeral');
      expect(item.detail, 'lasting for a very short time\n덧없는');
      expect(item.platform, 'youtube');
      expect(item.contentId, 'dQw4w9WgXcQ');
      expect(item.contentTitle, 'Some Video');
      expect(item.timestamp, 142.5);
    });

    test('omits empty definition/translation from detail', () {
      final word = Word(
        id: 'w2',
        word: 'brief',
        platform: 'netflix',
        contentTitle: 'Title',
        contentId: 'abc',
        timestamp: 10,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromWord(word);

      expect(item.detail, '');
    });
  });

  group('DetailItem.fromSentence', () {
    test('maps original/translation into headline/detail', () {
      final sentence = Sentence(
        id: 's1',
        original: 'Nothing in life is ephemeral.',
        translation: '인생에서 덧없지 않은 것은 없다.',
        platform: 'youtube',
        contentTitle: 'Some Video',
        contentId: 'dQw4w9WgXcQ',
        timestamp: 142.5,
        savedAt: '2026-08-14T00:00:00.000Z',
      );

      final item = DetailItem.fromSentence(sentence);

      expect(item.id, 's1');
      expect(item.headline, 'Nothing in life is ephemeral.');
      expect(item.detail, '인생에서 덧없지 않은 것은 없다.');
      expect(item.platform, 'youtube');
      expect(item.contentId, 'dQw4w9WgXcQ');
      expect(item.contentTitle, 'Some Video');
      expect(item.timestamp, 142.5);
    });
  });
}
