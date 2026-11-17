# CORE-001.v3 golden fixture specification

Status: Proposed catalogue — executable boards/hashes mostly **PENDING_FREEZE**
Canonical atom digests: [canonical-v3-test-vectors.md](./canonical-v3-test-vectors.md) (**SPECIFIED**).

## Freeze protocol (D9)

1. Hand-checkable / invariant oracles  
2. Structural + mathematical checks  
3. Dart engine  
4. TypeScript engine  
5. Cross-language byte equality  
6. Negative/fail-closed cases  
7. Historical v1/v2 regression  
8. Immutable checksum ledger  

Dual agreement alone is necessary but not sufficient.

Each fixture row uses: `SPECIFIED` | `PENDING_FREEZE` | `FROZEN` | `PASS` | `FAIL`.

## Catalogue (V3-01…V3-35 retained; additions below)

| ID | Scenario | Oracle notes | Status |
| --- | --- | --- | --- |
| V3-01…V3-35 | Prior catalogue | Boards PENDING_FREEZE; V3-02 arithmetic hand-checkable | PENDING_FREEZE / historical for 17–19 |
| V3-36 | Playable board falsely `ended/no_legal_moves` | `deriveTerminalExpectation` reject | SPECIFIED (behavior) / board PENDING_FREEZE |
| V3-37 | Budget exhausted falsely `in_progress` | Reject | SPECIFIED / PENDING_FREEZE |
| V3-38 | No offers/placement falsely `in_progress` | Reject | SPECIFIED / PENDING_FREEZE |
| V3-39 | No placement, budget left → `ended/no_legal_moves` | Accept | SPECIFIED / PENDING_FREEZE |
| V3-40 | Budget + no placement simultaneous | `move_limit_reached` | SPECIFIED / PENDING_FREEZE |
| V3-41 | Valid ended; `hasLegalMove` false | Gameplay false; terminal unchanged | SPECIFIED / PENDING_FREEZE |
| V3-42 | Forged score + recomputed matching hash | Schema may pass; **replay FAIL** | SPECIFIED (class) |
| V3-43 | Forged board + matching hash | Replay FAIL | SPECIFIED (class) |
| V3-44 | Forged terminal + self-consistent hash | §5.3 reject and/or replay FAIL | SPECIFIED (class) |
| V3-45 | Structurally pretty unreachable history | Parse may pass snapshot checks; **replay FAIL**; provenance | SPECIFIED (class) |
| V3-46 | Altered move sequence → different score | Replay diverges from claimed | SPECIFIED (class) |
| V3-47 | Wrong rulesVersion pin | Dispatch/reject; no silent reinterpret | SPECIFIED (class) |
| V3-48 | Client overwrites trusted checkpoint | Tournament rejects; engine unused | SPECIFIED (class) |
| V3-49 | Intermediate cascade arithmetic overflow | Fail closed both languages | SPECIFIED (class) / PENDING_FREEZE numeric fixture |
| V3-50 | Impossible initial (no legal placement) | `parseInitialGameState` reject; not zero-move success | SPECIFIED / PENDING_FREEZE |
| V3-51 | Exact canonical atom digests CV-01…09 | Independent Python SHA | **SPECIFIED** |
| V3-52 | Full state key-order independence | Same stateHash | PENDING_FREEZE |

### Authority matrix for negative hash/score cases

| Case | Schema/§5.3 | Hash self-match | Authoritative replay |
| --- | --- | --- | --- |
| V3-42 forged score | may pass | can match forged | **FAIL** |
| V3-43 forged board | may pass | can match | **FAIL** |
| V3-44 forged terminal | **reject** if inconsistent | irrelevant | FAIL if somehow stored |
| V3-45 unreachable | structure maybe pass | maybe match | **FAIL** |
| V3-46 sequence tamper | n/a | n/a | **FAIL** vs ledger |
| V3-47 wrong version | reject / wrong dispatch | n/a | **FAIL** |
| V3-48 checkpoint overwrite | n/a | n/a | Tournament **FAIL** |

Parser alone does **not** detect all seven; replay/tournament authority required where noted.
