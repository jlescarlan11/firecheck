# FireCheck deferred work and code comment cleanup PRD

Date: 2026-11-18
Status: Draft for implementation planning
Scope: The eight primary audit findings, additional maintenance and validation notes, and related gateway operating limits.

## Purpose

Make FireCheck's unfinished work explicit and verifiable. Enumerators need dependable completion and sync, enough geographic context to resolve duplicates, and consistent form requirements. Supervisors need controlled data access and reliable publishing. Maintainers need comments that describe current behavior or point to a concrete outstanding requirement.

The audit found one explicit source TODO and seven other substantive deferred-work comment groups. The absence of TODO tags does not imply that the work is complete. Conversely, a historical migration comment or an intentional compatibility adapter does not establish a current defect.

This PRD defines the outcomes needed to close those findings. It also records optional enhancements and accepted limitations so they can be addressed without expanding every old comment into a new feature. Dates, individual owners, issue URLs, and unresolved product decisions remain unassigned; requirement IDs below provide repository-local traceability.

## Users and outcomes

| User | Required outcome |
| --- | --- |
| Enumerator | Complete a survey offline, retain evidence and drafts, and receive accurate pending, synced, or failed status when connectivity changes. |
| Enumerator resolving a duplicate | Distinguish their feature from the competing feature before choosing a resolution. |
| Supervisor | Manage access and map publication through the supported administrative flow without exposing unrelated data to writes. |
| GIS collaborator | Continue opening supported photo and export links after access-policy or folder-layout changes. |
| Maintainer | Understand every deferred item, its disposition, dependencies, and evidence needed for closure. |

## Constraints and approach

Use the current working tree as the starting point, including explicit working-map selection, assignment-scoped form snapshots, shared-map sync, gateway uploads, and the supported direct-Drive fallback. Existing specs describe intent; executable code and development checks establish actual behavior. Recheck each affected path before implementation because substantial concurrent changes exist.

Recommended approach: deliver focused changes in dependency order, beginning with policy characterization and reliable integration coverage. A comment-only pass would hide unfinished work. A single rewrite would combine unrelated migration, UX, and infrastructure risks. No approach has been approved merely by writing this draft.

Preserve saved surveys, photos, pending jobs, assignment identity, and historical artifacts. Use forward migrations for schema or policy changes; do not rewrite applied migrations to make their comments disappear. Do not introduce a new sync architecture, remove a supported fallback, upgrade dependencies, or build owner invitations solely to satisfy an old comment.

## Priorities and completion states

P1 means investigate and resolve access/data-integrity exposure first; this is scheduling priority, not a confirmed exploit severity. P2 means restore coverage or deliver a concrete product gap. P3 means a bounded decision, documentation correction, or conditional enhancement.

Each requirement must end as **implemented**, **accepted limitation**, **superseded**, or **deferred with an owner and review trigger**. Implementation requires passing evidence. Other states require a written rationale and responsible owner; deleting a comment is insufficient. Required P1/P2 delivery may only be deferred by an explicit scope decision. A conditional dependency note can remain in code when it is still accurate.

## Primary requirements

### R01 Restrict photo mutations to authorized users

