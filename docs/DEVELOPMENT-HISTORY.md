# Puzzle Duel — Mandatory development and operational ledger

Owner mandate: 2026-11-28. Read this file before EVERY project action, including advice, build commands, review, Jira, GitHub, debugging, deployment and tests. Append a dated record after every meaningful action, including failed or blocked actions. Never reconstruct configuration from memory when repository evidence exists.

## Canonical references
- Staging: [SERVER-CONFIG.md](staging/SERVER-CONFIG.md). Oracle IPv4 **84.13.66.211**; transport **https://84-13-66-211.sslip.io**. JWT issuer https://staging.puzzle-duel.app is NOT the transport URL. Trusted HTTPS /healthz HTTP 200 preflight required each time. Both Google OAuth client IDs and native Firebase flags must come from the runbook. Local signed release build + install; no uninstall, data wipe, direct Oracle SSH or unapproved deployment.
- [Observability release gate](staging/STAGING-OBSERVABILITY-RELEASE-GATE.md).
- [Native Firebase build](../apps/mobile/firebase/STAGING_BUILD.md).
- [PZD-54 account isolation and notifications](architecture/PZD-54-ACCOUNT-ISOLATION-AND-NOTIFICATIONS.md).
- Read actual current branch, relevant feature docs, accepted ADRs, Jira decisions and PR diffs. Never regress accepted behavior without explicit owner approval.

## GOLDEN RULE 0 — mandatory ordered workflow
1. Read DEVELOPMENT-HISTORY.md.
2. Read SERVER-CONFIG.md.
3. Check previous product decisions and developments, including observability requirements.
4. Verify no regression of existing behavior.
5. **ABSOLUTE NO-REGRESSION — Log Gönder (UAT):** No action or change may negatively impact manual diagnostic upload, its visibility, authorized guest/verified-account operation, HTTP 201 + reportId delivery, or Request ID / Report ID Inspector correlation. Before every change assess impact; after every development run applicable regression tests and verify end-to-end on staging before merge/release/Done. FAIL or NOT_RUN blocks acceptance; green CI alone is insufficient. Never bypass authentication, redaction, or production isolation; never fake success. If a regression is found, prioritize restoring diagnostics before unrelated work.
6. Record outcomes, changes, tests and decisions after every action.

## Current accepted constraints / regression matrix
- Gameplay, scoring, graphics and game animations immutable unless owner explicitly approves.
- Guest Practice available; verified Apple/Google required for tournament. No Firebase Auth. Do not silently create or merge accounts; preserve legitimate progress. Login UX should remain simple; do not expose technical recovery/session/writer options in normal login. Exceptional recovery must be investigated, not hidden or bypassed; owner rejects unsolicited recovery UI. Exact historical UX acceptance must be checked against Jira/PR before changes.
- Logout must clear personal tournament score, progress, rank, badges and account-scoped cached state; reject stale async completions. Same-account re-login restores legitimate server history.
- All transient feedback via single swipe-dismissible Top Banner (info/warning/success); no bottom Snackbar/Toast. No misleading free/paid copy.
- Staging Log Gönder and Crash Test visible; privacy-safe request/report correlation mandatory. No named-player provisioning resurrection.
- Preserve unrelated local changes; no automatic stash/reset; no merge/deploy without owner approval.

## Recorded history (not a claim of fresh UAT)
- 2026-11-22: runbook records trusted TLS HTTP 200 on sslip.io. JWT issuer deliberately remains distinct.
- PZD-53: personal records / account-scoped sync; preserve Practice/Tournament/All segments and verified tournament results. Verify actual issue history before altering.
- PZD-54 PR #60: d24e1be initial isolation/banner, 31b5c54 generation/drag/copy remediation, 624ebf5 leaderboard/cache/session fences, 7f45613 sync edge/register/401 fixes. GitHub workflows all green at 7f45613; Cursor reported 518 passed, 68 visual golden skipped; device UAT not accepted.
- 2026-11-28: assistant supplied wrong staging transport hostname and omitted Google OAuth IDs in build advice. Owner reported recovery/login/connectivity failure. Source comparison showed recovery sheet already existed on PR base; exact device failure cause not independently proven. No code revert performed. Review approval withdrawn pending device validation. Runbook corrected in e6279c4; do not repeat incorrect build recipe.
- 2026-11-28: owner requires mandatory read/write ledger for every project action. This file and AGENTS.md enforce the process. Documentation only; no gameplay/auth code change or deployment.

