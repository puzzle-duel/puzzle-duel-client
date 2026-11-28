import 'dart:async';

import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
import 'package:puzzle_duel_mobile/badges/local/local_badge_ledger.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Verified-account sync of practice completion evidence → badge awards.
/// Mirrors personal-records fencing; never blindly merges earned counts.
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
  var _inFlight = false;

  Future<void> scheduleSyncIfNeeded({bool force = false}) async {
    final access = sessionAuth?.cachedAccess;
    if (access == null || !access.isVerified) return;
    if (_inFlight && !force) return;
    _inFlight = true;
    final generation = ledger.generation;
    final scope = ledger.identity.activeScope;
    try {
      // Guest→verified: carry durable guest completion evidence into player scope.
      await ledger.adoptGuestProgressIntoActivePlayer();
      if (ledger.generation != generation ||
          ledger.identity.activeScope != scope) {
        return;
      }
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
        if (ledger.generation != generation ||
            ledger.identity.activeScope != scope) {
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
        if (ledger.generation != generation ||
            ledger.identity.activeScope != scope) {
          return;
        }
        if (result.status == 401 || result.status == 403) {
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
        // Continue if more pending beyond batch limit.
        final remaining = await ledger.pendingCount();
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
        attempt = 0; // progress made
      }
    } finally {
      _inFlight = false;
    }
  }
}
