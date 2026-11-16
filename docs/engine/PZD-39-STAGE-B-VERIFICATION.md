# PZD-39 — Stage B verification report (CORE-001.v3 Dart)

**Gate outcome:** READY FOR FINAL INDEPENDENT REVIEW  
**Verified HEAD:** `00a26a0f75da3539d1b6aa61b50d6ca4cfba29dc`  
**Branch:** `feature/PZD-39-core001v3-dart-engine`  
**Draft PR:** https://github.com/puzzle-duel/puzzle-duel-client/pull/18  
**PR base:** `docs/core-001-v3-ruleset-design` @ `a09866b888e92dad8b69ff1f6b55b9e89252cda1`  
**Evidence UTC:** 2026-11-16T22:43:37Z  
**Working tree at verification:** clean (no uncommitted changes)

This report attributes all PASS evidence to the HEAD above. It does **not** claim TypeScript parity, tournament readiness, or GitHub Actions CI PASS.

---

## 1. SDK and package

| Item | Value |
| --- | --- |
| Executable (worktree-relative) | `.dart-sdk/bin/dart` (gitignored; not tracked) |
| Version | Dart SDK 3.14.0 (stable) |
| Package | `packages/puzzle_duel_rules` |
| `environment.sdk` | `^3.14.0` |
| `crypto` (pubspec / lock) | `^3.0.6` / `3.0.8` |
| `test` | `^1.26.0` |

Commands were run from `packages/puzzle_duel_rules` using the portable SDK above.

---

## 2. Stage B file scope

Diff vs design base `a09866b` (implementation only; no gameplay v1/v2 fixture edits):

- `.gitignore`
- `packages/puzzle_duel_rules/lib/puzzle_duel_rules.dart`
- `packages/puzzle_duel_rules/lib/src/{canonical,checked_int,challenge_generator,failure,parse,placement,resolution,values}.dart`
- `packages/puzzle_duel_rules/pubspec.yaml` / `pubspec.lock`
- `packages/puzzle_duel_rules/test/{core001_v3,challenge_generator,placement,state_validation}_test.dart`

Generator remains pinned to Accepted `gen-001.v1` + `rulesVersion == core-001.v2` (rejects other pins). Diff is OfferSlot wrapping + versioned `toJsonFor` only.

---

## 3. Dart quality gate (exact)

| Check | Command | Exit | PASS | FAIL | SKIP |
| --- | --- | ---: | ---: | ---: | ---: |
| Formatting | `dart format --output=none --set-exit-if-changed .` | 0 | yes | 0 | 0 |
| Analyzer | `dart analyze` | 0 | clean | 0 | 0 |
| Full package | `dart test` | 0 | **140** | **0** | **0** |
| V3 targeted | `dart test test/core001_v3_test.dart` | 0 | **44** | 0 | 0 |

### Per-file totals (sum = 140; no double-count)

| Suite | PASS |
| --- | ---: |
| `test/core001_v3_test.dart` | 44 |
| `test/resolution_test.dart` | 24 |
| `test/challenge_generator_test.dart` | 21 |
| `test/match_shift_test.dart` | 17 |
| `test/placement_test.dart` | 16 |
| `test/state_validation_test.dart` | 10 |
| `test/deterministic_rng_test.dart` | 8 |

---

## 4. Historical fixture integrity (bytes)

| Check | Result |
| --- | --- |
| `git diff a09866b..HEAD -- docs/contracts/gameplay/v{1,2}` | empty |
| `git diff origin/main...HEAD -- docs/contracts/gameplay/v{1,2}` | empty |
| Local `CHECKSUMS.txt` verify v1 | **27/27 OK** |
| Local `CHECKSUMS.txt` verify v2 | **8/8 OK** |
| Blob SHA-256 parity vs `origin/main` for all CHECKSUMS paths | **35/35 OK** |

---

## 5. Historical behavior regression (executed)

