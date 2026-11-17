# CORE-001.v3 implementation roadmap

Status: **ADR-E01 D1–D10 Accepted for architecture/design (2026-11-17)**; implementation, executable fixture freeze, integration, and release have separate evidence and approval gates.
Revised for P0/P1 remediation (status-agnostic terminal validation; hash≠authority; canonical bytes; provenance; initial playability; checked ints).

## Stages

### A — Owner design approval (complete: design only)

Deliverables: Accepted ADR-E01 D1–D10, architecture review, fixture spec, canonical vectors, this plan.  
Historical v1/v2 reference checks and atom digests are documented; they do not prove executable v3 parity.

### B — Dart v3

`hasLegalPlacement`, `deriveTerminalExpectation`, tagged offers, checked ints, v3 dispatch.  
`dart test` + pending goldens. Evidence and acceptance tracked in PZD-39 Stage B PR.

### C — TypeScript pure engine

Independent replay module; same predicates; no Flutter/Dart runtime dependency. Evidence and acceptance tracked in PZD-39 Stage C PR.

### D — Freeze

Independent oracle + dual PASS + negatives + v1/v2 regression + ledger. Only then FROZEN/PASS. Evidence and acceptance tracked in PZD-39 Stage D PR.

### E — Tournament wiring

PZD-38 consumes engine results; owns identity/time/idempotency/writer/LB. Trusted checkpoints only. Evidence and acceptance tracked in PZD-39 Stage E PR.

### F — Release evidence

Matrix PASS/FAIL/SKIP/NOT_RUN. No production pin early. Live-provider authentication, final contract, production UAT and release require separate acceptance.

## Gate clarification

Design acceptance is not runtime acceptance. Consult each stage's latest PR and verification report for PASS/FAIL/SKIP/NOT_RUN; do not infer test completion from this roadmap. Full GameState hash freeze, production authenticated HTTP, device UAT, merge and deploy require their own gates.
