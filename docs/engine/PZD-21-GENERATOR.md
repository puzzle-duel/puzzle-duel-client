# PZD-21 — Accepted `gen-001.v1` challenge generator

Jira: [PZD-21](https://puzzle-duel-app.atlassian.net/browse/PZD-21).

Decision record (Accepted): [PZD-21-GENERATOR-DECISIONS.md](PZD-21-GENERATOR-DECISIONS.md).

Package: [`packages/puzzle_duel_rules`](../../packages/puzzle_duel_rules/README.md).

This document describes the implemented Dart API. It does **not** change GEN decisions.

## Public API

| Symbol | Role |
| --- | --- |
| `Pcg32` / `randomBound` | Accepted GEN-01 PRNG |
| `DifficultyProfile` | Easy / Medium / Hard |
| `GeneratorVersion.gen001V1` | `gen-001.v1` |
| `ChallengeGenerationConfig` | Profile + exact Accepted parameters |
| `generateChallenge(config, seed)` | Deterministic generation entry point |
| `GeneratedChallenge` | Outer metadata + immutable `GameState` |
| `ChallengeGenerationFailure` | `invalid_config` / `generation_exhausted` |

No Flutter, Flame, networking, or host `Random`.

## Profiles

| Profile | Board | Moves | Obstacles | Occupied |
| --- | ---: | ---: | ---: | ---: |
| Easy | 5 | 15 | 1 | 6 |
| Medium | 6 | 12 | 2 | 10 |
| Hard | 7 | 10 | 4 | 16 |

Monster is rejected. Profiles are versioned starting settings, not validated difficulty.

## Draw ordering

1. Validate config (no RNG).
2. `seed32` once.
3. Up to 256 board attempts; on failure keep PRNG state; **do not** draw supply.
4. Obstacles via partial Fisher–Yates, then sort row-major.
5. Occupied cells via partial Fisher–Yates on free cells (selection order kept).
6. Per occupied cell: `randBound(3)` shape, `randBound(4)` direction.
7. Reject boards with any H/V run ≥ 3.
8. After accept: `supplyLength = moveLimit + 2` pieces; offers = first 3; future = rest.
9. `parseInitialGameState` + S0/S1 checks.
10. Return deeply immutable `GeneratedChallenge` with `rulesVersion = core-001.v2`.

## PRNG reference

Seed `0` / `1` / `4294967295` first-10 tables and `randBound` vectors live in the Accepted decision document. Package tests copy those expected integers literally.

## Fixtures

Directory: [`docs/contracts/generator/gen-001.v1/`](../contracts/generator/gen-001.v1/README.md).

Positive fixtures were authored by an independent Python BigInt reference, then verified by Dart. `CHECKSUMS.txt` covers positive files.

## Determinism

Same `(generatorVersion, profile/config, seed)` → identical challenge JSON, including full `futurePieces`. Failed board attempts consume RNG and are part of that sequence.

## Cross-runtime parity

| Evidence | Status |
| --- | --- |
| Dart ↔ independent Python fixtures | Covered by tests |
| Dart ↔ backend TypeScript runtime | **NOT_RUN** |

## Remaining product risks

- UTC-date → seed mapping not specified.
- Early board-full + empty stream still unapproved.
- Easy/Medium/Hard are not empirically rated.
- Backend generator still required for ranked cross-runtime proof.
