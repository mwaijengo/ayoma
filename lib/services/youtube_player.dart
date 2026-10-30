import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'native_player.dart';

/// A YouTube video, or the live stream a YouTube channel is currently running.
class YoutubeSource {
  const YoutubeSource._({required this.url, this.videoId, this.channelId});

  final String url;
  final String? videoId;
  final String? channelId;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _hosts = {'youtube.com', 'youtube-nocookie.com', 'youtu.be'};

  /// Null when [raw] is not a YouTube link. Handles watch, youtu.be, live,
  /// shorts, embed, `channel/<id>/live` and `@handle` links.
  static YoutubeSource? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|music)\.'), '');
    if (!_hosts.contains(host)) return null;
    final url = raw.trim();
    final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? video(String? id) => id != null && _videoId.hasMatch(id) ? id : null;

    if (host == 'youtu.be') return YoutubeSource._(url: url, videoId: video(path.firstOrNull));
    if (video(uri.queryParameters['v']) case final id?) return YoutubeSource._(url: url, videoId: id);
    if (path.length >= 2 && path[1] == 'live_stream') {
      return YoutubeSource._(url: url, channelId: uri.queryParameters['channel']);
    }
    if (path.length >= 2 && const {'embed', 'live', 'shorts', 'v', 'e'}.contains(path[0])) {
      return YoutubeSource._(url: url, videoId: video(path[1]));
    }
    if (path.length >= 2 && path[0] == 'channel' && path[1].startsWith('UC')) {
      return YoutubeSource._(url: url, channelId: path[1]);
    }
    // @handle, /c/name or /user/name: resolved from the page when opened.
    return YoutubeSource._(url: url);
  }

  bool get resolved => videoId != null || channelId != null;

  /// Finds the video for links that only name a channel.
  Future<YoutubeSource> resolve() async {
    if (resolved) return this;
    var page = url;
    if (!Uri.parse(page).path.endsWith('/live')) page = '${page.replaceFirst(RegExp(r'/+$'), '')}/live';
    final res = await http
        .get(Uri.parse(page), headers: const {'User-Agent': _browserAgent, 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 12));
    final html = res.body;
    final canonical = RegExp(r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([A-Za-z0-9_-]{11})"')
        .firstMatch(html);
    if (canonical != null) return YoutubeSource._(url: url, videoId: canonical.group(1));
    final channel = RegExp(r'"(?:channelId|externalId)":"(UC[A-Za-z0-9_-]{22})"').firstMatch(html);
    if (channel != null) return YoutubeSource._(url: url, channelId: channel.group(1));
    throw const FormatException('No YouTube video found');
  }

  static const _browserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
}

