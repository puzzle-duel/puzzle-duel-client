#!/usr/bin/env bash
# PZD-27 — physical iPhone staging UAT (Google Sign-In).
# Guest bootstrap + real Google OAuth. No hardcoded bearer tokens.
# Requires: Oracle staging HTTPS healthy, migrations 0005–0007 applied,
# PZD_STAGING_GOOGLE_AUDIENCES set on the server, then service restarted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE_ID="${PZD_IOS_DEVICE_ID:-00008160-001C5C993E80000A}"
STAGING_ORIGIN="${PZD_STAGING_BASE_URL:-https://84-13-66-211.sslip.io}"
GOOGLE_SERVER_CLIENT_ID="${PZD_GOOGLE_SERVER_CLIENT_ID:-450107669068-a4l8vrgas78rqdm8aou7kvnhsldkafbi.apps.googleusercontent.com}"
GOOGLE_IOS_CLIENT_ID="${PZD_GOOGLE_IOS_CLIENT_ID:-450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse.apps.googleusercontent.com}"

case "$STAGING_ORIGIN" in
  https://*) ;;
  *) echo "HTTPS staging origin required: $STAGING_ORIGIN" >&2; exit 1 ;;
esac

echo "==> healthz $STAGING_ORIGIN"
curl -fsS --connect-timeout 5 --max-time 15 "${STAGING_ORIGIN%/}/healthz" >/dev/null

echo "==> provider challenge probe (expect 201 after migrations + audiences)"
# Status-only: discard body so nonce/binding never hit disk or stdout.
CHALLENGE_CODE="$(
  curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
    -X POST "${STAGING_ORIGIN%/}/v1/auth/providers/challenge" \
    -H 'Content-Type: application/json' \
    -d '{"provider":"google","purpose":"login"}' || true
)"
echo "challenge HTTP $CHALLENGE_CODE"
if [[ "$CHALLENGE_CODE" != "201" ]]; then
  echo "BLOCKED: Google provider routes not ready on staging (got HTTP $CHALLENGE_CODE)." >&2
  echo "Apply migrations 0005/0006/0007, set PZD_STAGING_GOOGLE_AUDIENCES, restart pzd-staging.service." >&2
  exit 2
fi

echo "==> flutter pub get"
flutter pub get --enforce-lockfile

echo "==> release build + install on $DEVICE_ID"
# Prefer release-mode physical-device UAT. Firebase Crashlytics staging remains opt-in.
# PZD_STAGING_FIREBASE=1 also injects the staging Google URL scheme into Info.plist.
#
# PZD_GUEST_RETRY_ENABLED is intentionally OMITTED (client default false).
# Oracle staging currently has PZD_STAGING_GUEST_RETRY_ENABLED unset/off.
# Do not pass --dart-define=PZD_GUEST_RETRY_ENABLED=true until that server
# flag is confirmed true — mismatched retry enables REFRESH_REPLAY risk.
PZD_STAGING_FIREBASE=1 flutter build ios --release \
  --dart-define=PZD_STAGING_BASE_URL="$STAGING_ORIGIN" \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true \
  --dart-define=PZD_GOOGLE_SERVER_CLIENT_ID="$GOOGLE_SERVER_CLIENT_ID" \
  --dart-define=PZD_GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID"

flutter install --release -d "$DEVICE_ID"

cat <<EOF

Installed release build on $DEVICE_ID.
1. Launch Puzzle Duel from the iPhone home screen (detach from flutter run).
2. Confirm guest Practice works without login.
3. Open official tournament → Google Sign-In → registered Google test account.
4. Confirm player_id preserved, tournament resumes once, kill/relaunch keeps session.
5. Cancelled Google Sign-In must not consume an attempt.
6. Settings → Log Gönder / Crash Test remain available for correlation.

Real signed Google nonce success is NOT claimed by this script — record device UAT evidence in PZD-27.
EOF
