# CORE-001.v3 implementation roadmap

Status: Proposed plan — **no engine coding until ADR-E01 Accepted**.

## Stages

### A — Proposed ADR + fixture approval (this PR)

**Deliverables**

- `docs/adr/ADR-E01-core-001-v3-natural-terminal.md`
- `docs/contracts/gameplay/v3/FIXTURE-SPEC.md`
- `docs/engine/CORE-001-V3-BASELINE-AUDIT.md`
- `docs/engine/CORE-001-V3-TOURNAMENT-INTEGRATION.md`

**Tests:** documentation review only; run historical checkers to prove non-regression of suites we did not touch:

```bash
# client or backend worktree
python3 docs/contracts/gameplay/v1/reference_check.py
python3 docs/contracts/gameplay/v2/reference_check.py
```

**Complete when:** owner Accepts or returns comments on ADR-E01 decisions.

### B — Dart engine v3

**Deliverables:** `RulesVersion.core001V3`, tagged offers parse/validate, `hasLegalMove`, terminalReason, offer spent commit, version dispatch in `applyMove`.

**Tests:**

```bash
cd packages/puzzle_duel_rules && dart test
```

Plus new v3 golden tests once fixtures frozen.

### C — TypeScript engine v3

**Deliverables:** pure `src/engine/core001/` (name TBD) with no Nest/DB/HTTP; mirror Dart semantics.

**Tests:** `node --experimental-strip-types --test test/engine/**/*.test.mts`

### D — Golden parity + historical regression

Freeze fixtures; dual-run; SHA-256 ledger; v1/v2 checksum unchanged.

### E — Tournament integration contract

Wire replay to PZD-38 series games only after engine PASS; engine must not mutate entitlement, deadlines, writer generation, journals, or leaderboards.

### F — Final review / release evidence

Matrix PASS/FAIL/SKIP/NOT_RUN; no production pin until evidence attached.

## Non-goals until approval

- Implementing Stages B–F code
- Accepting ADR-E01 unilaterally
- Touching `feature/PZD-38-trusted-ingress` / PR #13
