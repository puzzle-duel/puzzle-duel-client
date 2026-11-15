# PZD-16 proposed protection for main

Status of this proposal: not applied. This file does not change GitHub settings.

## What was observed

An unauthenticated `GET /repos/puzzle-duel/{repository}/branches/main/protection` during this task returned **401** for both repositories. The task record of an authenticated read is **403**. Neither response is a protection document.

The protection state is **NOT VERIFIED**. This document does not say that protection is enabled and does not say that it is disabled.

## Recommended policy, for the owner to apply later

Apply the same rules to `puzzle-duel-client` and `puzzle-duel-backend`.

- Nobody pushes commits straight to `main`.
- Changes enter through a pull request.
- The required status check is `PR quality gate / quality-gate`, after the first green run shows that exact name. Do not require `PZD-11 fixtures` while that workflow stays path-filtered. A missing path-filtered run stays pending.
- Force pushes and deletion of `main` stay off.
- One approving review is expected from the owner or a person the owner names. `CODEOWNERS` is not added until that list exists.
- Administrators do not bypass the pull request or the required check unless the owner writes the bypass reason on the pull request or the incident record.
- The bypass is a one-time recovery, not a lasting exception.

## Recovery

If `main` cannot take a fix because the required check is broken:

1. The owner records the incident and the reason a bypass is needed.
2. An administrator merges the repair pull request with the recorded bypass, or temporarily turns the broken check off, merges, and turns it back on in the same change window.
3. The following pull request restores the check if it was turned off.
4. The incident note says who acted and when.

Rollback of a bad merge is a revert pull request through the same gate. It is not a force push. If the branch itself is damaged and a force push is the only repair, the owner authorizes that force push in writing, once, and the protection is turned back on afterward.

## What this task did not do

No branch protection, ruleset, team permission, or secret was written. No deploy ran.
