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

/// Canonical SFX sequence for a resolved move's waves (no invented clears).
List<GameSfxEvent> sfxEventsForWaves(
  Iterable<int> waveNumbers, {
  bool includePlace = true,
}) {
  final events = <GameSfxEvent>[];
  if (includePlace) {
    events.add(GameSfxEvent.place);
  }
  var cleared = false;
  for (final wave in waveNumbers) {
    events.add(sfxForClearWave(wave));
    cleared = true;
  }
  if (cleared) {
    events.add(GameSfxEvent.chainComplete);
  }
  return events;
}

/// Mute-ready SFX API. Implementations must never throw into gameplay.
abstract class GameSfx extends ChangeNotifier {
  bool get muted;
  set muted(bool value);
  void play(GameSfxEvent event);
}

/// Asset-backed SFX with debounce, haptics, and fail-soft playback.
///
/// Lifecycle rules:
/// - Queued work checks mute/dispose before acquire, after awaits, before play.
/// - Dispose is safe while playback is in flight (late work is dropped).
/// - One transient failure does not permanently disable audio.
/// - Distinct events may overlap via a small player pool; same-event spam is
///   debounced.
final class AssetGameSfx extends GameSfx {
  AssetGameSfx({
    AudioPlayer Function()? playerFactory,
    this.playOverride,
  }) : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;

  /// Test seam: when set, skips AudioPlayer and invokes this instead.
  @visibleForTesting
  final Future<void> Function(String assetPath, double volume)? playOverride;
  final List<AudioPlayer> _pool = [];
  final Map<GameSfxEvent, DateTime> _lastPlayed = {};
  final Set<int> _inFlight = {};

  bool _muted = false;
  bool _disposed = false;
  int _playEpoch = 0;
  int _nextTicket = 0;
  int _failureStreak = 0;
  DateTime? _cooldownUntil;
  static const _maxTransientFailures = 3;
  static const _cooldown = Duration(seconds: 2);

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    // Invalidate queued async work so mute takes effect immediately.
    _playEpoch++;
    notifyListeners();
  }

  /// True when a short cooldown is active after repeated transient failures.
  @visibleForTesting
  bool get isInFailureCooldown {
    final until = _cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
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

  bool get _playbackAllowed {
    if (_disposed || _muted) return false;
    final until = _cooldownUntil;
    if (until != null && DateTime.now().isBefore(until)) return false;
    return true;
  }

  @override
  void play(GameSfxEvent event) {
    if (!_playbackAllowed) return;
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

    final epoch = _playEpoch;
    final ticket = ++_nextTicket;
    _inFlight.add(ticket);

    // Isolate plugin/channel failures from gameplay / test zones.
    scheduleMicrotask(() {
      runZonedGuarded(() {
        // ignore: discarded_futures
        _playAsset(event, epoch: epoch, ticket: ticket);
      }, (error, stack) {
        _inFlight.remove(ticket);
        _noteTransientFailure(error, stack);
      });
    });
  }

  void _noteTransientFailure(Object error, StackTrace stack) {
    if (_disposed) return;
    _failureStreak++;
    assert(() {
      debugPrint('GameSfx transient failure ($_failureStreak): $error\n$stack');
      return true;
    }());
    if (_failureStreak >= _maxTransientFailures) {
      _cooldownUntil = DateTime.now().add(_cooldown);
      _failureStreak = 0;
    }
  }

  void _noteSuccess() {
    _failureStreak = 0;
    _cooldownUntil = null;
  }

  Future<void> _playAsset(
    GameSfxEvent event, {
    required int epoch,
    required int ticket,
  }) async {
    try {
      if (!_stillValid(epoch)) return;
      final path = _asset[event];
      if (path == null) return;

      final override = playOverride;
      if (override != null) {
        if (!_stillValid(epoch)) return;
        await override(path, 0.7);
        if (!_stillValid(epoch)) return;
        _noteSuccess();
        return;
      }

      if (!_stillValid(epoch)) return;
      final player = _acquire();
      if (player == null) return;
      if (!_stillValid(epoch)) return;

      await player.stop();
      if (!_stillValid(epoch)) return;

      await player.play(AssetSource(path), volume: 0.7);
      if (!_stillValid(epoch)) return;
      _noteSuccess();
    } catch (error, stack) {
      _noteTransientFailure(error, stack);
    } finally {
      _inFlight.remove(ticket);
    }
  }

  bool _stillValid(int epoch) =>
      !_disposed && !_muted && epoch == _playEpoch && !isInFailureCooldown;

  AudioPlayer? _acquire() {
    if (_disposed || _muted) return null;
    try {
      if (_pool.length < 4) {
        final created = _playerFactory();
        if (_disposed) {
          // ignore: discarded_futures
          created.dispose();
          return null;
        }
        _pool.add(created);
        return created;
      }
      final next = _pool.removeAt(0);
      _pool.add(next);
      return next;
    } catch (error, stack) {
      _noteTransientFailure(error, stack);
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playEpoch++;
    _inFlight.clear();
    final players = List<AudioPlayer>.from(_pool);
    _pool.clear();
    for (final p in players) {
      // ignore: discarded_futures
      Future<void>(() async {
        try {
          await p.stop();
        } catch (_) {}
        try {
          await p.dispose();
        } catch (_) {}
      });
    }
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
