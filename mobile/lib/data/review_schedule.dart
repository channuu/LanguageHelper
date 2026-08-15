/// Fixed-schedule spaced repetition (design.md §5.1 "Option B", compressed
/// to 5 levels). Index = review level (0-4). `review_level` is a plain int
/// column so a future FSRS ("Option A") swap-in only needs to replace this
/// module, not the schema or UI.
const List<String> kReviewLevelNames = ['새 항목', '학습 중', '복습 필요', '익숙해짐', '완전히 외움'];

/// Days until next review per level. Level 0 (new) has no schedule.
const List<int?> kReviewIntervalDays = [null, 1, 7, 30, 90];

const int kMaxReviewLevel = 4;

/// ISO8601 next-review timestamp for [level], counted from [from].
/// Returns null for level 0 (new items are never scheduled).
String? nextReviewAtForLevel(int level, DateTime from) {
  final days = kReviewIntervalDays[level];
  if (days == null) return null;
  return from.add(Duration(days: days)).toIso8601String();
}

/// Whether an item at [reviewLevel] with the given [nextReviewAt] (ISO8601
/// or null) belongs in today's review queue.
bool isDueForReview(int reviewLevel, String? nextReviewAt) {
  if (reviewLevel == 0) return true;
  if (nextReviewAt == null) return true;
  return DateTime.parse(nextReviewAt).isBefore(DateTime.now());
}