Priority: P1. Source: [photo storage policies](../../../supabase/migrations/010_storage_photos_rls.sql#L7).

The migration grants authenticated users bucket-wide writes and defers stricter policies. Later database-row policies do not alone constrain object storage writes. Separately, photo reads were deliberately opened for GIS links; write cleanup must not silently change that read contract.

Acceptance criteria:

- Document the supported object naming, ownership, submission-to-assignment relationships, cleanup actor, and legacy objects before changing policies. An object name supplied by a client must not itself establish authorization.
- In a development database, prove that an unauthenticated actor and an authenticated nonmember cannot create, overwrite, rename, or delete another assignment's photo. Define and test authorized member, supervisor, service-worker, revoked-member, and cross-assignment cases under the chosen policy.
- Preserve valid photo upload, retry, and supported cleanup. Reconcile existing objects safely; ambiguous ownership is reported for review rather than guessed or deleted.
- Add a forward migration and real policy tests under representative database roles; mocked client success does not establish RLS correctness.
- Verify the agreed GIS photo-read behavior remains usable. If public reads remain accepted, document that removing assignment membership does not revoke a known public photo URL. Any privacy change to public reads requires a separate product decision and link compatibility plan.

### R02 Restore review and sync integration coverage

Priority: P2. Source: [skipped review test](../../../test/integration/review_happy_path_test.dart#L98).

Replace the skipped test's obsolete orchestration assumptions with coverage of the current user flow. Completion in shared-map mode and legacy export/upload mode need different assertions; an old `submittedAt` stamp must not become the definition of successful shared-map sync.

Acceptance criteria:

- Exercise the real review orchestration and local repositories with controlled remote boundaries and an explicitly selected assignment.
- Cover supported shared-map and legacy modes, including validation failure, offline pending work, remote rejection, transient retry, and successful completion.
- Await a deterministic completion signal with a bounded timeout. Do not substitute arbitrary sleeps or a fake controller that bypasses the worker.
- Failed or unacknowledged work never appears synced; retries do not create duplicate accepted work. Switching maps during a run preserves the original assignment/account ownership.
- Shared-map mode must not invoke the legacy export path. Completed/submitted work remains editable for progressive submissions; administrator closure blocks edits. Do not restore a submitted-means-read-only rule from the old test.
- In both supported modes, edit a previously accepted survey, persist the changes, queue the new revision, and complete another sync/upload. Prove that an intentional revision is accepted as new work while retrying the same revision does not duplicate it; remote closure still prevents unauthorized edits.
- Enable the rewritten test, or replace it with named runnable tests and remove the obsolete skipped file in the same change. Explain which new test covers each old assertion that still matters.

### R03 Restore sketch through completed survey coverage

Priority: P2. Source: [skipped feature test](../../../test/integration/set_up_complete_feature_test.dart#L71).

Acceptance criteria:

- Select a downloaded working map, enter the current sketch interaction, create a valid building geometry, finish the drawing, answer applicable required questions, attach required photographic evidence, and complete the survey.
- Assert geometry, feature, survey, photo, and queued work belong to that map and account. Verify completion survives repository reload.
- Cover cancel, invalid or outside-boundary geometry, validation failure, and map switching with unfinished drawing; none may silently lose or reassign saved work.
- Use the supported map test adapter for automated gestures. Keep physical Mapbox rendering validation separate from widget-test evidence.
- Replace or enable the skipped test with deterministic runnable coverage; retain the mandatory photo invariant.

### R04 Show both geometries during duplicate review

Priority: P2. Source: [duplicate review](../../../lib/features/conflict_review/presentation/dedup_review_screen.dart#L13).

Acceptance criteria:

- Show the proposed and competing geometries together, fit the viewport to both, and label them in text and a legend so color alone is unnecessary. Support the geometry types the duplicate flow actually accepts.
- Keep Keep both, Replace theirs, Discard mine, and Skip semantics unchanged. Prevent repeated submissions while a decision is pending.
- Resolve both feature IDs through authorized data sources. Missing, stale, inaccessible, or malformed geometry produces a clear unavailable state, never fabricated geometry.
- Work from cached geometry offline without requiring fresh basemap tiles. Permit Skip; disable destructive decisions when required comparison information is unavailable, with an explanation.
- Verify loading, error, retry, offline, selection changes, and narrow-screen states. Check native map appearance on a development Android device.

### R05 Display the selected study boundary

Priority: P2. Source: [invisible boundary rendering](../../../lib/features/map/presentation/map_renderer.dart#L727).

Acceptance criteria:

- Render the working assignment's boundary with a visible outline; a dashed orange line is the proposed treatment, subject to contrast and native rendering checks. Do not obscure survey features or intercept their interactions.
- Fit and replace the correct boundary when the working map changes, including after style reload. Clear stale boundary layers when no valid map is selected.
- Use stored boundary data offline. Preserve the existing boundary provenance and distinguish a source boundary from an inferred fallback where relevant.
- Support valid imported geometry; malformed or missing geometry must not crash the map. Drawing validation continues to use authoritative boundary rules, independent of presentation.
- Verify layer lifecycle and assignment isolation automatically, and inspect contrast, zoom behavior, and feature interaction on a development Android device.

### R06 Make building requirement configuration consistent

Priority: P2. Source: [unmapped fields](../../../lib/features/survey/building_form/domain/building_form_applicability.dart#L108) and [requirement defaults](../../../lib/core/forms/field_requirements.dart).

`cbmsId` and `fireFightingFacilities` lack requirement keys and can count as unanswered even though completion validation does not enforce them. Resolve this mismatch across configuration, labels, completion, and remaining-question counts.

Acceptance criteria:

- Define stable keys and agree on their omitted-key behavior before changing saved configuration semantics. Preserve existing assignments' completion rules by default; do not silently make previously optional fields mandatory. Any stricter rule needs explicit configuration/versioning and a compatibility fixture.
- Define whether an explicit “none” counts as an answered facilities question and whether CBMS ID needs a format rule. Align the requirement sidecar with the current form-definition visibility/editability contract rather than adding a parallel form policy.
- For explicit required and optional values, UI labels, applicable unanswered counts, validators, and review completion agree. Optional supplied values still obey their validity rules.
- Hidden fields and does-not-exist behavior follow existing applicability rules. The minimum-photo rule remains mandatory regardless of legacy sidecar values.
- Cover old sidecars without these keys, malformed config, per-assignment snapshots, offline reload, and switching between maps with different rules. Preserve existing draft values and completed evidence.
- Update the configuration contract and examples together with automated field-policy tests.

### R07 Resolve the campaign identity contract

Priority: P3. Source: [campaign foreign-key TODO](../../../supabase/migrations/001_initial_schema.sql#L33).

Choose whether `campaign_id` is an external identifier or an internally managed entity. Proposed default: document external identity unless a real campaign lifecycle is required; an old TODO alone does not justify a campaigns product.

Acceptance criteria:

- Record the identity authority, validation rules, and whether UUID existence is locally enforceable. Inventory existing references without modifying them.
- External identifier: update the current schema documentation and input-validation contract; explain why there is intentionally no local FK.
- Internal entity: define campaign creation and access, map every existing reference, and add a forward migration with verified backfill and constraint validation. Never invent campaign ownership or discard unmatched assignments.
- Cover existing assignment registration and import compatibility. Preserve the historical migration and link its deferred intent to this disposition.

### R08 Resolve the owner invitation promise

Priority: P3. Source: [future invitations](../../../supabase/migrations/015_assignment_members.sql#L33).

Proposed default: retain current supervisor-managed enrollment and mark owner invitations superseded for this release. Existing `owner` membership must not implicitly grant enrollment authority.

Acceptance criteria:

- Document who may add/remove members, how gateway and legacy deployments differ, and which legacy claim path is permitted after activation.
- Verify ordinary members and owner-role users cannot gain supervisor authority through client input. Test authorization, removal, and retry behavior through the supported administrative boundary.
- Preserve authorized users' offline work while enforcing access on subsequent online requests. Never promise remote deletion of offline copies.
- If invitations are desired, create a separately scoped requirement for issuer authority, expiry, revocation, single use, recipient identity, and audit records before implementation.

## Additional audit follow ups

| ID and priority | Requirement and completion evidence |
| --- | --- |
| F01 P3 Direct Drive resumability | [Reserved resumable URI](../../../lib/core/drive/drive_upload_api.dart#L15): inventory direct-Drive fallback use separately from gateway chunk uploads. Proposed default: retain restart-on-failure as a documented fallback limitation. If resumability is selected, persist session state by account/job, handle expired sessions and app restart, reconcile server offsets, and prove exactly one completed receipt. Do not implement a second resumable transport for an unused path. |
| F02 P3 Connectivity adapter | [Version-dependent adapter](../../../lib/core/drive/drive_upload_controller.dart#L13): retain it while `connectivity_plus` remains 5.x. Record the 6.x-or-later upgrade as the removal trigger. When upgrading, prove Wi-Fi auto-upload preference, network transitions, and single active subscription behavior before removing the adapter. No dependency upgrade is required here. |
| F03 P2 Device validation | [Photo benchmark](../../../tool/photo_processing_benchmark_test.dart#L49) and [physical-phone checks](../../APP_SIZE_AUDIT.md#L146): complete the development-device protocol below. A host event-loop measurement or emulator launch cannot close Android responsiveness or camera/GPS validation. |
| F04 P3 License decision | [License TBD](../../../README.md#L166): obtain the rights holders' choice, check relevant third-party notices, then update repository metadata consistently. No license is selected by this PRD. If unresolved, retain an owned decision rather than imply permission to redistribute. |
| F05 P3 Clarify input contract | [Cache side-channel comment](../../../lib/core/sync/data/remote_attributions_cache_repository.dart#L195): describe both supported assignment ID inputs, precedence, and the missing-ID failure. Check conflicting contextual/inline identities and verify no cross-assignment writes or successful cursor advancement on invalid input. Preserve durable shared-feed handling and the supported compatibility fallback. Remove vague timing language after checking callers; a typed API redesign is optional. |
| F06 P3 Remove obsolete copy when unused | [English localization source](../../../lib/core/i18n/app_en.arb) and [Tagalog source](../../../lib/core/i18n/app_tl.arb): check `phase2FormNote` for handwritten references and runtime string lookup. If unused, remove both source entries and regenerate localization output. If used, replace obsolete phase wording with accurate copy in both languages. Never hand-edit only generated output. |

## Related gateway follow ups

These were documentation findings in the audit rather than additional source TODOs. They are included so “all findings addressed” does not leave operating-limit statements ambiguous. Source: [gateway operating limits and organized outputs](../../../server/drive-gateway/README.md#L171).

| ID and priority | Requirement and acceptance criteria |
| --- | --- |
| O01 P3 Transfer progress accuracy | Reconcile the claim that progress updates only per component with current transfer-progress providers and widgets. A component spanning multiple persisted download ranges must visibly advance before the entire component finishes. On the active gateway path, test bounded, monotonic byte progress, retries/resume, unknown totals, and restart; retries must not double-count bytes. Distinguish transfer, verification, and import. Never show 100% completion before verification/acknowledgment. Update stale documentation if already implemented; preserve explicit import-memory and file-size limits unless separately changed. |
| O02 P2 Publication reliability | Reconcile documented request budgets with the selected runtime configuration; do not assume either 150 or 300 seconds is universally available. Measure representative maximum supported inputs in development, interrupt/retry publication, and prove partial versions never become current. If supported workloads exceed the measured budget, implement durable checkpointed publication with bounded retries, observable terminal status, and idempotent completion. Otherwise document the tested synchronous limit and escalation trigger. Existing background shared-map exports must not be mistaken for a durable source-publication implementation. |
| O03 P3 Orphan cleanup and retention | Default to reporting candidates without deletion. Inventory gateway-owned folders using stable metadata, exclude active/current versions and resumable transfers, and detect concurrent reference changes. Define an owner-approved retention policy before enabling deletion. Any later apply mode needs a reviewable manifest, repeatability, and a recovery procedure. No cleanup execution or deletion is authorized by this PRD. |
| O04 P2 Export layout documentation | Reconcile the obsolete UUID output-path statement with the implemented organized map/surveyor layout and shared-map derived exports. Document each active mode and its consumers. Verify newest-completed ordering, archive placement, receipt-link stability, folder identity, and dry-run migration output. Update supervisor scripts only after identifying their contract; do not move historical survey artifacts merely to normalize paths. |

## Decisions and accountable roles

Roles below are proposed responsibilities, not assigned individuals. Resolve a decision before its dependent implementation; independent requirements can proceed.

| Decision | Recommended starting point | Responsible role |
| --- | --- | --- |
| Photo write authority and legacy ownership | Assignment-authorized mutations with explicit service cleanup; preserve current agreed read contract | Backend maintainer and data steward |
| Missing requirement-key compatibility | Preserve legacy completion semantics; require explicit configuration for stricter new fields | Survey designer and mobile maintainer |
| Campaign authority | External identity unless an internal lifecycle is needed | Product owner and backend maintainer |
| Invitation model | Supervisor enrollment; defer owner invitations | Product owner |
| Fallback transport lifetime | Keep supported fallback, avoid duplicating gateway resumability | Mobile maintainer |
| Device performance budget | Adopt the proposed thresholds below after baseline review | Mobile maintainer and field-test owner |
| License and retention | Explicit rights-holder choice; no automatic deletion | Rights holders and data steward |

## Delivery sequence and dependencies

1. **Characterize and assign:** map active versus legacy paths, attach a responsible person and evidence location to each ID, resolve relevant policy/configuration decisions, and record baseline failures separately from concurrent work.
2. **Protect and verify:** implement R01 after policy characterization; restore R02 and R03 against the current orchestration. Develop policy and test work independently where safe. Do not gate policy fixes on visual polish.
3. **Complete field UX:** deliver R04–R06 with assignment-isolation fixtures, offline states, and native rendering checks. R06 requires the compatibility decision before changing defaults.
4. **Reconcile contracts:** complete R07–R08, F01–F02, F04–F06, and O01/O04 by implementation or a recorded disposition. Maintain historical context rather than erasing it.
5. **Validate operating limits:** complete F03 and O02 with measured development evidence; document O03's policy and safe report-only path. Any infrastructure extension gets its own implementation plan before rollout.

Do not combine production policy rollout, destructive cleanup, dependency upgrades, and visual changes into one release. Each implementation change should cite the requirement IDs it satisfies and explain remaining limitations.

## Development verification

The following is the planned verification contract, not a report of executed checks. Use Codex review; external-provider review is not required. No staging walk is required by this PRD. Development results do not establish production behavior.

Automated checks for affected changes:

```sh
flutter analyze
flutter test --no-pub
flutter test --no-pub tool/photo_processing_benchmark_test.dart --reporter expanded
python3 -m unittest discover -s tool -p 'check_apk_size_test.py'
```

Run gateway checks from `server/drive-gateway` when backend or output contracts change:

```sh
npm run check
npm test
```

Add development database policy/migration checks for R01/R07; record the database version, applied migration set, role matrix, results, and the exact reproducible command in the implementation change. Test clean installation and upgrade of representative legacy data. Gateway mocks alone cannot close database-policy requirements.

For a release-build check, use the existing script with publishing disabled:

```sh
FIRECHECK_UPLOAD_APK=0 bash tool/build_android_release.sh
```

Inspect the script and prerequisites first; local signing or build configuration may be required. Build verification must not publish artifacts as a side effect. Changes to localization require regeneration and a check for obsolete handwritten references.

### Development Android protocol

Record device model, Android version, RAM, app commit/build mode, active transport/sync mode, dataset size, and network conditions. Use a representative lower-spec physical device and a typical field device, or document the unavailable device class as pending. Use development data and sanitized evidence.

- Check sign-in, explicit map selection, offline map use, boundary display, duplicate comparison, camera/GPS, draft persistence, account switching, process restart, and interrupted/background upload.
- Capture a 3000×2000 photo and a representative larger camera photo repeatedly in profile/release mode. Record processing duration, peak memory, UI frame timing, output correctness, orientation/metadata behavior, and cancellation/retry results.
- Proposed performance targets, subject to baseline approval: no crash or ANR; no survey/photo loss across interruption; p95 processing time at most 5 seconds for the 3000×2000 case; fewer than 5% of frames exceeding the display's frame budget during that case; no individual UI stall exceeding 250 ms. Measure at least 20 processed photos per device, separate warm-up samples, and report sample count and failures. Larger-photo results remain separately reported until a supported maximum and budget are agreed.
- Report host benchmark output separately. Do not substitute its event-loop gaps for Android frame timing. If device checks cannot be run, retain F03 as pending with an owner and next check; do not mark it passed.

## Completion and evidence

Maintain a disposition record with requirement ID, owner, status, linked change or issue, development evidence, remaining risk, and review trigger. A repository link to this requirement can be used until a real issue exists; never invent issue URLs.

The cleanup delivery is complete when every ID in this PRD has that record, all required implemented outcomes pass their acceptance checks, no targeted integration test remains silently skipped, and documentation describes the supported modes consistently. Distinguish delivered functionality from accepted or deferred scope in the final report. Any unresolved P1/P2 requirement means full remediation remains incomplete unless the product owner explicitly changes scope.

Comment cleanup follows the behavior change: remove completed deferred wording, replace vague future-phase promises with a requirement/issue link and reason, retain useful compatibility instructions, and preserve applied migration history. Planning snippets, fixture stubs, temporary-file variables, and intentionally unsupported FTP uploads are excluded from defect counts.

Final evidence must state the exact development checks run, any failed or blocked checks, device coverage, and whether deployed behavior was verified. This document creates requirements only; it does not change product behavior, deploy migrations, move files in Drive, select a license, or establish successful runtime verification.
