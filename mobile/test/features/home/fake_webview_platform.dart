// Minimal fake `webview_flutter` platform implementation used only so that
// widget tests can construct a real `YoutubePlayerController` /
// `YoutubePlayer` (from youtube_player_flutter 10.x, which wraps
// youtube_player_iframe + webview_flutter) without a real platform WebView
// engine being available. Overrides just enough of the abstract surface to
// avoid the `UnimplementedError` default bodies that the platform interface
// throws for unhandled calls in a headless `flutter test` run.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakePlatformWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  final Map<String, JavaScriptChannelParams> _channels = {};

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    // Simulate the page firing the iframe API's "onReady" event once the
    // (fake) HTML/JS has "loaded", so the controller's readiness Completer
    // resolves instead of hanging until the real 30s timeout.
    for (final channel in _channels.values) {
      channel.onMessageReceived(
        JavaScriptMessage(message: '{"playerId": "${channel.name}", "Ready": null}'),
      );
    }
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    _channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<String?> currentUrl() async => null;
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
