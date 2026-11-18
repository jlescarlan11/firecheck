# Changelog

## 0.1.10 — submission release

- Download and select multiple maps; review and upload your own changes progressively while preserving accepted revision history.
- Add missing buildings and roads through **New Feature**, with sketch validation, Undo and discard confirmation.
- Compare duplicate geometry offline; distinguish the dashed orange assignment boundary from blue edit geometry.
- Align survey requirement labels, completion counts and review validation with the downloaded form configuration.
- Improve download/transfer progress and protect upload jobs against account changes, stale revisions and concurrent drains.
- Migrate the local database to schema v20 while preserving upload history and file/receipt bindings.
- Harden gateway publication checks and add a forward photo-storage authorization migration for separate backend operator rollout.

The mobile version is `0.1.10+4015` (expected ARM64 Android code `6015`). The reviewed source has 1128 passing Flutter tests and 70 passing gateway tests; analyzer findings remain at the existing baseline. A prior same-source development build (`0.1.9` / code `6014`) passed the ARM64 size gate and an approved in-place UI walkthrough. Submission binary verification is a separate release step.

Known limits: direct-Drive retries restart failed transfers, and process identity loss can require a full app-process restart. Full new-survey/real-upload acceptance, extended device and hosted capacity checks, and backend rollout remain unverified. See [release notes](docs/releases/0.1.10.md) and [development evidence](docs/verification/2026-11-18-cleanup/README.md).

## Earlier releases

Earlier public releases through `v0.1.3` are recorded in the [GitHub release history](https://github.com/jlescarlan11/firecheck/releases). Development versions `0.1.9` were used for local validation; they are not evidence of a public release.
