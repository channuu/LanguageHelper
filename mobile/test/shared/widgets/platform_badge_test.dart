import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_helper_app/shared/widgets/platform_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows YouTube label for youtube platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'youtube')));
    expect(find.text('YouTube'), findsOneWidget);
  });

  testWidgets('shows Netflix label for netflix platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'netflix')));
    expect(find.text('Netflix'), findsOneWidget);
  });

  testWidgets('shows Disney+ label for disney platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'disney')));
    expect(find.text('Disney+'), findsOneWidget);
  });

  testWidgets('shows 쿠팡플레이 label for coupang platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'coupang')));
    expect(find.text('쿠팡플레이'), findsOneWidget);
  });

  testWidgets('falls back to the raw platform string for an unknown platform', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'vimeo')));
    expect(find.text('vimeo'), findsOneWidget);
  });

  testWidgets('platform match is case-insensitive', (tester) async {
    await tester.pumpWidget(wrap(const PlatformBadge(platform: 'YouTube')));
    expect(find.text('YouTube'), findsOneWidget);
  });
}
