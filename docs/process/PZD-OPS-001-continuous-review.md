# Puzzle Duel — Continuous Review & Jira Synchronization Protocol
**Document ID:** PZD-OPS-001  
**Status:** Proposed — owner review required  
**Applies to:** `puzzle-duel-client`, `puzzle-duel-backend`, Jira project `PZD`  
**Jira:** https://puzzle-duel-app.atlassian.net/jira/software/projects/PZD/boards/35

## Intent and operational truth
The owner authorizes continuous review and corrective iteration **within the currently approved Jira task**, without asking the owner each time a fix is necessary. The owner must explicitly approve **starting a different task**, changing product decisions/Accepted ADRs, merging to protected branches, deploys, store releases, paid resources, and material scope changes.

This Markdown file is an **operating contract, not executable automation**. Cursor/local actions do not automatically wake ChatGPT. An event-driven integration or scheduled agent with working GitHub and Jira permissions must actually run this protocol. When no such trigger is active, report `MONITOR_NOT_ACTIVE` and never imply autonomous review happened. A CI pass is not an AI code review.

## Roles and boundaries
- **Owner:** approves new task kickoff and irreversible/production operations; decides unresolved product and architecture policy.
- **Cursor:** implements ONLY the already-approved task specification; reads `AGENTS.md`, `BLUEPRINT.md`, relevant feature files, this protocol and Accepted ADRs; runs targeted checks; pushes commits/PR; posts an exact delivery report to the Jira issue or PR. For fixes on the SAME task, iterate without asking owner again if scope and accepted rules are unchanged. Do not claim tests not executed.
- **Reviewer/ChatGPT:** monitors GitHub PR/commit/check changes *when invoked by actual triggering infrastructure*, reads code diffs and critical files, validates scope + tests, records severity-ranked findings, writes executable Cursor follow-up instructions, and updates Jira. It cannot directly interact with an unattended local Cursor instance merely by publishing a prompt. If a Cursor automation/connector is not configured, place the prompt as a Jira comment and PR review; the user or a configured agent must deliver it to Cursor.
- **GitHub Actions:** automatic deterministic checks on PR/commit where configured; these checks supplement, never substitute for human/AI review.

## Source hierarchy and decision handling
1. The owner's latest explicit decisions and Jira task scope.
2. Current approved product blueprint plus rule IDs, e.g. CORE-001.
3. **Accepted** ADRs only (Proposed/Deprecated/Rejected are not binding).
4. Task-specific contract and fixture specifications, without contradicting 1–3.
5. Existing code conventions where consistent.

If sources conflict or an implementation requires a new product/architecture decision, STOP **that part of the task**; record `OWNER_DECISION_REQUIRED` and a concrete choice with impact. Continue only safe independent work. Never invent rules for blank futurePieces, cascade limits, official attempt lifecycle, lifetime ranking or ad consent.

## Review trigger and deduplication
Whenever a connected reviewer is invoked after a new `PZD-*` commit, PR open/synchronize/reopen, CI completion/failure, or a relevant Jira update:
1. Identify the Jira issue key and repo/PR/HEAD SHA.
2. Read the current issue, target branch, diff, changed files, CI evidence, Blueprint, AGENTS and pertinent Accepted ADRs. Cross-repo work reads BOTH.
3. Use `repo + PR number + HEAD SHA + check conclusion` as a review fingerprint. If previously reviewed with no new evidence, do not spam comments or repeat work.
4. Distinguish what was **directly verified** from Cursor-reported outcomes and what could not be tested.
5. Update Jira with commit/PR/check links and meaningful progress, not individual file saves or unpushed edits.
6. Evaluate code in order: rule conformity; architecture/security; deterministic state; edge cases; concurrency/error recovery; tests; integration; privacy/secret handling; regressions; CI status.
7. For any issue, file a review finding with severity `BLOCKER/P1/P2/P3`, exact file/function, reproduction, expected behavior and a minimal acceptance test.
8. If a fix is needed, generate a **single consolidated Cursor fix prompt** anchored to the existing Jira task and open PR(s), not a new Jira task. No need to ask owner to revise that same task. If direct Cursor dispatch is unavailable, publish that prompt to Jira and notify the owner once (do not pretend it was executed).
9. Rerun the review against the *new HEAD* only after a new push/check event. Do not repeatedly claim fixed without new evidence.
10. Do not move to a new task until owner says to proceed.

