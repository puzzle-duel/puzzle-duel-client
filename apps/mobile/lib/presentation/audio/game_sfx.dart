import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Presentation-only arcade SFX events.
enum GameSfxEvent {
  place,
  reject,
  clear,
  cascade,
  chainComplete,
  roundEnd,
}

/// Maps clear-wave index to SFX (wave 1 = clear, later = cascade).
GameSfxEvent sfxForClearWave(int wave) =>
    wave <= 1 ? GameSfxEvent.clear : GameSfxEvent.cascade;

/// Mute-ready SFX API. Implementations must never throw into gameplay.
abstract class GameSfx extends ChangeNotifier {
  bool get muted;
  set muted(bool value);
  void play(GameSfxEvent event);
}

/// Asset-backed SFX with debounce, haptics, and fail-soft playback.
final class AssetGameSfx extends GameSfx {
  AssetGameSfx({AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  final List<AudioPlayer> _pool = [];
  final Map<GameSfxEvent, DateTime> _lastPlayed = {};

  bool _muted = false;
  bool _disposed = false;
  bool _audioAvailable = true;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    notifyListeners();
  }

  static const _asset = {
    GameSfxEvent.place: 'sfx/place.wav',
    GameSfxEvent.reject: 'sfx/reject.wav',
    GameSfxEvent.clear: 'sfx/clear.wav',
    GameSfxEvent.cascade: 'sfx/cascade.wav',
    GameSfxEvent.chainComplete: 'sfx/chain_complete.wav',
    GameSfxEvent.roundEnd: 'sfx/round_end.wav',
  };

  static const _minInterval = {
    GameSfxEvent.place: Duration(milliseconds: 40),
    GameSfxEvent.reject: Duration(milliseconds: 140),
    GameSfxEvent.clear: Duration(milliseconds: 60),
    GameSfxEvent.cascade: Duration(milliseconds: 60),
    GameSfxEvent.chainComplete: Duration(milliseconds: 200),
    GameSfxEvent.roundEnd: Duration(milliseconds: 400),
  };

  @override
  void play(GameSfxEvent event) {
    if (_disposed || _muted || !_audioAvailable) return;
    final now = DateTime.now();
    final last = _lastPlayed[event];
    final gap = _minInterval[event] ?? Duration.zero;
    if (last != null && now.difference(last) < gap) return;
    _lastPlayed[event] = now;

    try {
      switch (event) {
        case GameSfxEvent.reject:
          HapticFeedback.lightImpact();
        case GameSfxEvent.place:
          HapticFeedback.selectionClick();
        case GameSfxEvent.clear:
        case GameSfxEvent.cascade:
        case GameSfxEvent.chainComplete:
        case GameSfxEvent.roundEnd:
          HapticFeedback.mediumImpact();
      }
    } catch (_) {}

    // Isolate plugin/channel failures from gameplay / test zones.
    scheduleMicrotask(() {
      runZonedGuarded(() {
        // ignore: discarded_futures
        _playAsset(event);
      }, _onAudioError);
    });
  }

  void _onAudioError(Object error, StackTrace stack) {
    _audioAvailable = false;
    assert(() {
      debugPrint('GameSfx disabled after error: $error\n$stack');
      return true;
    }());
  }

  Future<void> _playAsset(GameSfxEvent event) async {
    if (!_audioAvailable) return;
    final path = _asset[event];
    if (path == null) return;
    try {
      final player = _acquire();
      if (player == null) return;
      await player.stop();
      await player.play(AssetSource(path), volume: 0.7);
    } catch (error, stack) {
      _onAudioError(error, stack);
    }
  }

  AudioPlayer? _acquire() {
    if (!_audioAvailable) return null;
    try {
      if (_pool.length < 4) {
        final created = _playerFactory();
        _pool.add(created);
        return created;
      }
      final next = _pool.removeAt(0);
      _pool.add(next);
      return next;
    } catch (error, stack) {
      _onAudioError(error, stack);
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final p in _pool) {
      // ignore: discarded_futures
      p.dispose();
    }
    _pool.clear();
    super.dispose();
  }
}

/// Test double that records plays without audio I/O.
final class RecordingGameSfx extends GameSfx {
  final List<GameSfxEvent> events = [];
  bool _muted = false;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    notifyListeners();
  }

  @override
  void play(GameSfxEvent event) {
    if (_muted) return;
    events.add(event);
  }
}
