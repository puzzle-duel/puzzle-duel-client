# Puzzle Duel — Mandatory development and operational ledger

Owner mandate: 2026-11-28. Read this file before EVERY project action, including advice, build commands, review, Jira, GitHub, debugging, deployment and tests. Append a dated record after every meaningful action, including failed or blocked actions. Never reconstruct configuration from memory when repository evidence exists.

## Canonical references
- Staging: [SERVER-CONFIG.md](staging/SERVER-CONFIG.md). Oracle IPv4 **84.13.66.211**; transport **https://84-13-66-211.sslip.io**. JWT issuer https://staging.puzzle-duel.app is NOT the transport URL. Trusted HTTPS /healthz HTTP 200 preflight required each time. Both Google OAuth client IDs and native Firebase flags must come from the runbook. Local signed release build + install; no uninstall, data wipe, direct Oracle SSH or unapproved deployment.
- [Observability release gate](staging/STAGING-OBSERVABILITY-RELEASE-GATE.md).
- [Native Firebase build](../apps/mobile/firebase/STAGING_BUILD.md).
- [PZD-54 account isolation and notifications](architecture/PZD-54-ACCOUNT-ISOLATION-AND-NOTIFICATIONS.md).
- Read actual current branch, relevant feature docs, accepted ADRs, Jira decisions and PR diffs. Never regress accepted behavior without explicit owner approval.

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