/// YouTube's own IFrame player in a WebView, driven by the AyomaMax controls.
class YoutubeEmbedPlayer implements StreamPlayer {
  YoutubeEmbedPlayer._(this._source, this._muted) {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('Ayoma', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          // Keeps taps on the YouTube logo or title from leaving the player.
          onNavigationRequest: (r) => r.isMainFrame ? NavigationDecision.prevent : NavigationDecision.navigate,
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false) _fail('NETWORK');
          },
        ),
      );
    final platform = _web.platform;
    if (platform is AndroidWebViewController) platform.setMediaPlaybackRequiresUserGesture(false);
    _events.add(const PlayerSizeEvent(16, 9));
    _load();
  }

  static Future<YoutubeEmbedPlayer> open(YoutubeSource source, {required bool muted}) async =>
      YoutubeEmbedPlayer._(await source.resolve(), muted);

  final YoutubeSource _source;
  bool _muted;
  late final WebViewController _web;
  final _events = StreamController<PlayerEvent>();
  /// Chromium draws video on its own hardware layer, which only shows when
  /// Android composites the WebView itself (hybrid composition).
  late final Widget _view = IgnorePointer(
    child: _web.platform is AndroidWebViewController
        ? WebViewWidget.fromPlatformCreationParams(
            params: AndroidWebViewWidgetCreationParams(
              controller: _web.platform,
              displayWithHybridComposition: true,
            ),
          )
        : WebViewWidget(controller: _web),
  );
  Timer? _readyTimeout;
  bool _disposed = false;
  bool _wantPlaying = true;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Widget get view => _view;

  void _load() {
    _readyTimeout?.cancel();
    _readyTimeout = Timer(const Duration(seconds: 25), () => _fail('TIMEOUT'));
    _events.add(const PlayerStateEvent(buffering: true, playing: false, ended: false));
    _web.loadHtmlString(_html(), baseUrl: _host);
  }

  String _html() {
    final config = jsonEncode({
      'host': _host,
      'width': '100%',
      'height': '100%',
      'videoId': _source.videoId ?? 'live_stream',
      'playerVars': {
        'autoplay': 1,
        'mute': _muted ? 1 : 0,
        'controls': 0,
        'playsinline': 1,
        'rel': 0,
        'fs': 0,
        'disablekb': 1,
        'iv_load_policy': 3,
        'cc_load_policy': 0,
        'channel': ?_source.channelId,
      },
    });
    return '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script>
var player;
function send(m){Ayoma.postMessage(JSON.stringify(m));}
function onYouTubeIframeAPIReady(){
  var c=$config;
  c.events={
    onReady:function(e){send({event:'ready'});e.target.playVideo();},
    onStateChange:function(e){send({event:'state',state:e.data});if(e.data===5)e.target.playVideo();},
    onError:function(e){send({event:'error',code:e.data});}
  };
  player=new YT.Player('p',c);
}
</script>
<script src="https://www.youtube.com/iframe_api" onerror="send({event:'error',code:'NETWORK'})"></script>
</body></html>''';
  }

  void _onMessage(String raw) {
    if (_disposed) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    switch (msg['event']) {
      case 'ready':
        _readyTimeout?.cancel();
      case 'state':
        final state = msg['state'];
        if (state == 1) _readyTimeout?.cancel();
        // YouTube pauses itself when the view is resized (e.g. on rotation).
        if (state == 2 && _wantPlaying) {
          _js('playVideo');
          return;
        }
        _events.add(
          PlayerStateEvent(
            buffering: state == 3 || state == -1 || state == 5,
            playing: state == 1,
            ended: state == 0,
          ),
        );
      case 'error':
        _fail('${msg['code']}');
    }
  }

  void _fail(String code) {
    if (_disposed) return;
    _readyTimeout?.cancel();
    final (text, canOpen) = switch (code) {
      '100' => ('Video hii ya YouTube haipo tena au imefanywa ya siri.', false),
      '101' || '150' || '152' => ('Mmiliki wa video hii hairuhusu ichezwe nje ya YouTube.', true),
      '2' => ('Link ya YouTube ya chaneli hii si sahihi.', false),
      'NETWORK' || 'TIMEOUT' => ('Mtandao unasumbua. Angalia bando lako kisha ujaribu tena.', false),
      _ => ('Imeshindikana kucheza video hii ya YouTube. Jaribu tena.', true),
    };
    _events.add(PlayerErrorEvent(code: 'YOUTUBE_$code', drm: false, detail: code, text: text, openUrl: canOpen ? _source.url : null));
  }

  Future<void> _js(String method) async {
    if (_disposed) return;
    try {
      await _web.runJavaScript('if(window.player&&player.$method)player.$method();');
    } catch (_) {
      // The page may still be loading; the next state change catches up.
    }
  }

  @override
  Future<void> play() {
    _wantPlaying = true;
    return _js('playVideo');
  }

  @override
  Future<void> pause() {
    _wantPlaying = false;
    return _js('pauseVideo');
  }

  @override
  Future<void> retry() async {
    if (!_disposed) _load();
  }

  @override
  Future<void> setMuted(bool muted) {
    _muted = muted;
    return _js(muted ? 'mute' : 'unMute');
  }

  /// YouTube picks the quality itself from the connection speed.
  @override
  Future<void> setMaxHeight(int maxHeight) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _js('stopVideo');
    _disposed = true;
    _readyTimeout?.cancel();
    await _events.close();
  }

  static const _host = 'https://www.youtube-nocookie.com';
}
