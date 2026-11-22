# Puzzle Duel iOS staging — server and local-build runbook

**Updated:** 2026-11-22  
**Environment:** staging / `version/0.0.2`  
**Authoritative infrastructure reference:** [Backend Oracle server config](https://github.com/puzzle-duel/puzzle-duel-backend/blob/version/0.0.2/docs/staging/SERVER-CONFIG.md)

> **DO NOT ASK FOR THE ORACLE IP AGAIN:** `84.13.66.211` (`forest-dash-vnic`). This IP is **not** a verified HTTPS API URL. **DO NOT** send the owner to the historical offline Easy / Medium / Hard home. Only the backend-backed tournament/leaderboard shell is acceptable.

## Known infrastructure values

| Setting | Actual / recorded value |
| --- | --- |
| Oracle VM | `forest-dash-vnic` |
| Oracle public IPv4 | **`84.13.66.211`** |
| SSH account | `pzd-staging` |
| Backend runtime | Node 26, `pzd-staging.service` |
| Backend listener | **`127.0.0.1:8787` on Oracle only**, not from Mac/iPhone |
| Database | PostgreSQL 18 / isolated DB `pzd_staging` |
| Auto CD | Backend `version/**` push via `puzzle-duel-backend/.github/workflows/staging-cd.yml` |
| iOS local build | Physical iPhone ID `00008160-001C5C993E80000A` |
| iOS branch | `puzzle-duel-client/version/0.0.2` |
| iOS launch entrypoint | `apps/mobile/lib/main.dart` → `TournamentUatApp` exclusively |
| Firebase staging project | `puzzle-duel-staging` |
| iOS Firebase resource flag | `PZD_STAGING_FIREBASE=1` |
| App diagnostics | `PZD_FIREBASE_CONFIGURED=true`, `PZD_DIAGNOSTIC_ENV=staging`, `PZD_STAGING_DIAGNOSTICS=true` |
| Backend diagnostic log | `/home/pzd-staging/pzd-staging/http-diagnostics.log` on Oracle |
| Proposed hostname in legacy code/contracts | `staging.puzzle-duel.app` — **NOT VERIFIED WORKING** |

## HTTPS and auth: DO NOT PRETEND THE DOMAIN WORKS

2026-11-22 tests:
- `https://staging.puzzle-duel.app/healthz` → DNS resolution failed.
- `https://84.13.66.211/healthz` → TCP 443 connected but TLS handshake failed.
- `curl --resolve staging.puzzle-duel.app:443:84.13.66.211 https://staging.puzzle-duel.app/healthz` → TLS handshake failed.
- Oracle local backend health check succeeded via GitHub CD, but that **does not** prove external TLS or API access.

**No verified public HTTPS staging origin is recorded as of this revision.** Do not blindly substitute the Oracle IP or an invented hostname in `PZD_STAGING_BASE_URL`.

The client `GuestAuthClient` requires a valid HTTPS origin, and its `sessionVaultBinding` currently expects JWT issuer `https://staging.puzzle-duel.app`. The backend guest issuer is tied to the same value. Any move to IP-based HTTPS or another hostname requires a real trusted certificate and coordinated auth-issuer changes, not just a build flag.

The app has an intentionally **fail-closed** startup on `version/0.0.2`: missing HTTPS config or failed guest auth displays an explicit error; never silently opens offline practice. The old `presentation/home/home_screen.dart` difficulty-choice UI has been deleted on this branch. Do not change game mechanics or animations.

## Local Mac workflow (never remote build)

From the **Mac**, preserve unrelated working-tree changes; do not run destructive `git reset --hard` or stashes automatically:

```sh
cd ~/Desktop/workspace/puzzle-duel-client
git status --short
git fetch origin
git switch version/0.0.2
git pull --ff-only origin version/0.0.2
git branch --show-current
git rev-parse --short HEAD
cd apps/mobile
flutter pub get --enforce-lockfile
```

Last confirmed release commit **at initial branch verification**: `58f1d3e`; check current `origin/version/0.0.2` because commits may advance.

**Only when an externally reachable, trusted HTTPS `PZD_STAGING_BASE_URL` is verified**, set the real origin in the Mac shell. Example (uses an already-configured variable; does not invent a value):

```sh
: "${PZD_STAGING_BASE_URL:?Verified HTTPS staging origin is required}"
curl -fsS --connect-timeout 5 --max-time 15 "${PZD_STAGING_BASE_URL%/}/healthz"
PZD_STAGING_FIREBASE=1 flutter run \
  -d 00008160-001C5C993E80000A \
  --device-timeout 60 \
  --release \
  --dart-define=PZD_STAGING_BASE_URL="$PZD_STAGING_BASE_URL" \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true \
  2>&1 | tee /tmp/pzd-version-0.0.2-ios.log
```

This compiles and installs on the **local Mac and physical iPhone**. It does not invoke remote iOS build or Android distribution.

## Oracle diagnostics are NOT Mac commands

```sh
ssh pzd-staging@84.13.66.211
systemctl status pzd-staging.service --no-pager -l
curl -i http://127.0.0.1:8787/healthz
tail -n 50 /home/pzd-staging/pzd-staging/http-diagnostics.log
```

`127.0.0.1` on Mac is the Mac, and on Oracle is the Oracle VM. Caddy/`systemctl` checks belong on Oracle. Avoid modifying the co-resident Forest Dash service.

## Pre-build and release gates

1. The local branch must be exactly `version/0.0.2` with up-to-date commit; don't build if `git switch` or `git pull` failed due to local modifications.
2. `main.dart` must launch only `TournamentUatApp`. Never revert to the historic offline shell.
3. A valid HTTPS origin must work from the Mac and iPhone; `/healthz` should return 2xx. Verify guest auth and tournament/leaderboard independently.
4. Existing Firebase staging configuration and dSYM upload must be verified independently; avoid claiming symbolication complete because a build succeeded.
5. Preserve all board rules, game engine and animation appearance. No production deployment.

## Recording changes

When HTTPS ingress is actually fixed, add the **tested exact HTTPS origin**, certificate/issuer decision, and verification date here and in the backend canonical server config. No password, token or private key may be committed.
