# Account Page with Bottom Navigation — Design

## Goal

Surface a user-facing **Account** page and a **bottom navigation bar** that switches between Home and Account. The Account page shows the signed-in user's name, email, and avatar, and provides a confirmed Sign-out action. Sign-out is currently not exposed in any UI.

## Non-goals

- No assignment / enumerator info on the Account page.
- No app version / build display.
- No bottom nav on deeper routes (e.g. `/map`, `/feature/:id`, `/review`) — the nav appears only on Home and Account.
- No profile editing, password changes, or account deletion.
- No preserved per-tab navigation stack (Account has no sub-routes, so there is nothing to preserve).

## Architecture

Two top-level GoRoutes (`/` and `/account`) each render their own `Scaffold` with a shared `AppBottomNav` widget. Tab taps call `context.go(...)`, not `push`, so the back stack does not accumulate when switching tabs. This matches the existing flat-router pattern in `lib/core/router/app_router.dart` and avoids the larger refactor a `StatefulShellRoute` would require.

The existing auth redirect (`session == null → /sign-in`) already protects `/account` without any change.

## Components

### `AppTab` enum

```dart
enum AppTab { home, account }
```

Lives in `lib/core/navigation/app_bottom_nav.dart`.

### `AppBottomNav`

`StatelessWidget` wrapping Material 3 `NavigationBar` with two destinations:

- **Home** — `Icons.home_outlined` / `Icons.home` (selected).
- **Account** — `Icons.person_outline` / `Icons.person` (selected).

Parameters:

- `current: AppTab` — which tab the host screen says is selected.

Behavior:

- `onDestinationSelected`: if the tapped index matches `current`, no-op. Otherwise `context.go('/')` or `context.go('/account')`.
- Labels are localized via `AppLocalizations` (`navHome`, `navAccount`).

### `AccountScreen`

`ConsumerWidget` at `lib/features/account/presentation/account_screen.dart`.

Reads `supabaseAuthStateProvider` and pulls `Session.user`. From `user.userMetadata`:

- `full_name` (String?) — display name.
- `email` (falls back to `user.email`).
- `avatar_url` (String?) — profile picture.

Layout — `Scaffold` with:

- AppBar — title from `AppLocalizations.accountTitle` ("Account").
- Body — `ListView` (so content scrolls on small devices):
  1. 24px top padding.
  2. Centered `CircleAvatar` (radius 48) — `NetworkImage(avatar_url)` if present, else `Icon(Icons.person, size 48)` over surfaceVariant background.
  3. 16px gap.
  4. Name centered, `Theme.textTheme.titleLarge`. Falls back to email local-part if `full_name` is null.
  5. Email centered, `Theme.textTheme.bodyMedium` with `onSurfaceVariant` color.
  6. 24px gap, then a `Divider`.
  7. `ListTile`: leading `Icon(Icons.logout)`, title "Sign out" (localized), `onTap` → confirm dialog.
- `bottomNavigationBar: const AppBottomNav(current: AppTab.account)`.

If the session is `null` (defensive — the router should have redirected), render an empty `Scaffold` with the bottom nav and an empty body; do not crash.

### Home wiring

Add `bottomNavigationBar: const AppBottomNav(current: AppTab.home)` to the existing `Scaffold` in `lib/features/home/presentation/home_screen.dart`. No other changes to Home.

## Sign-out flow

1. User taps the Sign-out `ListTile` on Account.
2. `showDialog<bool>` returns an `AlertDialog`:
   - Title: "Sign out?" (localized).
   - Content: "You'll need to sign in again to continue." (localized).
   - Actions: Cancel (returns `false`) and Sign out (returns `true`).
3. On `true`:
   - `await ref.read(googleAuthRepositoryProvider).signOut()`.
   - Supabase session goes null → `supabaseAuthStateProvider` emits null → GoRouter redirect sends the user to `/sign-in`.
4. On error during `signOut()`:
   - Catch, check `context.mounted`, then show a `SnackBar` "Couldn't sign out. Try again." (localized).
   - Stay on Account.

No manual navigation calls in the success path — the router redirect handles it.

## Router change

In `lib/core/router/app_router.dart`, add one route alongside the existing flat list:

```dart
GoRoute(
  path: '/account',
  builder: (context, state) => const AccountScreen(),
),
```

No change to the `redirect` callback.

## Localization

New keys in `lib/generated/l10n/app_localizations.dart` (added via ARB files):

- `navHome` — "Home"
- `navAccount` — "Account"
- `accountTitle` — "Account"
- `accountSignOut` — "Sign out"
- `accountSignOutConfirmTitle` — "Sign out?"
- `accountSignOutConfirmBody` — "You'll need to sign in again to continue."
- `accountSignOutCancel` — "Cancel"
- `accountSignOutError` — "Couldn't sign out. Try again."

Both `app_en.arb` and any other locale ARBs in the repo get the same keys.

## Testing

### `AccountScreen` widget tests

- Given a Supabase session with `full_name`, `email`, and `avatar_url` in metadata, all three render.
- Given metadata without `full_name`, the email local-part is shown as the name.
- Given metadata without `avatar_url`, the fallback `Icons.person` icon renders.
- Tapping the Sign-out tile shows the confirmation dialog.
- Tapping Cancel in the dialog dismisses it and does NOT call `signOut()`.
- Tapping Sign out in the dialog calls `signOut()` once on the (fake) `GoogleAuthRepository`.
- If `signOut()` throws, the error SnackBar appears and `AccountScreen` is still on screen.

A `FakeGoogleAuthRepository` (already in `lib/features/auth/data/fake_google_auth_repository.dart`) is overridden into `googleAuthRepositoryProvider` for these tests.

### `AppBottomNav` widget test

- Renders with `current: AppTab.home` → tapping the Account destination triggers navigation to `/account` (verified by mounting inside a minimal `GoRouter` with two stub routes that record the matched path).
- Tapping the currently-selected destination is a no-op (the recording stub receives no extra navigation).

## File map

**New**

- `lib/features/account/presentation/account_screen.dart`
- `lib/core/navigation/app_bottom_nav.dart`
- `test/features/account/account_screen_test.dart`
- `test/core/navigation/app_bottom_nav_test.dart`

**Edited**

- `lib/core/router/app_router.dart` — add `/account` route + import.
- `lib/features/home/presentation/home_screen.dart` — add `bottomNavigationBar`.
- `lib/core/i18n/app_en.arb` and `lib/core/i18n/app_tl.arb` — add 8 localization keys.

## Risks and edge cases

- **Empty/null `user_metadata` fields.** Google sign-in normally populates `full_name`, `email`, and `avatar_url`, but treat each as optional. Fallbacks are spelled out above.
- **Network avatar load failure.** `NetworkImage` failures surface as a broken image; wrap the avatar in a builder that swaps to the fallback icon `onBackgroundImageError`.
- **Sign-out partial failure.** `GoogleSignInAuthRepository.signOut()` calls both Google sign-out and Supabase sign-out sequentially. If the Google call throws, Supabase may still hold a session. The catch + SnackBar path stays on Account; user can retry. This matches existing behavior elsewhere in the app.
- **Double-tap on Sign out.** Disable the dialog's Sign-out button while the await is in flight (toggle local state in the dialog's StatefulBuilder, or use a guard flag on the screen).
