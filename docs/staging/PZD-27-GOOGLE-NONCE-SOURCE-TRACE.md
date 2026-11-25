# PZD-27 — Google iOS nonce source trace

**Status:** Source-verified against installed Pub cache + CocoaPods.  
**Physical-device signed ID-token nonce claim:** NOT_RUN (requires staging migrations + audiences + owner UAT).

Pinned versions on `feature/PZD-27-google-ios-staging`:

| Package | Version |
|---|---|
| `google_sign_in` | 7.2.0 |
| `google_sign_in_ios` | 6.4.0 |
| `google_sign_in_platform_interface` | 3.1.0 |
| CocoaPods `GoogleSignIn` | 10.1.0 |
| CocoaPods `AppAuth` | 3.0.0 |

## Call chain (first challenge)

1. **App adapter** — `apps/mobile/lib/tournament/platform_provider_sign_in.dart`  
   - `_google` → `_prepareGoogleWithNonce(nonce)` (lines ~97–98, 133–151)  
   - First call: `GoogleSignIn.instance.initialize(..., nonce: nonce)`  
   - Later calls: `GoogleSignInPlatform.instance.init(InitParameters(..., nonce: nonce))`

2. **App-facing package** — `~/.pub-cache/.../google_sign_in-7.2.0/lib/google_sign_in.dart`  
   - `initialize` docs: nonce “passed as part of any authentication requests” (lines ~309–326)  
   - Forwards into `GoogleSignInPlatform.instance.init(InitParameters(nonce: …))`

3. **Platform interface** — `google_sign_in_platform_interface-3.1.0/lib/src/types.dart`  
   - `InitParameters.nonce` (lines ~114–115)

4. **iOS Dart plugin** — `google_sign_in_ios-6.4.0/lib/google_sign_in_ios.dart`  
   - `init` stores `_nonce = params.nonce` (lines ~45–46)  
   - `authenticate` → `_signIn(scopeHint, _nonce)` (line ~84)  
   - `_signIn` → `_api.signIn(scopeHint, nonce)` (lines ~233–234)  
   - Plugin test `passes nonce if provided` (test/google_sign_in_ios_test.dart ~127–146)

5. **Pigeon bridge** — `google_sign_in_ios-6.4.0/lib/src/messages.g.dart` + `darwin/.../messages.g.swift`  
   - `signIn(List<String> scopeHint, String? nonce)` forwards nonce as second argument (~470–480 Dart; ~583–584 Swift)

6. **Native Flutter plugin** — `darwin/.../GoogleSignInPlugin.swift`  
   - `signIn(scopeHint:nonce:completion:)` → `performSignIn(..., nonce:)` (~209–221, 288–304)  
   - Calls `signIn.signIn(withPresenting:hint:additionalScopes:nonce:completion:)`

7. **Wrapper** — `GoogleSignInWrappers.swift`  
   - `GIDSignInWrapper.signIn(..., nonce:)` → `gidSignIn.signIn(..., nonce: nonce)` (~57–75)

8. **Google Sign-In iOS SDK 10.1.0** — `Pods/GoogleSignIn/.../GIDSignIn.m`  
   - Public API documents “custom nonce” (`GIDSignIn.h` ~224–242)  
   - Builds `GIDSignInInternalOptions` with `nonce:` (~347–362)  
   - `authorizationRequestWithOptions:` creates `OIDAuthorizationRequest` **with** `nonce:options.nonce` when set (~928–935)

9. **AppAuth 3.0.0** — `Pods/AppAuth/.../OIDAuthorizationRequest.m`  
   - Stores `_nonce` (~151)  
   - Adds `nonce` query parameter to the authorization URL (~353–354)  
   - `OIDAuthorizationService` validates ID token nonce equals request nonce (~672–678)

## Subsequent challenges (different server nonces)

`GoogleSignIn.initialize` must only run once (undefined if called again). The adapter therefore:

1. First challenge → `initialize(nonce: challenge1)`  
2. Later challenges → `GoogleSignInPlatform.instance.init(InitParameters(nonce: challengeN))` which overwrites `GoogleSignInIOS._nonce`  
3. Next `authenticate` uses the updated `_nonce` on the native `signIn` call

**Source-verified:** subsequent nonces are forwarded into the same native path.  
**Physical-device-verified:** NOT_RUN — must observe a signed Google ID token `nonce` claim matching the server challenge on a real iPhone.

## Verdict

| Layer | Nonce forwarded? |
|---|---|
| Flutter adapter | Yes (source) |
| google_sign_in 7.x / platform_interface | Yes (source) |
| google_sign_in_ios 6.4.0 | Yes (source + plugin unit test) |
| Pigeon / Swift plugin | Yes (source) |
| GoogleSignIn 10.1.0 → AppAuth request | Yes (source) |
| Google-issued signed ID token claim | **NOT_RUN** on device |

No Pub-cache patch required. Backend nonce verification must remain fail-closed.
