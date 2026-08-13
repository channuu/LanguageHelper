import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:english_helper_app/features/home/detail_item.dart';
import 'package:english_helper_app/features/home/item_detail_screen.dart';

import 'fake_webview_platform.dart';

DetailItem _youtubeItem({String contentId = 'dQw4w9WgXcQ'}) => DetailItem(
      id: 'w1',
      headline: 'ephemeral',
      detail: 'lasting for a very short time',
      platform: 'youtube',
      contentId: contentId,
      contentTitle: 'Some Video',
      timestamp: 142.5,
    );

DetailItem _netflixItem() => const DetailItem(
      id: 'w2',
      headline: 'brief',
      detail: '짧은',
      platform: 'netflix',
      contentId: '81234567',
      contentTitle: 'Some Show',
      timestamp: 10,
    );

void main() {
  WebViewPlatform.instance = FakeWebViewPlatform();

  Widget buildScreen(DetailItem item) {
    return MaterialApp(home: ItemDetailScreen(item: item));
  }

  testWidgets('shows headline, detail, and source info', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('lasting for a very short time'), findsOneWidget);
    expect(find.textContaining('Some Video'), findsOneWidget);
  });

  testWidgets('shows a play button for a valid YouTube item', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsOneWidget);
  });

  testWidgets('hides the play button for a non-YouTube item', (tester) async {
    await tester.pumpWidget(buildScreen(_netflixItem()));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsNothing);
  });

  testWidgets('shows an unplayable message for an invalid YouTube content ID', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem(contentId: 'not-a-valid-id')));
    await tester.pumpAndSettle();

    expect(find.text('재생하기'), findsNothing);
    expect(find.text('재생할 수 없는 항목입니다'), findsOneWidget);
  });

  testWidgets('tapping play swaps the button for an inline player', (tester) async {
    await tester.pumpWidget(buildScreen(_youtubeItem()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('재생하기'));
    // Not pumpAndSettle(): the real inline player schedules its own
    // recurring post-frame/overlay-timer work while "playing" (fine on a
    // real device), which never fully quiesces under the fake WebView
    // platform used here. A few bounded pumps are enough to let the button
    // swap for the player without waiting for full settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('재생하기'), findsNothing);
    expect(find.byType(YoutubePlayer), findsOneWidget);
  });
}
