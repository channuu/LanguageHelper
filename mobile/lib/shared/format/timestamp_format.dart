/// Formats a duration in seconds as `m:ss` (minutes not zero-padded,
/// seconds zero-padded to 2 digits), e.g. `formatTimestamp(142.5) == '2:22'`.
String formatTimestamp(double seconds) {
  final total = seconds.toInt();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
