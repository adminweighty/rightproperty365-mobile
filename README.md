# RightProperty365 mobile

The Flutter app (Android and iOS) for RightProperty365, a multi-country property marketplace launching in Zimbabwe. It mirrors what the web app offers customers: browse and search listings, explore the directories, send enquiries, and sign in.

Related repositories: the Next.js web app and design system (`rightproperty365`) and the Go API (`RightProperty365-Backend`).

## Requirements

- Flutter 3.50 (stable), Dart 3.14. On the original development machine the SDK is at `C:\Users\User\Flutter`. Add `C:\Users\User\Flutter\bin` to `PATH`, and in Android Studio set **Settings > Languages & Frameworks > Flutter > Flutter SDK path** to `C:\Users\User\Flutter`.
- Android SDK with command-line tools and accepted licences (`flutter doctor --android-licenses`).
- iOS builds need a Mac with Xcode. They cannot be built on Windows.
- Node 23.6 or newer, only for `tool/sync_web_data.mjs`.

Material widgets come from the `material_ui` package in this Flutter version. Import `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`, which is deprecated.

## Run

```bash
flutter pub get
```

```bash
flutter run
```

Enquiries and sign-in call the Go API. Start the backend (`go run ./cmd/api` in the backend repository) first. Its README lists the development accounts.

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

## Keeping in step with the web

Listings, directory profiles and photos are **sample data mirrored from the web repository**. Do not edit `assets/data` or `assets/images` by hand. After the web's `src/lib/data/listings.ts`, `directory.ts` or photos change, run:

```bash
node tool/sync_web_data.mjs C:\WindowsProjects\htdocs\rightproperty365
```

Then run the tests; several assert the mirrored counts (18 listings, 29 profiles), so update them when the web data grows.

Colours mirror the web's `design/tokens/tokens.json`. `lib/app/theme/tokens.dart` is a straight copy of the palette (same names and values) and `app_colors.dart` holds the semantic light and dark colours. When the web tokens change, update both to match.

Launcher icons and the splash screen are generated from `assets/brand` (official logo kit v4.1):

```bash
dart run flutter_launcher_icons
```

```bash
dart run flutter_native_splash:create
```

## Structure

```
lib/
  main.dart
  app/
    app.dart                 MaterialApp
    bootstrap.dart           Builds the services: sample data, API repositories, auth
    app_scope.dart           AppServices and the InheritedWidget that provides them
    router.dart              go_router routes and the Routes helpers
    theme/                   tokens.dart, app_colors.dart, app_theme.dart
  core/
    config.dart              API base URL, privacy notice version
    api/                     ApiClient (JSON, bearer token, error envelope), idempotency keys
    format.dart              Money and area formatting
    widgets/                 Brand outline, card, section heading, logo; badges; Reveal; AsyncView
  features/
    listings/                Listing model and repository; home, search, detail, cards
    directory/               Profile model, directory and business-enquiry repositories; hub, lists, profile
    enquiries/               Shared contact model, receipt and the enquiry form
    property_requests/       Listing request model, repository and screen
    auth/                    User model, auth repository, token store, controller; sign-in, register, account
    markets/                 Market configuration
    shell/                   Bottom navigation and the Activity placeholder
assets/
  data/                      listings.json, directory.json (mirrored from the web)
  images/                    Sample photos and CREDITS.md (Unsplash licence)
  brand/                     Logo and app icon sources
tool/sync_web_data.mjs       Mirrors the web sample data and photos
test/                        Data, repository, auth and screen tests
```

## Conventions

- **Colours come from `context.colors`.** Screens never use raw hex or import `tokens.dart`.
- **Brand styling.** Cards use `BrandCard`: the indigo-to-turquoise gradient outline shows while pressed, focused or hovered, and always on featured listings and sponsored profiles. Section titles use `SectionHeading` (3px gradient rule). The search field uses `BrandSearchField`. Use the logo only through `BrandLogo`; never recolour or retype it.
- **Contact is enquiry-only.** No screen shows a phone number or email address for a listing, agent or profile. Listing enquiries go to `POST /v1/property-requests`; directory enquiries go to `POST /v1/business-enquiries`. There is a test that fails if a profile screen shows contact details.
- **Say only what the system knows.** A saved enquiry is "received". It is never described as delivered or read.
- **Sponsored is always labelled.** Sponsored profiles sort first and carry a "Sponsored" badge.
- **Idempotency.** Enquiry repositories reuse the key when unchanged content is retried and create a new one when the content changes.
- **Sessions.** Sign-in uses `token_delivery: "bearer"`. The token is kept in the Android Keystore / iOS Keychain (`flutter_secure_storage`) and sent as `Authorization: Bearer`. When signed in, enquiries omit name and email and the API uses the account. Roles decide what is shown only; the API authorises every request.
- **Money** is a decimal string with an ISO 4217 code, always shown with the code (`USD 385,000`). **Times** are sent to the API in UTC.
- **Motion.** Entrance animations (`Reveal`), the rotating hero, the stat count-up and outline transitions are switched off when the OS asks for reduced motion.
- **Accessibility.** 48dp touch targets, one spoken summary per card, headings marked for screen readers, photo alt text, and layouts that hold at 200% text size (there is a test for the form).
- **Repositories are interfaces.** Sample repositories are replaced by API implementations once listing and directory endpoints exist.

## What is built

- Home: photo hero with the featured listings rotating, search, stats, just listed, featured, for sale, to rent, commercial and land, explore by city, popular suburbs, directory entry points
- Search with deal, category and text filters
- Listing detail with photo, the agent and agency (linked to their profiles), and the request form
- Directories: hub, list per kind (service providers grouped by trade), profile with services, areas, agents and listings, and an enquiry form
- Sign-in, registration with role selection, account screen with roles and memberships, sign-out
- Light and dark themes, official launcher icon and splash screen

## Not built yet

These are required by the specification and come later:

- Email confirmation and password reset inside the app. The links in those emails open the website; deep links are not set up.
- My Property Activity (saved, enquired, applied, viewings). The Activity tab is a placeholder.
- Agent and seller inbox, listing management
- Push notifications and device token registration
- In-app account deletion (required by both app stores)
- Maps, photo galleries, YouTube tours
- Real listing and directory data from the API
- Bundled Inter font (the platform sans is used), localisation, release signing
- Multi-factor authentication (not implemented by the backend yet)

## Branches

| Branch | Purpose |
| --- | --- |
| `dev` | Integration branch. Feature branches merge here first. |
| `main` | Reviewed, release-ready code. |
| `production` | What is published to the stores. |

Remote: `origin` is `https://github.com/adminweighty/rightproperty365-mobile.git`.
