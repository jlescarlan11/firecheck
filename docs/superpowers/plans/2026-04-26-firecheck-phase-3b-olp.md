# FireCheck Mobile — Phase 3b (OLP household survey + Lebel ng Kahinaan scoring) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the BFP CFPP household fire safety survey (35-item checklist) as a collapsible section inside the existing building form, with live scoring → 3-tier classification → full-screen result route with breakdown + Tagalog suggestions for unchecked items.

**Architecture:** Additive to Phase 3a. New Drift schema v4 (adds `homeowner_acknowledged` + `completed_at` to existing `household_surveys` table). New `features/survey/olp_survey/` module with pure rubric config, sealed-class `OlpClassification`, pure `computeOlpScore` function, value-class `OlpFormState`, debounced autosave notifier (mirrors Phase 2/3a), and a set of section widgets that compose into a single `OlpSection` collapsible. New full-screen result route at `/feature/:featureId/olp/result` consumes the same notifier state. The 35-item rubric is data-driven via `OlpRubric.items` so BFP-vetted wording can swap as a config-only change pre-pilot.

**Tech Stack additions:** None — all dependencies already present.

**Phase 3b demo state:** Login → Get Maps (existing) → tap a building polygon → detail screen opens → scroll to bottom of building form → expand **OLP household survey · Optional** → see 3 disclaimers + Homeowner agrees switch + Section A construction subform + 4 scored sections (B/C/D/E) → tick items → live score footer updates `Iskor: X / 35 · [Badge]` → tap **View breakdown →** → full-screen result with score hero + 4 progress bars + unchecked-items list with paired Tagalog suggestions → tap **Mark survey complete** (enabled only after homeowner-agrees) → returns to building form → kill app → reopen → all OLP state including `completed_at` persisted.

---

## File structure (Phase 3b additions + modifications)

### New files

```
lib/features/survey/olp_survey/
├── data/
│   └── household_survey_repository.dart
├── domain/
│   ├── olp_rubric.dart
│   ├── olp_classification.dart
│   ├── olp_score.dart
│   ├── construction_details.dart
│   ├── olp_form_state.dart
│   └── olp_form_validator.dart
└── presentation/
    ├── olp_section.dart
    ├── olp_section_providers.dart
    ├── olp_section_notifier.dart
    ├── disclaimer_callout.dart
    ├── construction_details_subform.dart
    ├── scored_section_widget.dart
    ├── score_footer.dart
    └── result/
        ├── olp_result_screen.dart
        ├── score_hero.dart
        ├── per_section_progress.dart
        ├── unchecked_items_list.dart
        └── mark_complete_button.dart

supabase/migrations/004_household_surveys_acknowledged_completed.sql
```

### Modified files

```
lib/core/db/tables/household_surveys.dart       # +2 columns
lib/core/db/database.dart                       # schemaVersion 3 → 4 + onUpgrade branch
lib/core/db/database.g.dart                     # regenerated
lib/core/i18n/app_en.arb                        # ~95 new keys
lib/core/i18n/app_tl.arb                        # ~95 new keys (Tagalog)
lib/generated/l10n/*                            # regenerated
lib/features/survey/building_form/presentation/building_form.dart  # embed OlpSection
lib/core/router/app_router.dart                 # add /feature/:featureId/olp/result
```

### Test files

```
test/core/db/migration_v3_to_v4_test.dart
test/features/survey/olp_survey/domain/olp_rubric_test.dart
test/features/survey/olp_survey/domain/olp_score_test.dart
test/features/survey/olp_survey/domain/olp_form_state_test.dart
test/features/survey/olp_survey/domain/olp_form_validator_test.dart
test/features/survey/olp_survey/data/household_survey_repository_test.dart
test/features/survey/olp_survey/presentation/olp_section_notifier_test.dart
test/features/survey/olp_survey/presentation/disclaimer_callout_test.dart
test/features/survey/olp_survey/presentation/scored_section_widget_test.dart
test/features/survey/olp_survey/presentation/score_footer_test.dart
test/features/survey/olp_survey/presentation/result/olp_result_screen_test.dart
```

---

### Task 1: Schema v3 → v4 (Drift table + migration + test)

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/tables/household_surveys.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/database.dart`
- Regenerate: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/db/database.g.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/db/migration_v3_to_v4_test.dart`

- [ ] **Step 1: Add the two new columns to the table**

Edit `lib/core/db/tables/household_surveys.dart`. Add these two columns after the existing `safetySuggestions` declaration (and before the `primaryKey` getter):

```dart
BoolColumn get homeownerAcknowledged =>
    boolean().withDefault(const Constant(false))();
DateTimeColumn get completedAt => dateTime().nullable()();
```

- [ ] **Step 2: Bump schemaVersion + extend onUpgrade**

In `lib/core/db/database.dart`, find `int get schemaVersion => 3;` and change to:

```dart
@override
int get schemaVersion => 4;
```

Find the `MigrationStrategy` block. Append (preserving all existing `if (from < N)` branches) a new branch:

```dart
if (from < 4) {
  await m.addColumn(householdSurveys, householdSurveys.homeownerAcknowledged);
  await m.addColumn(householdSurveys, householdSurveys.completedAt);
}
```

- [ ] **Step 3: Regenerate Drift codegen**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && dart run build_runner build --delete-conflicting-outputs
```

Expected: `Succeeded` line at end. `database.g.dart` updated.

- [ ] **Step 4: Write the failing migration test**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/test/core/db/migration_v3_to_v4_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 4', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(4));
  });

  test('household_surveys has homeowner_acknowledged + completed_at on a fresh install',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.householdSurveys).insert(
          HouseholdSurveysCompanion.insert(submissionId: 's1'),
        );

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.homeownerAcknowledged, isFalse);
    expect(row.completedAt, isNull);
  });
}
```

- [ ] **Step 5: Run the test**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/db/migration_v3_to_v4_test.dart
```

Expected: `All tests passed!` (2 tests).

- [ ] **Step 6: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/db/ test/core/db/
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/db/ test/core/db/migration_v3_to_v4_test.dart && git commit -m "$(cat <<'EOF'
feat(db): schema v3 → v4 — household_surveys gains acknowledged + completed_at

Adds homeowner_acknowledged (bool default false) and completed_at
(datetime nullable) to household_surveys. Drift onUpgrade branch
runs the additive migration. Existing rows get safe defaults.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Supabase migration 004

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/supabase/migrations/004_household_surveys_acknowledged_completed.sql`

- [ ] **Step 1: Write the SQL migration**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/supabase/migrations/004_household_surveys_acknowledged_completed.sql`:

```sql
-- Phase 3b: add homeowner acknowledgement + completion timestamp to household_surveys.
alter table public.household_surveys
  add column homeowner_acknowledged boolean not null default false;
alter table public.household_surveys
  add column completed_at timestamptz null;
```

- [ ] **Step 2: Push the migration to Supabase**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && supabase db push
```

Expected: `Applying migration 004_household_surveys_acknowledged_completed.sql...` then `Done.`. If `supabase db push` is not configured / errors out (e.g., no linked project), STOP and report — local-only Drift schema works for tests, but production sync will fail later.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add supabase/migrations/004_household_surveys_acknowledged_completed.sql && git commit -m "$(cat <<'EOF'
feat(supabase): migration 004 — household_surveys.acknowledged + completed_at

