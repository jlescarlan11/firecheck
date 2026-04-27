# FireCheck Mobile — Phase 3b Design Spec

**Date:** 2026-04-26
**Status:** Draft v1 (brainstorming output)
**Phase:** 3b — OLP household fire safety survey + Lebel ng Kahinaan scoring
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor:** `docs/superpowers/specs/2026-04-25-firecheck-phase-3a-design.md`
**Source rubric:** BFP CFPP Rev.00 (07.27.23) household checklist (user-supplied OLP PRD)

## 1. Summary

Phase 3b adds the OLP (Oplan Ligtas na Pamayanan) household fire safety survey + scoring engine to FireCheck Mobile. After this ships, an enumerator can:

1. Open any building's submission detail screen.
2. Expand the always-present **OLP household survey · Optional** section at the bottom of the building form.
3. Acknowledge the BFP disclaimers + flip the homeowner-agrees switch.
4. Fill Section A (10 construction-element materials, descriptive only).
5. Tick items in scored Sections B/C/D/E (35 total scoreable items).
6. Watch the live score footer update on every change (`Iskor: X / 35 · [classification badge]`).
7. Tap "View breakdown" to push a full-screen result route showing the score hero, per-section progress bars, and unchecked items each paired with a Tagalog safety suggestion.
8. Tap "Mark survey complete" on the result screen to persist `completed_at`.

## 2. Scope

### In scope

- **Drift schema bump v3 → v4**: add `homeowner_acknowledged` (bool default false) and `completed_at` (datetime nullable) columns to existing `household_surveys` table. Matching Supabase migration 004.
- **Static rubric config** (`OlpRubric`): 35 scoreable items across 4 sections (B/C/D/E) + 10 descriptive Section A construction elements + 12/23/24 classification thresholds. Data-driven via `OlpRubricItem` records keyed by stable `code` (`B-01`, `C-10`, etc.) with i18n keys for statements + suggestions.
- **Pure scoring** (`computeOlpScore`, `classify`): count of checked codes in B+C+D+E → score (0–35) → sealed `OlpClassification` (`Ligtas` / `MayroongDapatIpangamba` / `LabisNaMapanganib`). Returns per-section breakdown + list of unchecked items.
- **OLP form state + autosave**: `OlpFormState` value class with `copyWith` + clear-flag pattern; `OlpSectionNotifier` with 500 ms debounce + `flushNow()` + dispose-time best-effort flush, mirroring Phase 2/3a. On every flush the repository writes the 5 jsonb columns + computed `lebel_ng_kahinaan` + `safety_suggestions` for durability.
- **Collapsible OLP section** inside `BuildingForm`: disclaimer callout + `homeowner_acknowledged` switch + Section A subform + 4 scored checklist sections + sticky live-score footer with "View breakdown" link.
- **Full-screen result route** at `/feature/:featureId/olp/result`: large-numeral score, classification badge in 3-tier color, 4 per-section progress bars, unchecked-items + suggestions list, "Mark survey complete" button (gated on `homeownerAcknowledged`).
- **i18n** for 35 item statements + 35 paired suggestions + 3 classification labels + disclaimer text + UI chrome (~80 keys, EN + TL).

### Out of scope

- Sync queue / Supabase upload of OLP data — Phase 4.
- Result-screen PDF export / printable receipt — PRD §8 v2 deferral.
- Homeowner SMS sharing — PRD §3 non-goal.
- Road OLP — roads don't have households.
- In-app rubric editor — PRD §3 non-goal.
- Predictive risk modeling — PRD §3 non-goal.
- Per-item edit history — only `submittedBy` + `completedAt` tracked.
- Server-side recompute — function is pure for that future use, but no wiring this phase.
- OLP review-screen warning surfacing ("OLP not filled on residential building") — Phase 4.

## 3. Architecture

### 3.1 Module layout

