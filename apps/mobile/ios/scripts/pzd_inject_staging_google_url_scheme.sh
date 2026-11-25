#!/bin/sh
# Injects the Puzzle Duel *staging* Google OAuth reversed client ID into the
# built app Info.plist only when staging Firebase/Google opt-in is enabled.
# Production builds must not inherit staging OAuth URL schemes.
# Do not invent production OAuth identifiers here.
set -eu

PLIST="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
test -f "$PLIST"

STAGING_SCHEME='com.googleusercontent.apps.450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse'
URL_NAME='app.puzzleduel.puzzleDuelMobile.google-staging'

# Strip any previously injected staging Google URL type (idempotent rebuilds).
if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$PLIST" >/dev/null 2>&1; then
  i=0
  while /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$i" "$PLIST" >/dev/null 2>&1; do
    name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$i:CFBundleURLName" "$PLIST" 2>/dev/null || true)"
    scheme0="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$i:CFBundleURLSchemes:0" "$PLIST" 2>/dev/null || true)"
    if [ "$name" = "$URL_NAME" ] || [ "$scheme0" = "$STAGING_SCHEME" ]; then
      /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes:$i" "$PLIST"
      # Indices shift after delete; restart scan.
      i=0
      continue
    fi
    i=$((i + 1))
  done
  # Drop empty CFBundleURLTypes array left after removals.
  if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0' "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$PLIST" 2>/dev/null || true
  fi
fi

if [ "${PZD_STAGING_FIREBASE:-0}" != "1" ] && [ "${PZD_STAGING_GOOGLE_OAUTH:-0}" != "1" ]; then
  echo "note: skipping staging Google URL scheme (production / non-staging build)"
  exit 0
fi

if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$PLIST"
fi

# Append without clobbering unrelated URL schemes.
idx=0
while /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$idx" "$PLIST" >/dev/null 2>&1; do
  idx=$((idx + 1))
done

/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleTypeRole string Editor" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleURLName string $URL_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$idx:CFBundleURLSchemes:0 string $STAGING_SCHEME" "$PLIST"
echo "note: injected staging Google URL scheme into Info.plist"
