# PZD-27 — Apple / Google authentication (Flutter client)

Status: Implemented on `feature/PZD-27-apple-google-auth` (mock-tested).  
Backend contract: merged PZD-26 @ `be7a510` — see backend `docs/staging/PZD-26-PROVIDER-AUTH-CONTRACT.md`.

## Product rules (binding)
- No login at launch; unlimited guest Practice.
- Apple **or** Google required before official ranked tournament claim.
- Guest link preserves immutable `player_id`; never email-merge.
- ACCOUNT_CONFLICT never silently switches accounts.
- Firebase Auth prohibited; Crashlytics remains.

## Architecture
- `GuestAuthClient` — guest create/refresh + verified credential replacement with generation guard.
- `ProviderAuthClient` — `/v1/auth/providers/challenge|login|link` + logout.
- `AuthCoordinator` — challenge → native assertion → link/login.
- `PlatformProviderSignIn` — `sign_in_with_apple` / `google_sign_in` (no Firebase Auth).
- `TournamentController` — ranked auth gate before claim; resume-once after success.
- `auth_sheet.dart` — Apple/Google sheet + conflict UX.

## Dart defines (owner-supplied; never commit secrets)
| Define | Purpose |
|---|---|
| `PZD_GOOGLE_SERVER_CLIENT_ID` | Google OAuth Web/server client ID (ID token audience) |
| `PZD_GOOGLE_IOS_CLIENT_ID` | Optional iOS client ID |

Staging vs production must use separate OAuth clients.

## Native configuration checklist

### iOS (`app.puzzleduel.puzzleDuelMobile`) — do not change bundle ID
- [ ] Sign in with Apple capability + entitlements
- [ ] Apple Services / App ID configured for backend audiences
- [ ] Google URL scheme / reversed client ID in `Info.plist`
- [ ] Deployment target compatible with `sign_in_with_apple` 6.x
- [ ] Provisioning profile includes Sign in with Apple

### Android (`app.puzzleduel.puzzle_duel_mobile`) — do not change application ID
- [ ] SHA-1 / SHA-256 for debug and release registered in Google Cloud
- [ ] Server/Web client ID matches `PZD_GOOGLE_SERVER_CLIENT_ID`
- [ ] Apple on Android: **not** equivalent to iOS; Services ID + browser callback required — currently fail-closed until owner configures and accepts UAT

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
| Real Apple device UAT | **BLOCKED** / **NOT_RUN** — needs Apple capability + audiences |
| Real Google device UAT | **BLOCKED** / **NOT_RUN** — needs OAuth client IDs; Flutter `google_sign_in` 6.x lacks portable nonce binding (backend requires nonce claim) |
| Android Apple Sign-In | **BLOCKED** until Services ID callback proven |
| Account deletion + Apple token revocation APIs | **Production release blocker** — backend documents requirement; no client fake success |
| Backend staging deploy / migrations 0005–0007 | **NOT_RUN** without owner approval |

## Observability
Breadcrumb operations (reuse existing `LogCode`; never log tokens/nonces/subjects/emails):
`auth_sheet_opened`, `auth_provider_selected_*`, `provider_challenge_*`, `provider_sign_in_*`, `provider_link_*`, `provider_login_*`, `auth_account_conflict`, `auth_credential_replaced`, `tournament_auth_gate`, `tournament_auth_resume`, `auth_logout`.

Diagnostic allowlist extended in `UatApi.diagnosticErrorCode` for provider error codes.

## UAT instructions (when unblocked)
1. Launch as guest; confirm Practice works without auth sheet.
2. Tap Play today's tournament → auth sheet.
3. Link with Apple (iOS) or Google → verified; player_id unchanged.
4. Confirm claim occurs only after success; cancel/offline does not consume attempt.
5. Force ACCOUNT_CONFLICT with a second provider account; guest progress preserved; explicit login only after confirmation.
6. Kill app mid-link; confirm recoverable guest or verified state; no orphaned claim.
