# CORE-001.v3 ↔ Tournament (PZD-38) integration boundary

Status: Proposed — revised for P0-2 authority clarification.

## Engine owns

Placement/cascade/offers/`hasLegalPlacement`/`deriveTerminalExpectation`/score/canonical hash **of a candidate state**.

## Tournament owns

Identity, entitlement, trusted ingress time, idempotency, writer generation, command ordering, series advance, leaderboards, **authoritative replay**, authenticated checkpoints bound to move ledger.

## Explicit non-authority

- Client `stateHash` / score / terminalReason are not ranked truth.
- Matching hash to attacker JSON ≠ earned score.
- Engine must not write admission journal, deadlines, or LB rows.
- Checkpoint optimization allowed only if server-authenticated and replay-bound.

## Subgame completion

On verified `ended` with `move_limit_reached` or `no_legal_moves`, tournament may allow Advance per series rules. Four-category publish only after all six verified completions (ADR-T02).
