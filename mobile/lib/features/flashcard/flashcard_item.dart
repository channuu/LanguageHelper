import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

/// One flashcard's testable content. Word items test 뜻→단어 (see the
/// translation, type the English word); sentence items test 번역→원문.
class FlashcardItem {
  final String id;
  final bool isWord;
  final String promptLabel;
  final String prompt;
  final String correctAnswer;
  final String backHeadline;
  final String backSubtext;
  final String backDetail;
  final String backExample;
  final String contentTitle;
  final String platform;
  final int reviewLevel;
  final String? lastReviewedAt;

  const FlashcardItem({
    required this.id,
    required this.isWord,
    required this.promptLabel,
    required this.prompt,
    required this.correctAnswer,
    required this.backHeadline,
    required this.backSubtext,
    required this.backDetail,
    required this.backExample,
    required this.contentTitle,
    required this.platform,
    required this.reviewLevel,
    required this.lastReviewedAt,
  });

  factory FlashcardItem.fromWord(Word w) => FlashcardItem(
        id: w.id,
        isWord: true,
        promptLabel: '영어로 어떻게 말할까요?',
        prompt: w.translation.isNotEmpty ? w.translation : w.definition,
        correctAnswer: w.word,
        backHeadline: w.word,
        backSubtext: w.translation,
        backDetail: w.definition,
        backExample: w.sentence,
        contentTitle: w.contentTitle,
        platform: w.platform,
        reviewLevel: w.reviewLevel,
        lastReviewedAt: w.lastReviewedAt,
      );

  factory FlashcardItem.fromSentence(Sentence s) => FlashcardItem(
        id: s.id,
        isWord: false,
        promptLabel: '원문을 입력해보세요',
        prompt: s.translation,
        correctAnswer: s.original,
        backHeadline: s.original,
        backSubtext: s.translation,
        backDetail: '',
        backExample: '',
        contentTitle: s.contentTitle,
        platform: s.platform,
        reviewLevel: s.reviewLevel,
        lastReviewedAt: s.lastReviewedAt,
      );
}
