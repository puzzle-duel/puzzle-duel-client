# PZD-27 — Apple / Google authentication (Flutter client)

Status: Security remediation in progress on `feature/PZD-27-apple-google-auth` (P1-01/02/03 after review #10625).  
Backend contract: merged PZD-26 @ `be7a510` — see backend `docs/staging/PZD-26-PROVIDER-AUTH-CONTRACT.md`.

## Product rules (binding)
- No login at launch; unlimited guest Practice.
- Apple **or** Google required before official ranked tournament claim.
- Guest link preserves immutable `player_id`; never email-merge.
- ACCOUNT_CONFLICT never silently switches accounts.
- Firebase Auth prohibited; Crashlytics remains.

## Architecture
- `GuestAuthClient` — guest create/refresh + verified credential replacement with **serialized** generation-aware vault commits; durable `pending_link` marker for uncertain link completion.
- `ProviderAuthClient` — `/v1/auth/providers/challenge|login|link` + logout.
- `AuthCoordinator` — challenge → native assertion → identity-preserving bearer refresh → link/login; explicit provider recovery (never silent guest mint).
- `PlatformProviderSignIn` — `sign_in_with_apple` / `google_sign_in` **7.x** (no Firebase Auth).
- `TournamentController` — ranked auth gate before claim; resume-once after success.
- `auth_sheet.dart` — Apple/Google sheet + conflict + recovery UX.

## Google nonce (P1-01)

| Layer | Capability |
|---|---|
| Backend PZD-26 | Requires cryptographically signed `nonce` claim in Google ID token |
| `google_sign_in` 6.x | **No** portable `nonce` parameter — **implementation blocker** for real Google |
| `google_sign_in` 7.x + `google_sign_in_ios` 6.4.0 + GoogleSignIn 10.1.0 | **Source-verified** end-to-end into AppAuth `nonce` query param (see `PZD-27-GOOGLE-NONCE-SOURCE-TRACE.md`) |
| Client adapter | First challenge: `initialize(nonce:)`; later challenges: `GoogleSignInPlatform.init` overwrites plugin `_nonce` before `authenticate` |
| Apple | `SignInWithApple.getAppleIDCredential(nonce:)` — SDK embeds SHA-256 digest (backend verifies) |
| Config blockers | Missing `PZD_GOOGLE_SERVER_CLIENT_ID` / iOS client ID / Apple capability → `PROVIDER_CONFIG_MISSING` / fail-closed — distinct from SDK capability |
| Physical-device signed claim | **NOT_RUN** until staging schema/audiences + owner UAT |

Do **not** weaken backend nonce verification. Do **not** introduce Firebase Auth.

## Credential mutation + refresh ownership
- Single `_mutationChain` serializes durable vault writes/clears.
- Generation bump on replace/logout; stale `_pending` auth futures never reused across generations.
- **All network refresh** (including post-native near-expiry refresh) goes through `authenticate` single-flight — never a parallel `_authenticate` under the mutation lock.
- `refreshGuestPreservingIdentity` joins that flight then asserts exact `player_id` + `fid`.
- Pending rotation cleared only by the winning commit; concurrency tests cover rotation retry on/off.

## Provider linking recovery (identity-preserving)
- Before link HTTP: durable marker `provider|<playerId>` (never tokens/nonces).
- Backend success + lost response / timeout / vault failure → `recoveryRequired`.
- Recovery UI calls **`recoverPendingLink`** → backend **`POST /v1/auth/providers/recover`** (create-forbidden). Never generic `login`.
- Guest-validity probe uses **`authenticate(forceRefresh: true, allowGuestCreate: false)`** (single-flight). Cached JWT expiry is not proof the backend family is still active; only a successful server refresh of the expected guest player yields `RECOVERY_RETRY_LINK`.
- Temporary probe network failures (`REFRESH_UNAVAILABLE` / `AUTH_NETWORK_UNAVAILABLE`) keep the durable marker and do not mint a guest or call recover.
- Server rejects unknown subject (`RECOVERY_NOT_LINKED`) / wrong linked player (`ACCOUNT_CONFLICT`) before creating player/link/family.
- Client also refuses vault commit if returned `playerId` ≠ marker (belt-and-suspenders).
- Generic `loginExisting` remains for intentional ACCOUNT_CONFLICT account switch only.
- Companion backend branch: `feature/PZD-26-provider-recovery` (PZD-26 contract extension).
- Restart: `consumePendingLinkRecoveryIfNeeded` surfaces recovery without minting a new guest.

## Native Google/Apple nonce honesty
- Source passes challenge nonce into `google_sign_in` 7.x / Apple SDK.
- Repeated platform init + **actual signed nonce claim on device** = **NOT_RUN** until owner UAT evidence. Do not claim real-provider success.

## Dart defines (owner-supplied; never commit secrets)
| Define | Purpose |
|---|---|
| `PZD_GOOGLE_SERVER_CLIENT_ID` | Google OAuth Web/server client ID (ID token audience) |
| `PZD_GOOGLE_IOS_CLIENT_ID` | Optional iOS client ID |

Staging vs production must use separate OAuth clients.

## Native configuration checklist

### iOS (`app.puzzleduel.puzzleDuelMobile`) — do not change bundle ID
- [ ] Sign in with Apple capability + entitlements *(Google-only staging UAT may proceed without Apple entitlement; Apple remains fail-closed)*
- [ ] Apple Services / App ID configured for backend audiences *(deferred until Apple enrollment)*
- [x] Google URL scheme injected **only for staging builds** via `ios/scripts/pzd_inject_staging_google_url_scheme.sh` when `PZD_STAGING_FIREBASE=1` / `PZD_STAGING_GOOGLE_OAUTH=1` — scheme: `com.googleusercontent.apps.450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse` (not present in production Info.plist source)
- [ ] Deployment target compatible with `sign_in_with_apple` 6.x
- [ ] Provisioning profile includes Sign in with Apple *(not required for Google-only staging UAT)*

### Android (`app.puzzleduel.puzzle_duel_mobile`) — do not change application ID
- [ ] SHA-1 / SHA-256 for debug and release registered in Google Cloud
- [ ] Server/Web client ID matches `PZD_GOOGLE_SERVER_CLIENT_ID`
- [ ] Apple on Android: **not** equivalent to iOS; Services ID + browser callback required — currently fail-closed until owner configures and accepts UAT
- Android Debug Client ID (record only; out of this task): `450107669068-m6upi7tq3rsstadcik4n4c7qfolb6lk6.apps.googleusercontent.com`

## Staging Google OAuth (owner-provided; not secrets)

| Role | Value |
|---|---|
| Web / Server Client ID (`PZD_GOOGLE_SERVER_CLIENT_ID` + backend `aud`) | `450107669068-a4l8vrgas78rqdm8aou7kvnhsldkafbi.apps.googleusercontent.com` |
| iOS Client ID (`PZD_GOOGLE_IOS_CLIENT_ID` + backend `azp`) | `450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse.apps.googleusercontent.com` |
| iOS reversed Client ID / URL scheme | `com.googleusercontent.apps.450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse` |

Backend `PZD_STAGING_GOOGLE_AUDIENCES` must include **both** Web and iOS client IDs (token `aud` + `azp` verification). Do not add Android until Android UAT is in scope. No Google client secret. No Firebase Auth.

## Physical iPhone staging UAT command

Verified HTTPS origin: `https://84-13-66-211.sslip.io`. Device: `00008160-001C5C993E80000A`.

```sh
cd ~/Desktop/workspace/puzzle-duel-client/apps/mobile
# Prefer the helper (fails closed if provider challenge ≠ 201):
bash scripts/ios_staging_google_uat.sh
```

Equivalent one-shot (after staging migrations 0005–0007 + Google audiences + service restart):

```sh
cd ~/Desktop/workspace/puzzle-duel-client/apps/mobile
curl -fsS --connect-timeout 5 --max-time 15 https://84-13-66-211.sslip.io/healthz >/dev/null
PZD_STAGING_FIREBASE=1 flutter build ios --release \
  --dart-define=PZD_STAGING_BASE_URL=https://84-13-66-211.sslip.io \
  --dart-define=PZD_FIREBASE_CONFIGURED=true \
  --dart-define=PZD_DIAGNOSTIC_ENV=staging \
  --dart-define=PZD_STAGING_DIAGNOSTICS=true \
  --dart-define=PZD_GOOGLE_SERVER_CLIENT_ID=450107669068-a4l8vrgas78rqdm8aou7kvnhsldkafbi.apps.googleusercontent.com \
  --dart-define=PZD_GOOGLE_IOS_CLIENT_ID=450107669068-b0l835r1cv1mfga7h3ovdd1hjte0tfse.apps.googleusercontent.com
flutter install --release -d 00008160-001C5C993E80000A
```

Launch from the iPhone home screen. Real signed Google nonce UAT is **NOT_RUN** until device evidence is recorded.

## Contract notes (from merged PZD-26 source)
- Link challenge response has **no** `binding` field (server binds `link:{playerId}:{fid}`).
- Login challenge returns `{ provider, purpose, nonce, binding }`.
- Success bundle camelCase: `playerId`, `accountType`, `accessToken`, `refreshToken`, `expiresAt`, `linkedProviders`.
- JWT claim is `account_type` (snake_case); body field is `accountType`.
- **`PROVIDER_CONFIG_MISSING` is not a JSON `error` body** — HTTP **503** `{ "error": "AUTH_UNAVAILABLE" }` with diagnostic reason only. Client UI maps both codes to the same copy.
- Logout: `POST /v1/auth/logout` → **200** `{ "status": "revoked" }` (family revoke, not account deletion).
- Account deletion / Apple token revocation endpoints **do not exist** — production release blocker; do not invent client success.

## Known blockers / honesty gates
| Item | Status |
|---|---|
| Mock unit/widget coverage | Implemented / run in CI |
| Real Apple device UAT (nonce claim) | **BLOCKED** / **NOT_RUN** — needs Apple capability + audiences; SDK path implemented |
| Real Google device UAT (nonce claim) | **BLOCKED** / **NOT_RUN** — client OAuth IDs + URL scheme prepared; waiting backend migrations 0005–0007 + `PZD_STAGING_GOOGLE_AUDIENCES` + owner device evidence |
| Android Apple Sign-In | **BLOCKED** until Services ID callback proven |
| Account deletion + Apple token revocation APIs | **Production release blocker** — backend documents requirement; no client fake success |
| Backend staging deploy code (PR #74) | **Deployed** @ `b340f7d` (2026-11-25 CD) — provider routes still unmounted until schema + audiences |
| Backend staging migrations 0005–0007 | **NOT applied** (owner approval required) |
| Backend `PZD_STAGING_GOOGLE_AUDIENCES` | **MISSING** on Oracle `staging.env` (owner action) |

## Observability
Breadcrumb operations (reuse existing `LogCode`; never log tokens/nonces/subjects/emails):
`auth_sheet_opened`, `auth_provider_selected_*`, `provider_challenge_*`, `provider_sign_in_*`, `provider_link_*`, `provider_login_*`, `auth_account_conflict`, `auth_credential_replaced`, `auth_pending_link_*`, `tournament_auth_gate`, `tournament_auth_resume`, `auth_logout`.

Diagnostic allowlist extended in `UatApi.diagnosticErrorCode` for provider error codes.

## UAT instructions (when unblocked)
1. Launch as guest; confirm Practice works without auth sheet.
2. Tap Play today's tournament → auth sheet.
3. Link with Apple (iOS) or Google → verified; player_id unchanged.
4. Confirm claim occurs only after success; cancel/offline does not consume attempt.
5. Force ACCOUNT_CONFLICT with a second provider account; guest progress preserved; explicit login only after confirmation.
6. Kill app mid-link; confirm recovery sheet (no new guest); explicit provider login restores progress.
