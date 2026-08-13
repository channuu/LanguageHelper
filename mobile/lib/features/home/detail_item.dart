import '../../data/models/sentence.dart';
import '../../data/models/word.dart';

class DetailItem {
  final String id;
  final String headline;
  final String detail;
  final String platform;
  final String contentId;
  final String contentTitle;
  final double timestamp;

  const DetailItem({
    required this.id,
    required this.headline,
    required this.detail,
    required this.platform,
    required this.contentId,
    required this.contentTitle,
    required this.timestamp,
  });

  factory DetailItem.fromWord(Word w) => DetailItem(
        id: w.id,
        headline: w.word,
        detail: [w.definition, w.translation].where((s) => s.isNotEmpty).join('\n'),
        platform: w.platform,
        contentId: w.contentId,
        contentTitle: w.contentTitle,
        timestamp: w.timestamp,
      );

  factory DetailItem.fromSentence(Sentence s) => DetailItem(
        id: s.id,
        headline: s.original,
        detail: s.translation,
        platform: s.platform,
        contentId: s.contentId,
        contentTitle: s.contentTitle,
        timestamp: s.timestamp,
      );
}
