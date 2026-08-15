class Word {
  final String id;
  final String word;
  final String definition;
  final String sentence;
  final String translation;
  final String platform;
  final String contentTitle;
  final String contentId;
  final double timestamp;
  final String savedAt;
  final int reviewCount;
  final String? nextReviewAt;
  final int reviewLevel;
  final String? lastReviewedAt;

  const Word({
    required this.id,
    required this.word,
    this.definition = '',
    this.sentence = '',
    this.translation = '',
    required this.platform,
    required this.contentTitle,
    required this.contentId,
    required this.timestamp,
    required this.savedAt,
    this.reviewCount = 0,
    this.nextReviewAt,
    this.reviewLevel = 0,
    this.lastReviewedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'word': word,
        'definition': definition,
        'sentence': sentence,
        'translation': translation,
        'platform': platform,
        'content_title': contentTitle,
        'content_id': contentId,
        'timestamp': timestamp,
        'saved_at': savedAt,
        'review_count': reviewCount,
        'next_review_at': nextReviewAt,
        'review_level': reviewLevel,
        'last_reviewed_at': lastReviewedAt,
      };

  factory Word.fromMap(Map<String, Object?> map) => Word(
        id: map['id'] as String,
        word: map['word'] as String,
        definition: (map['definition'] as String?) ?? '',
        sentence: (map['sentence'] as String?) ?? '',
        translation: (map['translation'] as String?) ?? '',
        platform: (map['platform'] as String?) ?? '',
        contentTitle: (map['content_title'] as String?) ?? '',
        contentId: (map['content_id'] as String?) ?? '',
        timestamp: (map['timestamp'] as num?)?.toDouble() ?? 0,
        savedAt: (map['saved_at'] as String?) ?? '',
        reviewCount: (map['review_count'] as int?) ?? 0,
        nextReviewAt: map['next_review_at'] as String?,
        reviewLevel: (map['review_level'] as int?) ?? 0,
        lastReviewedAt: map['last_reviewed_at'] as String?,
      );

  Word copyWith({
    int? reviewCount,
    String? nextReviewAt,
    int? reviewLevel,
    String? lastReviewedAt,
  }) =>
      Word(
        id: id,
        word: word,
        definition: definition,
        sentence: sentence,
        translation: translation,
        platform: platform,
        contentTitle: contentTitle,
        contentId: contentId,
        timestamp: timestamp,
        savedAt: savedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
        reviewLevel: reviewLevel ?? this.reviewLevel,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      );
}
