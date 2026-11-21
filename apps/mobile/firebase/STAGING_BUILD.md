# PZD-52 — Native Firebase staging build

Firebase project: `puzzle-duel-staging`. Native configuration is **opt-in**; production builds must not include staging Firebase resources.

## Android staging (release APK)

From `apps/mobile`:

```sh
flutter pub get
ORG_GRADLE_PROJECT_pzdStagingFirebase=true flutter build apk --release \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true
```

The Android Google Services Gradle plugin is applied only when the Gradle property `pzdStagingFirebase=true`. The `android/app/google-services.json` file is inert otherwise. Verify that the resulting APK includes the Firebase app ID resources and that production builds do not.

## iOS staging (signed IPA)

From `apps/mobile` on a macOS runner with valid Apple distribution signing:

```sh
flutter pub get
PZD_STAGING_FIREBASE=1 flutter build ipa --release \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true
```

The Runner Xcode build phase copies the staging `GoogleService-Info.plist` into the app bundle only when `PZD_STAGING_FIREBASE=1`. Verify the IPA contains this plist for staging and does **not** contain it for production. Confirm that the environment variable is passed through to Xcode on the chosen CI runner.

## Release gates

1. CI `flutter analyze` and `flutter test` green.
2. Android release APK and iOS signed IPA build on their respective runners.
3. Inspect staging and production native resources (fail closed if staging config is present in production).
4. Distribute staging build via Firebase App Distribution using a CI credential with appropriate permission (do not commit secrets).
5. On installed staging build, open Profile > Developer Diagnostics. Send nonfatal, then force test crash and reopen app. Confirm Crashlytics ingestion, custom breadcrumbs, and symbolication.
6. Production builds must omit `PZD_STAGING_DIAGNOSTICS` and `PZD_FIREBASE_CONFIGURED`, and must not set native staging flags.

**NOT YET VERIFIED:** Native build, signing, App Distribution upload, Crashlytics ingestion. Do not mark PZD-52 Done before these gates.
