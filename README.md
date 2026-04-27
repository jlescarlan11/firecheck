# FireCheck Mobile

Offline-first Flutter Android app for the **Philippine Bureau of Fire Protection (BFP)** — replaces two legacy paper-and-tablet apps (Attribution + Household Survey) with one tool that an enumerator can use in the field, fully offline, then upload everything when back on Wi-Fi.

**Status:** MVP shipped. Tag `phase-4b-upload-flow`. PR [#3](https://github.com/jlescarlan11/firecheck/pull/3) covers the latest phase. Pilot-ready for internal testing. See [the phase roadmap](#phase-roadmap) for what comes next.

---

## What it does

| Capability | What the user does |
|---|---|
| **Offline-first** | Download an assignment + map tiles once. After that, every screen works without network. |
| **Building survey** | Tap a polygon on the map → fill the form (Identity, Construction, Cost, Fire-fighting, Fire load) → take a photo → done. Multi-tab support if a polygon hosts more than one structure. |
| **Road survey** | Tap a road polyline → fill width/features/material → photo → done. |
| **OLP (Household survey)** | For residential buildings, fills the *Lebel ng Kahinaan* household section with live vulnerability scoring. |
| **Add new feature** | Long-press anywhere inside the assignment boundary to add a missing building or road. Server gets it on next upload. |
| **Sync engine** | Outbox pattern, two-phase photo upload, retry/backoff with WorkManager background ticks, 401 refresh, 409 bundle-export fallback. |
| **Review + Upload** | Pre-submit review screen lists summary, blockers, warnings, dead jobs. Biometric-gated. After upload, assignment locks and form goes read-only. |

---

## Tech stack

- **Flutter** 3.22+ / Dart 3.4+
- **State** — Riverpod 2.5
- **Routing** — go_router 14
- **Local DB** — Drift (SQLite) at schema v5
- **Map** — Mapbox Maps SDK 2.22 with offline tile packs
- **Backend** — Supabase (Postgres + PostGIS + Auth + Storage)
- **Background work** — workmanager 0.5
- **Biometric** — local_auth 2.2
- **Lints** — very_good_analysis

---

## Quick start

### 1. Prerequisites

- Flutter `>=3.22.0` (stable channel)
- Android Studio + an Android 13+ emulator (Pixel 7 recommended)
- A Supabase project with the migrations in `supabase/migrations/` applied (ask the team for credentials)
- A Mapbox public access token (`pk.…`) — sign up free at mapbox.com

### 2. Clone + install deps

```bash
git clone https://github.com/jlescarlan11/firecheck.git
cd firecheck
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter gen-l10n                                            # i18n codegen
```

### 3. Configure environment

```bash
cp .env.example .env
# fill in SUPABASE_URL, SUPABASE_ANON_KEY, MAPBOX_ACCESS_TOKEN
```

### 4. Run

```bash
flutter run -d emulator-5554
```

Sign in with the test admin account (ask the team), tap **Get Maps**, then survey a polygon.

### 5. Run the test suite

```bash
flutter analyze     # should be clean
flutter test        # 294 tests passing as of Phase 4b
```

For the full happy-path walkthrough, see [`docs/ONBOARDING.md`](docs/ONBOARDING.md).

---

## Project structure

```
lib/
  core/                     # cross-feature primitives
    auth/                   # AuthState + currentUserIdProvider
    db/                     # Drift schema, tables, migrations
    geo/                    # GeoJSON decode, polygon/polyline math
    i18n/                   # ARB sources (gen-l10n target)
    location/               # geolocator wrappers
    mapbox/                 # offline tile-pack adapter
    photos/                 # camera + image processor + storage
    router/                 # go_router config + auth/lock redirects
    security/               # BiometricGate
    supabase/               # client provider
    sync/                   # outbox, worker, retry, bundle export, providers
  features/
    assignment/             # Get Maps + assignment lock state
    auth/                   # login + AuthStateNotifier
    home/                   # home screen + progress card
    map/                    # MapScreen + Mapbox renderer
    new_feature/            # add-new pin/polygon flow
    review/                 # ReviewScreen + use cases (Phase 4b)
    survey/
      building_form/        # building survey + sections + autosave
      road_form/            # road survey + sections + autosave
      olp_survey/           # household survey + scoring
      photo_capture/        # photo strip + capture flow
  generated/l10n/           # generated AppLocalizations (do not edit)
  main.dart                 # entry point + ProviderScope wiring
  app.dart                  # MaterialApp.router + theme + l10n delegates

supabase/
  migrations/               # 010 SQL migrations through Phase 4b
  seed/                     # ra_9514_types reference data

docs/superpowers/
  specs/                    # phase design docs (one per phase)
  plans/                    # phase implementation plans (TDD-style)

test/                       # 294 tests, mirrors lib/ structure
```

---

## Phase roadmap

The app shipped in 7 phases. See `docs/superpowers/specs/` for the design behind each.

| Phase | Tag | What landed |
|---|---|---|
| 0 — Foundations | `phase-0-foundations` | Flutter scaffold, Drift, Supabase, auth, biometric infra |
| 1 — Map + Get Maps | `phase-1-map` | Assignment download, Mapbox, offline tiles, GPS pin |
| 2 — Building form | `phase-2-form` | Tap-polygon → form, autosave, photos, multi-tab |
| 3a — Roads + Add-new | `phase-3a-roads-and-add-new` | Road form, long-press-to-add |
| 3b — OLP | `phase-3b-olp` | Household survey + Lebel ng Kahinaan scoring |
| 4a — Sync engine | `phase-4a-sync-engine` | Outbox, worker, retry, WorkManager, 409 bundle |
| 4b — Upload flow | `phase-4b-upload-flow` | Review screen, Upload Data, biometric gate, lock state |
| **5 — Polish** *(next)* | — | Sentry, EN+TL review, accessibility, field-walk script |

---

## Documentation

- **Master spec** — `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md` (architecture, schema, sync model, validation rules, phased plan)
- **Per-phase specs** — `docs/superpowers/specs/2026-04-2*-firecheck-phase-*-design.md`
- **Per-phase plans** — `docs/superpowers/plans/2026-04-2*-firecheck-phase-*.md` (TDD-style, one task at a time)
- **Onboarding for new contributors** — [`docs/ONBOARDING.md`](docs/ONBOARDING.md)

---

## Contributing

Read [`docs/ONBOARDING.md`](docs/ONBOARDING.md) first. Then, in order:

1. Pick something from Phase 5 (or open a discussion for a new phase).
2. Write a design spec in `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and get team review.
3. Write a TDD-style implementation plan in `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`.
4. Implement task-by-task; commit per task with a descriptive message.
5. Tag the new phase, push, open a PR against the previous phase's snapshot branch.

---

## License

Project for an academic group. License TBD by the team.
