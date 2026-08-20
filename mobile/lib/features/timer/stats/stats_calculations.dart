import '../../../data/models/sentence.dart';
import '../../../data/models/study_session.dart';
import '../../../data/models/word.dart';

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Sums [StudySession.durationSeconds] per calendar day (local midnight).
Map<DateTime, int> groupSessionsByDay(List<StudySession> sessions) {
  final map = <DateTime, int>{};
  for (final s in sessions) {
    final day = _dateOnly(s.startedAt);
    map[day] = (map[day] ?? 0) + s.durationSeconds;
  }
  return map;
}

/// Counts session rows (not summed duration) per calendar day.
Map<DateTime, int> countSessionsByDay(List<StudySession> sessions) {
  final map = <DateTime, int>{};
  for (final s in sessions) {
    final day = _dateOnly(s.startedAt);
    map[day] = (map[day] ?? 0) + 1;
  }
  return map;
}

/// Counts saved [Word]s and [Sentence]s together per calendar day, keyed by
/// their `savedAt` field. Entries with an empty or unparseable `savedAt`
/// are skipped rather than thrown — `Word.savedAt`/`Sentence.savedAt`
/// default to `''` when the underlying DB column is missing/null, and an
/// empty string is not a valid ISO8601 date.
Map<DateTime, int> groupSavesByDay(List<Word> words, List<Sentence> sentences) {
  final map = <DateTime, int>{};
  void addAll(Iterable<String> savedAts) {
    for (final raw in savedAts) {
      if (raw.isEmpty) continue;
      DateTime parsed;
      try {
        parsed = DateTime.parse(raw);
      } catch (_) {
        continue;
      }
      final day = _dateOnly(parsed);
      map[day] = (map[day] ?? 0) + 1;
    }
  }

  addAll(words.map((w) => w.savedAt));
  addAll(sentences.map((s) => s.savedAt));
  return map;
}

/// Consecutive days (ending at [today], inclusive) present with a positive
/// value in [dayTotals]. 0 if [today] itself has no activity yet.
int currentStreakDays(Map<DateTime, int> dayTotals, {DateTime? today}) {
  final start = _dateOnly(today ?? DateTime.now());
  var streak = 0;
  var day = start;
  while ((dayTotals[day] ?? 0) > 0) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

/// The longest run of consecutive active days found anywhere in
/// [dayTotals] (not necessarily ending today).
int longestStreakDays(Map<DateTime, int> dayTotals) {
  final activeDays = dayTotals.entries.where((e) => e.value > 0).map((e) => e.key).toList()
    ..sort();
  if (activeDays.isEmpty) return 0;
  var longest = 1;
  var current = 1;
  for (var i = 1; i < activeDays.length; i++) {
    final gap = activeDays[i].difference(activeDays[i - 1]).inDays;
    current = gap == 1 ? current + 1 : 1;
    if (current > longest) longest = current;
  }
  return longest;
}

/// Active-vs-elapsed day counts for [monthStart]..[throughDay] (both
/// inclusive, same-month range expected but not enforced).
({int active, int elapsed}) monthActivityCounts(
  Map<DateTime, int> dayTotals,
  DateTime monthStart,
  DateTime throughDay,
) {
  var elapsed = 0;
  var active = 0;
  var day = _dateOnly(monthStart);
  final end = _dateOnly(throughDay);
  while (!day.isAfter(end)) {
    elapsed++;
    if ((dayTotals[day] ?? 0) > 0) active++;
    day = day.add(const Duration(days: 1));
  }
  return (active: active, elapsed: elapsed);
}

/// `active / elapsed` from [monthActivityCounts], or 0 if elapsed is 0.
double monthlyActivityRate(Map<DateTime, int> dayTotals, DateTime monthStart, DateTime throughDay) {
  final counts = monthActivityCounts(dayTotals, monthStart, throughDay);
  if (counts.elapsed == 0) return 0;
  return counts.active / counts.elapsed;
}

/// Sum of [dayTotals] values for days in `[start, end)` (end exclusive).
int sumSecondsInRange(Map<DateTime, int> dayTotals, DateTime start, DateTime end) {
  var total = 0;
  var day = _dateOnly(start);
  final endDay = _dateOnly(end);
  while (day.isBefore(endDay)) {
    total += dayTotals[day] ?? 0;
    day = day.add(const Duration(days: 1));
  }
  return total;
}

/// Percentage change of [currentTotal] vs [previousTotal], rounded to the
/// nearest integer. Null when [previousTotal] is 0 — there's no baseline to
/// compare against, so the delta badge should be omitted rather than
/// showing a meaningless "+inf%".
int? periodDeltaPercent(int currentTotal, int previousTotal) {
  if (previousTotal <= 0) return null;
  return ((currentTotal - previousTotal) / previousTotal * 100).round();
}

/// 0 (no dot) / 1 (small) / 2 (medium) / 3 (large) calendar-cell dot tier
/// for a day with [daySeconds] of activity, relative to [maxSecondsInMonth]
/// (the busiest day in the displayed month). Thresholds: <1/3 → 1,
/// 1/3..2/3 inclusive → 2, >2/3 → 3.
int calendarDotTier(int daySeconds, int maxSecondsInMonth) {
  if (daySeconds <= 0 || maxSecondsInMonth <= 0) return 0;
  final fraction = daySeconds / maxSecondsInMonth;
  if (fraction > 2 / 3) return 3;
  if (fraction >= 1 / 3) return 2;
  return 1;
}
