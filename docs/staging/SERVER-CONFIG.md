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

## Actual Oracle HTTPS hostname (operator Caddyfile, 2026-11-22)

**Configured Caddy hostname:** `84-13-66-211.sslip.io` → `127.0.0.1:8787`. Oracle IPv4 remains `84.13.66.211`. Forest Dash is separately hosted on `:80` / port `3001` and must not be modified.

**Candidate external Flutter API origin:** `https://84-13-66-211.sslip.io`. This is from the **actual live /etc/caddy/Caddyfile**, unlike the obsolete `staging.puzzle-duel.app` placeholder. **Public HTTPS/TLS verification is still required** before running a release build.

From Mac:
```sh
curl -i --connect-timeout 5 --max-time 12 https://84-13-66-211.sslip.io/healthz
```
Only use the candidate origin in `PZD_STAGING_BASE_URL` if the above returns HTTP 200 with valid trusted TLS (no `-k`). Example after success:
```sh
export PZD_STAGING_BASE_URL=https://84-13-66-211.sslip.io
```
The guest JWT `iss` value remains `https://staging.puzzle-duel.app` in both client and backend **as an issuer identity**; it does **not** need to match the Caddy connection origin. Do not casually rewrite it or invalidate existing guest tokens.

## HTTPS and auth: DO NOT PRETEND THE DOMAIN WORKS

2026-11-22 tests:
- `https://staging.puzzle-duel.app/healthz` → DNS resolution failed.
- `https://84.13.66.211/healthz` → TCP 443 connected but TLS handshake failed.
- `curl --resolve staging.puzzle-duel.app:443:84.13.66.211 https://staging.puzzle-duel.app/healthz` → TLS handshake failed.
- Oracle local backend health check succeeded via GitHub CD, but that **does not** prove external TLS or API access.

**The live Caddy hostname is now known (above), but public HTTPS is not yet confirmed working.** Do not blindly substitute the Oracle IP or an invented hostname in `PZD_STAGING_BASE_URL`.

The client `GuestAuthClient` requires a valid HTTPS origin, and its `sessionVaultBinding` currently expects JWT issuer `https://staging.puzzle-duel.app`; the backend signs tokens with the same issuer. The issuer is an identity claim and can remain unchanged when the HTTPS transport uses the verified sslip.io hostname. TLS must still be valid and trusted.

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

## Standalone on-device iOS release: no terminal dependency

**Do NOT use `flutter run --debug` or terminate an attached debug session and assume its installed app is a standalone release.** The standard local UAT workflow is to compile an iOS **release** app on the Mac, install the already-built app on the physical device, then open it **from the iPhone home screen** with the terminal detached.

Use this only after a trusted public HTTPS staging origin is configured. The Oracle IP is `84.13.66.211`, but no verified public TLS origin exists at the last check. Do not substitute a broken hostname or `http://84.13.66.211:8787` (loopback-only backend, guest auth is HTTPS-only).

```sh
cd ~/Desktop/workspace/puzzle-duel-client/apps/mobile

# A real verified HTTPS origin must be supplied by the operator.
: "${PZD_STAGING_BASE_URL:?Verified public HTTPS staging origin required}"
case "$PZD_STAGING_BASE_URL" in https://*) ;; *) echo 'HTTPS staging origin required'; exit 1;; esac
curl -fsS --connect-timeout 5 --max-time 15 "${PZD_STAGING_BASE_URL%/}/healthz" || exit 1

flutter pub get --enforce-lockfile

# Compile and sign LOCALLY on the Mac (do not use --no-codesign).
PZD_STAGING_FIREBASE=1 flutter build ios --release \
  --dart-define=PZD_STAGING_BASE_URL="$PZD_STAGING_BASE_URL" \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true

# Install the prebuilt release app; do NOT use flutter run for persistent device UAT.
flutter install --release -d 00008160-001C5C993E80000A
```

After installing, launch **Puzzle Duel from the iPhone icon**, force-quit the app, disconnect the cable / close the Mac terminal, and relaunch from the icon. Check that the **TournamentUatApp** opens (or displays a specific staging auth/connectivity error), **never** a black Flutter debug explanation, old Easy/Medium/Hard page, or indefinite blank screen. Reinstall the release over a previous debug install; do not uninstall the app casually, because guest credentials and local state might be lost.

The 2026-11-22 iOS startup fix now renders a visible **Connecting to tournament…** frame before Firebase initialization and HTTPS guest authentication, and shows a specific failure screen if initialization throws. It does not make an unconfigured HTTPS endpoint work. A physical-device cold-launch/kill/relaunch regression test is still required before marking this issue fully closed.

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