```
lib/features/survey/olp_survey/
├── data/
│   └── household_survey_repository.dart       # CRUD + JSON pack/unpack of section maps
├── domain/
│   ├── olp_rubric.dart                        # static 35-item config + 10-element Section A + thresholds
│   ├── olp_classification.dart                # sealed: Ligtas | MayroongDapatIpangamba | LabisNaMapanganib
│   ├── olp_score.dart                         # pure: OlpScoreResult + computeOlpScore + classify
│   ├── construction_details.dart              # value class: Map<element, ConstructionDetail>
│   ├── olp_form_state.dart                    # value class: answers, constructionDetails, homeownerAcknowledged, completedAt
│   └── olp_form_validator.dart                # finalization gate (homeownerAcknowledged required)
└── presentation/
    ├── olp_section.dart                       # ExpansionTile-style collapsible inside BuildingForm
    ├── olp_section_providers.dart             # repo + notifier providers
    ├── olp_section_notifier.dart              # debounced 500ms autosave StateNotifier
    ├── disclaimer_callout.dart                # tan callout + homeownerAcknowledged switch
    ├── construction_details_subform.dart      # Section A: 10 elements × radio + conditional "Iba pa" text
    ├── scored_section_widget.dart             # generic 1-section checkbox list (used 4× for B/C/D/E)
    ├── score_footer.dart                      # sticky "Iskor: X / 35 · [Badge] · View breakdown →"
    └── result/
        ├── olp_result_screen.dart             # full route at /feature/:featureId/olp/result
        ├── score_hero.dart                    # large numeral + classification badge
        ├── per_section_progress.dart          # 4 progress bars
        ├── unchecked_items_list.dart          # ListView of unchecked + paired suggestion
        └── mark_complete_button.dart          # finalize FilledButton (gated by homeownerAcknowledged)
```

### 3.2 Modified files

- `lib/core/db/database.dart` — `schemaVersion 3 → 4`; `onUpgrade` adds two columns.
- `lib/core/db/tables/household_surveys.dart` — adds `homeownerAcknowledged` + `completedAt` columns.
- `lib/features/survey/building_form/presentation/building_form.dart` — embeds `OlpSection` at the bottom (after fire-load section).
- `lib/core/router/app_router.dart` — adds `/feature/:featureId/olp/result` route.
- `lib/core/i18n/app_en.arb` + `app_tl.arb` — many new keys.

### 3.3 New Supabase migration

`supabase/migrations/004_household_surveys_acknowledged_completed.sql`:
```sql
alter table public.household_surveys
  add column homeowner_acknowledged boolean not null default false;
alter table public.household_surveys
  add column completed_at timestamptz null;
```

### 3.4 Reused infrastructure

`_section_card.dart`, `_persistent_text_field.dart` (for "Iba pa" free-text), the debounced-autosave pattern, `appDatabaseProvider`, `submissionRepositoryProvider`, FK chain test seeding, AppDatabase-inside-testWidgets-body pattern.

### 3.5 Data flow

**Per-edit autosave:**
```
User taps checkbox / radio / disclaimer switch / "Iba pa" text
  → OlpSectionNotifier.update(mutation)
  → state mutates immediately
  → 500ms debounce schedules _flush()
  → _flush computes OlpScoreResult via pure fn
  → repo.upsertForSubmission persists 5 jsonb cols + lebelNgKahinaan + safetySuggestions
  → homeownerAcknowledged + completedAt persisted (completedAt only when markComplete fired)
```

**Result-screen route:**
```
User taps "View breakdown →" in score footer
  → context.push('/feature/${featureId}/olp/result')
  → OlpResultScreen reads same olpFormNotifierProvider (keyed by submission)
  → renders score hero + progress bars + unchecked items + suggestions
  → user taps "Mark survey complete" (only enabled when homeownerAcknowledged)
  → notifier.markComplete() sets completedAt = now, flushes
  → context.pop() returns to building form
```

## 4. Schema bump v3 → v4

### 4.1 Drift table

Add to `lib/core/db/tables/household_surveys.dart`:

```dart
BoolColumn get homeownerAcknowledged =>
    boolean().withDefault(const Constant(false))();
DateTimeColumn get completedAt => dateTime().nullable()();
```

### 4.2 Database migration

In `lib/core/db/database.dart`:

```dart
@override
int get schemaVersion => 4;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async => m.createAll(),
  onUpgrade: (m, from, to) async {
    // ... existing v1→v2, v2→v3 branches preserved ...
    if (from < 4) {
      await m.addColumn(householdSurveys, householdSurveys.homeownerAcknowledged);
      await m.addColumn(householdSurveys, householdSurveys.completedAt);
    }
  },
);
```

