# PZD-52 — Native Firebase staging build

Firebase project: `puzzle-duel-staging`. Native configuration is opt-in; production builds must not include staging Firebase resources.

## Android staging (release APK)

From `apps/mobile`:

```sh
flutter pub get --enforce-lockfile
ORG_GRADLE_PROJECT_pzdStagingFirebase=true flutter build apk --release \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true
```

The Android Google Services Gradle plugin is applied only when the Gradle property `pzdStagingFirebase=true`. The `android/app/google-services.json` file is inert otherwise.

## iOS staging (unsigned CI build)

From `apps/mobile` on macOS:

```sh
flutter pub get --enforce-lockfile
PZD_STAGING_FIREBASE=1 flutter build ios --release --no-codesign \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true
```

The Runner Xcode build phase copies the staging `GoogleService-Info.plist` into the app bundle only when `PZD_STAGING_FIREBASE=1`; otherwise it removes any stale copy. The Firebase iOS bundle ID must match the Runner target's `PRODUCT_BUNDLE_IDENTIFIER`.

## Release gates

1. Flutter 3.50.0 `pub get --enforce-lockfile`, `analyze`, and `test` pass.
2. Android staging and production release APKs build; staging resources are present only in staging.
3. iOS staging and production builds succeed; staging plist is present only in staging.
4. Staging App Distribution, device UAT, Crashlytics ingestion, and symbolication are verified separately.

**NOT YET VERIFIED:** Physical-device ingestion, symbolication, and Firebase App Distribution. Do not mark PZD-52 Done before these gates.
