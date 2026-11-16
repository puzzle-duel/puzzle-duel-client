# gen-001.v1 generator fixtures

Accepted algorithm: [`docs/engine/PZD-21-GENERATOR-DECISIONS.md`](../../../engine/PZD-21-GENERATOR-DECISIONS.md).  
Implementation guide: [`docs/engine/PZD-21-GENERATOR.md`](../../../engine/PZD-21-GENERATOR.md).

These fixtures are **independent** of the Dart package. They were produced by a standalone Python BigInt reference that implements the Accepted PCG32 / Fisher–Yates / supply contract, then checked by the Dart `generateChallenge` tests.

## Layout

| Path | Role |
| --- | --- |
| `fixtures/*.json` | Positive challenges for Easy/Medium/Hard × seeds |
| `invalid/probes.json` | Negative config probes (expect `invalid_config`) |
| `CHECKSUMS.txt` | SHA-256 of each positive fixture file |

## Schema

Each positive fixture matches GEN-07:

`generatorVersion`, `rulesVersion` (`core-001.v2`), `seed`, `profile`, `config`, `blocked`, `cells`, `offers`, `futurePieces`, `turnsUsed`, `score`, `status`.

Gameplay `docs/contracts/gameplay/v1` and `v2` fixtures are untouched.

## Parity

| Check | Status |
| --- | --- |
| Independent Python reference ↔ Dart `generateChallenge` | Exercised by package tests |
| Client/backend TypeScript executable parity | **NOT_RUN** (backend generator not authorized in PZD-21) |
