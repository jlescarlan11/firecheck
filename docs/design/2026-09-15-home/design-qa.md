# FireCheck Home redesign — 2026-09-15

final result: passed

## Target and evidence

- Selected visual truth: `docs/design/2026-09-15-home/reference.png` (first displayed mockup, Todoist direction).
- Rendered Flutter screen: `docs/design/2026-09-15-home/home-phone.png`.
- Tablet capture: `docs/design/2026-09-15-home/home-tablet.png`.
- Full-view comparison: `docs/design/2026-09-15-home/comparison.png`.
- Reopen the comparison with `docs/design/2026-09-15-home/comparison.html`.
- Captures use the actual HomeScreen and app theme, with controlled local provider state: 24 of 60 features surveyed, six pending files, unlocked assignment, no conflicts or failed survey syncs. They are not screenshots of a signed-in device session.
- App viewport: 390 × 844 logical pixels, devicePixelRatio 1; tablet: 900 × 844.
- Source raster: 853 × 1844. Comparison fits it proportionally within a 390 × 844 CSS region (390 × approximately 843.1 actual image, less than one pixel of letterboxing). Implementation raster: 390 × 844, shown at its native logical size.
- The comparison page was captured in the in-app browser at 900 × 960. It displays both images together at the same scale. The browser is showing static Flutter captures, not a running web implementation.
- The final comparison is legible at full resolution; the complete 390px phone capture was also inspected for text, icon, and divider detail. No separate region crops were needed.

## Comparison history

1. Initial Flutter capture (`build/ui-review/home-390.png`) placed the main action too low and used taller list rows. The save note fell below the initial viewport. **P2: excess vertical spacing**. This first capture also used the existing diagnostic fixture, so its different counts were not judged as design defects.
2. Reduced progress gaps, adjusted the metric to 40px, set the primary action to 56px minimum height, and reduced list-row padding to match the reference's approximately 76px rows. Added a dedicated capture fixture matching the reference's 24/60 and six-file state.
3. Corrected the bottom navigation divider to paint in the foreground. Recaptured the phone and tablet layouts and reviewed them alongside the selected reference. Main action, management rows, save note, and navigation now fit together at 390 × 844. No actionable P0/P1/P2 findings remain.

## Required fidelity surfaces

- **Typography:** Native Roboto, 32px screen heading, 40px metric, 20px section heading, 17px action and row titles, 14px row details, 13px secondary status. The hierarchy and wrapping follow the reference. The generated reference's letterforms and the platform's font rendering differ slightly; this is acceptable P3 polish, not a reason to add another font dependency.
- **Spacing:** 24px phone margins, open sections, a full-width primary action, approximately 76px management rows, and a persistent 76px navigation bar. Larger text scrolls rather than clipping. Tablet content is constrained to 680px.
- **Colors:** White surface, existing FireCheck red `#B93228`, charcoal labels, muted gray secondary text, thin separators. No new decorative cards, gradients, or shadows. Solid native button color replaces the generated image's uneven texture.
- **Assets:** Material's outlined map, upload, flame, and save symbols are used as native UI icons. No rasterized UI or new decorative imagery. The selected mockup is preserved separately as review evidence.
- **Copy and state:** Primary and section copy follow the reference. Production data drives progress and pending/uploading/failed-file summaries. Home-specific English and Tagalog translations were added without changing shared action labels on other screens.

## Intentional product adaptations

- Added an overflow menu for the existing shapefile export action, including its disabled, busy, validation-error, and export-error behavior.
- Retained submission notices, conflict navigation, and closed-assignment read-only behavior. Closed assignments expose “View map” and hide review/upload.
- Used “Download your assignment” for Get maps because a feature count does not establish that offline map tiles are available.
- Used “Survey changes are saved on this device” rather than asserting “Working offline” without a connection-state signal.
- File counts identify pending files; completed history is excluded and active uploads count toward the badge. Failed files show a retry-needed message.
- Survey sync attention remains distinct from the file upload queue.
- The existing Home/Account routes are retained. The minimal bottom-navigation appearance is scoped to Home; Account has not been redesigned in this pass.

## Verification

- Home, export, progress, navigation, and capture suite: **34 passed**.
- After final cleanup, interaction and visual capture rerun: **10 passed**.
- Targeted analyzer for implementation and new test/capture helpers: **No issues found**.
- Debug Android APK build: successful (see `build/app/outputs/flutter-apk/app-debug.apk`).
- `git diff --check`: clean.
- Interaction tests exercise map/download/upload queue/account navigation, biometric cancellation and success, review without biometrics, export validation and invocation, empty export disabling, pending/failed/uploading/completed count handling, conflict navigation, and Tagalog at 320px with 1.5× text scale.
- Existing tests cover empty progress, loading errors with retry, submitted and closed assignment behavior, and narrow English layout.
- New translations are complete in both locales. Flutter still reports 19 pre-existing untranslated Tagalog messages elsewhere.

## Limits and follow-up polish

- Live Google authentication, Mapbox, camera/GPS, network transfer, and device-specific font rendering were not retested. The interaction checks validate Home navigation and action wiring with controlled dependencies, not remote service execution.
- P3: native icon stroke shapes and font rendering differ slightly from the generated reference.
- Home is the implemented scope. Survey forms, map controls, and Account remain future redesign work.

## Implementation checklist

- [x] Match the chosen layout in the existing Flutter screen.
- [x] Preserve navigation, export, review, and exception states.
- [x] Support localized and enlarged text.
- [x] Capture matching-state phone and tablet evidence.
- [x] Resolve significant visual mismatches and rerun focused checks.
