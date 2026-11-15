# Cursor handoff — PZD-11 (first bounded task)
Jira: https://puzzle-duel-app.atlassian.net/browse/PZD-11
Start state: Documentation exists in both repositories, but PZD-11 contracts are in review branches. **Do not begin until contract PR(s) are merged or copy this exact specification from the review PR.**

## Single task
Produce a language-independent, audited fixture suite for CORE-001. No application code, app scaffold, server, authentication, IAP, ads, deployment or monetization work.

## Execute in order
1. Read `BLUEPRINT.md`, `AGENTS.md`, `docs/features/F01-core-and-levels.md` (client), `docs/testing/QUALITY-GATES.md`, and `docs/contracts/gameplay/PZD-11-CONTRACT.md`.
2. Audit contract for contradictions and identify any unresolved decisions; if they affect outputs, STOP and ask, don't choose.
3. On `feature/PZD-11-canonical-fixtures`, create the JSON schema and individual reference fixtures in `docs/contracts/gameplay/v1/`. Keep coordinate convention and shape/direction tokens exact.
4. Independently compute assertions for matching/shift/cascade and fully document wave breakdown. Do not supply guessed complex expected values.
5. Produce parity evidence: equivalent fixtures with identical contents/hash for client and backend; if only one repo is editable, publish the canonical source and exact sync procedure rather than claiming parity.
6. Do structural JSON validation and documented manual/reference checks. Add runnable validation only if it requires no unapproved runtime/dependency.
7. Submit PR `[PZD-11] Define canonical gameplay replay fixtures` and link Jira issue.

## Strict exclusions
No implementation of F01 motor, no changing V3.2 rules, no Monster production, no paid services, no changing ADR status, no production changes, no merge. CI/test results must distinguish executed vs unexecuted. Report file list, independent derivations, known gaps and exact verification commands.

## Output template
- Contract compliance: PASS / gaps
- Fixture list with cases
- Expected scoring/phase traces
- Validation commands and outcomes
- Client/backend parity evidence
- Jira/PR URL
- Blockers needing owner approval