| Check | Exit | Notes |
| --- | ---: | --- |
| v1 `python3 reference_check.py` | 0 | 13 golden fixtures PASS |
| v1 `node validate.mjs` | 0 | fixtures + schema + CHECKSUMS PASS |
| v2 `python3 reference_check.py` | 0 | terminal null + early empty-stream probes PASS |
| v2 `node validate.mjs` | 0 | same + CHECKSUMS PASS |
| Dart v1 fullMove goldens (`resolution_test`) | 0 | 9 fixtures including cascades/end |
| Dart v2 early-board-full empty stream | 0 | remains `MoveSafety.earlyBoardEndEmptyStream` |
| Generator goldens vs independent Python reference | 0 | profile/seed matrix PASS |

Checker scripts themselves print `NOT_RUN` for product engines; Dart engine coverage is the package tests above, not those checker lines.

---

## 6. Canonical vectors (independent)

Python 3 `hashlib.sha256` over the exact UTF-8 strings in `docs/contracts/gameplay/v3/canonical-v3-test-vectors.md`:

| Vector | Result |
| --- | --- |
| CV-01 … CV-09 | **OK** (fail=0) |

Dart suite also asserts the same digests and key-order independence. Full GameState digests remain **PENDING_FREEZE** per ADR-E01.

---

## 7. Adversarial / security summary

Covered by Stage B tests + source review at HEAD `00a26a0`:

| Area | Result | Evidence |
| --- | --- | --- |
| Version isolation | PASS | v1/v2 wire without `terminalReason`/tagged offers; unknown version fail-closed |
| Offer slots | PASS | piece/spent closed schema; bare null rejected; spent extras rejected |
| Natural terminal | PASS | move-limit precedence; no_legal_moves; cascade reopen stays in_progress |
| Spent / empty stream | PASS | replace then spent; select spent → `offerUnavailable`; state preserved |
| Cascades / scoring | PASS | wave `n * unique * 100`; PZD-20 path reused; v3 checked arithmetic |
| Integer safety | PASS | checked turns+1, mul, accumulate, score add; overflow preserves state |
| Canonical hashing | PASS | CV-01…09; integrity ≠ ranked authority asserted |
| Generator | PASS | still v2-only pin; goldens PASS |
| Historical fixtures | PASS | bytes + checkers + Dart goldens |

### Findings

| Severity | Item | Status |
| --- | --- | --- |
| P0 | None at verified HEAD | — |
| P1 | Prior: unchecked v3 `turnsUsed + 1` (ADR §10) | **Fixed** in `00a26a0` (`integer_overflow` fail-closed; v1/v2 path unchanged) |
| P2 | Package README still describes v1/v2-only public API surface | Open (docs polish; not replay-affecting) |
| P2 | Full v3 board golden freeze | Deferred to Stage D / PENDING_FREEZE |

### Test-quality notes

- CV digests are independently specified (Python oracle), not taken from Dart output alone.
- Wave score `300` and overflow bounds use hand-checkable arithmetic.
- Some assertions use type matchers (`isA<OfferSpent>`) **plus** terminal/status/score checks; not count-only.
- No skipped tests in the package run (SKIP=0).

---

## 8. NOT_RUN

- TypeScript CORE-001.v3 engine (Stage C)
- Dual-engine golden freeze / cross-language byte parity (Stage D)
- Full GameState `stateHash` freeze
- Tournament / PZD-38 ranked integration
- Claiming GitHub Actions workflow PASS without inspecting Actions logs for this HEAD
- Merge / deploy / marking PZD-39 Done

---

## 9. Remaining gates

1. **Stage C** — TypeScript pure replay module reproducing this Dart contract.
2. **Stage D** — Freeze protocol in `FIXTURE-SPEC.md`; dual-engine PASS.
3. **Tournament** — Authoritative replay under trusted ingress (PZD-38+), never client hash.

---

## 10. Sign-off statement

Against HEAD `00a26a0f75da3539d1b6aa61b50d6ca4cfba29dc`, mandatory Stage B Dart format/analyze/test, historical v1/v2 byte+behavior checks, generator regression, and independent canonical vectors all **PASS** with **0 FAIL / 0 SKIP**. No unresolved P0/P1.

**STAGE B — READY FOR FINAL INDEPENDENT REVIEW.**
