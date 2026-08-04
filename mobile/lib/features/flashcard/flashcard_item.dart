import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

class FlashcardItem {
  final String id;
  final String front;
  final String back;
  final String contentTitle;
  final bool isWord;

  const FlashcardItem({
    required this.id,
    required this.front,
    required this.back,
    required this.contentTitle,
    required this.isWord,
  });

  factory FlashcardItem.fromWord(Word w) => FlashcardItem(
        id: w.id,
        front: w.word,
        back: [w.definition, w.sentence].where((s) => s.isNotEmpty).join('\n\n'),
        contentTitle: w.contentTitle,
        isWord: true,
      );

  factory FlashcardItem.fromSentence(Sentence s) => FlashcardItem(
        id: s.id,
        front: s.original,
        back: s.translation,
        contentTitle: s.contentTitle,
        isWord: false,
      );
}
