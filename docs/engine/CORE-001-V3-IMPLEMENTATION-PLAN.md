# CORE-001.v3 implementation roadmap

Status: Proposed — **no engine coding until ADR-E01 Accepted by owner**.
Revised for P0/P1 remediation (status-agnostic terminal validation; hash≠authority; canonical bytes; provenance; initial playability; checked ints).

## Stages

### A — Owner design approval (current)

Deliverables: ADR-E01 Proposed, architecture review, fixture spec, canonical vectors, this plan.  
Tests: historical v1/v2 `reference_check.py` PASS; atom digests SPECIFIED.  
Complete when: owner accepts D1–D10.

### B — Dart v3

`hasLegalPlacement`, `deriveTerminalExpectation`, tagged offers, checked ints, v3 dispatch.  
`dart test` + pending goldens.

### C — TypeScript pure engine

Independent replay module; same predicates; no Flutter/Dart runtime dependency.

### D — Freeze

Independent oracle + dual PASS + negatives + v1/v2 regression + ledger. Only then FROZEN/PASS.

### E — Tournament wiring

PZD-38 consumes engine results; owns identity/time/idempotency/writer/LB. Trusted checkpoints only.

### F — Release evidence

Matrix PASS/FAIL/SKIP/NOT_RUN. No production pin early.

## NOT_RUN until later stages

Dart/TS v3 code, full GameState hash freeze, Nest e2e, device UAT, deploy.