After editing tables, regenerate Drift via:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4.3 Supabase migration

`supabase/migrations/004_household_surveys_acknowledged_completed.sql` (shown in §3.3).

### 4.4 No data migration

Existing rows are pre-Phase-3b drafts. Defaults (`homeowner_acknowledged=false`, `completed_at=null`) are semantically correct: no one has consented or finalized.

## 5. Rubric data model

### 5.1 Rubric config

`lib/features/survey/olp_survey/domain/olp_rubric.dart`:

```dart
enum OlpSection { b, c, d, e }

class OlpRubricItem {
  const OlpRubricItem({
    required this.code,
    required this.section,
    required this.statementKey,
    required this.suggestionKey,
  });
  final String code;            // stable id: 'B-01', 'C-10', etc.
  final OlpSection section;
  final String statementKey;    // i18n key
  final String suggestionKey;   // i18n key for paired suggestion
}

class OlpRubric {
  // PRD risk #2: 12/23 boundary unverified — verify against printed CFPP form before pilot.
  static const ligtasThreshold = 24;
  static const mayroongThreshold = 12;

  static const items = <OlpRubricItem>[
    // Section B — 15 draft items (PRD risk #1: verify before pilot)
    OlpRubricItem(code: 'B-01', section: OlpSection.b, statementKey: 'olpItemB01Statement', suggestionKey: 'olpItemB01Suggestion'),
    // ... 14 more B items
    // Section C — 9 items (PRD §4 numbering 10–18)
    OlpRubricItem(code: 'C-10', section: OlpSection.c, statementKey: 'olpItemC10Statement', suggestionKey: 'olpItemC10Suggestion'),
    // ... 8 more C items
    // Section D — 5 items (PRD §4 numbering 25–29)
    OlpRubricItem(code: 'D-25', section: OlpSection.d, statementKey: 'olpItemD25Statement', suggestionKey: 'olpItemD25Suggestion'),
    // ... 4 more D items
    // Section E — 6 items (PRD §4 numbering 30–35)
    OlpRubricItem(code: 'E-30', section: OlpSection.e, statementKey: 'olpItemE30Statement', suggestionKey: 'olpItemE30Suggestion'),
    // ... 5 more E items
  ]; // 35 items total

  static const constructionElements = <String>[
    'roof', 'ceiling', 'roomPartitions', 'trusses', 'windows',
    'corridorWalls', 'columns', 'mainDoor', 'exteriorWall', 'beams',
  ];

  static const materials = <String>['kahoy', 'semento', 'bakal', 'others'];
}
```

The implementation plan will fully populate the 35-item list with code + i18n key per row, plus the matching ARB entries (en + tl).

### 5.2 Form state

`lib/features/survey/olp_survey/domain/olp_form_state.dart`:

```dart
class OlpFormState {
  const OlpFormState({
    required this.submissionId,
    this.checkedCodes = const {},
    this.constructionDetails = const {},
    this.homeownerAcknowledged = false,
    this.completedAt,
  });

  final String submissionId;
  final Set<String> checkedCodes;
  final Map<String, ConstructionDetail> constructionDetails;
  final bool homeownerAcknowledged;
  final DateTime? completedAt;

  OlpFormState copyWith({
    Set<String>? checkedCodes,
    Map<String, ConstructionDetail>? constructionDetails,
    bool? homeownerAcknowledged,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  });
}

class ConstructionDetail {
  const ConstructionDetail({required this.material, this.materialOther});
  final String material;        // 'kahoy' | 'semento' | 'bakal' | 'others'
  final String? materialOther;  // required when material == 'others'
}
```

### 5.3 Pure scoring

`lib/features/survey/olp_survey/domain/olp_score.dart`:

