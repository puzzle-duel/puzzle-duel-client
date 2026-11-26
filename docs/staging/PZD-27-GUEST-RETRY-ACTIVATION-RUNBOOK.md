# PZD-27 / PZD-50 — Guest refresh retry activation runbook

**Status:** Ready for owner-gated staging activation. Flags remain **OFF**.  
**Do not** enable production. **Do not** loosen `REFRESH_REPLAY` revoke semantics.

## Current read-only state (2026-11-26)

| Knob | Value |
| --- | --- |
| Oracle `PZD_STAGING_GUEST_RETRY_ENABLED` | `<unset>` → OFF (`=== 'true'` required) |
| Client `PZD_GUEST_RETRY_ENABLED` | default **false**; UAT script omits define |

## Prerequisites (already implemented)

- Migration `0002_guest_refresh_retry` (additive `rotation_id_digest` on staging guest refresh).
- Backend HMAC successor derivation when retryable mode is on (`PZD-GUEST-ROTATION-V1`).
- Client Keychain rotation intent + vault write-ahead journal (this PR) for crash-safe credential commits.
- Historic revoked families are **not** reactivated by enabling retry.

## Exact activation order (staging only)

### 1) Confirm HEADs and CI green

```bash
# client PR tip and backend version/0.0.2 tip after merge of retry docs/impl
git -C puzzle-duel-client rev-parse HEAD
git -C puzzle-duel-backend rev-parse origin/version/0.0.2
```

### 2) Migration plan (pzd_staging only)

Use the repo’s dedicated migration workflow (never on app startup / public push):

```bash
# Plan only — inspect backup/role checks before apply
# Example shape (operator runbook may wrap this):
#   APPLY workflow PLAN pzd_staging 0002_guest_refresh_retry
```

Owner approval required before apply.

### 3) Migration apply + verify

```bash
# APPLY pzd_staging 0002_guest_refresh_retry
# Then read-only verify: column pzd_guest_refresh.rotation_id_digest exists;
# no guest row mutations beyond schema.
```

### 4) Oracle server flag (isolated staging service)

```bash
# Read-only probe first (no mutation):
#   show env | grep PZD_STAGING_GUEST_RETRY_ENABLED
#
# Enable only after owner approval:
#   set PZD_STAGING_GUEST_RETRY_ENABLED=true on staging service
#   restart staging guest-auth process
#   health check staging HTTPS / ready probe
#
# Confirm:
#   PZD_STAGING_GUEST_RETRY_ENABLED=true
```

Do **not** paste secret values (DB URLs, signing keys, HMAC material) into tickets or chat.

Signing/derivation: staging guest JWT signing keys and the existing refresh HMAC domain (`PZD-GUEST-ROTATION-V1`) must already be configured for staging; retry mode does not introduce a new operator secret beyond the env flag + migration.

### 5) Matching client build define

Build **after** Oracle flag is confirmed true:

```bash
flutter build ios --release \
  --dart-define=PZD_STAGING_BASE_URL="$STAGING_ORIGIN" \
  --dart-define=PZD_GUEST_RETRY_ENABLED=true \
  # …existing staging Google/Firebase defines…
```

Do **not** uninstall, clear Keychain, or mint a replacement guest for continuity tests.

Until step 4 is true, keep omitting `PZD_GUEST_RETRY_ENABLED` (client default false).

### 6) Verification matrix (sacrificial staging guest)

1. Lost HTTP response **after** server commit with durable `rotationId` → same successor, no revoke.
2. Real used-token replay / wrong rotationId → `REFRESH_REPLAY` + family revoke (still).
3. App kill after rotation intent save → restart reuses same `rotationId`.
4. Concurrent refresh single-flight on client.
5. 02:59→03:02 UTC cutover with same rotationId.
6. Vault journal crash mid-commit → startup reconcile before refresh.

### 7) Rollback

```bash
# Client: rebuild without PZD_GUEST_RETRY_ENABLED (or =false)
# Oracle: unset / set PZD_STAGING_GUEST_RETRY_ENABLED=false; restart
# Keep migration column — do not drop; do not revive revoked families
# Do not disable replay detection
```

## Blockers before activation

- Owner approval for migration apply + Oracle env mutation.
- Oracle flag currently OFF — client must stay OFF for parity.
- Device UAT evidence on sacrificial guest after flags ON.

## Related

- Backend: `docs/staging/PZD-50-GUEST-RETRY-ROLLOUT.md`
- Backend: `docs/staging/PZD-27-REFRESH-REPLAY-INVESTIGATION.md`
- Client vault journal: `GuestVaultJournal` / `reconcilePersistedVault` in `guest_auth.dart`
