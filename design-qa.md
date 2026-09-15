# FireCheck app redesign — 2026-09-15

final result: passed

## Scope and selected direction

The user chose the first Todoist-inspired minimalist reference for the app. The initial implementation incorrectly stopped at Home; this pass applies the same visual language throughout the existing Flutter app.

- Selected reference: `docs/design/2026-09-15-home/reference.png`.
- Screen gallery: `docs/design/2026-09-15-app/index.html`.
- Overview: `docs/design/2026-09-15-app/overview.png`.
- Actual Flutter capture harness: `tool/app_redesign_review_test.dart`.
- Prior Home comparison and QA history: `docs/design/2026-09-15-home/`.

The approved image specifies Home. Other screens extend its typography, spacing, white surfaces, red actions, and thin dividers while retaining their existing workflows. There is no separate approved mockup for each form.

## Implemented coverage

| Area | Applied changes |
| --- | --- |
| Shared theme and navigation | White surfaces, charcoal text, red primary actions, consistent field/button styles, minimal Home/Account navigation, readable typography, 24px phone gutters and 680px reading width on large screens. |
| Sign-in and Account | Clear entry heading and sign-in action; compact profile, open navigation rows, separated sign-out action. |
| Downloads | Page introduction, download-source selection and simplified assignment rows; readable-map policy is automatic; existing download/retry states retained. |
| Upload queue | Readable summary and file rows, shared scroll area for header/settings/files, pending-only database query, 50-row incremental loading, lazy file widgets, persistent upload action. |
| Building and road surveys | Open sections with readable headings, quieter fields and status panels, matching photo strip and submission tabs; dropdowns fit narrow screens. |
| Household survey and results | Readable section hierarchy, construction choices, score and classification, progress rows and recommendations. |
| Map and geometry editing | White zoom/recenter controls, red add-feature action, neutral editing toolbar and shared dialog/sheet styles. |
| Review and upload outcomes | Open assignment summary, validation and failed jobs; readable success details with accessible copy/open buttons. |
| Activity and conflict review | Shared page layout, readable attribute tables, comparisons stacked on phones and side by side on larger screens, duplicate decisions. |
| Form rules and closed assignments | Shared typography, spacing, scrolling, and action styles. |

## Rendered evidence and findings

The baseline captured 19 screens/component views at three configurations: **57 passing captures**. The follow-up below adds a download-progress view and refreshes downloads/uploads, bringing the gallery to 20 views.

- Phone: 390 × 844, 1× text, device pixel ratio 1.
- Tablet: 900 × 844, 1× text, device pixel ratio 1.
- Small phone: 320 × 640, 1.5× text, device pixel ratio 1.
- The gallery switches between those saved renders; images open at full size.
- The 1296 × 960 overview is an in-app browser screenshot of that gallery, not a running web port of the app.
- Captures use actual Flutter widgets and controlled provider/local database fixtures. Household-form and comparison-component views isolate the production component for inspection. The map uses the real MapScreen controls with an explicitly labeled placeholder for native Mapbox imagery.

Resolved findings:

1. **P1: narrow upload screen overflow with enlarged text.** The summary, settings, and files now scroll together; upload stays accessible at the bottom. A regression check scrolls to the retry control and checks that it is tappable.
2. **P1: long building dropdown options exceeded the available width.** Building type, construction material, and cost dropdowns now expand within the form width and allow variable-height menu items.
3. **P2: inconsistent typography and boxed sections across screens.** Shared layout/theme styles replace tiny uppercase headings, dense stacked cards, and competing action colors.
4. **P2: narrow conflict comparisons.** The two sets of answers stack vertically below 560px while preserving the difference highlight and show/hide filter.
5. **Capture setup issue:** custom text styles initially fell back to the test font. The theme now explicitly applies Roboto, and all final images were regenerated and inspected.

The selected Home hierarchy remains recognizable: large heading and metric, one red primary action, open management rows, muted save status, and simple navigation. Forms adapt that style to data entry rather than copying Home's composition. No actionable P0/P1/P2 visual findings remain in the inspected captures. Native icon/font rendering and diagnostic shadow rendering may differ slightly on an Android device.

## Verification

- Redesign baseline `flutter test --no-pub`: **869 passed, 2 skipped**, no failures. Follow-up validation is recorded below.
- `flutter test --no-pub --update-goldens tool/app_redesign_review_test.dart`: **57 passed**.
- `flutter build apk --debug --no-pub`: **successful**, output `build/app/outputs/flutter-apk/app-debug.apk`.
- Full repository analysis: **no errors**; existing warnings and lint information remain elsewhere in the repository. The analyzer reported no diagnostics in the redesigned production presentation files and shared theme at the checked revision.
- `git diff --check`: clean.
- Existing interaction tests cover authentication routing, account actions, download states, map/geometry tools, form persistence/validation, review/upload, conflicts, and activity. Updated assertions follow the new labels, button types, and localized app wrapper.
- New design strings are included in English and Tagalog. Flutter reports 19 pre-existing untranslated Tagalog messages elsewhere.

## Practical limits

The checks use local fixtures and mocked platform/service dependencies. Live Google sign-in, Mapbox imagery, camera/GPS hardware, remote uploads, and device-specific rendering were not retested on a connected Android device. The debug APK is built for device review; no app-store release was published.

## Follow-up: download progress and pending upload changes

- Shapefile and tile download progress now show a clamped percentage. Unknown totals show “Calculating progress…” with an indeterminate bar, rather than a misleading numeric percentage.
- Removed the import-options toggle and its preference lookup. All app downloads use the readable-map policy, regardless of a previously saved strict choice. Missing layers and standard survey columns produce warnings. Corrupt geometry/attribute data and downloads containing no geometry are rejected; arbitrary SHP filenames receive header validation too.
- Completed upload jobs stay in audit storage but are excluded from the queue query. The queue loads 50 rows initially, adds another 50 near the end of scrolling, and offers a load-more fallback. The widget list builds lazily. SQL aggregate totals keep Home badges, byte totals, failures, and upload activity accurate for rows not yet loaded.
- Updated gallery includes `app-download-progress-{320,390,900}.png` and refreshed downloads/uploads. The 390px downloads and progress renders were visually inspected.
- **172 relevant tests passed**, including pagination over 603 stored jobs, unseen active/failed rows, completed-history exclusion, live completion updates, scroll-triggered loading, lazy construction with 1,000 changes, progress edge cases, and readable/corrupt map validation.
- **9 refreshed visual captures passed** at phone, tablet, and enlarged-text sizes.
- Android debug APK rebuilt successfully. Targeted analysis reported no errors or warnings; minor lint information remains. `git diff --check` passed.

## Installable UI update: 0.1.1+2

- Built the updated Android release APK, rather than only the debug artifact.
- Verified package `ph.gov.bfp.firecheck`, version name `0.1.1`, and version code `2`.
- Verified the APK signature matches the prior 0.1.0 release certificate.
- Copied the APK to `build/apk-download/FireCheck-0.1.1-release.apk` and verified its hash matches the build output.
- Refreshed the local phone download page/server on the current Wi-Fi address; the APK URL returned HTTP 200 with the expected 135,074,511-byte length.
- No Android device was connected, so installation on the user's phone remains a manual download/update step.