## Jira state machine (based on evidence)
| Status | Set only when |
|---|---|
| To Do | Task created, no analysis/development started |
| Analysis | Specification/acceptance criteria being authored or materially unresolved |
| In Progress | Cursor implementing or reworking requested changes in same task |
| Code Review | PR pushed and waiting technical review; review failures with active fixes -> In Progress |
| In Test | Technical review accepted, deterministic tests/CI/UAT underway |
| Done | Acceptance criteria and required tests satisfied, evidence recorded, owner-approved completion/merge policy met |

Jira comments must include timestamp, evidence links, HEAD SHA, checks run vs NOT_RUN, review decision, next requested action, and any blockers. Do not mark Done merely because Cursor said PASS or a PR was opened. If a task spans client/backend, both sides must meet the acceptance bar.

## Same-task autonomous iteration policy
**Allowed without repeated owner permission:** request rerun of tests, clarify test assertions, propose and request fixes matching accepted scope, update Jira progress/comments/status accordingly, and review new pushes. All modifications should go through Cursor's existing feature branch/PR and targeted tests.

**Requires owner's explicit approval:** any different Jira key / epic; approving Proposed ADR or revised blueprint rule; adding unrelated scope/features; dependency with significant licensing/privacy/cost impacts; merge, direct commit to main, release/deploy, changing live infrastructure, secrets/credentials, and destructive operations.

## Review outcome contract
Write a single concise report:
```
Jira: PZD-###
Repository / PR / HEAD:
Review: APPROVE | CHANGES_REQUESTED | BLOCKED | WAITING_FOR_EVIDENCE
Verified: [command/results with links or "not run"]
Cursor-reported (not independently verified): ...
Findings:
- P1 — path:line — actual vs expected — reproduction — required test
Jira transition + comment: [confirmed state]
Cursor action: [prompt posted / agent dispatched / no dispatcher configured]
Next gate: SAME_TASK_FIX | SAME_TASK_TEST | OWNER_APPROVAL_FOR_NEW_TASK
```

## Cursor feedback format
A Cursor fix request MUST include:
- Jira key, links, exact branch and latest HEAD, and files allowed to change.
- Numbered findings, expected outputs, negative tests and verification commands.
- Exclusions, ADR/blueprint constraints, no merge/deploy, and response schema.
- No broad speculative refactors or unrelated new work.

## Mandatory post-development summary (GOLDEN RULE)
After every meaningful development milestone, implementation, bug fix, refactoring, or review remediation, Cursor (and any coding agent) must deliver a clear development summary to the owner **in Turkish**, keeping technical identifiers and file names in English, and must record the same summary on the corresponding Jira issue. Required sections: what was implemented; why; how it works; files changed; impact; technical decisions; testing with actual executed results; GitHub branch/SHA/PR/CI; Jira status and comment references; remaining work/risks/blockers; next step; owner action required (yes/no and what). A milestone is not complete until this summary is delivered. Providing a summary does not require stopping for approval unless a real approval gate was reached. Persist and follow this rule at the start of every task. Distinguish Implemented / Tested / Verified / Merged / Deployed / NOT_RUN / BLOCKED honestly.

## Automation availability / fail-safe
A true unattended review loop needs **two independently functioning integrations**: (1) source event scheduling or GitHub webhook/periodic polling, and (2) an agent runtime that can inspect code, post Jira/PR updates and submit fix prompts to Cursor. This document does not provision either.

If only hourly monitoring is available, state that latency and never claim action-by-action immediate review. A GitHub Actions workflow can automatically run unit/fixture checks on pushes, but cannot by itself run the ChatGPT conversation or control local Cursor. Never give a CI workflow unattended production credentials or permission to merge.

## Current tracked task example — PZD-11
- Client PR: https://github.com/puzzle-duel/puzzle-duel-client/pull/3
- Backend PR: https://github.com/puzzle-duel/puzzle-duel-backend/pull/3
- Known review issues: cascade guard mismatch at 20-wave boundary, JSON Schema validation coverage, missing CI checks; fixture parity and empty piece stream policy must remain explicit.
- Keep issue under same-task revision/review until evidence clears findings; do not automatically start PZD-17.
