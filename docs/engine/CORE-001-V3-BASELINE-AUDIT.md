# CORE-001.v3 Phase 0 baseline audit

Date: 2026-11-17
Client worktree: `puzzle-duel-client-core001v3` @ `d8fcfb0`
Backend worktree: `puzzle-duel-backend-core001v3` @ `e3ca274`

## Inventory

| Area | Current implementation | v3 requirement | Gap |
| --- | --- | --- | --- |
| State schema | Dart `GameState` v1/v2; offers `Piece?` length 3; no `terminalReason` | `core-001.v3` + tagged offers + `terminalReason` | New version + fields |
| Piece offers | v1 all pieces; v2 one null only at budget terminal | Multiple spent slots while active | New validation branch |
| Future piece stream | Finite list; empty allowed in parse | Empty ≠ terminal | Predicate change only for v3 |
| Placement legality | PZD-18 directional land on empty unblocked | Reuse via `hasLegalMove` | Public predicate missing |
| Cascade resolution | PZD-19/20 Dart | Unchanged | None for mechanics |
| Scoring | Integer wave formula | No terminal bonus | Preserve |
| Natural terminal | End on move limit or board-full empty cells; v2 early empty-stream fail-closed | Success on `!hasLegalMove` | **Primary product gap** |
| State hashing | Dart equality / hashCode; fixture SHA for files | Canonical JSON SHA-256 | Cross-language hash undefined |
| Replay verification | Client Dart engine; backend **generator only** + Python/Node checkers | Pure TS product replay engine | **Missing TS engine** |
| Dart/TS parity | Documented as required (PZD-14); checkers ≠ engines | Dual golden PASS | TS gameplay engine absent |

## Source anchors

- Client engine: `packages/puzzle_duel_rules/lib/src/{values,parse,placement,match_shift,resolution}.dart`
- Termination today: `resolution.dart` `_finishApplied` uses `budgetExhausted \|\| boardFull`
- Offer commit: `_commitOffers` v1/v2 switch; no v3
- Backend: `src/generator.mts` pins `core-001.v2`; `docs/contracts/gameplay/v{1,2}/validate.mjs` checkers
- Tournament dependency: ADR-T02 TD-11; T-10A owner approval

## Explicit non-claims

This audit does not implement v3. Historical fixtures were not modified.