```dart
sealed class OlpClassification {
  const OlpClassification();
}
class Ligtas extends OlpClassification { const Ligtas(); }
class MayroongDapatIpangamba extends OlpClassification { const MayroongDapatIpangamba(); }
class LabisNaMapanganib extends OlpClassification { const LabisNaMapanganib(); }

class OlpScoreResult {
  const OlpScoreResult({
    required this.totalScore,
    required this.sectionScores,
    required this.classification,
    required this.uncheckedItems,
  });
  final int totalScore;
  final Map<OlpSection, int> sectionScores;
  final OlpClassification classification;
  final List<OlpRubricItem> uncheckedItems;
}

OlpScoreResult computeOlpScore(OlpFormState state) {
  final checked = state.checkedCodes;
  final sectionScores = {for (final s in OlpSection.values) s: 0};
  var total = 0;
  final unchecked = <OlpRubricItem>[];
  for (final item in OlpRubric.items) {
    if (checked.contains(item.code)) {
      total++;
      sectionScores[item.section] = sectionScores[item.section]! + 1;
    } else {
      unchecked.add(item);
    }
  }
  return OlpScoreResult(
    totalScore: total,
    sectionScores: sectionScores,
    classification: classify(total),
    uncheckedItems: unchecked,
  );
}

OlpClassification classify(int score) {
  if (score >= OlpRubric.ligtasThreshold) return const Ligtas();
  if (score >= OlpRubric.mayroongThreshold) return const MayroongDapatIpangamba();
  return const LabisNaMapanganib();
}
```

### 5.4 Persistence shape

`HouseholdSurveyRepository`:
- Pack `checkedCodes` into the four section JSON columns: each section's column stores `{"itemCode": true}` for checked items only.
- Pack `constructionDetails` into `constructionDetailsJson` as `{"roof": {"material": "kahoy"}, ...}`. When `material == 'others'`, also store `materialOther`.
- Persist computed `lebelNgKahinaan` (string) + `safetySuggestions` (JSON array of suggestion i18n keys) on every flush so the result is durable across app restarts without re-running the rubric.
- `homeownerAcknowledged` + `completedAt` are direct Drift columns (post-bump).

## 6. UI flow

### 6.1 OLP section inside `BuildingForm`

Embedded as the bottom-most section, using Material's `ExpansionTile` collapsed by default. Header reads:

```
OLP household survey · Optional   ▼
```

When expanded, the section body renders top-to-bottom:

1. **`DisclaimerCallout`** — tan/amber callout with the 3 BFP disclaimers + a "Pumayag ang nakatira" (Homeowner agrees) switch wired to `state.homeownerAcknowledged`.
2. **Section A — `ConstructionDetailsSubform`**: 10 rows, one per construction element. Each row is a label + RadioGroup<String>(`kahoy` / `semento` / `bakal` / `others`). When `others` is picked, an inline `PersistentTextField` appears for `materialOther`. Single material per element (per Q5a decision).
3. **Section B / C / D / E** — four instances of `ScoredSectionWidget`. Each renders the section title + a vertical list of `CheckboxListTile`s; tapping toggles the item code in `state.checkedCodes`.
4. **`ScoreFooter`** — sticky inside the section: `Iskor: 18 / 35 · [Yellow badge: Mayroong Dapat Ipangamba] · View breakdown →`. Score recomputes on every state change. The "View breakdown" link calls `context.push('/feature/${featureId}/olp/result')`.

### 6.2 Result screen route

Route: `/feature/:featureId/olp/result`. New `GoRoute` in `app_router.dart` building `OlpResultScreen(featureId)`. Layout:

1. **`ScoreHero`** — large numeral "18 / 35" centered, classification badge below in matching color (green / yellow / red).
2. **`PerSectionProgress`** — 4 progress bars labeled "Kaayusan ng Tahanan: 6/15", etc., each filled to its score / max ratio.
3. **`UncheckedItemsList`** — `ListView` of unchecked items grouped by section. Each row shows the item statement + the paired Tagalog suggestion below it.
4. **`MarkCompleteButton`** — pinned to the bottom via `Scaffold.bottomNavigationBar`. Disabled while `homeownerAcknowledged == false`; tooltip explains why. When enabled, tapping sets `completedAt = DateTime.now()` via `notifier.markComplete()`, then `context.pop()` back to the building form.

### 6.3 Building form footer impact

OLP is **non-blocking** for the parent building form's Done button. The existing `validateBuildingForm` does not consult OLP state. Phase 4's review screen will surface "OLP not filled on residential building" as a *warning*; Phase 3b doesn't wire that.

