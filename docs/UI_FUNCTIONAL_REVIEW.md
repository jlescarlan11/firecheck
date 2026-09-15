# UI and Functionality Review

Reviewed on 2026-09-12 before implementation. FireCheck is a Flutter Android
field-survey app; this pass preserves the existing offline survey architecture
and the uncommitted photo, road-form, and map-import work already in the checkout.

## Findings and Changes

| Finding | Resolution |
| --- | --- |
| Upload All included exhausted jobs in its count but never retried them. | Explicit retries now reset failed and dead jobs, including attempt counts and stale errors. Background retry policy is unchanged. |
| Pending upload counts included completed history. | Completed jobs no longer contribute to the repository's pending count. |
| Merged-away features inflated home progress and review validation. | Both queries now exclude merge tombstones, consistent with the map. |
| Photo recovery accepted a missing parent submission and cleared its recovery context. | Capture persistence now checks the parent before processing; failed recovery retains its source. |
| Home offered an empty map and mixed field work with form-rule tooling. | Empty map action is disabled, downloads remain available, and form rules are reachable from Account. Upload queue is always reachable from Home and Account. |
| Upload controls overflowed narrow screens and async actions had no failure feedback. | Responsive settings layout, safe-area footer, explicit retry icons, operation guards, and preference/upload error feedback. |
| Low-storage and empty-assignment screens had no recovery action. | Both now offer retry/reset actions. |
| Sign-in lacked app identity; account could render a blank body. | Existing brand image, constrained sign-in layout, account loading/error/signed-out states, wrapped profile text. |
| Inconsistent default component styling. | Shared neutral Material theme with red primary actions, green secondary accents, consistent fields and button sizing, and 8px card corners. |

## Verification

- Full suite: 860 passed, 2 skipped, 1 obsolete low-storage button assertion.
  Updated that assertion to exercise the new retry action and reran its whole
  test file: 6 passed. The full suite was not repeated after that test-only edit.
- Focused implementation regression run: 65 passed. Visual capture run: 6 passed.
- Final `flutter build apk --debug --no-pub`: succeeded.
- `git diff --check`: clean.
- Regression tests cover upload retries/counts, merge tombstones, photo recovery,
  empty home actions, home error recovery, and 320px layouts at 1.5x text scale.
- `flutter test --update-goldens tool/ui_review_test.dart` renders Home, Sign-in,
  and Uploads at 390px and 900px. Six images are written to `build/ui-review/`.
  These use controlled local state, not a live authenticated account.
- Debug APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Existing lint warnings remain; dependency upgrades and backend migrations were
  outside this change.
- A subsequent targeted analyzer run hit an existing custom_lint plugin load
  failure (invalid Mach-O library); the earlier full analysis completed with no
  compile errors.

## Remaining Release Checks

Live Google authentication, camera/GPS permissions, Mapbox offline downloads, and
remote upload still need an authenticated Android smoke test. The local emulator
disconnected during APK installation. Build and widget checks do not establish
those device/service integrations, and this pass is not a production-release
certification.
