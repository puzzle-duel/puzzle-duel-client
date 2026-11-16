# PZD-39 — CORE-001.v3 adversarial architecture review

Status: **Review complete — ADR-E01 remains Proposed**
Date: 2026-11-17
Repos: Backend PR #14 @ `b5dc911` / Client PR #17 @ `9c7dcb4` (pre-revision); this document revises the proposal.
Authoritative historical engines: Dart `packages/puzzle_duel_rules` (PZD-17…PZD-20); checkers under `docs/contracts/gameplay/v{1,2}` are **not** product engines.
Tournament design: ADR-T02 Accepted (design only). PZD-38 PR #13 out of scope.

## Phase -1 integrity

| Tree | Branch | HEAD | Dirty? | Action |
| --- | --- | --- | --- | --- |
| backend | `feature/PZD-38-trusted-ingress` | `4473a39` | clean | untouched |
| backend-core001v3 | `docs/core-001-v3-ruleset-design` | see post-commit | was clean | design only |
| client | `feature/PZD-22-flutter-app-bootstrap` | `59570b2` | `__pycache__` only | untouched |
| client-core001v3 | `docs/core-001-v3-ruleset-design` | see post-commit | was clean | design only |
| client-pzd23 | detached `223ba3f` | staged visual PNGs + pbxproj | **preserve** | untouched |

PR #14 head matched backend worktree `b5dc911`. PR #17 head matched client worktree `9c7dcb4`.

## Phase 0 — Cross-PR discrepancy report

| Check | Result |
| --- | --- |
| Six design files SHA-256 identical across repos | **PASS** (byte-identical) |
| Only docs added; no runtime code | **PASS** |
| v1/v2 fixtures / `gen-001.v1` / Dart engine unchanged | **PASS** |
| ADR status Proposed | **PASS** |
| Semantic contradictions between repos | **None** |
| PR description Jira host `little-minds-app.atlassian.net` | **P2 doc defect** — should be `puzzle-duel-app.atlassian.net` |
| Executable golden vectors present | **FAIL as parity claim** — catalogue is prose/`PENDING_FREEZE` only (correctly NOT_RUN) |

No silent choice between repos required: documents already matched.

## Phase 1 — Technical findings

### P0 — Must resolve in Proposed ADR before Acceptance

| ID | Finding | Evidence | Resolution in revised ADR |
| --- | --- | --- | --- |
| P0-1 | Canonicalization contradiction: “sorted object keys” vs “fixed piece field order” | ADR-E01 §9 | **Single algorithm:** recursive lexicographic UTF-8 key sort; no special-case piece order |
| P0-2 | `integrity_failure` listed as `TerminalReason` wire value risks forged “successful” terminals | ADR-E01 §5.1 | Remove from successful-state enum; integrity stays `MoveUnsafe` / parse failure only |
| P0-3 | Simplified `hasLegalMove` stated as definition without proof | ADR + PZD-18 `applyPlacement` | Normative definition = existential over `applyPlacement`; PZD-18 lemma documented separately |

### P1 — Required before freeze / implementation

| ID | Finding | Resolution |
| --- | --- | --- |
| P1-1 | Fixture catalogue lacks executable expected boards/hashes | Explicit `PENDING_FREEZE`; freeze protocol Stage D |
| P1-2 | Integer domain for cross-language JSON unspecified | Constrain to IEEE-safe integers `0…2^53-1` for score/turns; reject out-of-range |
| P1-3 | Simultaneous `move_limit` and `!hasLegalMove` precedence only briefly noted | Hard rule: **`move_limit_reached` wins** |
| P1-4 | Spent-slot + non-empty stream invariant underspecified | After commit with non-empty stream, consumed slot must be `piece`; `spent` only when stream empty at commit |
| P1-5 | Backend has no TS gameplay engine | Stage C mandatory; checkers ≠ engines |

### P2 — Follow-ups

| ID | Finding |
| --- | --- |
| P2-1 | UI tray rendering of `spent` vs empty not specified (presentation-only) |
| P2-2 | PR footer wrong Atlassian host |
| P2-3 | Unicode normalization: recommend NFC reject or identity-only (no free-form strings in state today) |

## 1.1 Tagged tray — adversarial verdict

**Recommend keep tagged `OfferSlot` (`piece` \| `spent`).**

| Criterion | Assessment |
| --- | --- |
| Unambiguous | Yes vs overloaded JSON `null` |
| Fixed indices 0..2 | Preserved |
| Stream exhaustion | `spent` write on empty stream after cascade |
| Versioned | `rulesVersion: core-001.v3` only |
| Selectability | `kind!=piece` → `offer_unavailable` (unsafe), never natural terminal |
| Never-initialized | **Not needed** if challenges always publish three `piece` slots |
| Forgery | Bare `null`, unknown `kind`, extra props → parse reject |

Alternative B (`Piece|null` with v3 null-while-active) remains rejected as default due to v2 semantic collision.

## 1.2 Terminal predicate — revised

After placement + **complete** cascades + offer commit + structural validation:

```
if turnsUsed >= moveLimit:
  ended(terminalReason=move_limit_reached)
else if not hasLegalMove(state):
  ended(terminalReason=no_legal_moves)
else:
  in_progress(terminalReason=null)
```

- Empty `futurePieces` alone never ends.
- Do not evaluate terminal before cascades/commit.
- If both move-limit and no-legal-move hold after the same move → **`move_limit_reached` only**.

## 1.3 Legal-move proof (PZD-18)

**Normative:**

```
hasLegalMove(S) :=
  S.status == in_progress AND
  exists i in {0,1,2}, tap in cells:
    applyPlacement(S, Move(i,tap)) is PlacementApplied
```

