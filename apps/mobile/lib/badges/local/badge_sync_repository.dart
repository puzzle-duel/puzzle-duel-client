import 'dart:async';

import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
import 'package:puzzle_duel_mobile/badges/local/local_badge_ledger.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Verified-account sync of practice completion evidence → badge awards.
/// Mirrors PZD-53 personal-records fencing (scope + generation in-flight).
final class BadgeSyncRepository {
  BadgeSyncRepository({
    required this.api,
    required this.sessionAuth,
    required this.ledger,
  });

  final UatApi api;
  final GuestAuthClient? sessionAuth;
  final LocalBadgeLedger ledger;

  static const _maxAttempts = 3;

  Future<void>? _syncInFlight;
  PracticeIdentityScope? _syncInFlightScope;
  int? _syncInFlightGeneration;
  var _syncBlockedUntilResume = false;

  void fence() {
    _syncBlockedUntilResume = true;
    // Do not clear in-flight markers here — stale finally must compare tokens.
  }

  void allowResume() {
    _syncBlockedUntilResume = false;
  }

  Future<void> scheduleSyncIfNeeded({bool force = false}) async {
    final access = sessionAuth?.cachedAccess;
    if (access == null || !access.isVerified) return;

    final generation = ledger.generation;
    final scope = ledger.identity.activeScope;
    if (scope.kind != PracticeIdentityKind.player) return;
    if (force) allowResume();

    if (_syncInFlight != null &&
        _syncInFlightScope == scope &&
        _syncInFlightGeneration == generation) {
      await _syncInFlight;
      if (!_stillActive(scope, generation)) return;
      if (_syncBlockedUntilResume) return;
    }

    if (_syncBlockedUntilResume && !force) return;

    if (_syncInFlight != null &&
        _syncInFlightScope == scope &&
        _syncInFlightGeneration == generation) {
      return _syncInFlight;
    }

    late final Future<void> operation;
    operation = () async {
      try {
        await _syncBody(scope, generation);
      } finally {
        if (identical(_syncInFlight, operation) &&
            _syncInFlightScope == scope &&
            _syncInFlightGeneration == generation) {
          _syncInFlight = null;
          _syncInFlightScope = null;
          _syncInFlightGeneration = null;
        }
      }
    }();
    _syncInFlight = operation;
    _syncInFlightScope = scope;
    _syncInFlightGeneration = generation;
    await operation;
  }

  bool _stillActive(PracticeIdentityScope scope, int generation) {
    return ledger.generation == generation &&
        ledger.identity.activeScope == scope;
  }

  Future<void> _syncBody(
    PracticeIdentityScope scope,
    int generation,
  ) async {
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'badge_sync_started',
        ),
      ),
    );
    var attempt = 0;
    while (attempt < _maxAttempts) {
      if (!_stillActive(scope, generation)) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.info,
              code: LogCode.screenOpened,
              operation: 'badge_sync_stale_scope_rejected',
            ),
          ),
        );
        return;
      }
      final batch = await ledger.peekPendingCompletions(
        limit: BadgeMilestones.practiceBadgeSyncMaxCompletions,
      );
      if (!_stillActive(scope, generation)) return;
      if (batch.isEmpty) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.info,
              code: LogCode.screenOpened,
              operation: 'badge_sync_completed',
            ),
          ),
        );
        return;
      }
      final result = await api.post(
        '/v1/profile/me/badges/practice/sync',
        {'completions': batch},
      );
      if (!_stillActive(scope, generation)) return;
      if (result.status == 401 || result.status == 403) {
        _syncBlockedUntilResume = true;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.authExpired,
              operation: 'badge_sync_failed',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        return;
      }
      if (result.status < 200 || result.status >= 300) {
        attempt += 1;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'badge_sync_failed',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        continue;
      }
      final syncedIds = <String>{
        for (final row in batch) row['completionId']?.toString() ?? '',
      }..removeWhere((id) => id.isEmpty);
      await ledger.acknowledgeSyncedCompletions(syncedIds);
      if (!_stillActive(scope, generation)) return;
      final remaining = await ledger.pendingCount();
      if (!_stillActive(scope, generation)) return;
      if (remaining == 0) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.info,
              code: LogCode.httpCompleted,
              operation: 'badge_sync_completed',
              httpStatus: result.status,
            ),
          ),
        );
        return;
      }
      attempt = 0;
    }
  }
}
