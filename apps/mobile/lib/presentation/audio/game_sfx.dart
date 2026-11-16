import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';

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

  /// True after a successful [prepare] (or immediate readiness for test doubles).
  bool get isPrepared;

  /// Non-blocking warm-up of players/assets. Safe to call multiple times.
  Future<void> prepare();

  void play(GameSfxEvent event);
}

/// Asset-backed SFX with debounce, haptics, fail-soft playback, and cold-start
/// preparation.
///
/// Lifecycle rules:
/// - Queued work checks mute/dispose before acquire, after awaits, before play.
/// - Dispose is safe while playback/prepare is in flight.
/// - One transient failure does not permanently disable audio.
/// - [prepare] must never block gameplay; [play] never awaits readiness.
final class AssetGameSfx extends GameSfx {
  AssetGameSfx({
    AudioPlayer Function()? playerFactory,
    this.playOverride,
    this.cacheLoadAll,
    int warmPoolSize = 2,
  }) : _playerFactory = playerFactory ?? AudioPlayer.new,
       _warmPoolSize = warmPoolSize.clamp(1, 4);

  final AudioPlayer Function() _playerFactory;
  final int _warmPoolSize;

  /// Test seam: when set, skips AudioPlayer and invokes this instead.
  @visibleForTesting
  final Future<void> Function(String assetPath, double volume)? playOverride;

  /// Test seam for AudioCache.loadAll.
  @visibleForTesting
  final Future<void> Function(List<String> paths)? cacheLoadAll;

  final List<AudioPlayer> _pool = [];
  final Map<GameSfxEvent, DateTime> _lastPlayed = {};
  final Set<int> _inFlight = {};

  bool _muted = false;
  bool _disposed = false;
  bool _prepared = false;
  int _playEpoch = 0;
  int _nextTicket = 0;
  int _failureStreak = 0;
  DateTime? _cooldownUntil;
  Future<void>? _prepareFuture;
  int _prepareCalls = 0;

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

  @override
  bool get isPrepared => _prepared;

  /// How many times [prepare] started work (tests: no duplicate prepare body).
  @visibleForTesting
  int get prepareCallCount => _prepareCalls;

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
  Future<void> prepare() {
    if (_disposed || _muted) return Future<void>.value();
    if (_prepared) return Future<void>.value();
    return _prepareFuture ??= _runPrepare();
  }

  Future<void> _runPrepare() async {
    _prepareCalls++;
    final epoch = _playEpoch;
    InteractionPerf.mark('sfx.prepare.start');
    final sw = Stopwatch()..start();
    try {
      final paths = _asset.values.toList(growable: false);
      final loader = cacheLoadAll;
      if (loader != null) {
        await loader(paths);
      } else if (playOverride == null) {
        await AudioCache.instance.loadAll(paths);
      }
      if (!_prepareStillValid(epoch)) return;

      // Bounded warm pool — never unlimited. Skip native players when the
      // test playOverride seam is active (no plugin channel in unit tests).
      if (playOverride == null) {
        while (_pool.length < _warmPoolSize && _prepareStillValid(epoch)) {
          final player = _playerFactory();
          if (_disposed) {
            // ignore: discarded_futures
            player.dispose();
            return;
          }
          _pool.add(player);
          // Decode/path warm-up without audible playback.
          try {
            await player.setSource(AssetSource(_asset[GameSfxEvent.place]!));
            await player.setVolume(0.7);
          } catch (error, stack) {
            _noteTransientFailure(error, stack);
          }
        }
      }

      if (!_prepareStillValid(epoch)) return;
      _prepared = true;
      InteractionPerf.mark('sfx.prepare.done');
      assert(() {
        debugPrint('GameSfx prepare ${sw.elapsedMilliseconds}ms');
        return true;
      }());
      notifyListeners();
    } catch (error, stack) {
      _noteTransientFailure(error, stack);
      // Allow a later prepare retry after cooldown/failure.
      _prepareFuture = null;
    }
  }

  bool _prepareStillValid(int epoch) =>
      !_disposed && !_muted && epoch == _playEpoch;

  @override
  void play(GameSfxEvent event) {
    if (!_playbackAllowed) return;
    final now = DateTime.now();
    final last = _lastPlayed[event];
    final gap = _minInterval[event] ?? Duration.zero;
    if (last != null && now.difference(last) < gap) return;
    _lastPlayed[event] = now;

    InteractionPerf.mark('sfx.play.${event.name}');

    // Kick prepare if first play raced ahead of warm-up — never await it.
    if (!_prepared && _prepareFuture == null) {
      // ignore: discarded_futures
      prepare();
    }

    // Haptics are best-effort and must not gate visuals.
    scheduleMicrotask(() {
      if (_disposed || _muted) return;
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
    });

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
    _prepared = true;
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
        InteractionPerf.mark('sfx.player.create_or_reuse');
        await override(path, 0.7);
        if (!_stillValid(epoch)) return;
        _noteSuccess();
        InteractionPerf.mark('sfx.playback.started');
        return;
      }

      if (!_stillValid(epoch)) return;
      final player = _acquire();
      if (player == null) return;
      if (!_stillValid(epoch)) return;

      InteractionPerf.mark('sfx.player.create_or_reuse');
      await player.stop();
      if (!_stillValid(epoch)) return;

      await player.play(AssetSource(path), volume: 0.7);
      if (!_stillValid(epoch)) return;
      _noteSuccess();
      InteractionPerf.mark('sfx.playback.started');
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
      if (_pool.isNotEmpty) {
        final next = _pool.removeAt(0);
        _pool.add(next);
        return next;
      }
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
    _prepareFuture = null;
    _prepared = false;
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
  bool _prepared = true;
  int prepareCallCount = 0;
  Completer<void>? prepareGate;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    notifyListeners();
  }

  @override
  bool get isPrepared => _prepared;

  set isPrepared(bool value) => _prepared = value;

  @override
  Future<void> prepare() async {
    prepareCallCount++;
    final gate = prepareGate;
    if (gate != null) await gate.future;
    if (_muted) return;
    _prepared = true;
    notifyListeners();
  }

  @override
  void play(GameSfxEvent event) {
    if (_muted) return;
    events.add(event);
  }
}
