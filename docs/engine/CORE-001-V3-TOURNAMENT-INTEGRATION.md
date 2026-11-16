# CORE-001.v3 ↔ Tournament (PZD-38) integration boundary

Status: Proposed contract sketch — implementation deferred.

## Engine returns

- Validated post-move `GameState` (`rulesVersion`, board, offers, stream, score, turns, status, terminalReason)
- `stateHash`
- Move application outcome (applied / rejected / unsafe)

## Engine must NOT

- Consume daily entitlement
- Mutate inactivity / hard UTC deadlines
- Change writer generation
- Write admission journal rows
- Publish daily/weekly leaderboard rows
- Decide claim windows

## Tournament service must

- Pin `rulesVersion` + `gen-001.v1` (or later) in immutable manifest per ordinal
- Admit commands under PZD-38 trusted ingress
- Authorize writer + board_revision
- Replay moves server-side under pinned version
- On subgame `ended` with `move_limit_reached` or `no_legal_moves`, allow Advance when series rules permit
- Publish four category scores only after all six verified completions

## Client

- May show natural terminal UX; must not treat local terminal as ranked truth
