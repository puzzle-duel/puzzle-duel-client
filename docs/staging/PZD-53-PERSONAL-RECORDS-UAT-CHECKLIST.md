# PZD-53 — Phase 2 Personal Records UAT Checklist

**Baseline:** Phase 1 staging (backend `7f8362e` / client `6cc15cd`) + new Phase 2 build.  
**Do not mark PASS until actually performed.** Physical-device and multi-device rows start as `NOT_RUN`.

## Preconditions

- [ ] Staging migration `0010_player_personal_best` planned + applied (owner-approved Action)
- [ ] Staging backend deploy includes personal-records routes
- [ ] New staging iOS build installed (over existing app for migration scenario A)
- [ ] Verified Apple/Google account available (no named staging DB accounts)

## A — Existing record migration

1. Install new staging release over existing app (do not clear data).
2. Login with existing verified account.
3. Open Profile.
4. Verify previous Practice records remain visible.
5. Verify existing badges unchanged.
6. Verify remote sync succeeds (or honest pending/offline status).

Result: `NOT_RUN`

## B — Online Practice personal record

1. Complete Easy Practice with a new high score.
2. Open Profile → Practice / All.
3. Verify Easy Practice + All Easy (if highest).
4. Verify Tournament Easy unchanged.
5. Complete a lower-score Easy game; record must not decrease.

Result: `NOT_RUN`

## C — Offline Practice

1. Verified account + known local records.
2. Disable network; complete Practice with new high score.
3. Verify immediate local visibility + pending/offline status.
4. Kill app; relaunch offline; record survives.
5. Restore network; automatic reconciliation; synchronized status.

Result: `NOT_RUN`

## D — Tournament board record

1. Complete an official individual manifest (full series → F2-B publication).
2. Note each board’s final individual score (not daily series total).
3. Profile → Tournament shows matching difficulty max; All uses max with Practice.
4. Practice segment unchanged; leaderboard/badge behavior unchanged.

Result: `NOT_RUN`  
Note: Tournament PBs become available after H1/F2-B publication, not mid-series.

## E — Account isolation

1. Login A → establish records → logout.
2. Guest must not see A’s remote/local verified records.
3. Login B → only B’s records.
4. Login A again → A’s records + pending resume if any.

Result: `NOT_RUN`

## F — Multi-device recovery

1. Sync verified records on device 1.
2. Authenticate same player on device 2 → remote records appear.
3. Higher Practice on device 2 → refresh device 1 → both converge on max.

Result: `NOT_RUN`

## G — Observability

1. Perform personal-record sync.
2. Settings → Log Gönder → real Report ID.
3. Unified Request Log Inspector: `profile_personal_records` route correlation.
4. Firebase custom breadcrumbs for `fetchPersonalRecords` / `syncPracticeRecords` when configured.

Result: `NOT_RUN`

## Observability release gate (unchanged)

- Log Gönder (UAT) visible on staging; Crash Test visible with honest Firebase status.
- Production builds hide test controls.
