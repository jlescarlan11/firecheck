# FireCheck deferred work implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Execute tasks in this session; the user has authorized implementation with GPT-6.1 Sol medium agents.

**Goal:** Resolve the cleanup PRD through tested code changes and explicit, evidence-backed dispositions.

**Architecture:** Preserve the current shared-map and compatibility transports. Before each behavior change, simplify the touched code under existing characterization tests, then implement the smallest change under failing behavioral tests. Forward migrations preserve historical data and public GIS read contracts.

**Tech Stack:** Flutter/Dart, Riverpod, Drift, Mapbox, TypeScript/Node, PostgreSQL/PostGIS.

**Spec:** [Cleanup PRD](../specs/2026-11-18-codebase-task-cleanup-prd.md).

## Global Constraints

- User explicitly requests cleanup of touched code before implementation and GPT-6.1 Sol medium agents.
- Preserve concurrent working-tree changes. Work on the current feature branch; do not stage or commit unrelated files, deploy, publish, or delete remote artifacts.
- Preserve saved surveys, photos, drafts, pending work, assignment/account identity, and public photo-read compatibility.
- Submitted is editable; remote closure controls edit restrictions. Shared sync must not invoke legacy export.
- Default new field configuration to legacy optional behavior for omitted keys. Required photo evidence remains mandatory.
- Physical checks require an attached authorized device. No fabricated verification, license selection, or retention approval.
- Build locally with `FIRECHECK_UPLOAD_APK=0`; no staging walk or external-provider review.

## Review Focus

- Cross-assignment/account identity ambiguity must fail atomically before cache/cursor changes.
- Photo path changes, revoked users, and direct Storage writes must not bypass authorization.
- Map style reload, missing counterpart geometry, and offline tiles must not produce misleading comparison/boundaries.
- Retried revisions must be idempotent while an intentional later revision remains uploadable.
- Range retries/restart must not double-count progress or advertise completion before verification.

## Task 1: Consistent building field policy

Files: `lib/core/forms/field_requirements.dart`, building form applicability/validator and identity/facilities sections, their focused tests, configuration docs.

Interface: add stable requirement constants `building.cbmsId` and `building.fireFightingFacilities`; their absent-key policy is optional, while other existing absent keys retain required defaults. Existing public form validation/count APIs remain compatible.

- [x] Run current field/model/validator/count tests; characterize defaults. Clean duplicated requirement-to-field decisions into a focused shared policy where needed, preserving behavior first; rerun tests.
- [x] Add failing tests for required/optional/omitted keys, hidden and does-not-exist applicability, unanswered counts, and required markers.
- [x] Wire both fields through the existing requirement policy and validators/UI without new form infrastructure. An explicit `none` facilities option counts as an answer; no new CBMS format restriction.
- [x] Run focused tests and analyzer; report cleanup-first evidence and diff for review.

## Task 2: Authorized photo storage mutations

Files: new forward migration `supabase/migrations/20261118050717_authorize_photo_storage_mutations.sql`, new role-based test in `server/drive-gateway/test/photo-storage.test.ts`, reusable local migration fixture as needed.

Interface: authorization derives from canonical submission/assignment records and authenticated actor, not client owner claims. Preserve `<submission UUID>/<photo UUID>.jpg`, public reads, retries, and service cleanup. Choose author-owned writes with current assignment membership; peers cannot overwrite another author's evidence. New uploads precede photo row registration, so validate submission identity and path without requiring an already-existing photo row.

- [x] Characterize the current policy and upload ordering. Clean up a reusable local database test fixture before introducing policy behavior; avoid rewriting applied migrations.
- [x] Add a failing real PostgreSQL role matrix for anonymous/author/peer/nonmember/revoked actor, inserts/overwrite/rename/delete, malformed paths, registration/retry, and service cleanup.
- [x] Add narrowly scoped forward policy functions/policies with fixed search paths and restricted execution. Refuse closed-assignment mutations where current submission rules require it.
- [x] Verify migration chain on a disposable local PostGIS database and role matrix; report any real Storage API parity limits.

## Task 3: Geographic comparison and boundary visibility

Files: `lib/features/conflict_review/presentation/dedup_review_screen.dart`, focused new comparison model/widget files, `lib/features/map/presentation/map_renderer.dart`, relevant providers and tests.

Interface: load mine/counterpart from authorized local/cached records; expose a bounded comparison widget with explicit missing/error state. Retain existing durable resolution API and skip behavior. Boundary rendering uses the current Mapbox style API.

