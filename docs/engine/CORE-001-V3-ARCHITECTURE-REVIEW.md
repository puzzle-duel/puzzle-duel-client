# PZD-39 — CORE-001.v3 architecture review (P0/P1 remediation revision)

Status: **Remediation complete — ADR-E01 remains Proposed**
Date: 2026-11-17
Supersedes prior review prose where they conflict; D1–D10 recommendations unchanged.
Independent review source: PR #14 / #17 comments (2026-11-17 REQUEST REVISIONS).

## Workspace integrity (Phase -1)

| Tree | Branch | HEAD at start | Dirty | Action |
| --- | --- | --- | --- | --- |
| backend Phase A | `feature/PZD-38-trusted-ingress` | `4473a39` | clean | untouched |
| backend design | `docs/core-001-v3-ruleset-design` | `c64bd57` | clean | remediate docs |
| client PZD-22 | `feature/PZD-22-flutter-app-bootstrap` | `59570b2` | `__pycache__` only | untouched |
| client design | `docs/core-001-v3-ruleset-design` | `e818be2` | clean | remediate docs |
| client PZD-23 | detached `223ba3f` | staged visuals | preserve | untouched |

## P0/P1 remediation matrix

| ID | Finding | Document change | Verification | Result |
| --- | --- | --- | --- | --- |
| P0-1 | Circular terminal validation via `hasLegalMove` on ended states | Split `hasLegalPlacement` (status-agnostic) vs `hasLegalMove` (gameplay) vs `deriveTerminalExpectation` | Spec examples V3-36…V3-41 | **REMEDIATED in Proposed ADR** |
| P0-2 | SHA-256 treated as authenticity/score proof | Separate hashing / validation / authoritative replay; client hash never ranked authority | Negative cases V3-42…V3-48 | **REMEDIATED** |
| P1-1 | Canonical JSON underspecified | Exact ASCII/escaping/integer/null byte contract + independent digests | `canonical-v3-test-vectors.md` | **REMEDIATED** |
| P1-2 | Spent provenance vs structure | Structure may check shape; legitimacy only via replay | §Spent provenance | **REMEDIATED** |
| P1-3 | Dual-engine agreement ≠ correctness | Freeze requires independent oracle + negatives | Fixture freeze protocol | **REMEDIATED** |
| P1-4 | Initial-state validity | `parseInitialGameState` requires playable in_progress | §Initial challenges | **REMEDIATED** |
| P1-5 | Intermediate integer overflow | Checked arithmetic before precision loss | §Integer safety | **REMEDIATED** |

## Final D1–D10 package (approval-ready)

| ID | Final recommended behavior | Normative invariants | Prior defect | Remediation | Rejected alternatives | Compatibility | Acceptance tests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D1 | Tagged `piece` / `spent` tray length 3 | Bare null forbidden; spent has no piece fields; indices 0..2 | Ambiguous null vs v2 | Keep tagged schema | B null-active; C variable length | v1/v2 unchanged | V3-08/13/22/24/33 |
| D2 | Simultaneous budget+no-placement → `move_limit_reached` | Single successful reason | Underspecified dual | Hard precedence | Prefer no_legal_moves | Analytics only | V3-26/40 |
| D3 | Normative placement via PZD-18 geometry; `hasLegalPlacement` status-agnostic | Lemma shortcut not future contract | Circular ended check | Split predicates | Board-full-only | T-10A enabled | V3-36…41 |
| D4 | Structure: spent well-formed; stream invariant; **provenance = replay** | Parser ≠ history proof | Overclaimed parse power | Explicit provenance boundary | Trust snapshot history | Replay required | V3-33/45 |
| D5 | Canonical UTF-8 sorted-key compact JSON + SHA-256 hex; ASCII enum tokens | Exact escapes; reject non-ASCII/floats | Underspecified bytes | Byte contract + vectors | JSON.stringify-as-spec | New v3 only | Vectors SPECIFIED |
| D6 | JSON-safe ints; checked intermediates | Fail before 2^53 loss | Final-parse-only risk | Checked ops both langs | Unbounded BigInt | v1/v2 arith unchanged | V3-29/49 |
| D7 | Successful reasons: `move_limit_reached` \| `no_legal_moves` only | No integrity_failure on success | Forgery surface | Keep narrowed enum | Extra reasons | Proof envelope | V3-32 |
| D8 | Immutable v1/v2 dispatch | No silent rewrite | — | Preserve | Amend v2 | Historical replays | V3-17…19 |
| D9 | Independent oracle + dual engines before freeze | Agreement ≠ correctness | Dual-bug risk | Multi-layer freeze | Freeze from one engine | Release gate | Freeze protocol |
| D10 | Initial challenges: 3 live pieces + legal placement + in_progress | Impossible initial fail-closed | Missing playability | Initial parse rules | Allow zero-move success | Generator later pin | V3-50 |

**No additional owner questions.** Residual engineering detail (module paths) is not product-impacting.

## Recommendation

**READY FOR OWNER DESIGN APPROVAL** of D1–D10 as revised in ADR-E01 (Proposed).

Not ready for: ADR Acceptance ceremony without owner sign-off; engine implementation; golden PASS claims; merge/deploy.
