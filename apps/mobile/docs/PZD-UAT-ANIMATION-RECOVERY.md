# Physical iPhone UAT — Animation parity + same-device writer recovery

Status: **BLOCKED until both Draft PRs pass CI and UAT server is intentionally configured.**
Do not merge/deploy to production or mark PZD-40 Done.

## Required paired branches

- Client: `feature/pzd-same-device-recovery-client` (stacked on
  `fix/pzd-tournament-animation-parity`).
- Backend: `feature/pzd-same-device-writer-recovery`.
- Both branches should be checked out at reviewed pinned SHAs.
- Existing daily claims that predate device key registration CANNOT recover.

## Isolated UAT backend settings

Only in a nonproduction UAT process with a disposable PostgreSQL database:

```sh
export NODE_ENV=development
export PZD_RUNTIME_PROFILE=development
export PZD_RANKED_HTTP_ENABLED=true
export PZD_SAME_DEVICE_RECOVERY_ENABLED=true
export PZD_UAT_SESSION_TTL_MS=45000
```

Use the normal UAT secrets/provenance and PostgreSQL connection configuration,
not hard-coded credentials. Shortened auth TTL never changes the 300-second
game idle deadline or the hard cutoff. Do not copy these settings to production.

## Sequence

1. Use a Player A identity that has NOT claimed the current UTC date.
2. On the physical iPhone, log in A with a valid JWT. Confirm the session
   opens, the device key registers, and the original claim is created.
3. Complete one legal scoring move; record score, board revision and
   writerGeneration from the server.
4. Log in as Player B on the same phone with an independently valid JWT.
   Confirm B has an isolated session, key and daily claim.
5. After more than 45 seconds have elapsed since A's initial session opened
   but **before** A's 300-second idle cutoff, log in A with a fresh JWT.
6. A should open a new verified session and receive the existing immutable
   daily claim. The recovery challenge must require the original registered
   device key and increment generation exactly once.
7. Confirm A's next legal command receives 200 and server-authoritative
   score/revision. Verify old writer generation is rejected with 409.
8. Repeat with the same JWT on an unrelated device: recovery must be rejected.
9. Expired idle deadline / completed or forfeited series: recovery must be
   rejected, and claims/scores must not change.
10. Check Practice/Tournament cascade, +score feedback, 420ms navigation
    gating, final challenge Results, Reduce Motion, background/foreground
    and no double navigation.

## Verification boundaries

- Flutter Linux CI does NOT compile iOS Swift. Build the iPhone target with
  Xcode and verify Secure Enclave signing/key persistence before physical UAT.
- Server must remain the sole authority for writer ownership and score.
- A failed recovery does not retry a rejected command or restart a daily claim.
- Always capture accepted/rejected outcomes and exact timestamps without
  sharing JWTs, session secrets, private keys or device signatures in logs.
- Older series (including the previously reported locked series) have no
  pre-registered device anchor and are intentionally not recoverable by this
  protocol.