## 7. Validation rules + finalization

### 7.1 Pure validator

`lib/features/survey/olp_survey/domain/olp_form_validator.dart`:

```dart
class OlpValidationResult {
  OlpValidationResult({
    required this.canMarkComplete,
    required this.fieldErrors,
  });
  final bool canMarkComplete;
  final Map<String, String> fieldErrors;
}

OlpValidationResult validateOlpForFinalize(OlpFormState state) {
  final errors = <String, String>{};
  if (!state.homeownerAcknowledged) {
    errors['homeownerAcknowledged'] = 'homeowner_must_agree';
  }
  // Section A incomplete is a warning, not a blocker (PRD §9).
  // Partial completion is allowed — unchecked items treated as 'false', not 'missing' (PRD §9).
  return OlpValidationResult(
    canMarkComplete: errors.isEmpty,
    fieldErrors: errors,
  );
}
```

`canMarkComplete` drives the Mark Complete button's enabled state.

### 7.2 Finalization

`OlpSectionNotifier.markComplete()`:
1. Sets `state.completedAt = DateTime.now()`.
2. Calls `flushNow()` so the new value lands immediately.
3. Result-screen widget pops via `context.pop()`.

Subsequent reopens of the OLP section show `Survey complete · Lebel: <classification>` in the header; body remains editable so corrections recompute and re-set `completedAt` (we don't reset on edit; it tracks the most-recent finalize).

### 7.3 Edge cases

- **Empty survey**: score = 0, classification = `LabisNaMapanganib`, all 35 in `uncheckedItems` (PRD §9).
- **Boundary scores**: 24 → `Ligtas`; 12 → `MayroongDapatIpangamba`; 11 → `LabisNaMapanganib`. Unit-tested explicitly.
- **Mid-edit recompute after complete**: changing a checkbox after `completedAt` is set recomputes classification immediately; `completedAt` is preserved.
- **Section A "Iba pa" with no description**: required when material == 'others' — soft validation (red helper text in subform) but not a fieldError (descriptive only, doesn't block finalize).

## 8. i18n additions

Approximate ~80 new ARB keys (EN + TL):

| Category | Keys (samples) |
|---|---|
| Section headers | `olpSectionTitle`, `olpSectionA`, `olpSectionB`, `olpSectionC`, `olpSectionD`, `olpSectionE` |
| Item statements | `olpItemB01Statement` … `olpItemE35Statement` (35 keys) |
| Suggestions | `olpItemB01Suggestion` … `olpItemE35Suggestion` (35 keys) |
| Construction elements | `olpElementRoof`, `olpElementCeiling`, …, `olpElementBeams` (10) |
| Materials | `olpMaterialKahoy`, `olpMaterialSemento`, `olpMaterialBakal`, `olpMaterialOthers`, `olpMaterialOthersHint` |
| Classifications | `olpClassLigtas`, `olpClassMayroong`, `olpClassLabis` |
| Disclaimers | `olpDisclaimerVoluntary`, `olpDisclaimerSurveyorRole`, `olpDisclaimerNoSelling`, `olpHomeownerAgreesLabel` |
| UI chrome | `olpSectionHeader`, `olpScoreLabel`, `olpViewBreakdown`, `olpMarkComplete`, `olpAcknowledgmentRequiredTooltip`, `olpResultTitle`, `olpResultSurveyComplete` |

Generated files via `flutter gen-l10n` after each ARB change.

## 9. Testing strategy

### 9.1 Unit tests (no Flutter deps)

- `OlpRubric.items.length == 35`; section counts (B=15, C=9, D=5, E=6); all `code` values unique; all `statementKey` + `suggestionKey` values resolve in the generated AppLocalizations.
- `classify(score)` boundary cases: 0, 11, 12, 23, 24, 35 → expected tier.
- `computeOlpScore` — empty state → score 0, all 35 unchecked, `LabisNaMapanganib`. Full-checked → score 35, no unchecked, `Ligtas`. Partial of known codes → known per-section breakdown. Unknown codes silently ignored.
- `OlpFormState.copyWith` + `clearCompletedAt` clear-flag.
- `validateOlpForFinalize` — `homeownerAcknowledged=false` blocks; `=true` allows.

### 9.2 Repository tests

- `HouseholdSurveyRepository.upsert` round-trips a fully-populated `OlpFormState` through 5 jsonb columns + `lebel_ng_kahinaan` + `safety_suggestions` + `homeowner_acknowledged` + `completed_at`.
- Empty/null defaults match schema.
- `decodeCheckedCodes(json)` empty / single / many cases.
- `decodeConstructionDetails(json)` parses material + materialOther correctly; returns empty Map on malformed input.

### 9.3 Migration test

`test/core/db/migration_v3_to_v4_test.dart`:
- Seed v3 schema DB with a `household_surveys` row.
- Run v3→v4 migration via `m.addColumn`.
- Assert: row intact; new columns present with correct defaults.

### 9.4 Notifier tests

- Debounced 500 ms write lands in `household_surveys` after `update(...)`.
- `flushNow()` writes immediately.
- Toggling an item code recomputes and persists `lebel_ng_kahinaan` + `safety_suggestions`.
- `markComplete()` sets `completed_at` and calls `flushNow`.
- Disclaimer toggle persists `homeowner_acknowledged`.

### 9.5 Widget tests

- `DisclaimerCallout` switch toggles emit `homeownerAcknowledged` updates.
- `ScoredSectionWidget` renders one CheckboxListTile per item; tapping toggles its code.
- `ScoreFooter` shows `Iskor: N / 35` and the right badge for a seeded notifier state.
- `OlpResultScreen` smoke — score numeral + badge text + 4 progress bars + unchecked-items list render. Mark Complete button disabled when `homeownerAcknowledged=false`, enabled when true. Tap pops the route.
- `BuildingForm` smoke — confirms OLP section header renders below fire-load section. Defer per Phase 2 T18 precedent if it hangs.

### 9.6 Acceptance gate

- `flutter analyze` clean.
- `flutter test` ≥ 175 passing (Phase 3a ended at 152).
- `flutter build apk --debug` succeeds.
- Manual happy path on emulator: open building → expand OLP → toggle disclaimer → tick items across all sections → live score updates → tap "View breakdown" → Mark Complete → result persists across app kill.
- Tag `phase-3b-olp` (push remains user-gated).

## 10. Conventions reused

- Drift codegen via `dart run build_runner build --delete-conflicting-outputs`.
- Riverpod 2.5 `StateNotifierProvider.autoDispose.family` keyed by submission/feature id.
- Value class with `copyWith` + clear-flag pattern for nullable fields.
- `very_good_analysis` lint set; project-wide overrides preserved.
- `subagent-driven-development` for plan execution (one subagent per task, two-stage review).
- Commit format `<type>(<scope>): <subject>` + Claude trailer.
- AppDatabase-inside-testWidgets-body for widget tests (avoids Drift+FakeAsync zone deadlock).
- FK chain test seeding (assignments → features → submissions before household_surveys).
- `submittedBy` (NOT `enumeratorId`) on `SubmissionsCompanion.insert`.
- No automatic push; tagging happens at the final task; user pushes manually.

## 11. Open items / risks documented

PRD risks flagged here, blocking pre-pilot but not this phase's ship:

- **PRD risk #1**: Section B item count + statement wording. Implementation will draft 15 plausible items based on "Kaayusan ng Tahanan" (orderly home) themes; entire rubric is data-driven so verified BFP items swap as a config-only change.
- **PRD risk #2**: 12/23 boundary unverified. Constants in `OlpRubric` (`mayroongThreshold = 12`, `ligtasThreshold = 24`) swap in one place when verified.
- **PRD §11 Q3**: Should the homeowner sign on-device? Not addressed in Phase 3b; deferred.
- **PRD §11 Q4**: "Not applicable" vs "not checked" distinction (e.g., household with no kitchen) — Phase 3b treats unchecked uniformly as "not affirmed", per PRD §9. May revisit if pilot feedback requires it.
- **PRD §11 Q5**: Suggestion strings are draft Tagalog phrasings I commit to the i18n bundle; BFP-vetted phrasings swap as ARB-only changes.
