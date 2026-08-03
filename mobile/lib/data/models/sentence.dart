class Sentence {
  final String id;
  final String original;
  final String translation;
  final String platform;
  final String contentTitle;
  final String contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;

  const Sentence({
    required this.id,
    required this.original,
    this.translation = '',
    required this.platform,
    required this.contentTitle,
    required this.contentId,
    required this.timestamp,
    required this.savedAt,
    this.reviewCount = 0,
    this.nextReviewAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'original': original,
        'translation': translation,
        'platform': platform,
        'content_title': contentTitle,
        'content_id': contentId,
        'timestamp': timestamp,
        'saved_at': savedAt,
        'review_count': reviewCount,
        'next_review_at': nextReviewAt,
      };

  factory Sentence.fromMap(Map<String, Object?> map) => Sentence(
        id: map['id'] as String,
        original: map['original'] as String,
        translation: (map['translation'] as String?) ?? '',
        platform: (map['platform'] as String?) ?? '',
        contentTitle: (map['content_title'] as String?) ?? '',
        contentId: (map['content_id'] as String?) ?? '',
        timestamp: (map['timestamp'] as num?)?.toDouble() ?? 0,
        savedAt: (map['saved_at'] as String?) ?? '',
        reviewCount: (map['review_count'] as int?) ?? 0,
        nextReviewAt: map['next_review_at'] as String?,
      );

  Sentence copyWith({int? reviewCount, String? nextReviewAt}) => Sentence(
        id: id,
        original: original,
        translation: translation,
        platform: platform,
        contentTitle: contentTitle,
        contentId: contentId,
        timestamp: timestamp,
        savedAt: savedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      );
}
