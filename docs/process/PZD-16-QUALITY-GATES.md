# PZD-16 pull request quality gates

This document adds CI and review rules. It does not change Blueprint rules, ADR status, or gameplay fixtures.

Jira: [PZD-16](https://puzzle-duel-app.atlassian.net/browse/PZD-16).

## What runs on every pull request

`.github/workflows/pr-quality-gate.yml` runs on every pull request into `main`, including edits to the pull request body. It has no path filter, so the check does not stay pending when the diff is outside one directory. The job name is `quality-gate`. The workflow requests `contents: read`, uses no secrets, and does not use `pull_request_target`.

`actions/checkout` is pinned to `11d5960a326750d5838078e36cf38b85af677262`, the `v4.4.0` commit. The existing fixture workflow still uses the floating `v4` tag. This change does not rewrite that workflow.

The gate is `tools/pr_quality_gate.py`. It uses the Python standard library.

- Markdown links to files in this repository must resolve. `http`, `https`, and `mailto` links are left alone. Fenced examples are not treated as links.
- The first `Status:` line in each `docs/adr/ADR-*.md` file must start with Proposed, Accepted, Rejected, Superseded, or Deprecated. Proposed records stay legal. Accepted records stay legal.
- A diff from the pull request base must not change `docs/contracts/gameplay/v1/fixtures/01` through `12`. Fixture `13` and `docs/contracts/gameplay/v2/` are not in that immutable set. They remain covered by the fixture workflow and its checksums when those paths change.
- Text files are scanned for private-key headers, `AKIA` access-key IDs, GitHub tokens, Slack tokens, and live Stripe secret keys. A line that says the value is an example, dummy, redacted, or placeholder is kept. The word "password" in a sentence is not a secret.

Pull request metadata is checked only when GitHub provides the event payload. A local run without that payload prints `NOT_RUN` for metadata and still checks the tree. The title needs a `PZD-<number>`, unless the body contains `Policy exception:` followed by `automation`, `dependency update`, or `hotfix`. The body needs the headings in `.github/PULL_REQUEST_TEMPLATE.md`. The Tests section needs a fenced command. "all tests passed" without that fence fails.

Commit messages are not validated in CI. Already merged history is not rechecked. New work should still name the issue in the branch, the title, and the commits. That convention is not a retroactive gate.

## Gameplay checks that stay where they are

`.github/workflows/pzd11-fixtures.yml` is unchanged. It still runs, when its paths change:

```bash
python3 docs/contracts/gameplay/v1/reference_check.py
node docs/contracts/gameplay/v1/validate.mjs
python3 docs/contracts/gameplay/v2/reference_check.py
node docs/contracts/gameplay/v2/validate.mjs
```

and the SHA-256 checksum files beside those suites. A pass of those checkers is a contract check. It is not a Dart or TypeScript production-engine result. Those engines do not exist.

Because the fixture workflow is path-filtered, it must not be a required status until it runs on every pull request. A required path-filtered check stays pending on other diffs.

## Commands

```bash
python3 tools/pr_quality_gate_test.py
python3 tools/pr_quality_gate.py
```

## Pre-scaffold checks, still NOT_RUN

[PZD-14 evidence](../architecture/PZD-14-EVIDENCE.md) records the accepted stacks and the checks that have not run. This workflow does not run them and does not add a job that would stay pending.

When an owner authorizes scaffolding, add a separate workflow that runs on that pull request and returns success or failure, not a skip:

Client, on Flutter 3.50.0 and Dart 3.14.0:

- `flutter --version` shows those versions.
- `flutter pub get` resolves Flame 1.38.2.
- `flutter analyze` covers a file that names `GameWidget` and `ColorEffect`.
- First-party code does not need to pass a `package:material_ui` value into a legacy Material public type.

Backend, on Node.js 26:

- `node --version` shows a 26 release.
- NestJS 12 installation exits 0 and the lockfile records Nest, TypeScript, and RxJS.
- TypeScript compilation exits 0.
- The process starts and shuts down.

Do not mark those jobs required before they exist. Do not use a macOS runner until a mobile project exists. Ubuntu runs this gate.

No production gameplay code is added here.
