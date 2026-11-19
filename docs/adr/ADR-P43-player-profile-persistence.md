# ADR-P43 — Player profile practice persistence and badge reads

Status: **Proposed** (PZD-43 hardening; owner freeze required before production enablement)

## Context

PZD-43 needs personal practice records, version-aware personal bests, and an authoritative On-Time badge collection. Review of the first implementation found two mandatory gaps:

1. Practice file scopes were derived from display `playerLabel` (collision / guest fallback risk).
2. Default storage used `Directory.systemTemp` (not durable across normal app restarts).

## Decision

### Identity (P0)

1. **Never** use display names or UAT player labels as practice persistence identities.
2. Authenticated practice scopes use the **verified internal `playerId`** returned by `POST/GET /v1/tournament/session` (caller-owned only).
3. Guest practice scopes use a **persisted random local UUID** in `practice-identity.json`.
4. File tokens are only `guest_<uuid>` or `player_<uuid>`. Invalid / label tokens are rejected.
5. **Guest → authenticated migration does not copy or merge** records. Scopes remain separate until an explicit future product decision.
6. Logout / missing / invalid `playerId` clears the authenticated binding and returns reads to the guest scope. Player-scoped files remain on disk but are unread while logged out.
7. Legacy unscoped `practice-records.json` and previous label-scoped `practice-records-<label>.json` files migrate **only into the guest scope**, once, with a migration marker. They never enter a player scope.

If session responses omit a trustworthy UUID `playerId`, the client stays on the guest scope rather than inventing an authenticated identity.

### Durable storage (P1)

1. Default practice/settings/identity directory is the platform **application support** path via `path_provider` (`…/puzzle_duel`).
2. Automated tests inject a temporary directory override; production code does not default to `Directory.systemTemp`.
3. Practice I/O goes through `LocalKvStore`. Production `DirectoryKvStore` performs filesystem work in a worker isolate with temp-file rename for atomicity. Tests inject `MemoryKvStore`.
4. Corrupt bests files are rebuilt from history without discarding valid personal bests after a successful rewrite.
5. History remains bounded (`maxRecords = 40`) with immortalized version-aware bests.
6. Uninstall removes application-support data. Reinstall does **not** restore practice history. Cross-device sync is out of scope.
7. Practice scores are never sent to ranked claim/publication/leaderboard APIs.

### Offline-first Practice (P0 UAT)

1. `beginLocal()` exposes Home + Practice as soon as identity/settings are ready.
2. `refreshTournament()` runs independently; OFFLINE/TIMEOUT/UNAUTHENTICATED during refresh stay as Tournament-area banners and never block Practice.
3. Offline session failures do **not** clear a previously verified practice player binding.
4. Bounded identity-scoped `TournamentHomeSnapshot` may show a last-known Home summary marked stale; never live countdowns, offline claims, ranked moves, or invented badge grants.

### Badges

Unchanged: candidate `GET /v1/tournament/me/badges` derives On-Time counts from immutable F2-B rows. No new grant rules. Ranked HTTP stays gated / denied in production.

## Consequences

- Profile and practice isolation follow server player identity when available.
- Owner must still accept this ADR before treating storage/identity as frozen.
- Durable path depends on `path_provider` (explicitly added for PZD-43 P1).

## Non-goals

- Automatic guest→cloud merge
- Practice score verification / ranked promotion
- XP / level / streak systems
- Lifetime ranking math
- Production ranked HTTP enablement
