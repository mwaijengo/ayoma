import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/catalog.dart';

sealed class PlayerEvent {
  const PlayerEvent();
}

class PlayerStateEvent extends PlayerEvent {
  const PlayerStateEvent({required this.buffering, required this.playing, required this.ended});

  final bool buffering;
  final bool playing;
  final bool ended;
}

class PlayerSizeEvent extends PlayerEvent {
  const PlayerSizeEvent(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 16 / 9 : width / height;
}

class PlayerErrorEvent extends PlayerEvent {
  const PlayerErrorEvent({required this.code, required this.drm, required this.detail, this.text, this.openUrl});

  final String code;
  final bool drm;
  final String detail;
  final String? text;

  /// A page the user can open instead, e.g. a YouTube video that blocks embedding.
  final String? openUrl;

  String get message {
    if (text != null) return text!;
    if (drm) return 'Imeshindikana kufungua ulinzi wa chaneli hii (DRM).';
    if (code.contains('NETWORK') || code.contains('TIMEOUT')) {
      return 'Mtandao unasumbua. Angalia bando lako kisha ujaribu tena.';
    }
    if (code.contains('BAD_HTTP_STATUS') || code.contains('FILE_NOT_FOUND')) {
      return 'Chaneli hii haipatikani kwa sasa. Jaribu tena baadaye.';
    }
    return 'Imeshindikana kucheza chaneli hii. Jaribu tena.';
  }
}

/// What the player screen drives: the native stream player or the YouTube embed.
abstract interface class StreamPlayer {
  Stream<PlayerEvent> get events;
  Widget get view;
  Future<void> play();
  Future<void> pause();
  Future<void> retry();
  Future<void> setMuted(bool muted);
  Future<void> setMaxHeight(int maxHeight);
  Future<void> dispose();
}

/// Media3 (ExoPlayer) on Android, drawn into a Flutter [Texture].
/// Handles HLS, DASH, ClearKey, Widevine and custom request headers.
class NativePlayer implements StreamPlayer {
  NativePlayer._(this.textureId)
    : events = EventChannel('ayoma/player/$textureId').receiveBroadcastStream().map(_parse).where((e) => e != null).cast();

  static const _channel = MethodChannel('ayoma/player');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// [playback] is the `playback` object from the server.
  static Future<NativePlayer> open(Json playback, {required int maxHeight, required bool muted}) async {
    final id = await _channel.invokeMethod<int>('create', {...playback, 'maxHeight': maxHeight, 'muted': muted});
    return NativePlayer._(id!);
  }

  static Future<void> keepScreenOn(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on PlatformException catch (_) {
      // Not critical; the screen may just dim during playback.
    }
  }

  final int textureId;
  @override
  final Stream<PlayerEvent> events;
  bool _disposed = false;

  @override
  late final Widget view = Texture(textureId: textureId);

  @override
  Future<void> play() => _call('play');
  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> retry() => _call('retry');
  @override
  Future<void> setMuted(bool muted) => _call('setMuted', {'muted': muted});
  @override
  Future<void> setMaxHeight(int maxHeight) => _call('setMaxHeight', {'maxHeight': maxHeight});

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _call('dispose');
    _disposed = true;
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    if (_disposed) return;
    await _channel.invokeMethod<void>(method, {'id': textureId, ...args});
  }

  static PlayerEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    switch (raw['event']) {
      case 'state':
        return PlayerStateEvent(
          buffering: raw['state'] == 'buffering' || raw['state'] == 'idle',
          playing: raw['playing'] == true,
          ended: raw['state'] == 'ended',
        );
      case 'size':
        return PlayerSizeEvent((raw['width'] as num).toInt(), (raw['height'] as num).toInt());
      case 'error':
        return PlayerErrorEvent(
          code: '${raw['code'] ?? ''}',
          drm: raw['drm'] == true,
          detail: '${raw['message'] ?? ''}',
        );
    }
    return null;
  }
}
