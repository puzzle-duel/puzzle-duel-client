# PZD-14 evidence log

Status: review evidence. This file does not accept an ADR, the Blueprint, or a host design.

Review date: 2026-11-15. Jira: [PZD-14](https://puzzle-duel-app.atlassian.net/browse/PZD-14).

The same bytes of this file and of [PZD-14-GAMEPLAY-PARITY.md](PZD-14-GAMEPLAY-PARITY.md) are required in both repositories.

## What was read

- [BLUEPRINT.md](../../BLUEPRINT.md) on `main`. The commit `12263dc` (backend) / `e78f728` (client), message `[PZD-10] Accept final Blueprint v1.0 reconciliation`, says the owner accepted Blueprint v1.0 with documented deferred boundaries. The status line inside `BLUEPRINT.md` still says formal Blueprint acceptance is pending. PZD-14 does not change that file.
- [AGENTS.md](../../AGENTS.md), [README.md](../../README.md), feature specs, quality gates, and the ADRs present on `main`.
- [PZD-11-CONTRACT.md](../contracts/gameplay/PZD-11-CONTRACT.md), [PZD-10-RECONCILIATION.md](../contracts/gameplay/PZD-10-RECONCILIATION.md), and the `v1` and `v2` fixture suites.
- Jira PZD-10, PZD-11, PZD-12, and PZD-14. PZD-12 remains To Do. No production host was contacted.

## Version evidence

| Item | Recorded value | Source | How checked |
| --- | --- | --- | --- |
| Flutter stable | 3.50.0, published 2026-11-11, bundles Dart 3.14.0 | [Flutter 3.50 blog](https://flutter.dev/blog/whats-new-in-flutter-3-50), [3.50.0 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.50.0) | Page read. Not installed here. |
| Flutter supported mobile targets, as of 3.50 | Android API 24–37. iOS 15–27. API 23 and iOS 14 are unsupported. | [Supported platforms](https://docs.flutter.dev/reference/supported-platforms) | Page read. |
| Flame stable | 1.38.2, published 2026-08-27. SDK `>=3.11.0 <4.0.0`. Flutter `>=3.41.0`. Depends on `flutter`. | [pub.dev API](https://pub.dev/api/packages/flame) | `curl` of the API JSON. |
| Flame prerelease | 2.0.0-dev.1 is prerelease. Not a candidate. | pub.dev package page | Page read. |
| Local Flutter | 3.47.8 stable, revision 737ba8f885, 2026-10-22. Dart 3.13.7. | `flutter --version` and `dart --version` on this machine | Command ran. |
| Node.js Active LTS | 26.x Lithium. 26.13.1 dated 2026-11-10. Active LTS began 2026-10-28. | [Release schedule](https://github.com/nodejs/release), [26.13.1 release](https://nodejs.org/en/blog/release/v26.13.1) | Pages read. `nodejs.org/dist/index.json` first `v26` LTS row was `v26.13.1`. |
| Node.js also still in LTS | 24 Maintenance, 22 Maintenance. | Node.js release schedule | Page read. |
| Local Node | v20.20.2 | `node --version` | Command ran. |
| NestJS | 12.5.0, released 2026-11-12. npm `engines.node` is `>=20`. Docs: run on Node 20.19+, or 22.12+ on the 22 line. CLI generators need 22.22.3+, 24.15+, or 26+. | [npm registry](https://registry.npmjs.org/@nestjs/core/latest), [version FAQ](https://docs.nestjs.com/faq/versions), [migration guide](https://docs.nestjs.com/migration-guide), [GitHub release v12.5.0](https://github.com/nestjs/nest/releases) | Registry JSON and docs read. CLI was not run. |
| TypeScript | Nest 12 migration says `nest upgrade` moves TypeScript to v6. | [Nest 12 migration guide](https://docs.nestjs.com/migration-guide) | Page read. No project was generated, so no resolved patch is claimed. |
| PostgreSQL supported majors on the versioning page | 18.7, 17.12, 16.16, 15.20, and 14.25 marked Yes. 18 final support date listed as 2030-11-14. 14 final release listed as 2026-11-12. 19 was announced as RC 2, not a supported final major. | [Versioning policy](https://www.postgresql.org/support/versioning/) | Page fetched 2026-11-15. |

PostgreSQL 14 is not a recommendation. Its own final-release date is 2026-11-12, before this review. PostgreSQL 18 is the newest stable major the page marks supported.

## Commands that ran

```bash
flutter --version
dart --version
node --version
curl -fsSL https://pub.dev/api/packages/flame
curl -fsSL https://nodejs.org/dist/index.json
curl -fsSL https://registry.npmjs.org/@nestjs/core/latest
curl -fsSL https://www.postgresql.org/support/versioning/
```

Disposable resolution, outside either repository, then deleted:

```bash
mkdir -p /tmp/pzd14-flame-spike
# pubspec.yaml named pzd14_flame_spike, publish_to none, flame: 1.38.2
flutter pub get
rm -rf /tmp/pzd14-flame-spike
```

Result: `flutter pub get` on the installed Flutter 3.47.8 resolved `flame 1.38.2` from pub.dev. Lock checksum `sha256:b4d7e59b81f35a426f8b39dcec10175180b9c2984b2b2e619021660d8951307c`. The directory was removed. No Flutter or Nest project was added to either repository.

## NOT_RUN

- Upgrade to Flutter 3.50.0 / Dart 3.14.0, and any Flame run on that SDK. Flame's published floor is Flutter 3.41.0, so 3.50 is above the declared floor. That is a constraint reading, not an execution result.
- Frame time, memory, battery, cold start, and CI minute measurements. No numbers of that kind are claimed.
- `nest new`, Nest CLI, and a TypeScript compile. Local Node v20.20.2 can run a Nest 12 application under the documented runtime floor, and it is below the documented CLI generator floor.
- iOS and Android device or simulator launches.
- Database creation, migrations, host inventory, and deployment.

## Decision summary

| Question | Recommendation | Status |
| --- | --- | --- |
| iOS/Android client | Flutter presentation, Flame rendering, pure Dart rules engine | Proposed in client ADR-001 |
| Flutter without Flame | Rejected as the primary client. Usable later if Flame's Flutter coupling becomes a defect. | Recorded, not accepted |
| Native Swift and Kotlin clients | Comparison only. Rejected for MVP because it duplicates the rules. | Recorded, not accepted |
| Backend application stack | NestJS 12, TypeScript, Node.js 26 Active LTS, PostgreSQL 18 | Proposed in backend ADR-005 |
| Smaller TypeScript HTTP framework alone | Rejected as the primary backend. Nest's module and test boundaries are the reason. | Recorded, not accepted |
| Where the service runs, and SportsDash isolation | No decision. Depends on PZD-12. | Proposed host notes stay in backend ADR-001 |