Mirrors local Drift v4 schema bump.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Phase 3b ARB keys (en + tl) + regenerate l10n

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/i18n/app_en.arb`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/i18n/app_tl.arb`
- Regenerate: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/generated/l10n/*`

- [ ] **Step 1: Append all ~95 keys to `app_en.arb`** (insert before the closing `}`, with a leading comma after the previous last entry)

```json
,
  "olpSectionTitle": "OLP household survey · Optional",
  "olpSectionA": "Construction details (descriptive)",
  "olpSectionB": "Kaayusan ng Tahanan",
  "olpSectionC": "Koneksyong Elektrikal",
  "olpSectionD": "Kusina",
  "olpSectionE": "Daanan o Labasan sa Bahay",
  "olpDisclaimerVoluntary": "This survey is voluntary, not mandatory.",
  "olpDisclaimerSurveyorRole": "The surveyor is a guide, not an enforcer.",
  "olpDisclaimerNoSelling": "The surveyor cannot sell or recommend fire extinguishers.",
  "olpHomeownerAgreesLabel": "Homeowner agrees",
  "olpScoreLabel": "Score",
  "olpScoreFraction": "{score} / {max}",
  "@olpScoreFraction": {"placeholders": {"score": {}, "max": {}}},
  "olpViewBreakdown": "View breakdown →",
  "olpMarkComplete": "Mark survey complete",
  "olpAcknowledgmentRequiredTooltip": "Homeowner must agree first",
  "olpResultTitle": "Survey result",
  "olpResultSurveyComplete": "Survey complete",
  "olpClassLigtas": "Ligtas ang Iyong Tahanan",
  "olpClassMayroong": "Mayroong Dapat Ipangamba",
  "olpClassLabis": "Labis na Mapanganib",
  "olpElementRoof": "Roof",
  "olpElementCeiling": "Ceiling",
  "olpElementRoomPartitions": "Room partitions",
  "olpElementTrusses": "Trusses",
  "olpElementWindows": "Windows",
  "olpElementCorridorWalls": "Corridor walls",
  "olpElementColumns": "Columns",
  "olpElementMainDoor": "Main door",
  "olpElementExteriorWall": "Exterior wall",
  "olpElementBeams": "Beams",
  "olpMaterialKahoy": "Wood",
  "olpMaterialSemento": "Concrete",
  "olpMaterialBakal": "Steel",
  "olpMaterialOthers": "Other",
  "olpMaterialOthersHint": "Specify other material",
  "olpItemB01Statement": "No accumulated trash inside the home",
  "olpItemB01Suggestion": "Dispose of trash in proper bins daily",
  "olpItemB02Statement": "No deep-stored materials in walkways",
  "olpItemB02Suggestion": "Move items to separate storage to keep walkways clear",
  "olpItemB03Statement": "Clothes are not piled on the bed",
  "olpItemB03Suggestion": "Store clothes in a closet or cabinet",
  "olpItemB04Statement": "Kitchen items are arranged properly",
  "olpItemB04Suggestion": "Add a rack or shelf for kitchen utensils",
  "olpItemB05Statement": "Doorways are not blocked",
  "olpItemB05Suggestion": "Move items blocking doorways",
  "olpItemB06Statement": "Windows are not stuck or sealed shut",
  "olpItemB06Suggestion": "Inspect and repair windows so they open easily",
  "olpItemB07Statement": "No piles of paper or cardboard inside",
  "olpItemB07Suggestion": "Recycle or dispose of old paper and cardboard",
  "olpItemB08Statement": "Long-stored items are properly stored",
  "olpItemB08Suggestion": "Use cabinets or storage boxes",
  "olpItemB09Statement": "No trash material under the house",
  "olpItemB09Suggestion": "Clean under the house regularly",
  "olpItemB10Statement": "There is a designated trash container",
  "olpItemB10Suggestion": "Place a trash container outside the house",
  "olpItemB11Statement": "No cardboard or items piled inside cabinets",
  "olpItemB11Suggestion": "Organize items inside cabinets",
  "olpItemB12Statement": "The LPG tank has a rubber hose",
  "olpItemB12Suggestion": "Buy a rubber hose for the LPG tank",
  "olpItemB13Statement": "Fire prevention is properly prepared",
  "olpItemB13Suggestion": "Check fire prevention measures",
  "olpItemB14Statement": "No bottles of alcohol or paint stored in the room",
  "olpItemB14Suggestion": "Move flammable liquids out of the room",
  "olpItemB15Statement": "There is a posted evacuation plan in case of fire",
  "olpItemB15Suggestion": "Create and post an evacuation plan",
  "olpItemC10Statement": "There is a circuit breaker",
  "olpItemC10Suggestion": "Install a circuit breaker on the main electrical line",
  "olpItemC11Statement": "The electrical panel has a cover",
  "olpItemC11Suggestion": "Install a cover on the electrical panel",
  "olpItemC12Statement": "Junction boxes have covers",
  "olpItemC12Suggestion": "Install covers on all junction boxes",
  "olpItemC13Statement": "Outlets have covers",
  "olpItemC13Suggestion": "Install covers on all outlets",
  "olpItemC14Statement": "Switches have covers",
  "olpItemC14Suggestion": "Install covers on all switches",
  "olpItemC15Statement": "Extension cords are used properly",
  "olpItemC15Suggestion": "Avoid overloading extension cords",
  "olpItemC16Statement": "No exposed electrical wires",
  "olpItemC16Suggestion": "Cover all exposed wires",
  "olpItemC17Statement": "Outlets and switches are in good condition",
  "olpItemC17Suggestion": "Replace damaged outlets and switches",
  "olpItemC18Statement": "Correct wire gauge is used",
  "olpItemC18Suggestion": "Consult an electrician for the correct gauge",
  "olpItemD25Statement": "No water leaks in the kitchen",
  "olpItemD25Suggestion": "Repair leaking pipes",
  "olpItemD26Statement": "No flammable items near the stove",
  "olpItemD26Suggestion": "Move flammable items away from the stove",
  "olpItemD27Statement": "Kitchen equipment is regularly inspected",
  "olpItemD27Suggestion": "Conduct weekly checks of stove and LPG",
  "olpItemD28Statement": "Sufficient smoke ventilation",
  "olpItemD28Suggestion": "Install an exhaust or add a window",
  "olpItemD29Statement": "Candles and lighters stored in proper containers",
  "olpItemD29Suggestion": "Designate containers for candles and lighters",
  "olpItemE30Statement": "Doorways and windows are clear and unblocked",
  "olpItemE30Suggestion": "Move items that are blocking",
  "olpItemE31Statement": "No dry leaves around the house",
  "olpItemE31Suggestion": "Clear dry leaves regularly",
  "olpItemE32Statement": "Easy escape during fire",
  "olpItemE32Suggestion": "Practice evacuation with family",
  "olpItemE33Statement": "The house is close to a road",
  "olpItemE33Suggestion": "Ensure easy access to a public road",
  "olpItemE34Statement": "Interior pathways are well-kept",
  "olpItemE34Suggestion": "Clean interior pathways",
  "olpItemE35Statement": "Adequate interior lighting",
  "olpItemE35Suggestion": "Install additional lighting if needed"
```

- [ ] **Step 2: Append the same key set to `app_tl.arb` with Tagalog values**

```json
,
  "olpSectionTitle": "Survey ng pamilya OLP · Opsyonal",
  "olpSectionA": "Detalye ng konstruksyon (deskriptibo)",
  "olpSectionB": "Kaayusan ng Tahanan",
  "olpSectionC": "Koneksyong Elektrikal",
  "olpSectionD": "Kusina",
  "olpSectionE": "Daanan o Labasan sa Bahay",
  "olpDisclaimerVoluntary": "Ang sarbey na ito ay boluntaryo, hindi sapilitan.",
  "olpDisclaimerSurveyorRole": "Ang surveyor ay isang gabay, hindi tagapagpatupad.",
  "olpDisclaimerNoSelling": "Hindi maaaring magbenta o magrekomenda ng fire extinguisher ang surveyor.",
  "olpHomeownerAgreesLabel": "Pumayag ang nakatira",
  "olpScoreLabel": "Iskor",
  "olpScoreFraction": "{score} / {max}",
  "@olpScoreFraction": {"placeholders": {"score": {}, "max": {}}},
  "olpViewBreakdown": "Tingnan ang detalye →",
  "olpMarkComplete": "Markahan ang sarbey bilang kompleto",
  "olpAcknowledgmentRequiredTooltip": "Kailangan munang pumayag ang nakatira",
  "olpResultTitle": "Resulta ng sarbey",
  "olpResultSurveyComplete": "Kompleto na ang sarbey",
  "olpClassLigtas": "Ligtas ang Iyong Tahanan",
  "olpClassMayroong": "Mayroong Dapat Ipangamba",
  "olpClassLabis": "Labis na Mapanganib",
  "olpElementRoof": "Bubong",
  "olpElementCeiling": "Kisame",
  "olpElementRoomPartitions": "Mga partisyon ng silid",
  "olpElementTrusses": "Mga troso",
  "olpElementWindows": "Mga bintana",
  "olpElementCorridorWalls": "Pader ng pasilyo",
  "olpElementColumns": "Mga haligi",
  "olpElementMainDoor": "Pangunahing pintuan",
  "olpElementExteriorWall": "Panlabas na pader",
  "olpElementBeams": "Mga sako",
  "olpMaterialKahoy": "Kahoy",
  "olpMaterialSemento": "Semento",
  "olpMaterialBakal": "Bakal",
  "olpMaterialOthers": "Iba pa",
  "olpMaterialOthersHint": "Ilarawan ang ibang materyales",
  "olpItemB01Statement": "Walang nakatambak na basura sa loob ng bahay",
  "olpItemB01Suggestion": "Itapon ang basura sa tamang lalagyan araw-araw",
  "olpItemB02Statement": "Walang nakaimbak na malalalim na materyales sa daanan",
  "olpItemB02Suggestion": "Ilipat ang mga gamit sa hiwalay na lalagyan upang malinis ang daanan",
  "olpItemB03Statement": "Hindi nakatambak ang mga damit sa kama",
  "olpItemB03Suggestion": "Itago ang damit sa armaryo o cabinet",
  "olpItemB04Statement": "Maayos ang pagkakahanay ng mga gamit-pang kusina",
  "olpItemB04Suggestion": "Magdagdag ng rack o shelf para sa mga gamit-pang kusina",
  "olpItemB05Statement": "May espasyo na hindi nakaharang sa mga pintuan",
  "olpItemB05Suggestion": "Ilipat ang mga gamit na nakaharang sa pintuan",
  "olpItemB06Statement": "Hindi nakaipit o nakasara ang mga bintana",
  "olpItemB06Suggestion": "Suriin at ayusin ang mga bintana upang madaling buksan",
  "olpItemB07Statement": "Walang nakatambak na papel o karton sa loob",
  "olpItemB07Suggestion": "I-recycle o itapon ang lumang papel at karton",
  "olpItemB08Statement": "Maayos ang pagkakatago ng mga gamit-na-malalim",
  "olpItemB08Suggestion": "Gumamit ng mga aparador o storage box",
  "olpItemB09Statement": "Walang basurang materyal sa silong",
  "olpItemB09Suggestion": "Linisin nang regular ang silong",
  "olpItemB10Statement": "May nakatakdang lalagyan ng basura",
  "olpItemB10Suggestion": "Maglagay ng lalagyan ng basura sa labas ng bahay",
  "olpItemB11Statement": "Walang nakatambak na karton at gamit sa loob ng kabinet",
  "olpItemB11Suggestion": "Ayusin ang mga gamit sa loob ng kabinet",
  "olpItemB12Statement": "May rubber hose ang tubig sa silindrong gas (LPG)",
  "olpItemB12Suggestion": "Bumili ng rubber hose para sa LPG",
  "olpItemB13Statement": "Maayos ang pagkakahanda sa pag-iwas sa apoy",
  "olpItemB13Suggestion": "Suriin ang mga panangga laban sa apoy",
  "olpItemB14Statement": "Walang nakaimbak na bote ng alkohol o pintura sa silid",
  "olpItemB14Suggestion": "Ilipat ang mga nasusunog na likido sa labas ng silid",
  "olpItemB15Statement": "May nakapostang plano ng paglabas kung magkasunog",
  "olpItemB15Suggestion": "Gumawa at i-post ang plano ng paglabas",
  "olpItemC10Statement": "May circuit breaker",
  "olpItemC10Suggestion": "Magkabit ng circuit breaker sa main electrical line",
  "olpItemC11Statement": "May takip ang electrical panel",
  "olpItemC11Suggestion": "Magkabit ng takip sa electrical panel",
  "olpItemC12Statement": "May takip ang junction boxes",
  "olpItemC12Suggestion": "Magkabit ng takip sa lahat ng junction boxes",
  "olpItemC13Statement": "May takip ang outlets",
  "olpItemC13Suggestion": "Magkabit ng takip sa lahat ng outlets",
  "olpItemC14Statement": "May takip ang switches",
  "olpItemC14Suggestion": "Magkabit ng takip sa lahat ng switches",
  "olpItemC15Statement": "Tama ang paggamit ng extension cord",
  "olpItemC15Suggestion": "Iwasan ang sobrang load sa extension cord",
  "olpItemC16Statement": "Walang exposed na electrical wires",
  "olpItemC16Suggestion": "Takipan ang lahat ng exposed wires",
  "olpItemC17Statement": "Maayos ang kondisyon ng outlets at switches",
  "olpItemC17Suggestion": "Palitan ang sirang outlets at switches",
  "olpItemC18Statement": "Tamang gauge ng wire ang ginagamit",
  "olpItemC18Suggestion": "Sumangguni sa elektrisyan para sa tamang gauge",
  "olpItemD25Statement": "Walang water leak sa kusina",
  "olpItemD25Suggestion": "Ayusin ang mga tubo na may leak",
  "olpItemD26Statement": "Walang nasusunog na bagay malapit sa kalan",
  "olpItemD26Suggestion": "Ilayo ang mga nasusunog na bagay sa kalan",
  "olpItemD27Statement": "Sinusuri nang regular ang gamit-kusina",
  "olpItemD27Suggestion": "Magkaroon ng lingguhang pagsusuri sa kalan at LPG",
  "olpItemD28Statement": "Sapat ang bentilasyon para sa usok",
  "olpItemD28Suggestion": "Magkabit ng exhaust o magdagdag ng bintana",
  "olpItemD29Statement": "Naitatago ang kandila at lighter sa tamang lalagyan",
  "olpItemD29Suggestion": "Maglagay ng nakatakdang lalagyan para sa kandila at lighter",
  "olpItemE30Statement": "Malinis at hindi nakaharang ang mga pintuan at bintana",
  "olpItemE30Suggestion": "Ilipat ang mga gamit na nakaharang",
  "olpItemE31Statement": "Walang tuyong dahon sa paligid ng bahay",
  "olpItemE31Suggestion": "Linisin ang mga tuyong dahon nang regular",
  "olpItemE32Statement": "Madaling makalabas kung magkasunog",
  "olpItemE32Suggestion": "Mag-ehersisyo ng paglabas kasama ang pamilya",
  "olpItemE33Statement": "Malapit ang bahay sa daan",
  "olpItemE33Suggestion": "Tiyakin na may madaling daan papunta sa pampublikong kalsada",
  "olpItemE34Statement": "Maayos ang panloob na daanan",
  "olpItemE34Suggestion": "Linisin ang mga daanan sa loob ng bahay",
  "olpItemE35Statement": "Sapat ang ilaw sa loob ng bahay",
  "olpItemE35Suggestion": "Magkabit ng karagdagang ilaw kung kailangan"
```

- [ ] **Step 3: Regenerate l10n classes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter gen-l10n
```

Expected: regenerates `lib/generated/l10n/app_localizations.dart` + per-locale files with no errors.

- [ ] **Step 4: Verify analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/i18n/ lib/generated/l10n/
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/core/i18n/ lib/generated/l10n/ && git commit -m "$(cat <<'EOF'
feat(i18n): Phase 3b ARB keys for OLP rubric + UI chrome

~95 keys covering 35 item statements + 35 paired suggestions, 10
construction elements, 4 materials, 3 classification labels, 3
disclaimer strings, and result-screen UI chrome. Both en + tl ARBs
updated; l10n classes regenerated. Item statements + suggestions are
draft (PRD risk #1) and will swap as a config-only change pre-pilot.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `OlpRubric` static config + tests

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_rubric.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/domain/olp_rubric_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rubric has exactly 35 items', () {
    expect(OlpRubric.items.length, 35);
  });

  test('section counts match the spec (B=15, C=9, D=5, E=6)', () {
    final byCount = <OlpSection, int>{};
    for (final item in OlpRubric.items) {
      byCount[item.section] = (byCount[item.section] ?? 0) + 1;
    }
    expect(byCount[OlpSection.b], 15);
    expect(byCount[OlpSection.c], 9);
    expect(byCount[OlpSection.d], 5);
    expect(byCount[OlpSection.e], 6);
  });

  test('all item codes are unique', () {
    final codes = OlpRubric.items.map((i) => i.code).toSet();
    expect(codes.length, 35);
  });

  test('thresholds are 12 and 24', () {
    expect(OlpRubric.mayroongThreshold, 12);
    expect(OlpRubric.ligtasThreshold, 24);
  });

  test('there are 10 construction elements', () {
    expect(OlpRubric.constructionElements.length, 10);
  });

  test('there are 4 materials', () {
    expect(OlpRubric.materials, ['kahoy', 'semento', 'bakal', 'others']);
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_rubric_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_rubric.dart`:

```dart
enum OlpSection { b, c, d, e }

class OlpRubricItem {
  const OlpRubricItem({
    required this.code,
    required this.section,
    required this.statementKey,
    required this.suggestionKey,
  });
  final String code;
  final OlpSection section;
  final String statementKey;
  final String suggestionKey;
}

class OlpRubric {
  // PRD risk #2: 12/23 boundary unverified — verify against printed
  // CFPP Rev.00 (07.27.23) form before pilot.
  static const ligtasThreshold = 24;
  static const mayroongThreshold = 12;

  static const items = <OlpRubricItem>[
    // Section B — 15 draft items (PRD risk #1: verify before pilot)
    OlpRubricItem(code: 'B-01', section: OlpSection.b, statementKey: 'olpItemB01Statement', suggestionKey: 'olpItemB01Suggestion'),
    OlpRubricItem(code: 'B-02', section: OlpSection.b, statementKey: 'olpItemB02Statement', suggestionKey: 'olpItemB02Suggestion'),
    OlpRubricItem(code: 'B-03', section: OlpSection.b, statementKey: 'olpItemB03Statement', suggestionKey: 'olpItemB03Suggestion'),
    OlpRubricItem(code: 'B-04', section: OlpSection.b, statementKey: 'olpItemB04Statement', suggestionKey: 'olpItemB04Suggestion'),
    OlpRubricItem(code: 'B-05', section: OlpSection.b, statementKey: 'olpItemB05Statement', suggestionKey: 'olpItemB05Suggestion'),
    OlpRubricItem(code: 'B-06', section: OlpSection.b, statementKey: 'olpItemB06Statement', suggestionKey: 'olpItemB06Suggestion'),
    OlpRubricItem(code: 'B-07', section: OlpSection.b, statementKey: 'olpItemB07Statement', suggestionKey: 'olpItemB07Suggestion'),
    OlpRubricItem(code: 'B-08', section: OlpSection.b, statementKey: 'olpItemB08Statement', suggestionKey: 'olpItemB08Suggestion'),
    OlpRubricItem(code: 'B-09', section: OlpSection.b, statementKey: 'olpItemB09Statement', suggestionKey: 'olpItemB09Suggestion'),
    OlpRubricItem(code: 'B-10', section: OlpSection.b, statementKey: 'olpItemB10Statement', suggestionKey: 'olpItemB10Suggestion'),
    OlpRubricItem(code: 'B-11', section: OlpSection.b, statementKey: 'olpItemB11Statement', suggestionKey: 'olpItemB11Suggestion'),
    OlpRubricItem(code: 'B-12', section: OlpSection.b, statementKey: 'olpItemB12Statement', suggestionKey: 'olpItemB12Suggestion'),
    OlpRubricItem(code: 'B-13', section: OlpSection.b, statementKey: 'olpItemB13Statement', suggestionKey: 'olpItemB13Suggestion'),
    OlpRubricItem(code: 'B-14', section: OlpSection.b, statementKey: 'olpItemB14Statement', suggestionKey: 'olpItemB14Suggestion'),
    OlpRubricItem(code: 'B-15', section: OlpSection.b, statementKey: 'olpItemB15Statement', suggestionKey: 'olpItemB15Suggestion'),
    // Section C — 9 items (codes 10–18 per PRD §4)
    OlpRubricItem(code: 'C-10', section: OlpSection.c, statementKey: 'olpItemC10Statement', suggestionKey: 'olpItemC10Suggestion'),
    OlpRubricItem(code: 'C-11', section: OlpSection.c, statementKey: 'olpItemC11Statement', suggestionKey: 'olpItemC11Suggestion'),
    OlpRubricItem(code: 'C-12', section: OlpSection.c, statementKey: 'olpItemC12Statement', suggestionKey: 'olpItemC12Suggestion'),
    OlpRubricItem(code: 'C-13', section: OlpSection.c, statementKey: 'olpItemC13Statement', suggestionKey: 'olpItemC13Suggestion'),
    OlpRubricItem(code: 'C-14', section: OlpSection.c, statementKey: 'olpItemC14Statement', suggestionKey: 'olpItemC14Suggestion'),
    OlpRubricItem(code: 'C-15', section: OlpSection.c, statementKey: 'olpItemC15Statement', suggestionKey: 'olpItemC15Suggestion'),
    OlpRubricItem(code: 'C-16', section: OlpSection.c, statementKey: 'olpItemC16Statement', suggestionKey: 'olpItemC16Suggestion'),
    OlpRubricItem(code: 'C-17', section: OlpSection.c, statementKey: 'olpItemC17Statement', suggestionKey: 'olpItemC17Suggestion'),
    OlpRubricItem(code: 'C-18', section: OlpSection.c, statementKey: 'olpItemC18Statement', suggestionKey: 'olpItemC18Suggestion'),
    // Section D — 5 items (codes 25–29)
    OlpRubricItem(code: 'D-25', section: OlpSection.d, statementKey: 'olpItemD25Statement', suggestionKey: 'olpItemD25Suggestion'),
    OlpRubricItem(code: 'D-26', section: OlpSection.d, statementKey: 'olpItemD26Statement', suggestionKey: 'olpItemD26Suggestion'),
    OlpRubricItem(code: 'D-27', section: OlpSection.d, statementKey: 'olpItemD27Statement', suggestionKey: 'olpItemD27Suggestion'),
    OlpRubricItem(code: 'D-28', section: OlpSection.d, statementKey: 'olpItemD28Statement', suggestionKey: 'olpItemD28Suggestion'),
    OlpRubricItem(code: 'D-29', section: OlpSection.d, statementKey: 'olpItemD29Statement', suggestionKey: 'olpItemD29Suggestion'),
    // Section E — 6 items (codes 30–35)
    OlpRubricItem(code: 'E-30', section: OlpSection.e, statementKey: 'olpItemE30Statement', suggestionKey: 'olpItemE30Suggestion'),
    OlpRubricItem(code: 'E-31', section: OlpSection.e, statementKey: 'olpItemE31Statement', suggestionKey: 'olpItemE31Suggestion'),
    OlpRubricItem(code: 'E-32', section: OlpSection.e, statementKey: 'olpItemE32Statement', suggestionKey: 'olpItemE32Suggestion'),
    OlpRubricItem(code: 'E-33', section: OlpSection.e, statementKey: 'olpItemE33Statement', suggestionKey: 'olpItemE33Suggestion'),
    OlpRubricItem(code: 'E-34', section: OlpSection.e, statementKey: 'olpItemE34Statement', suggestionKey: 'olpItemE34Suggestion'),
    OlpRubricItem(code: 'E-35', section: OlpSection.e, statementKey: 'olpItemE35Statement', suggestionKey: 'olpItemE35Suggestion'),
  ];

  static const constructionElements = <String>[
    'roof', 'ceiling', 'roomPartitions', 'trusses', 'windows',
    'corridorWalls', 'columns', 'mainDoor', 'exteriorWall', 'beams',
  ];

  static const materials = <String>['kahoy', 'semento', 'bakal', 'others'];
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_rubric_test.dart
```

Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/domain/olp_rubric.dart test/features/survey/olp_survey/domain/olp_rubric_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): static OlpRubric — 35 items + 12/24 thresholds + 10 elements

Data-driven rubric config keyed by stable item codes (B-01 … E-35).
Section B drafted as 15 plausible "Kaayusan ng Tahanan" items (PRD
risk #1 — verify with BFP partner pre-pilot). Sections C/D/E draw
from BFP fire-safety themes per PRD numbering.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `ConstructionDetail` + `OlpFormState` value classes

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/construction_details.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_form_state.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/domain/olp_form_state_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default state has empty maps + acknowledged=false + no completedAt', () {
    const s = OlpFormState(submissionId: 's1');
    expect(s.checkedCodes, isEmpty);
    expect(s.constructionDetails, isEmpty);
    expect(s.homeownerAcknowledged, isFalse);
    expect(s.completedAt, isNull);
  });

  test('copyWith updates only the named fields', () {
    const s = OlpFormState(submissionId: 's1');
    final s2 = s.copyWith(homeownerAcknowledged: true);
    expect(s2.homeownerAcknowledged, isTrue);
    expect(s2.checkedCodes, isEmpty);
    expect(s2.submissionId, 's1');
  });

  test('checkedCodes replaces wholesale', () {
    const s = OlpFormState(submissionId: 's1', checkedCodes: {'B-01'});
    final s2 = s.copyWith(checkedCodes: {'C-10', 'C-11'});
    expect(s2.checkedCodes, {'C-10', 'C-11'});
  });

  test('clearCompletedAt resets the timestamp', () {
    final s = OlpFormState(submissionId: 's1', completedAt: DateTime(2026));
    final s2 = s.copyWith(clearCompletedAt: true);
    expect(s2.completedAt, isNull);
  });

  test('ConstructionDetail captures material + materialOther', () {
    const d = ConstructionDetail(material: 'others', materialOther: 'galvanized iron');
    expect(d.material, 'others');
    expect(d.materialOther, 'galvanized iron');
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_form_state_test.dart
```

Expected: FAIL — files don't exist.

- [ ] **Step 3: Implement `ConstructionDetail`**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/construction_details.dart`:

```dart
class ConstructionDetail {
  const ConstructionDetail({required this.material, this.materialOther});
  final String material;
  final String? materialOther;
}
```

- [ ] **Step 4: Implement `OlpFormState`**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_form_state.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';

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
  }) {
    return OlpFormState(
      submissionId: submissionId,
      checkedCodes: checkedCodes ?? this.checkedCodes,
      constructionDetails: constructionDetails ?? this.constructionDetails,
      homeownerAcknowledged:
          homeownerAcknowledged ?? this.homeownerAcknowledged,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
```

- [ ] **Step 5: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_form_state_test.dart
```

Expected: `All tests passed!` (5 tests).

- [ ] **Step 6: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/domain/construction_details.dart lib/features/survey/olp_survey/domain/olp_form_state.dart test/features/survey/olp_survey/domain/olp_form_state_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): OlpFormState + ConstructionDetail value classes

Immutable state container with copyWith + clearCompletedAt clear-flag,
mirroring BuildingFormState/RoadFormState patterns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `OlpClassification` + `computeOlpScore` + `classify` (pure scoring)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_classification.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_score.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/domain/olp_score_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classify', () {
    test('score 0 → LabisNaMapanganib', () {
      expect(classify(0), isA<LabisNaMapanganib>());
    });
    test('score 11 → LabisNaMapanganib', () {
      expect(classify(11), isA<LabisNaMapanganib>());
    });
    test('score 12 → MayroongDapatIpangamba', () {
      expect(classify(12), isA<MayroongDapatIpangamba>());
    });
    test('score 23 → MayroongDapatIpangamba', () {
      expect(classify(23), isA<MayroongDapatIpangamba>());
    });
    test('score 24 → Ligtas', () {
      expect(classify(24), isA<Ligtas>());
    });
    test('score 35 → Ligtas', () {
      expect(classify(35), isA<Ligtas>());
    });
  });

  group('computeOlpScore', () {
    test('empty state → score 0, all 35 unchecked, LabisNaMapanganib', () {
      const state = OlpFormState(submissionId: 's1');
      final r = computeOlpScore(state);
      expect(r.totalScore, 0);
      expect(r.uncheckedItems.length, 35);
      expect(r.classification, isA<LabisNaMapanganib>());
      expect(r.sectionScores[OlpSection.b], 0);
      expect(r.sectionScores[OlpSection.c], 0);
      expect(r.sectionScores[OlpSection.d], 0);
      expect(r.sectionScores[OlpSection.e], 0);
    });

    test('all 35 checked → score 35, no unchecked, Ligtas', () {
      final allCodes = OlpRubric.items.map((i) => i.code).toSet();
      final state = OlpFormState(submissionId: 's1', checkedCodes: allCodes);
      final r = computeOlpScore(state);
      expect(r.totalScore, 35);
      expect(r.uncheckedItems, isEmpty);
      expect(r.classification, isA<Ligtas>());
      expect(r.sectionScores[OlpSection.b], 15);
      expect(r.sectionScores[OlpSection.c], 9);
      expect(r.sectionScores[OlpSection.d], 5);
      expect(r.sectionScores[OlpSection.e], 6);
    });

    test('partial checked → known per-section breakdown', () {
      const state = OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'B-02', 'C-10', 'D-25', 'E-30'},
      );
      final r = computeOlpScore(state);
      expect(r.totalScore, 5);
      expect(r.sectionScores[OlpSection.b], 2);
      expect(r.sectionScores[OlpSection.c], 1);
      expect(r.sectionScores[OlpSection.d], 1);
      expect(r.sectionScores[OlpSection.e], 1);
      expect(r.classification, isA<LabisNaMapanganib>());
      expect(r.uncheckedItems.length, 30);
    });

    test('unknown codes in checkedCodes are silently ignored', () {
      const state = OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'NOT-A-CODE', 'C-10'},
      );
      final r = computeOlpScore(state);
      expect(r.totalScore, 2); // only B-01 and C-10 count
    });
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_score_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement `OlpClassification`**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_classification.dart`:

```dart
sealed class OlpClassification {
  const OlpClassification();
}

class Ligtas extends OlpClassification {
  const Ligtas();
}

class MayroongDapatIpangamba extends OlpClassification {
  const MayroongDapatIpangamba();
}

class LabisNaMapanganib extends OlpClassification {
  const LabisNaMapanganib();
}
```

- [ ] **Step 4: Implement `OlpScoreResult` + `computeOlpScore` + `classify`**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_score.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';

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
  final sectionScores = <OlpSection, int>{
    for (final s in OlpSection.values) s: 0,
  };
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

- [ ] **Step 5: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_score_test.dart
```

Expected: `All tests passed!` (10 tests).

- [ ] **Step 6: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/domain/olp_classification.dart lib/features/survey/olp_survey/domain/olp_score.dart test/features/survey/olp_survey/domain/olp_score_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): OlpClassification sealed + computeOlpScore + classify

Pure scoring fn iterates the 35-item rubric, counts checked codes,
groups by section, and classifies by 12/24 thresholds. Unknown codes
in state.checkedCodes are silently ignored (defensive).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `OlpFormValidator` (pure finalization gate)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_form_validator.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/domain/olp_form_validator_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('homeownerAcknowledged=false → cannot mark complete', () {
    const s = OlpFormState(submissionId: 's1');
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isFalse);
    expect(r.fieldErrors.keys, contains('homeownerAcknowledged'));
  });

  test('homeownerAcknowledged=true → can mark complete (no other gates)', () {
    const s = OlpFormState(submissionId: 's1', homeownerAcknowledged: true);
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isTrue);
    expect(r.fieldErrors, isEmpty);
  });

  test('partial completion does not block finalize', () {
    const s = OlpFormState(
      submissionId: 's1',
      homeownerAcknowledged: true,
      checkedCodes: {'B-01'},
    );
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isTrue);
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_form_validator_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/domain/olp_form_validator.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';

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

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/domain/olp_form_validator_test.dart
```

Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/domain/olp_form_validator.dart test/features/survey/olp_survey/domain/olp_form_validator_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): OlpFormValidator — homeownerAcknowledged gates finalization

Pure validator. canMarkComplete is true iff homeownerAcknowledged is
true. Section A incompleteness is a warning per PRD §9, not surfaced
as a blocker.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `HouseholdSurveyRepository` (CRUD + JSON pack/unpack)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/data/household_survey_repository.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/data/household_survey_repository_test.dart`

### Phase 2/3a gotchas to remember

1. **FK chain**: tests must seed `assignments` → `features` → `submissions` BEFORE inserting `household_surveys`.
2. **`SubmissionsCompanion.insert` does NOT take `enumeratorId`** — the column is `submittedBy` (nullable). Required positional fields: `id`, `featureId`, `createdAt`, `updatedAt`.
3. **Drift `isNotNull`/`isNull` SQL helpers collide with `flutter_test` matchers.** If you import `package:drift/drift.dart` in a TEST file, hide them: `import 'package:drift/drift.dart' hide isNotNull, isNull;`.

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HouseholdSurveyRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = HouseholdSurveyRepository(db);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  test('upsert round-trips a fully populated state', () async {
    final state = OlpFormState(
      submissionId: 's1',
      checkedCodes: const {'B-01', 'C-10', 'D-25', 'E-30'},
      constructionDetails: const {
        'roof': ConstructionDetail(material: 'kahoy'),
        'mainDoor': ConstructionDetail(material: 'others', materialOther: 'aluminum'),
      },
      homeownerAcknowledged: true,
      completedAt: DateTime(2026, 4, 26, 12),
    );
    await repo.upsertForSubmission(
      state: state,
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const ['olpItemB02Suggestion', 'olpItemC11Suggestion'],
    );

    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNotNull);
    expect(loaded!.checkedCodes, {'B-01', 'C-10', 'D-25', 'E-30'});
    expect(loaded.constructionDetails['roof']?.material, 'kahoy');
    expect(loaded.constructionDetails['mainDoor']?.material, 'others');
    expect(loaded.constructionDetails['mainDoor']?.materialOther, 'aluminum');
    expect(loaded.homeownerAcknowledged, isTrue);
    expect(loaded.completedAt, DateTime(2026, 4, 26, 12));
  });

  test('upsert overwrites existing row', () async {
    await repo.upsertForSubmission(
      state: const OlpFormState(submissionId: 's1', checkedCodes: {'B-01'}),
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const [],
    );
    await repo.upsertForSubmission(
      state: const OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'B-02'},
        homeownerAcknowledged: true,
      ),
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const [],
    );
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded!.checkedCodes, {'B-01', 'B-02'});
    expect(loaded.homeownerAcknowledged, isTrue);
  });

  test('loadForSubmission returns null when no row exists', () async {
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNull);
  });

  test('decodeCheckedCodes handles empty + many', () {
    expect(HouseholdSurveyRepository.decodeCheckedCodes('{}'), isEmpty);
    expect(
      HouseholdSurveyRepository.decodeCheckedCodes('{"B-01":true,"B-02":true}'),
      {'B-01', 'B-02'},
    );
  });

  test('decodeConstructionDetails handles empty + populated', () {
    expect(
      HouseholdSurveyRepository.decodeConstructionDetails('{}'),
      isEmpty,
    );
    final m = HouseholdSurveyRepository.decodeConstructionDetails(
      '{"roof":{"material":"kahoy"},"mainDoor":{"material":"others","materialOther":"glass"}}',
    );
    expect(m['roof']?.material, 'kahoy');
    expect(m['mainDoor']?.materialOther, 'glass');
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/data/household_survey_repository_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/data/household_survey_repository.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';

class HouseholdSurveyRepository {
  HouseholdSurveyRepository(this._db);
  final AppDatabase _db;

  Future<void> upsertForSubmission({
    required OlpFormState state,
    required String lebelNgKahinaan,
    required List<String> safetySuggestionKeys,
  }) async {
    final byCheckedSection = _packCheckedBySection(state.checkedCodes);
    await _db.into(_db.householdSurveys).insertOnConflictUpdate(
          HouseholdSurveysCompanion.insert(
            submissionId: state.submissionId,
            constructionDetailsJson:
                Value(jsonEncode(_encodeConstruction(state.constructionDetails))),
            kaayusanJson: Value(jsonEncode(byCheckedSection[OlpSection.b] ?? {})),
            koneksyongElektrikalJson:
                Value(jsonEncode(byCheckedSection[OlpSection.c] ?? {})),
            kusinaJson: Value(jsonEncode(byCheckedSection[OlpSection.d] ?? {})),
            daananOLabasanJson:
                Value(jsonEncode(byCheckedSection[OlpSection.e] ?? {})),
            lebelNgKahinaan: Value(lebelNgKahinaan),
            safetySuggestions: Value(jsonEncode(safetySuggestionKeys)),
            homeownerAcknowledged: Value(state.homeownerAcknowledged),
            completedAt: Value(state.completedAt),
          ),
        );
  }

  Future<OlpFormState?> loadForSubmission(String submissionId) async {
    final row = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    if (row == null) return null;
    final checked = <String>{
      ...decodeCheckedCodes(row.kaayusanJson),
      ...decodeCheckedCodes(row.koneksyongElektrikalJson),
      ...decodeCheckedCodes(row.kusinaJson),
      ...decodeCheckedCodes(row.daananOLabasanJson),
    };
    return OlpFormState(
      submissionId: submissionId,
      checkedCodes: checked,
      constructionDetails: decodeConstructionDetails(row.constructionDetailsJson),
      homeownerAcknowledged: row.homeownerAcknowledged,
      completedAt: row.completedAt,
    );
  }

  Map<OlpSection, Map<String, bool>> _packCheckedBySection(
    Set<String> checkedCodes,
  ) {
    final out = <OlpSection, Map<String, bool>>{
      for (final s in OlpSection.values) s: <String, bool>{},
    };
    for (final item in OlpRubric.items) {
      if (checkedCodes.contains(item.code)) {
        out[item.section]![item.code] = true;
      }
    }
    return out;
  }

  Map<String, Map<String, dynamic>> _encodeConstruction(
    Map<String, ConstructionDetail> details,
  ) {
    return details.map((element, detail) {
      final m = <String, dynamic>{'material': detail.material};
      if (detail.materialOther != null) {
        m['materialOther'] = detail.materialOther;
      }
      return MapEntry(element, m);
    });
  }

  static Set<String> decodeCheckedCodes(String json) {
    try {
      final parsed = jsonDecode(json);
      if (parsed is! Map) return const {};
      return parsed.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toSet();
    } on Object {
      return const {};
    }
  }

  static Map<String, ConstructionDetail> decodeConstructionDetails(
    String json,
  ) {
    try {
      final parsed = jsonDecode(json);
      if (parsed is! Map) return const {};
      final out = <String, ConstructionDetail>{};
      parsed.forEach((key, value) {
        if (value is Map && value['material'] is String) {
          out[key.toString()] = ConstructionDetail(
            material: value['material'] as String,
            materialOther: value['materialOther'] as String?,
          );
        }
      });
      return out;
    } on Object {
      return const {};
    }
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/data/household_survey_repository_test.dart
```

Expected: `All tests passed!` (5 tests).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/data/household_survey_repository.dart test/features/survey/olp_survey/data/household_survey_repository_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): HouseholdSurveyRepository — upsert + load + JSON helpers

Packs checkedCodes by section into the four jsonb columns + serializes
ConstructionDetail to JSON for the construction_details column. Persists
lebel_ng_kahinaan + safety_suggestions on every upsert. Static decoders
exposed for unit tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: `OlpSectionNotifier` + providers (debounced autosave)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section_providers.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section_notifier.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/presentation/olp_section_notifier_test.dart`

### CRITICAL — schema gotcha

The `submissions` table column is `submittedBy` (nullable), NOT `enumeratorId`. Do NOT pass `enumeratorId` to `SubmissionsCompanion.insert`.

- [ ] **Step 1: Failing test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('debounced write lands after 500ms', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier);
    notifier.toggleItem('B-01');
    notifier.toggleItem('C-10');

    await Future<void>.delayed(const Duration(milliseconds: 600));

    final repo = HouseholdSurveyRepository(db);
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNotNull);
    expect(loaded!.checkedCodes, {'B-01', 'C-10'});
  });

  test('flushNow writes immediately + persists computed lebel + suggestions',
      () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier);
    notifier.toggleItem('B-01');
    await notifier.flushNow();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.lebelNgKahinaan, 'LabisNaMapanganib');
    // Suggestions list contains the 34 unchecked items' suggestion keys.
    expect(row.safetySuggestions, contains('olpItemB02Suggestion'));
  });

  test('setHomeownerAcknowledged toggles + persists', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier);
    notifier.setHomeownerAcknowledged(acknowledged: true);
    await notifier.flushNow();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.homeownerAcknowledged, isTrue);
  });

  test('markComplete sets completedAt and flushes', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier);
    await notifier.markComplete();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.completedAt, isNotNull);
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/olp_section_notifier_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement providers**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section_providers.dart`:

```dart
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final householdSurveyRepositoryProvider =
    Provider<HouseholdSurveyRepository>((ref) {
  return HouseholdSurveyRepository(ref.watch(appDatabaseProvider));
});

class OlpFormKey {
  const OlpFormKey({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;

  @override
  bool operator ==(Object other) =>
      other is OlpFormKey &&
      other.submissionId == submissionId &&
      other.featureId == featureId;

  @override
  int get hashCode => Object.hash(submissionId, featureId);
}

final olpSectionNotifierProvider = StateNotifierProvider.autoDispose
    .family<OlpSectionNotifier, OlpFormState, OlpFormKey>((ref, key) {
  return OlpSectionNotifier(
    submissionId: key.submissionId,
    featureId: key.featureId,
    repo: ref.watch(householdSurveyRepositoryProvider),
  );
});
```

- [ ] **Step 4: Implement notifier**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section_notifier.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpSectionNotifier extends StateNotifier<OlpFormState> {
  OlpSectionNotifier({
    required String submissionId,
    required this.featureId,
    required this.repo,
  }) : super(OlpFormState(submissionId: submissionId)) {
    _loadInitial();
  }

  final String featureId;
  final HouseholdSurveyRepository repo;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);

  Future<void> _loadInitial() async {
    final loaded = await repo.loadForSubmission(state.submissionId);
    if (loaded != null && mounted) state = loaded;
  }

  void toggleItem(String code) {
    final next = {...state.checkedCodes};
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    update((s) => s.copyWith(checkedCodes: next));
  }

  void setMaterial(String element, String material, {String? other}) {
    final next = {...state.constructionDetails};
    next[element] = ConstructionDetail(material: material, materialOther: other);
    update((s) => s.copyWith(constructionDetails: next));
  }

  void setHomeownerAcknowledged({required bool acknowledged}) {
    update((s) => s.copyWith(homeownerAcknowledged: acknowledged));
  }

  void update(OlpFormState Function(OlpFormState) mutate) {
    state = mutate(state);
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> markComplete() async {
    update((s) => s.copyWith(completedAt: DateTime.now()));
    await flushNow();
  }

  Future<void> _flush() async {
    try {
      final result = computeOlpScore(state);
      final lebelName = result.classification.runtimeType.toString();
      final suggestions =
          result.uncheckedItems.map((i) => i.suggestionKey).toList();
      await repo.upsertForSubmission(
        state: state,
        lebelNgKahinaan: lebelName,
        safetySuggestionKeys: suggestions,
      );
    } on Object {
      // Best-effort flush; swallow errors that race against db.close()
      // during provider container teardown in tests.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_flush());
    super.dispose();
  }
}
```

- [ ] **Step 5: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/olp_section_notifier_test.dart
```

Expected: `All tests passed!` (4 tests).

- [ ] **Step 6: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/olp_section_notifier.dart lib/features/survey/olp_survey/presentation/olp_section_providers.dart test/features/survey/olp_survey/presentation/olp_section_notifier_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): OlpSectionNotifier + providers — debounced autosave + markComplete

500ms debounce + flushNow + dispose-time best-effort flush. toggleItem,
setMaterial, setHomeownerAcknowledged are the public mutators. markComplete
sets completedAt and flushes immediately. _flush computes the score and
persists lebel_ng_kahinaan + safety_suggestions on every write.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: `DisclaimerCallout` widget

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/disclaimer_callout.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/presentation/disclaimer_callout_test.dart`

### CRITICAL — flutter_test + Drift Lock zone deadlock (avoid the trap)

When writing widget tests that use an in-memory `AppDatabase`: **create the DB INSIDE the `testWidgets` callback**, NOT in `setUp()`. This avoids the Phase 3a-discovered Drift+FakeAsync deadlock.

- [ ] **Step 1: Failing widget test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/disclaimer_callout.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders 3 disclaimer lines + Homeowner agrees switch',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DisclaimerCallout(submissionId: 's1', featureId: 'f1'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('This survey is voluntary, not mandatory.'),
      findsOneWidget,
    );
    expect(find.text('Homeowner agrees'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // Drain any pending debounce timer.
    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/disclaimer_callout_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/disclaimer_callout.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DisclaimerCallout extends ConsumerWidget {
  const DisclaimerCallout({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8ED),
        border: Border.all(color: const Color(0xFFF6D68E)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bullet(l.olpDisclaimerVoluntary),
          _bullet(l.olpDisclaimerSurveyorRole),
          _bullet(l.olpDisclaimerNoSelling),
          const Divider(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.olpHomeownerAgreesLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: state.homeownerAcknowledged,
                onChanged: (v) =>
                    notifier.setHomeownerAcknowledged(acknowledged: v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF92560A))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF92560A),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/disclaimer_callout_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/disclaimer_callout.dart test/features/survey/olp_survey/presentation/disclaimer_callout_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): DisclaimerCallout — 3 BFP disclaimers + Homeowner agrees switch

Tan/amber callout matching the does-not-exist callout style. Switch is
wired to the OLP notifier; toggling persists homeownerAcknowledged via
the standard 500ms debounce.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: `ConstructionDetailsSubform` (Section A widget)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/construction_details_subform.dart`

No standalone widget test for this task — `ConstructionDetailsSubform` will be exercised via the `OlpSection` smoke test in Task 14 + the manual happy path. The 10 elements × 4 materials matrix is rendered from `OlpRubric.constructionElements` + `OlpRubric.materials`, both of which are unit-tested in Task 4.

- [ ] **Step 1: Implement the widget**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/construction_details_subform.dart`:

```dart
import 'package:firecheck/features/survey/building_form/presentation/sections/_persistent_text_field.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConstructionDetailsSubform extends ConsumerWidget {
  const ConstructionDetailsSubform({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.olpSectionA,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        for (final element in OlpRubric.constructionElements)
          _ElementRow(
            element: element,
            elementLabel: _elementLabel(l, element),
            current: state.constructionDetails[element]?.material,
            currentOther: state.constructionDetails[element]?.materialOther,
            onMaterialChanged: (mat) {
              if (mat == null) return;
              notifier.setMaterial(element, mat);
            },
            onOtherChanged: (txt) {
              notifier.setMaterial(element, 'others', other: txt);
            },
          ),
      ],
    );
  }

  String _elementLabel(AppLocalizations l, String element) {
    switch (element) {
      case 'roof': return l.olpElementRoof;
      case 'ceiling': return l.olpElementCeiling;
      case 'roomPartitions': return l.olpElementRoomPartitions;
      case 'trusses': return l.olpElementTrusses;
      case 'windows': return l.olpElementWindows;
      case 'corridorWalls': return l.olpElementCorridorWalls;
      case 'columns': return l.olpElementColumns;
      case 'mainDoor': return l.olpElementMainDoor;
      case 'exteriorWall': return l.olpElementExteriorWall;
      case 'beams': return l.olpElementBeams;
      default: return element;
    }
  }
}

class _ElementRow extends StatelessWidget {
  const _ElementRow({
    required this.element,
    required this.elementLabel,
    required this.current,
    required this.currentOther,
    required this.onMaterialChanged,
    required this.onOtherChanged,
  });

  final String element;
  final String elementLabel;
  final String? current;
  final String? currentOther;
  final ValueChanged<String?> onMaterialChanged;
  final ValueChanged<String> onOtherChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(elementLabel, style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 8,
            children: [
              for (final m in OlpRubric.materials)
                ChoiceChip(
                  label: Text(_materialLabel(l, m)),
                  selected: current == m,
                  onSelected: (sel) {
                    if (sel) onMaterialChanged(m);
                  },
                ),
            ],
          ),
          if (current == 'others') ...[
            const SizedBox(height: 4),
            PersistentTextField(
              value: currentOther ?? '',
              labelText: l.olpMaterialOthersHint,
              onChanged: onOtherChanged,
            ),
          ],
        ],
      ),
    );
  }

  String _materialLabel(AppLocalizations l, String code) {
    switch (code) {
      case 'kahoy': return l.olpMaterialKahoy;
      case 'semento': return l.olpMaterialSemento;
      case 'bakal': return l.olpMaterialBakal;
      case 'others': return l.olpMaterialOthers;
      default: return code;
    }
  }
}
```

- [ ] **Step 2: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/presentation/construction_details_subform.dart
```

Expected: `No issues found!`. Fix lint without changing logic.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/construction_details_subform.dart && git commit -m "$(cat <<'EOF'
feat(olp): ConstructionDetailsSubform — Section A material picker

10 element rows × 4 ChoiceChip materials (kahoy/semento/bakal/others).
"Others" selection reveals an inline PersistentTextField for the
material name. Single material per element per Q5a.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: `ScoredSectionWidget` (generic checklist) + test

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/scored_section_widget.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/presentation/scored_section_widget_test.dart`

- [ ] **Step 1: Failing widget test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Section D renders 5 CheckboxListTiles + tapping toggles state',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScoredSectionWidget(
              section: OlpSection.d,
              submissionId: 's1',
              featureId: 'f1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNWidgets(5));

    // Tap the first CheckboxListTile, verify state mutates.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();

    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final state = container.read(olpSectionNotifierProvider(key));
    expect(state.checkedCodes, contains('D-25'));

    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/scored_section_widget_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/scored_section_widget.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ScoredSectionWidget extends ConsumerWidget {
  const ScoredSectionWidget({
    required this.section,
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final OlpSection section;
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);
    final items = OlpRubric.items.where((i) => i.section == section).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sectionLabel(l, section),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        for (final item in items)
          CheckboxListTile(
            key: Key('olp.item.${item.code}'),
            title: Text(_itemStatement(l, item.statementKey)),
            value: state.checkedCodes.contains(item.code),
            onChanged: (_) => notifier.toggleItem(item.code),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
      ],
    );
  }

  String _sectionLabel(AppLocalizations l, OlpSection s) {
    switch (s) {
      case OlpSection.b: return l.olpSectionB;
      case OlpSection.c: return l.olpSectionC;
      case OlpSection.d: return l.olpSectionD;
      case OlpSection.e: return l.olpSectionE;
    }
  }

  String _itemStatement(AppLocalizations l, String key) {
    return _resolveOlpKey(l, key);
  }
}

/// Resolves an OLP item statement or suggestion ARB key by name. The 70
/// per-item keys are too many to inline as a switch, so this helper uses
/// the AppLocalizations instance reflectively-by-name where possible. For
/// keys not present in this build, returns the raw key (a visible string
/// makes missing-translation bugs obvious during dev).
String _resolveOlpKey(AppLocalizations l, String key) {
  switch (key) {
    case 'olpItemB01Statement': return l.olpItemB01Statement;
    case 'olpItemB02Statement': return l.olpItemB02Statement;
    case 'olpItemB03Statement': return l.olpItemB03Statement;
    case 'olpItemB04Statement': return l.olpItemB04Statement;
    case 'olpItemB05Statement': return l.olpItemB05Statement;
    case 'olpItemB06Statement': return l.olpItemB06Statement;
    case 'olpItemB07Statement': return l.olpItemB07Statement;
    case 'olpItemB08Statement': return l.olpItemB08Statement;
    case 'olpItemB09Statement': return l.olpItemB09Statement;
    case 'olpItemB10Statement': return l.olpItemB10Statement;
    case 'olpItemB11Statement': return l.olpItemB11Statement;
    case 'olpItemB12Statement': return l.olpItemB12Statement;
    case 'olpItemB13Statement': return l.olpItemB13Statement;
    case 'olpItemB14Statement': return l.olpItemB14Statement;
    case 'olpItemB15Statement': return l.olpItemB15Statement;
    case 'olpItemC10Statement': return l.olpItemC10Statement;
    case 'olpItemC11Statement': return l.olpItemC11Statement;
    case 'olpItemC12Statement': return l.olpItemC12Statement;
    case 'olpItemC13Statement': return l.olpItemC13Statement;
    case 'olpItemC14Statement': return l.olpItemC14Statement;
    case 'olpItemC15Statement': return l.olpItemC15Statement;
    case 'olpItemC16Statement': return l.olpItemC16Statement;
    case 'olpItemC17Statement': return l.olpItemC17Statement;
    case 'olpItemC18Statement': return l.olpItemC18Statement;
    case 'olpItemD25Statement': return l.olpItemD25Statement;
    case 'olpItemD26Statement': return l.olpItemD26Statement;
    case 'olpItemD27Statement': return l.olpItemD27Statement;
    case 'olpItemD28Statement': return l.olpItemD28Statement;
    case 'olpItemD29Statement': return l.olpItemD29Statement;
    case 'olpItemE30Statement': return l.olpItemE30Statement;
    case 'olpItemE31Statement': return l.olpItemE31Statement;
    case 'olpItemE32Statement': return l.olpItemE32Statement;
    case 'olpItemE33Statement': return l.olpItemE33Statement;
    case 'olpItemE34Statement': return l.olpItemE34Statement;
    case 'olpItemE35Statement': return l.olpItemE35Statement;
    case 'olpItemB01Suggestion': return l.olpItemB01Suggestion;
    case 'olpItemB02Suggestion': return l.olpItemB02Suggestion;
    case 'olpItemB03Suggestion': return l.olpItemB03Suggestion;
    case 'olpItemB04Suggestion': return l.olpItemB04Suggestion;
    case 'olpItemB05Suggestion': return l.olpItemB05Suggestion;
    case 'olpItemB06Suggestion': return l.olpItemB06Suggestion;
    case 'olpItemB07Suggestion': return l.olpItemB07Suggestion;
    case 'olpItemB08Suggestion': return l.olpItemB08Suggestion;
    case 'olpItemB09Suggestion': return l.olpItemB09Suggestion;
    case 'olpItemB10Suggestion': return l.olpItemB10Suggestion;
    case 'olpItemB11Suggestion': return l.olpItemB11Suggestion;
    case 'olpItemB12Suggestion': return l.olpItemB12Suggestion;
    case 'olpItemB13Suggestion': return l.olpItemB13Suggestion;
    case 'olpItemB14Suggestion': return l.olpItemB14Suggestion;
    case 'olpItemB15Suggestion': return l.olpItemB15Suggestion;
    case 'olpItemC10Suggestion': return l.olpItemC10Suggestion;
    case 'olpItemC11Suggestion': return l.olpItemC11Suggestion;
    case 'olpItemC12Suggestion': return l.olpItemC12Suggestion;
    case 'olpItemC13Suggestion': return l.olpItemC13Suggestion;
    case 'olpItemC14Suggestion': return l.olpItemC14Suggestion;
    case 'olpItemC15Suggestion': return l.olpItemC15Suggestion;
    case 'olpItemC16Suggestion': return l.olpItemC16Suggestion;
    case 'olpItemC17Suggestion': return l.olpItemC17Suggestion;
    case 'olpItemC18Suggestion': return l.olpItemC18Suggestion;
    case 'olpItemD25Suggestion': return l.olpItemD25Suggestion;
    case 'olpItemD26Suggestion': return l.olpItemD26Suggestion;
    case 'olpItemD27Suggestion': return l.olpItemD27Suggestion;
    case 'olpItemD28Suggestion': return l.olpItemD28Suggestion;
    case 'olpItemD29Suggestion': return l.olpItemD29Suggestion;
    case 'olpItemE30Suggestion': return l.olpItemE30Suggestion;
    case 'olpItemE31Suggestion': return l.olpItemE31Suggestion;
    case 'olpItemE32Suggestion': return l.olpItemE32Suggestion;
    case 'olpItemE33Suggestion': return l.olpItemE33Suggestion;
    case 'olpItemE34Suggestion': return l.olpItemE34Suggestion;
    case 'olpItemE35Suggestion': return l.olpItemE35Suggestion;
    default: return key;
  }
}

/// Top-level helper for the result screen too.
String resolveOlpKey(AppLocalizations l, String key) =>
    _resolveOlpKey(l, key);
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/scored_section_widget_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/scored_section_widget.dart test/features/survey/olp_survey/presentation/scored_section_widget_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): ScoredSectionWidget — generic checkbox list per OlpSection

Renders one CheckboxListTile per rubric item in the given section.
Tap toggles via OlpSectionNotifier.toggleItem. Includes a public
resolveOlpKey() helper that maps statement/suggestion keys to localized
strings (used here + in result-screen suggestions list).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: `ScoreFooter` widget + test

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/score_footer.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/presentation/score_footer_test.dart`

- [ ] **Step 1: Failing widget test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/score_footer.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows 0 / 35 + Labis na Mapanganib for empty state',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScoreFooter(submissionId: 's1', featureId: 'f1'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0 / 35'), findsOneWidget);
    expect(find.text('Labis na Mapanganib'), findsOneWidget);
    expect(find.text('View breakdown →'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/score_footer_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/score_footer.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScoreFooter extends ConsumerWidget {
  const ScoreFooter({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key =
        OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final result = computeOlpScore(state);
    final color = _badgeColor(result.classification);
    final label = _classLabel(l, result.classification);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Text(
            l.olpScoreFraction(result.totalScore, OlpRubric.items.length),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () =>
                context.push('/feature/$featureId/olp/result'),
            child: Text(l.olpViewBreakdown),
          ),
        ],
      ),
    );
  }

  Color _badgeColor(OlpClassification c) => switch (c) {
        Ligtas() => const Color(0xFF276749),
        MayroongDapatIpangamba() => const Color(0xFFB7791F),
        LabisNaMapanganib() => const Color(0xFFC53030),
      };

  String _classLabel(AppLocalizations l, OlpClassification c) => switch (c) {
        Ligtas() => l.olpClassLigtas,
        MayroongDapatIpangamba() => l.olpClassMayroong,
        LabisNaMapanganib() => l.olpClassLabis,
      };
}
```

- [ ] **Step 4: Verify passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/score_footer_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 5: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/ test/features/survey/olp_survey/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/score_footer.dart test/features/survey/olp_survey/presentation/score_footer_test.dart && git commit -m "$(cat <<'EOF'
feat(olp): ScoreFooter — sticky live score + classification badge + breakdown link

Renders X / 35 + colored classification badge + 'View breakdown →' link
that pushes /feature/<id>/olp/result. Recomputes on every state change
via the pure scoring fn.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: `OlpSection` composer (collapsible)

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section.dart`

This is a composer widget — no standalone test (all sub-widgets are individually tested in T10/12/13).

- [ ] **Step 1: Implement**

Create `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/olp_section.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/construction_details_subform.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/disclaimer_callout.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/score_footer.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpSection extends ConsumerWidget {
  const OlpSection({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(l.olpSectionTitle),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          DisclaimerCallout(submissionId: submissionId, featureId: featureId),
          const SizedBox(height: 12),
          ConstructionDetailsSubform(
            submissionId: submissionId,
            featureId: featureId,
          ),
          const SizedBox(height: 12),
          for (final section in OlpSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ScoredSectionWidget(
                section: _toRubricSection(section),
                submissionId: submissionId,
                featureId: featureId,
              ),
            ),
          ScoreFooter(submissionId: submissionId, featureId: featureId),
        ],
      ),
    );
  }

  // OlpSection (this widget class) shadows the OlpSection enum from rubric
  // when both are imported in the same scope. Use a local enum here to
  // map our iteration to the rubric enum.
  static const _sections = [
    _S.b, _S.c, _S.d, _S.e,
  ];

  OlpSection _toRubricSection(OlpSection _) {
    // Note: not actually used; we iterate _sections below to avoid the
    // name collision. Keeping for symmetry with intent.
    throw UnimplementedError();
  }
}

// Avoid the OlpSection (widget class) vs OlpSection (rubric enum) name collision
// by iterating _SectionEnum.values mapped to OlpSection enum.
enum _S { b, c, d, e }
```

NOTE: the above has a naming collision (widget class `OlpSection` vs rubric enum `OlpSection`). The implementer should rename the widget class to `OlpSurveySection` to avoid the conflict. Use that name everywhere it's referenced (including the building form embed in Task 15). Final shape:

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/construction_details_subform.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/disclaimer_callout.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/score_footer.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpSurveySection extends ConsumerWidget {
  const OlpSurveySection({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(l.olpSectionTitle),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          DisclaimerCallout(submissionId: submissionId, featureId: featureId),
          const SizedBox(height: 12),
          ConstructionDetailsSubform(
            submissionId: submissionId,
            featureId: featureId,
          ),
          const SizedBox(height: 12),
          for (final section in OlpSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ScoredSectionWidget(
                section: section,
                submissionId: submissionId,
                featureId: featureId,
              ),
            ),
          ScoreFooter(submissionId: submissionId, featureId: featureId),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/olp_survey/presentation/olp_section.dart
```

Expected: `No issues found!`. Fix lint without changing logic.

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/olp_section.dart && git commit -m "$(cat <<'EOF'
feat(olp): OlpSurveySection — collapsible composer for OLP form

Card + ExpansionTile that wraps DisclaimerCallout, ConstructionDetailsSubform,
4 ScoredSectionWidget instances (B/C/D/E), and ScoreFooter. Default-collapsed
to keep the building form compact.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Embed `OlpSurveySection` in `BuildingForm`

**Files:**
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/building_form/presentation/building_form.dart`

- [ ] **Step 1: Read the existing file**

```bash
cat "/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/building_form/presentation/building_form.dart"
```

Note where the fire-load section is rendered — `OlpSurveySection` goes immediately after it.

- [ ] **Step 2: Add the import**

At the top of `building_form.dart`, add:

```dart
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section.dart';
```

- [ ] **Step 3: Add the OlpSurveySection child after fire-load**

Inside the `ListView` children, after the existing `FireLoadSection(...)` widget (and any spacer that follows), insert:

```dart
OlpSurveySection(
  submissionId: submissionId,
  featureId: featureId,
),
```

(Do not add OLP if `state.doesNotExist == true`. Wrap with `if (!state.doesNotExist) ...`. The OLP section should disappear when the building does-not-exist toggle is on, since there's no household to survey.)

- [ ] **Step 4: Run analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/survey/building_form/
```

Expected: `No issues found!`

- [ ] **Step 5: Run building form + olp tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/building_form/ test/features/survey/olp_survey/
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/building_form/presentation/building_form.dart && git commit -m "$(cat <<'EOF'
feat(building_form): embed OlpSurveySection at the bottom

Renders the OLP collapsible after the fire-load section. Hidden when
the building's does-not-exist toggle is on.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Result screen (5 widgets + route) + smoke test

**Files:**
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/result/score_hero.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/result/per_section_progress.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/result/unchecked_items_list.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/result/mark_complete_button.dart`
- Create: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/features/survey/olp_survey/presentation/result/olp_result_screen.dart`
- Modify: `/Users/johnlesterescarlan/Personal Projects/firecheck/lib/core/router/app_router.dart`
- Test: `/Users/johnlesterescarlan/Personal Projects/firecheck/test/features/survey/olp_survey/presentation/result/olp_result_screen_test.dart`

- [ ] **Step 1: Failing widget test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders score hero + 4 progress bars + Mark Complete disabled',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OlpResultScreen(submissionId: 's1', featureId: 'f1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0 / 35'), findsOneWidget);
    expect(find.text('Labis na Mapanganib'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Mark survey complete'),
    );
    expect(btn.onPressed, isNull);

    // Acknowledge → button enables.
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    container
        .read(olpSectionNotifierProvider(key).notifier)
        .setHomeownerAcknowledged(acknowledged: true);
    await tester.pump();

    final btn2 = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Mark survey complete'),
    );
    expect(btn2.onPressed, isNotNull);

    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
```

- [ ] **Step 2: Verify failure**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/result/olp_result_screen_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement `score_hero.dart`**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ScoreHero extends StatelessWidget {
  const ScoreHero({
    required this.score,
    required this.classification,
    super.key,
  });
  final int score;
  final OlpClassification classification;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final color = switch (classification) {
      Ligtas() => const Color(0xFF276749),
      MayroongDapatIpangamba() => const Color(0xFFB7791F),
      LabisNaMapanganib() => const Color(0xFFC53030),
    };
    final label = switch (classification) {
      Ligtas() => l.olpClassLigtas,
      MayroongDapatIpangamba() => l.olpClassMayroong,
      LabisNaMapanganib() => l.olpClassLabis,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            '$score / ${OlpRubric.items.length}',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Implement `per_section_progress.dart`**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class PerSectionProgress extends StatelessWidget {
  const PerSectionProgress({required this.sectionScores, super.key});
  final Map<OlpSection, int> sectionScores;

  static const _max = {
    OlpSection.b: 15,
    OlpSection.c: 9,
    OlpSection.d: 5,
    OlpSection.e: 6,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final section in OlpSection.values)
          _row(
            context,
            label: _label(l, section),
            score: sectionScores[section] ?? 0,
            max: _max[section]!,
          ),
      ],
    );
  }

  Widget _row(BuildContext context, {required String label, required int score, required int max}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
              Text('$score / $max', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: max == 0 ? 0 : score / max),
        ],
      ),
    );
  }

  String _label(AppLocalizations l, OlpSection s) {
    switch (s) {
      case OlpSection.b: return l.olpSectionB;
      case OlpSection.c: return l.olpSectionC;
      case OlpSection.d: return l.olpSectionD;
      case OlpSection.e: return l.olpSectionE;
    }
  }
}
```

- [ ] **Step 5: Implement `unchecked_items_list.dart`**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class UncheckedItemsList extends StatelessWidget {
  const UncheckedItemsList({required this.items, super.key});
  final List<OlpRubricItem> items;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_box_outline_blank, size: 16, color: Color(0xFFC53030)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        resolveOlpKey(l, item.statementKey),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text(
                    resolveOlpKey(l, item.suggestionKey),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3B82F6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Implement `mark_complete_button.dart`**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_validator.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MarkCompleteButton extends ConsumerWidget {
  const MarkCompleteButton({
    required this.submissionId,
    required this.featureId,
    super.key,
  });
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key = OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final notifier = ref.read(olpSectionNotifierProvider(key).notifier);
    final canComplete = validateOlpForFinalize(state).canMarkComplete;

    return Tooltip(
      message: canComplete ? '' : l.olpAcknowledgmentRequiredTooltip,
      child: FilledButton(
        onPressed: canComplete
            ? () async {
                await notifier.markComplete();
                if (context.mounted) context.pop();
              }
            : null,
        child: Text(l.olpMarkComplete),
      ),
    );
  }
}
```

- [ ] **Step 7: Implement `olp_result_screen.dart`**

```dart
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/mark_complete_button.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/per_section_progress.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/score_hero.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/unchecked_items_list.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpResultScreen extends ConsumerWidget {
  const OlpResultScreen({
    required this.submissionId,
    required this.featureId,
    super.key,
  });
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final key = OlpFormKey(submissionId: submissionId, featureId: featureId);
    final state = ref.watch(olpSectionNotifierProvider(key));
    final result = computeOlpScore(state);

    return Scaffold(
      appBar: AppBar(title: Text(l.olpResultTitle)),
      body: ListView(
        children: [
          ScoreHero(score: result.totalScore, classification: result.classification),
          PerSectionProgress(sectionScores: result.sectionScores),
          const Divider(),
          UncheckedItemsList(items: result.uncheckedItems),
          const SizedBox(height: 80), // bottom padding so button doesn't overlap last item
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: MarkCompleteButton(
              submissionId: submissionId,
              featureId: featureId,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Add the route**

Read `lib/core/router/app_router.dart` then add this route inside the existing `routes:` list (any position; before the catch-all if any):

```dart
GoRoute(
  path: '/feature/:featureId/olp/result',
  builder: (context, state) {
    final featureId = state.pathParameters['featureId']!;
    final submissionId = state.uri.queryParameters['submissionId'] ?? '';
    return OlpResultScreen(
      submissionId: submissionId,
      featureId: featureId,
    );
  },
),
```

Update the `ScoreFooter`'s push call (in `score_footer.dart`) to pass the `submissionId` query param:

```dart
context.push('/feature/$featureId/olp/result?submissionId=$submissionId');
```

Add the import at the top of `app_router.dart`:

```dart
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
```

- [ ] **Step 9: Verify test passes**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/survey/olp_survey/presentation/result/olp_result_screen_test.dart
```

Expected: `All tests passed!` (1 test).

- [ ] **Step 10: Run analyze + all OLP tests**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze && flutter test test/features/survey/olp_survey/
```

Expected: `No issues found!` and all OLP tests pass.

- [ ] **Step 11: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git add lib/features/survey/olp_survey/presentation/result/ lib/features/survey/olp_survey/presentation/score_footer.dart lib/core/router/app_router.dart test/features/survey/olp_survey/presentation/result/ && git commit -m "$(cat <<'EOF'
feat(olp): result screen — score hero + per-section bars + unchecked + Mark Complete

New /feature/:featureId/olp/result route. ScoreHero shows the big numeral
+ classification badge; PerSectionProgress draws 4 LinearProgressIndicator
bars; UncheckedItemsList pairs each unchecked item with its localized
suggestion; MarkCompleteButton is gated on homeownerAcknowledged and
sets completedAt + pops on tap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Final verification + tag

**Files:** none modified — verification + tag only.

- [ ] **Step 1: Run full analyze**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Run the full test suite**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test
```

Expected: ≥ 175 tests passing (Phase 3a ended at 152 + ~25-30 added by Phase 3b). Final line: `All tests passed!`.

- [ ] **Step 3: Build the debug APK**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Install + manual happy path on emulator**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && adb install -r build/app/outputs/flutter-apk/app-debug.apk && adb shell am force-stop ph.gov.bfp.firecheck && adb shell am start -n ph.gov.bfp.firecheck/.MainActivity
```

Then on the emulator:
- Tap a building polygon → detail screen opens.
- Scroll to the bottom of the building form → see the **OLP household survey · Optional** ExpansionTile.
- Tap to expand → 3 disclaimers + Homeowner agrees switch + Section A (10 elements with material chips) + 4 scored sections (B/C/D/E) + score footer.
- Tick a few items → footer updates `Iskor: N / 35` + classification badge in the right color.
- Tap **View breakdown →** → full-screen result with score hero, 4 progress bars, unchecked-items list with paired Tagalog suggestions.
- Mark Complete is disabled until you flip the Homeowner agrees switch back on the form.
- Flip Homeowner agrees → scroll back to result → Mark Complete enables → tap → returns to building form.
- Force-stop + relaunch the app → re-open the same building → OLP state intact.

- [ ] **Step 5: Tag the release locally**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -a phase-3b-olp -m "Phase 3b — OLP household survey + Lebel ng Kahinaan scoring

35-item BFP CFPP rubric (data-driven config). Pure scoring fn computes
score + classification + per-section breakdown + unchecked items.
OlpSurveySection ExpansionTile inside building form. Full result-screen
route at /feature/:featureId/olp/result. Schema bump v3→v4 adds
homeowner_acknowledged + completed_at columns.

PRD risks #1 + #2 flagged as pre-pilot blockers (rubric + boundary
verification). Items + suggestions swap as ARB-only changes."
```

- [ ] **Step 6: Confirm tag exists locally; do NOT push**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && git tag -l | tail -5
```

Expected: `phase-3b-olp` appears in the list.

- [ ] **Step 7: Hand off to user**

Inform the user:

> Phase 3b complete. `flutter analyze` clean, `flutter test` green (≥175 passing), debug APK built, manual happy path validated, tag `phase-3b-olp` created locally. Push when ready:
> ```
> git push origin main
> git push origin phase-3b-olp
> ```

---
