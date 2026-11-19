import 'dart:convert';

import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';

/// Bounded, identity-scoped, read-only Tournament Home summary for offline UI.
///
/// Never stores board cells, move streams, badges to grant, or raw HTTP blobs.
final class TournamentHomeSnapshot {
  const TournamentHomeSnapshot({
    required this.scopeKey,
    required this.capturedAtMs,
    required this.originalUtcDate,
    required this.seriesId,
    required this.ordinal,
    required this.ordinalLabel,
    required this.seriesScore,
    required this.awaitAdvance,
    required this.resultsPublished,
    required this.claimStatus,
    required this.original,
    this.terminalReason,
    this.turnsUsed,
    this.moveLimit,
    this.boardSize,
    this.verifiedAll,
    this.onTimeAwarded,
  });

  static const schemaVersion = 1;

  final String scopeKey;
  final int capturedAtMs;
  final String originalUtcDate;
  final String seriesId;
  final int? ordinal;
  final String? ordinalLabel;
  final int? seriesScore;
  final bool awaitAdvance;
  final bool resultsPublished;
  final String? claimStatus;
  final bool original;
  final String? terminalReason;
  final int? turnsUsed;
  final int? moveLimit;
  final int? boardSize;
  final int? verifiedAll;
  final bool? onTimeAwarded;

  TournamentDay toDay() => TournamentDay(
    seriesId: seriesId,
    ordinal: ordinal,
    ordinalLabel: ordinalLabel,
    seriesScore: seriesScore,
    claimStatus: claimStatus ?? '',
    original: original,
    gameScore: null,
    awaitAdvance: awaitAdvance,
    resultsPublished: resultsPublished,
    terminalReason: terminalReason,
    turnsUsed: turnsUsed,
    moveLimit: moveLimit,
    boardSize: boardSize,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'scopeKey': scopeKey,
    'capturedAtMs': capturedAtMs,
    'originalUtcDate': originalUtcDate,
    'seriesId': seriesId,
    'ordinal': ?ordinal,
    'ordinalLabel': ?ordinalLabel,
    'seriesScore': ?seriesScore,
    'awaitAdvance': awaitAdvance,
    'resultsPublished': resultsPublished,
    'claimStatus': ?claimStatus,
    'original': original,
    'terminalReason': ?terminalReason,
    'turnsUsed': ?turnsUsed,
    'moveLimit': ?moveLimit,
    'boardSize': ?boardSize,
    'verifiedAll': ?verifiedAll,
    'onTimeAwarded': ?onTimeAwarded,
  };

  static TournamentHomeSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    if (raw['schemaVersion'] != schemaVersion) return null;
    final scopeKey = raw['scopeKey']?.toString() ?? '';
    final seriesId = raw['seriesId']?.toString() ?? '';
    final originalUtcDate = raw['originalUtcDate']?.toString() ?? '';
    final capturedAtMs = raw['capturedAtMs'] is num
        ? (raw['capturedAtMs'] as num).toInt()
        : 0;
    if (scopeKey.isEmpty || seriesId.isEmpty || capturedAtMs <= 0) return null;
    if (PracticeIdentityScope.tryParseStorageKey(scopeKey) == null) return null;
    return TournamentHomeSnapshot(
      scopeKey: scopeKey,
      capturedAtMs: capturedAtMs,
      originalUtcDate: originalUtcDate,
      seriesId: seriesId,
      ordinal: raw['ordinal'] is num ? (raw['ordinal'] as num).toInt() : null,
      ordinalLabel: raw['ordinalLabel']?.toString(),
      seriesScore: raw['seriesScore'] is num
          ? (raw['seriesScore'] as num).toInt()
          : null,
      awaitAdvance: raw['awaitAdvance'] == true,
      resultsPublished: raw['resultsPublished'] == true,
      claimStatus: raw['claimStatus']?.toString(),
      original: raw['original'] != false,
      terminalReason: raw['terminalReason']?.toString(),
      turnsUsed: raw['turnsUsed'] is num
          ? (raw['turnsUsed'] as num).toInt()
          : null,
      moveLimit: raw['moveLimit'] is num
          ? (raw['moveLimit'] as num).toInt()
          : null,
      boardSize: raw['boardSize'] is num
          ? (raw['boardSize'] as num).toInt()
          : null,
      verifiedAll: raw['verifiedAll'] is num
          ? (raw['verifiedAll'] as num).toInt()
          : null,
      onTimeAwarded: raw['onTimeAwarded'] is bool
          ? raw['onTimeAwarded'] as bool
          : null,
    );
  }

  static TournamentHomeSnapshot? fromLive({
    required PracticeIdentityScope scope,
    required TournamentDay day,
    required String originalUtcDate,
    required int capturedAtMs,
    Map<String, Object?> results = const {},
  }) {
    final seriesId = day.seriesId;
    if (seriesId.isEmpty) return null;
    return TournamentHomeSnapshot(
      scopeKey: scope.storageKey,
      capturedAtMs: capturedAtMs,
      originalUtcDate: originalUtcDate,
      seriesId: seriesId,
      ordinal: day.ordinal,
      ordinalLabel: day.ordinalLabel,
      seriesScore: day.seriesScore,
      awaitAdvance: day.awaitAdvance,
      resultsPublished: day.resultsPublished,
      claimStatus: day.claimStatus,
      original: day.original,
      terminalReason: day.terminalReason,
      turnsUsed: day.turnsUsed,
      moveLimit: day.moveLimit,
      boardSize: day.boardSize,
      verifiedAll: results['all'] is num
          ? (results['all'] as num).toInt()
          : null,
      onTimeAwarded: results['onTimeAwarded'] == true
          ? true
          : results['onTimeAwarded'] == false
          ? false
          : null,
    );
  }
}

final class TournamentHomeSnapshotStore {
  TournamentHomeSnapshotStore(this._kv);

  final LocalKvStore _kv;

  static String fileNameFor(PracticeIdentityScope scope) =>
      'tournament-home-${scope.storageKey}.json';

  Future<TournamentHomeSnapshot?> load(PracticeIdentityScope scope) async {
    final raw = await _kv.read(fileNameFor(scope));
    if (raw == null) return null;
    try {
      final parsed = TournamentHomeSnapshot.tryParse(jsonDecode(raw));
      if (parsed == null) return null;
      if (parsed.scopeKey != scope.storageKey) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TournamentHomeSnapshot snapshot) async {
    await _kv.writeAtomic(
      fileNameFor(
        PracticeIdentityScope.tryParseStorageKey(snapshot.scopeKey)!,
      ),
      jsonEncode(snapshot.toJson()),
    );
  }
}