**PZD-18 lemma (current code only):** `applyPlacement` accepts an in-bounds empty unblocked tap whenever `offers[i]` is a live piece (direction affects landing, not acceptance). Therefore under **current** placement rules:

```
hasLegalMove(S) <=> (exists piece offer) AND (exists empty unblocked cell)
```

**Counterexample class if rules change:** any future tap-cell restriction that rejects some empty cells would break the lemma; normative existential must remain. Fixture V3-07 uses all-`spent` offers with empty cells → lemma and normative agree (`false`).

Spent/null selection is **not** a legal move; it is unsafe/`offer_unavailable`.

## 1.4 Failure classification matrix

| Condition | Class |
| --- | --- |
| Missing/unknown fields, bad enums, wrong offer length, bare null, unknown kind, spent with extra fields | **Parse rejection** |
| `blocked_tap` / `occupied_tap` / `game_ended` | **Gameplay rejection** |
| OOB tap, select `spent`, unresolved pre-move match, cascade corrupt/bound, invalid final | **MoveUnsafe fail-closed** |
| `turnsUsed>=moveLimit` after legal apply | **Natural terminal** `move_limit_reached` |
| `!hasLegalMove` after legal apply (budget remaining) | **Natural terminal** `no_legal_moves` |
| Forged terminalReason/score/hash on input | **Parse / proof rejection** — never natural success |

## Phase 2 — Canonicalization contract (v3 only)

**Algorithm `canonical_json_v3(value)`:**

1. Reject non-finite numbers; integers only in `-(2^53-1)…(2^53-1)`; gameplay scores/turns additionally `≥0` and within schema.
2. Encode strings as JSON strings over Unicode code points **as stored** (no NFC rewrite of shape/direction enums — enums are ASCII).
3. `null` is the JSON null token; missing fields are schema errors (not hashed).
4. Arrays: preserve order; recursively canonicalize elements.
5. Objects: include all schema fields; sort keys by UTF-8 byte lexicographic order; recursively canonicalize values.
6. Emit compact JSON (no insignificant whitespace) as UTF-8 bytes.
7. `stateHash = lowercase hex(SHA-256(utf8_bytes))`.

**No reliance on** Dart `hashCode`, JS object key insertion order, or pretty-print.

Historical v1/v2 fixture file checksums remain file-level SHA-256 of fixture documents — **unchanged** and **not** redefined as state hashes.

Golden hash vectors: `PENDING_FREEZE` until dual engines exist; include at least empty-board initial hash and one post-move hash with key-order permutation independence test.

## Phase 3 — Fixture completeness

See revised `FIXTURE-SPEC.md`. All expected boards/hashes remain **`PENDING_FREEZE`** except prose oracles. Independent hand-checkable items (wave score arithmetic) may be asserted without full engine; board geometry still PENDING_FREEZE.

## Phase 4 — Feasibility

| Component | Reuse | New |
| --- | --- | --- |
| Dart placement/match/shift/cascade/score | Reuse | v3 dispatch in offer commit + terminal + parse |
| Backend | Generator only today | New pure TS `src/engine/core001/` |
| Checkers Py/Node | Keep for v1/v2 | Optional v3 checker after freeze — still not product engine |
| Generator | `gen-001.v1` RNG unchanged | Later pin `rulesVersion: core-001.v3` in challenge envelope only |

Dependency graph: ADR Accept → Dart v3 → TS v3 → freeze fixtures → dual PASS → generator pin option → PZD-38 replay wiring.

## Phase 5 — Tournament boundary

Engine owns pure gameplay + proof. Tournament owns identity, entitlement, time, idempotency, writer, ordering, series advance, LB. No ownership overlap found in the integration doc; keep engine free of journal/deadline/LB side effects.

## Owner decision table

| ID | Question | Recommended option | Alternatives | Impact |
| --- | --- | --- | --- | --- |
| D1 | Offer tray representation | **Tagged `piece`/`spent`** | B: `Piece\|null` v3-null-active; C: variable length | Schema + UI + hashing |
| D2 | Terminal reason when budget and no-legal both true | **`move_limit_reached`** | Prefer `no_legal_moves`; dual reason | Proof enum / analytics |
| D3 | `hasLegalMove` definition | **Existential over `applyPlacement`** (+ document PZD-18 lemma) | Board-full-only (rejects T-10A) | Tournament natural end |
| D4 | Spent while stream non-empty | **Illegal after commit** (parse/invariant fail) | Allow | Prevents corrupt trays |
| D5 | Canonical JSON | **Recursive UTF-8 key sort; compact; SHA-256 hex** | Insertion order; Dart hashCode | Parity/security |
| D6 | Integer domain | **JSON-safe ints; score/turns in `0…2^53-1`** | Unbounded BigInt | Cross-language |
| D7 | `TerminalReason` on success | **`move_limit_reached` \| `no_legal_moves` only** | Include integrity_failure | Forgery surface |
| D8 | Historical dispatch | **Keep v1/v2 branches immutable** | Amend v2 in place | Breaks replays |
| D9 | Fixture freeze | **Dual-engine agreement then checksum ledger** | Freeze from one engine | False parity |
| D10 | Initial tray | **Always three `piece` slots** | Allow initial spent | Generator/UI |

### Classification

- Historical accepted: placement/cascade/score (PZD-18/19/20); v1/v2 end rules.
- Owner Tournament: T-10A natural no-legal-move success.
- Newly proposed v3: D1–D7, D9–D10.
- Engineering detail: module paths, optional checkers.
- Release verification: dual golden PASS, v1/v2 checksum regression, no Phase A edits.
