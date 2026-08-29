const _unset = Object();

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
  final int reviewLevel;
  final String? lastReviewedAt;
  final String updatedAt;
  final String? syncedAt;

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
    this.reviewLevel = 0,
    this.lastReviewedAt,
    required this.updatedAt,
    this.syncedAt,
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
        'review_level': reviewLevel,
        'last_reviewed_at': lastReviewedAt,
        'updated_at': updatedAt,
        'synced_at': syncedAt,
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
        reviewLevel: (map['review_level'] as int?) ?? 0,
        lastReviewedAt: map['last_reviewed_at'] as String?,
        // Migration backfills updated_at, but fall back to saved_at for
        // rows that somehow arrive without it (e.g. imported backups).
        updatedAt: (map['updated_at'] as String?) ??
            (map['saved_at'] as String?) ?? '',
        syncedAt: map['synced_at'] as String?,
      );

  Sentence copyWith({
    String? original,
    String? translation,
    int? reviewCount,
    Object? nextReviewAt = _unset,
    int? reviewLevel,
    Object? lastReviewedAt = _unset,
    String? updatedAt,
    Object? syncedAt = _unset,
  }) =>
      Sentence(
        id: id,
        original: original ?? this.original,
        translation: translation ?? this.translation,
        platform: platform,
        contentTitle: contentTitle,
        contentId: contentId,
        timestamp: timestamp,
        savedAt: savedAt,
        reviewCount: reviewCount ?? this.reviewCount,
        nextReviewAt: identical(nextReviewAt, _unset)
            ? this.nextReviewAt
            : nextReviewAt as String?,
        reviewLevel: reviewLevel ?? this.reviewLevel,
        lastReviewedAt: identical(lastReviewedAt, _unset)
            ? this.lastReviewedAt
            : lastReviewedAt as String?,
        updatedAt: updatedAt ?? this.updatedAt,
        syncedAt: identical(syncedAt, _unset)
            ? this.syncedAt
            : syncedAt as String?,
      );
}
