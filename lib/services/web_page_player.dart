import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'native_player.dart';

/// Shows a website's own player page (e.g. `…/player.php?channel=1`) when a
/// link turns out to be a page rather than a stream.
class WebPagePlayer implements StreamPlayer {
  WebPagePlayer(this.url, {this.headers = const {}}) {
    final userAgent = _header('User-Agent');
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_disposed) return;
            _events.add(const PlayerStateEvent(buffering: false, playing: true, ended: false));
            play();
            Future.delayed(const Duration(seconds: 3), play);
          },
          onWebResourceError: (e) {
            if (_disposed || !(e.isForMainFrame ?? false)) return;
            _events.add(
              const PlayerErrorEvent(
                code: 'WEB_PAGE_NETWORK',
                drm: false,
                detail: '',
                text: 'Mtandao unasumbua. Angalia bando lako kisha ujaribu tena.',
              ),
            );
          },
        ),
      );
    if (userAgent != null) _web.setUserAgent(userAgent);
    final platform = _web.platform;
    if (platform is AndroidWebViewController) platform.setMediaPlaybackRequiresUserGesture(false);
    _events.add(const PlayerSizeEvent(16, 9));
    _load();
  }

  final String url;
  final Map<String, String> headers;
  late final WebViewController _web;
  final _events = StreamController<PlayerEvent>();
  bool _disposed = false;

  /// Video on the page only shows when Android composites the WebView itself.
  /// Touches go to the app's own controls; the page autoplays.
  @override
  late final Widget view = IgnorePointer(
    child: _web.platform is AndroidWebViewController
        ? WebViewWidget.fromPlatformCreationParams(
            params: AndroidWebViewWidgetCreationParams(
              controller: _web.platform,
              displayWithHybridComposition: true,
            ),
          )
        : WebViewWidget(controller: _web),
  );

  @override
  Stream<PlayerEvent> get events => _events.stream;

  String? _header(String name) =>
      headers.entries.where((e) => e.key.toLowerCase() == name.toLowerCase()).firstOrNull?.value;

  void _load() {
    _events.add(const PlayerStateEvent(buffering: true, playing: false, ended: false));
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _web.loadRequest(
      uri,
      headers: {
        for (final e in headers.entries)
          if (e.key.toLowerCase() != 'user-agent') e.key: e.value,
      },
    );
  }

  Future<void> _js(String code) async {
    if (_disposed) return;
    try {
      await _web.runJavaScript(code);
    } catch (_) {
      // The page may not have loaded yet.
    }
  }

  @override
  Future<void> play() =>
      _js('document.querySelectorAll("video").forEach(function(v){var p=v.play();if(p)p.catch(function(){});});');

  @override
  Future<void> pause() => _js('document.querySelectorAll("video").forEach(function(v){v.pause();});');

  @override
  Future<void> retry() async {
    if (!_disposed) _load();
  }

  @override
  Future<void> setMuted(bool muted) =>
      _js('document.querySelectorAll("video").forEach(function(v){v.muted=$muted;});');

  @override
  Future<void> setMaxHeight(int maxHeight) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await pause();
    _disposed = true;
    await _events.close();
  }
}
