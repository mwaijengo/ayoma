import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'native_player.dart';

/// Shows a website's own player page (e.g. `…/player.php?channel=1`) when a
/// link turns out to be a page rather than a stream.
class WebPagePlayer implements StreamPlayer {
  WebPagePlayer(this.url, {this.headers = const {}, this.muted = false}) {
    final userAgent = _header('User-Agent');
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (_disposed) return;
            _events.add(const PlayerStateEvent(buffering: false, playing: true, ended: false));
            _js(_fillScript);
            // Pages start muted and ask for a tap; touches never reach the page, so apply
            // the app's own mute choice (and start the video) a few times while it loads.
            for (final seconds in const [0, 1, 3, 6]) {
              Future.delayed(Duration(seconds: seconds), () async {
                await play();
                await setMuted(muted);
                // Pages with a "tap to unmute" screen expose a handler for that tap.
                if (!muted) await _js('if(typeof window.unmuteOrPlay==="function")window.unmuteOrPlay();');
              });
            }
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

  /// Makes the page's video stretch to its whole box instead of leaving black side bars.
  static const _fillScript =
      'if(!document.getElementById("ayoma-fit")){var s=document.createElement("style");s.id="ayoma-fit";'
      's.textContent="html,body{margin:0;background:#000}video{object-fit:fill!important}";'
      '(document.head||document.documentElement).appendChild(s);}';

  final String url;
  final Map<String, String> headers;
  /// Whether the app wants sound off; the page itself starts muted.
  bool muted;
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
        // Player sites often refuse (403) a request that names no Referer.
        if (_header('Referer') == null && uri.hasAuthority) 'Referer': '${uri.scheme}://${uri.authority}/',
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
  Future<void> setMuted(bool muted) {
    this.muted = muted;
    return _js('document.querySelectorAll("video").forEach(function(v){v.muted=$muted;});');
  }

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
