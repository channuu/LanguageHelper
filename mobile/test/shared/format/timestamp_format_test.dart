import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/format/timestamp_format.dart';

void main() {
  test('formats whole seconds under a minute', () {
    expect(formatTimestamp(0), '0:00');
    expect(formatTimestamp(59), '0:59');
  });

  test('formats minutes and seconds with zero-padded seconds', () {
    expect(formatTimestamp(60), '1:00');
    expect(formatTimestamp(142.5), '2:22');
  });

  test('truncates fractional seconds', () {
    expect(formatTimestamp(9.9), '0:09');
  });
}
