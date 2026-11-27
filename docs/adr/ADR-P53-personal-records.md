# ADR-P53 — Remote Personal Records (Practice Sync + Tournament Projection)

- **Status:** Proposed (owner merge/deploy approval required)
- **Date:** 2026-11-27
- **Jira:** PZD-53 (extends PZD-43; relates PZD-26 / PZD-27)

## Context

Phase 1 (PZD-43) shipped local Practice personal bests and badge collection on Profile.
Phase 2 adds account-scoped remote personal records with All / Practice / Tournament
segments, offline-first Practice synchronization, and server-authoritative tournament
board personal bests — without changing gameplay, scoring, badges, or leaderboards.

## Decision

### Product semantics

| Concept | Rule |
| --- | --- |
| Difficulty | `easy` / `medium` / `hard` (canonical wire ids; never translated labels) |
| Personal record | Maximum **final score of a single completed board** for a difficulty + source |
| Practice source | Offline-capable; client-reported; provenance `client_reported_practice` |
| Tournament source | Server-authoritative individual board; provenance `tournament_f2b_verified_subgame` |
| Not a record | Daily series category totals, weekly aggregates, cumulative multi-board scores |
| All segment | `max(practice, tournament)` per difficulty for **profile display only** |
| Equal score | Not a new record; preserve original achievement metadata |

### Scoring version compatibility

| Mode | Rules | Generator |
| --- | --- | --- |
| Practice (current free play) | `core-001.v2` | `gen-001.v1` |
| Tournament (F2-B) | `core-001.v3` | `gen-001.v1` |

Records store `rules_version` + `generator_version` in the unique key.
Practice and Tournament remain separate stored rows.
The All segment compares numeric scores for personal profile display
(owner-approved; not competitive ranking). Cascade point math is the same
PZD-20 formula; terminal semantics differ between v2 and v3 (ADR-E01).
Competitive leaderboards and badge grants are unaffected.

### Tournament authority boundary

Canonical individual board scores: immutable `tournament_verified_subgame_score`
written inside F2-B publication on `h1_terminal_move` (entire six-board series).
Mid-series `authoritative_game_snapshot.score` is series-cumulative and must not
be used as a personal-best board score.

When `player_personal_best` exists, F2-B projects max-only tournament rows in the
same publication transaction. GET also derives tournament bests from verified
subgame scores when the projection table is empty/missing (rollout safety +
historical recovery).

### API (account-scoped; no tournament session)

- `GET /v1/profile/me/personal-records`
- `POST /v1/profile/me/personal-records/practice/sync`

Requires verified bearer + exact active refresh family (staging). Server derives
player id. Guests receive `403 RANKED_AUTH_REQUIRED`. Client cannot write
tournament records through the Practice sync path.

### Persistence

Table `player_personal_best` (staging migration `0010_player_personal_best`):

- Unique key: `(player_id, source, difficulty, rules_version, generator_version)`
- Atomic `INSERT … ON CONFLICT DO UPDATE … WHERE EXCLUDED.score > score`
- Runtime role: SELECT + column-scoped INSERT/UPDATE; no DELETE

### Client offline-first

- PracticeStore remains the local Practice best authority (including bests that
  survived bounded history pruning).
- Pending Practice sync and remote snapshots are keyed by
  `apiOrigin|player:<immutablePlayerId>`.
- Acknowledgements clear pending only when `remoteScore >= pending.score`
  (older in-flight acks cannot clear a newer local best).
- Logout fences sync generation; pending rows remain under the original scope.

## Consequences

- Practice cloud sync does **not** imply server-verified competitive results.
- Tournament personal bests appear after F2-B series publication (H1 terminal),
  not mid-series.
- Staging rollout: apply migration `0010_player_personal_best` via the reusable
  staging migration Action before relying on Practice sync (`503 SCHEMA_NOT_READY`
  until applied). Tournament GET derivation works without the new table.
- No merge/deploy/migration apply without owner approval.

## Non-goals

- Gameplay / animation / scoring changes
- Client-authoritative tournament records
- Auto-merge of guest Practice into unrelated verified accounts
- Leaderboard / badge / claim mutations from personal-record sync
- Full Practice anti-cheat / replay verification