- [x] Characterize resolution behavior and renderer lifecycle. Clean inline button/geometry code into focused helpers without behavior changes; verify characterization tests.
- [x] Add failing tests for both labeled geometries, absent/invalid counterpart, busy/retry, offline comparison, narrow layout, selected assignment changes, and boundary geometry/layer lifecycle.
- [x] Implement cached geometry comparison with no mandatory basemap dependency and disable destructive decisions when comparison is unavailable.
- [x] Render selected boundary as a visible noninteractive outline, clear stale layers after assignment/style changes, and preserve interaction/geofencing behavior.
- [x] Run widget/domain tests and analyzer. Record real Android rendering as pending if no device exists.

## Task 4: Restore runnable complete-survey and review integration tests

Files: the two skipped `test/integration/*` files, focused shared fixture under `test/support/`, and only minimal production orchestration cleanup if deterministic awaiting requires it.

Interface: current public UI/provider orchestration, real Drift repositories, controlled remote boundaries. No arbitrary delays or test-only production APIs.

- [x] Clean obsolete/duplicated test setup into reusable focused fixtures, preserving existing enabled assertions before adding coverage.
- [x] Replace skipped tests with current sketch → required answers/photo → persisted completion and review → sync/upload flow.
- [x] Cover both supported sync modes, validation, offline/rejection/retry, correct assignment/account ownership, pending photos/geometry/conflicts, and edit → resubmit versus duplicate retry. Preserve editability until remote closure.
- [x] Run both integration files and related existing tests; remove obsolete skip comments only with replacement evidence.

## Task 5: Cache identity and download progress

Files: `lib/core/sync/data/remote_attributions_cache_repository.dart`, existing shared-map/pull tests, `lib/core/gateway/gateway_map_source.dart`, gateway download tests.

Interface: supported synthetic and inline assignment IDs must agree when both exist; invalid identity fails atomically. Download events report persisted ranges before component completion, with final completion only after checksums.

- [x] Characterize helpers and clean download path/range bookkeeping before changing event behavior; verify existing tests.
- [x] Add failing tests for missing/mismatched identity and rollback/cursor behavior, per-range progress, restart/resume, truncated/reset responses, checksum failure, and account change.
- [x] Implement minimal identity guard and range progress stream while preserving size limits and resumable files. Keep byte progress bounded and distinguish verification from completed import.
- [x] Run focused gateway/cache/shared-sync tests and analyzer.

## Task 6: Backend operating contracts and safe inspection tooling

Files: `server/drive-gateway/README.md`, focused publication/output tests, new report-only orphan inventory helper/tool if metadata makes safe detection possible, supporting docs.

Interface: no new output layout or automatic deletion. Explicitly documented source-publication request budget differs from background generated exports. Safe inventory emits stable folder IDs and exclusion reasons without modifying Drive.

- [ ] Clean touched publication/inspection helpers under existing tests before adding any behavior.
- [ ] Characterize publication failure/current-pointer atomicity and output newest-completed ordering; cover retry and receipt-link identity using existing fixture.
- [ ] Reconcile stale output path and duration documentation against implementation/configuration. Implement report-only orphan candidates with protected active/current references and deterministic tests; do not apply cleanup.
- [ ] Measure disposable development publication workloads when possible; keep hosted runtime maximum-input checks pending if unavailable. Do not claim a durable publisher exists unless actually implemented and verified.
- [ ] Run gateway typecheck/full suite and document campaign external identity and supervisor-only enrollment, using existing tests plus missing negative authorization cases.

## Task 7: Remaining maintenance and final evidence

Execution update (2026-11-18): physical phone became available during Task5. Run Task7a (maintenance and isolated native validation) after Task5 review, before Task6; resume Task7b (final disposition, verification and whole-change review) after Task6. No requirements are removed.

Files: `lib/core/i18n/app_en.arb`, `lib/core/i18n/app_tl.arb`, generated localizations, narrow comment/doc edits, `docs/CODEBASE_TASK_CLEANUP.md` disposition record.

- [ ] Confirm obsolete locale key has no handwritten/runtime consumers, remove source keys, regenerate with `flutter gen-l10n`, verify output.
- [ ] Record F01 direct-Drive restart limitation and F02 valid connectivity adapter trigger. Clarify comments without unnecessary dependency upgrades.
- [ ] Record R07 external campaign identity and R08 supervisor enrollment decisions. Record license rights-holder decision pending, device coverage pending when unavailable, retention manual/report-only, and publication validation limitations with roles and review triggers.
- [ ] Run `flutter analyze`, `flutter test --no-pub`, host photo benchmark, Python size tests, gateway check/tests, and local release build with publishing disabled when prerequisites exist. Keep baseline failures distinguishable.
- [ ] Conduct fresh GPT-6.1 Sol medium code review of session changes, fix material findings, rerun affected checks, and fill all 18 disposition rows with actual evidence. Do not call full remediation complete while required external checks remain pending.