## Required append format
Date/time | action and reason | owner decision / relevant regression | repo/ref/PR/Jira | files or commands (no secrets) | actual result and evidence | tests/CI/UAT (PASS/FAIL/NOT_RUN) | blockers and next action.
Record build advice and operational actions as well as code changes. Never claim an action was performed or a test passed without evidence. Keep prior entries; correct mistakes with a new dated entry.

- 2026-11-28 — Owner requested immediate revert of any newly introduced login bottom-sheet development. Read ledger and SERVER-CONFIG first. Compared PR #60 base `2b42ac7` vs `ddea036`: `_presentRankedAuth` and `_presentSessionRecovery` identical after whitespace/trailing-comma normalization; recovery routing already exists on base. No targeted new sheet change found to revert. No auth code, gameplay, storage or backend mutation; no merge/deploy. Device login recovery cause still unverified; prior wrong build transport is a known configuration error, not proven sole cause. Tests/UAT NOT_RUN. Owner explicitly rejects unsolicited recovery UI; investigate separately if it persists on canonical verified build.

- 2026-11-28 — Owner requested device UAT. Read ledger then SERVER-CONFIG; PR #60 head cd42fd0 before this documentation entry. Provide canonical local signed iOS release recipe with trusted TLS HTTP 200 preflight, both documented Google OAuth IDs, Firebase and diagnostics flags, install over existing app. Target feature branch, no merge/deploy or source changes. Prior source CI green at 7f45613; current Mac preflight/build/device login and logout UAT NOT_RUN by assistant. Test normal login first; if recovery UI persists, capture diagnostic report/request ID and investigate before further changes. Preserve account data and prior UX.

- 2026-11-28 14:07+03 — Owner UAT reports three findings: guest Profile must show only Practice records, no All/Practice/Tournament segmented control; verified tournament personal records never appear (owner report); manual Log Gönder fails (owner report, status/requestId not yet provided). Read ledger, SERVER-CONFIG and observability gate. Source findings: player_profile_screen.dart renders _PersonalRecordsSegmentedControl unconditionally and _visibleRecords uses selected segment without guest restriction; guest copy mentions verified account. personal_records_repository.dart fetches GET /v1/profile/me/personal-records for verified accounts and filters tournament records by source/difficulty/core-001.v3/gen-001.v1; live payload/schema/publication not yet verified. tournament_settings.dart invokes sendStagingManualDiagnostics using controller.api; helper requires nonempty bearer and POST /v1/diagnostics/reports 201+reportId. Latest observed backend staging CD 46074806450 success, not live endpoint proof. Inspector workflow listing by filename unavailable via connector; no new inspector run executed. No source changes, no merge/deploy. Device UAT FAIL for reported features; actual HTTP status and request correlation pending. Preserve login UX, guest history, account isolation, banner, gameplay; investigate via Inspector and add regression coverage before release. Diagnostic failure is release blocker.

- 2026-11-28 — Owner explicitly strengthened GOLDEN RULE 0: never negatively impact Log Gönder; mandatory pre-change impact review and post-development regression/end-to-end gate. Recorded in AGENTS.md, observability release gate and ledger. Documentation only; current reported diagnostic failure remains unresolved, tests/UAT NOT_RUN for this documentation action; no merge/deploy.

- 2026-11-28 — Owner requested merge if CI passes and immediate test. Read ledger then SERVER-CONFIG; checked PR #60 head `296b367`: mergeable, unmerged; Flutter mobile run 46138800525 in progress, native verification 46138800475 pending, Android verification 46138800488 pending. Merge blocked by incomplete CI and GOLDEN RULE 0 diagnostic UAT failure; no new evidence of HTTP 201/reportId or Inspector correlation. No merge/deploy, no source change, no device test performed. Next: diagnose and restore manual diagnostics, verify guest/verified upload and Inspector correlation before acceptance. Feature-branch UAT does not require merge.
