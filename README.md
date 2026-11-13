# RightProperty365 mobile

The Flutter app (Android and iOS) for RightProperty365, a multi-country property marketplace launching in Zimbabwe. This first cut is the customer app foundation: browse, search, view a listing and send a property request.

Related repositories: the Next.js web app and design system (`rightproperty365`) and the Go API (`RightProperty365-Backend`).

## Requirements

- Flutter 3.50 (stable), Dart 3.14. On the original development machine the SDK is at `C:\Users\User\Flutter`. Add `C:\Users\User\Flutter\bin` to `PATH`, and in Android Studio set **Settings > Languages & Frameworks > Flutter > Flutter SDK path** to `C:\Users\User\Flutter`.
- Android SDK with command-line tools and accepted licences (`flutter doctor --android-licenses`).
- iOS builds need a Mac with Xcode. They cannot be built on Windows.

Material widgets come from the `material_ui` package in this Flutter version. Import `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`, which is deprecated.

## Run

```bash
flutter pub get
```

```bash
flutter run
```

The app calls the Go API for property requests. Start the backend (`go run ./cmd/api` in the backend repository) before sending one.

### API base URL

Set at build time with `--dart-define`. The default is `http://10.0.2.2:8080`, which reaches a server on your computer from the Android emulator.

| Target | Value |
| --- | --- |
| Android emulator | `http://10.0.2.2:8080` (default) |
| iOS simulator | `http://localhost:8080` |
| Physical device | `http://<your computer's LAN address>:8080` |
| Staging or production | The HTTPS API URL |

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Plain HTTP is allowed in Android **debug** builds only (`android/app/src/debug/AndroidManifest.xml`). Release builds require HTTPS. iOS has no cleartext exception configured yet: if the simulator blocks `http://localhost`, add a debug-only App Transport Security exception rather than a global one. This has not been tested, because iOS cannot be built on Windows.

## Checks

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter build apk --debug
```

## Structure

```
lib/
  main.dart
  app/
    app.dart                 MaterialApp, repositories wired into AppScope
    app_scope.dart           InheritedWidget that hands repositories to screens
    router.dart              go_router routes and the Routes helpers
    theme/
      tokens.dart            Mirror of the web design/tokens/tokens.json
      app_colors.dart        Semantic colours (ThemeExtension), light and dark
      app_theme.dart         ThemeData built from the semantic colours
  core/
    config.dart              API base URL, privacy notice version
    api/api_client.dart      JSON client and ApiFailure (error envelope)
    format.dart              Money and area formatting
    widgets/                 AsyncView, MessageView, AppBadge
  features/
    listings/
      data/                  Listing model, ListingRepository, SAMPLE listings
      presentation/          Home, search, listing detail, listing card
    property_requests/
      data/                  Request model, receipt, API repository
      presentation/          Request screen and form
    markets/data/            Market configuration
    shell/                   Bottom navigation, Activity and Account placeholders
test/                        Model, repository and form tests
```

## Conventions

- **Colours come from `context.colors`.** Screens never use raw hex or import `tokens.dart`. `tokens.dart` is a straight copy of the web `tokens.json` (same names and values); when the web tokens change, update it to match and adjust `app_colors.dart` if a semantic mapping changed.
- **Every customer request goes to the Go API** at `POST /v1/property-requests`. Customer details are never sent straight to an agent or a third party.
- **Say only what the system knows.** A saved request is "received". It is never described as delivered or read.
- **Idempotency.** `ApiPropertyRequestRepository` reuses the key when unchanged content is retried and creates a new one when the content changes.
- **Money** is a decimal string with an ISO 4217 code, always shown with the code (`USD 385,000`).
- **Times** are sent to the API in UTC.
- **Accessibility.** 48dp touch targets, one spoken summary per listing card, headings marked for screen readers, and layouts that hold at 200% text size (there is a test for the form).
- **Repositories are interfaces.** `SampleListingRepository` is sample data and is replaced by an API implementation once listing endpoints exist. The six sample ids match the listings seeded in the backend's in-memory dev store.

## Design notes

The theme mirrors the web design system: indigo `#1900AC` brand, turquoise `#21DDBA` accent, sans-serif only. The brand typeface is Inter. Its font files are not bundled yet, so the app uses the platform sans (Roboto on Android, San Francisco on iOS). The launcher icon and in-app logo are still Flutter defaults; the approved logo kit is in the web repository under `design/assets/logo`.

## What is built

- Home with search, categories and featured listings
- Search with deal, category and text filters, and an empty state
- Listing detail
- Property request form with validation, API field errors, failure states and a receipt
- Light and dark themes
- Bottom navigation: Home, Search, Activity, Account

## Not built yet

These are required by the specification and come later:

- Sign-in and accounts. The backend contract is `POST /v1/auth/login` with `token_delivery: "bearer"` and `GET /v1/me`; the token must go in secure storage. Activity and Account are placeholders until then.
- My Property Activity (saved, enquired, applied, viewings)
- Push notifications and device token registration
- Deep links
- In-app account deletion (required by both app stores)
- Maps, photos, YouTube tours
- Real listing data from the API
- Agent features: inbox, listings, leads
- Bundled Inter font, app icon and splash screen
- Localisation and release signing

## Branches

| Branch | Purpose |
| --- | --- |
| `dev` | Integration branch. Feature branches merge here first. |
| `main` | Reviewed, release-ready code. |
| `production` | What is published to the stores. |
