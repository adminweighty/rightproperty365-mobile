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

On staging the signing screen can show the demo signing code as a hint:

```bash
flutter run --dart-define=API_BASE_URL=https://staging-api.rightproperty365.com --dart-define=DEMO_SIGNING_CODE=1234
```

Leave `DEMO_SIGNING_CODE` out of production builds.

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

## Email links (confirm email, reset password)

The API emails links of the form `{WEB_BASE_URL}/verify-email?token=...` and `{WEB_BASE_URL}/reset-password?token=...`. The app has routes with the same paths, so a link opened on the phone lands on the right screen. There are three ways in:

| Way in | Works today | Needs |
| --- | --- | --- |
| Paste the link | Yes | Nothing. The confirm and reset screens accept the whole link from the email. |
| App scheme `rightproperty365://app/verify-email?token=...` | Yes, once installed | Nothing on the website. The backend would have to send this form of link. |
| Website link opens the app (Android App Links, iOS Universal Links) | Not until set up | See below. |

To make the website links open the app without asking:

- **Android:** the manifest already declares `https://rightproperty365.com` and `https://www.rightproperty365.com` for `/verify-email` and `/reset-password`. The website must serve `/.well-known/assetlinks.json` naming package `com.rightproperty365.rightproperty365` and the SHA-256 fingerprint of the release signing key. If the production `WEB_BASE_URL` uses a different host, change the hosts in `android/app/src/main/AndroidManifest.xml`.
- **iOS:** add the Associated Domains capability (`applinks:rightproperty365.com`) in Xcode with the Apple team, and serve `/.well-known/apple-app-site-association` from the website. Not done; it needs a Mac and the Apple developer account.

Try a link on an Android emulator or device:

```bash
adb shell am start -a android.intent.action.VIEW -d "rightproperty365://app/verify-email?token=PASTE_TOKEN"
```

In development the API writes the links to its log instead of sending email.

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
    widgets/                 Brand outline, card, section heading, logo; badges; Reveal; AsyncView;
                             SearchableSelectField
  features/
    listings/                Listing model and repository; home, search, detail, cards
    directory/               Profile model, directory and business-enquiry repositories; hub, lists, profile
    enquiries/               Shared contact model, receipt and the enquiry form
    property_requests/       Listing request model, repository and screen
    auth/                    User model, auth repository, token store, controller; sign-in, register,
                             account, confirm email, forgot and reset password
    activity/                ActivityStore (on-device) and the Activity screen: requests and saved
    inbox/                   Enquiries received by professionals, with assigning to a team member
    workspace/               Dashboard (organisations, capabilities, counters) and the account's "Your work" section
    team/                    Team members, roles, invitations, accepting an invitation, the assign sheet
    leases/                  Lease models and repository; list, detail (send, cancel, delete, PDF) and the draft form
    signing/                 Documents to sign, the guided signing screen, Adopt your signature, My signature,
                             PDF pages (pdf_pages.dart)
    markets/                 Market configuration
    shell/                   Bottom navigation
assets/
  data/                      listings.json, directory.json (mirrored from the web)
  images/                    Sample photos and CREDITS.md (Unsplash licence)
  brand/                     Logo and app icon sources
  fonts/signature/           Great Vibes, Kaushan Script, Allura and their OFL licences (copied from the web)
tool/sync_web_data.mjs       Mirrors the web sample data and photos
test/                        Data, repository, auth and screen tests
```

## Real-estate terminology

Every role name shown in the app comes from `lib/core/terminology.dart`, so the wording is the same on every screen. Role names are written as titles.

| API code | Shown as | Category |
| --- | --- | --- |
| `CONSUMER` | Prospective Buyer | Property Seekers |
| `TENANT` | Prospective Tenant | Property Seekers |
| `AGENT` | Estate Agent | Real Estate Professionals |
| `SALES_AGENT` | Sales Agent | Real Estate Professionals |
| `LETTINGS_AGENT` | Lettings Agent | Real Estate Professionals |
| `PROPERTY_MANAGER` | Property Manager | Real Estate Professionals |
| `SOLICITOR` | Solicitor | Real Estate Professionals |
| `AGENCY_OWNER` | Agency Principal | Real Estate Businesses |
| `AGENCY_ADMIN` | Agency Administrator | Real Estate Businesses |
| `AGENCY_STAFF` | Agency Staff | Real Estate Businesses |
| `LANDLORD` | Landlord | Property Owners |
| `PRIVATE_SELLER` | Property Seller (Vendor) | Property Owners |
| `DEVELOPER`, `HOST`, `SERVICE_PROVIDER` | Property Developer, Host, Property Service Provider | Other property businesses |

- On a listing, the agent is a **Sales Agent** (for sale) or **Lettings Agent** (to rent), and an owner listing directly is a **Property Seller** or **Landlord**.
- In an organisation, `OWNER` is the Agency Principal, `MANAGER` the Agency Administrator (Property Manager outside an agency), `AGENT` an Estate Agent. An agency is a **Real Estate Agency**.
- Verification statuses: Pending Verification, Under Review, Changes Requested, Approved, Rejected, Suspended.
- Enquiry statuses: New Enquiry, Assigned, Contacted, Viewing Requested, Viewing Scheduled, Follow-up Required, Converted, Closed. The API's current statuses are mapped onto these.
- **The API's wording wins.** Sign-up shows the roles, labels and group headings from `GET /v1/reference/account_roles`, and a membership shows the API's `role_label` when it sends one. The table above is what the app falls back to (offline, or on screens where the API sends only a code), and the source of the one-line description under each role. A role added or switched off on the server follows without an app update.
- A **Landlord** is an individual owner. A **Property Manager** belongs to a property-management organisation, and a **Solicitor** to a Law Firm.
- The **Solicitors** directory (`solicitors` kind) is always shown. It is empty in this app until the bundled directory data is replaced by the API's (see "Not built yet").

## Teams, leases and signing

These mirror the website's `/agent/team`, `/agent/leases`, `/account/signing` and `/sign/[token]`, on API 0.24.1.

- **What shows comes from the dashboard.** `GET /v1/me/dashboard` decides the "Your work" tiles on the Account tab: Documents to sign and My signature for everyone signed in, Leases when `capabilities.creates_leases`, a Team tile per organisation with `can_manage_team`, and Join a team for professional accounts. The API checks every action again.
- **Teams.** Members with their role, job title, open enquiries and status; an Agency Principal or Administrator changes a role (only to the API's `allowed_roles`), the job title, suspends, reactivates or removes, and invites by email with a role (an owner: administrator, agent or staff; an administrator: agent or staff). Pending invitations can be cancelled. Refusals such as `ROLE_NOT_ALLOWED` or `LAST_OWNER` are said in plain words (`teamMessage`).
- **Invitations.** `/invitations/{token}` matches the emailed link, and the Join a team screen accepts a pasted link. It shows the agency, role and inviter before signing in, then accepts with `POST /v1/invitations/{token}/accept`.
- **Assigning enquiries.** In Enquiries Received, someone whose organisation has `can_assign_work` sees Assign or Reassign on each listing enquiry; the sheet lists the members who can hold leads (not staff) and can return it to the agency inbox. The call sends an idempotency key.
- **Leases.** Drafts are made from the caller's approved templates (`GET /v1/me/lease-templates`), with an optional listing from `GET /v1/me/listings` (48 per page, the API's limit; a listing the agent can see but not edit is refused by the API with plain wording), 1 to 5 landlords and tenants, term, rent, payment day (a weekday for weekly rent), deposit, notice and optional clauses. Each save renders the draft PDF; the detail screen shows it in the app, the history, and Send for signing (message and reminders), Cancel and Delete when the API allows them.
- **Signing, the Adobe Sign way.** Documents to sign lists `GET /v1/me/signing-requests`; opening one asks for a fresh link token and opens `/sign/{token}`, the same path as the emailed link. The pages are drawn by the phone's own PDF renderer (`pdfx`: Android `PdfRenderer`, iOS PDFKit) with the fields placed over them. Start / Next goes through the signer's required fields in reading order (page, top, left); yellow boxes are theirs; name and date fill themselves. A signature or initials box opens **Adopt your signature**: Type (in the three script styles), Draw (a PNG at twice the pad's size, at most 200 KB) or Upload (PNG or JPEG of at most 500 KB, picked from the photo library). Then the emailed code (resend after 30 seconds or `Retry-After`), the consent, and Click to sign. Declining asks for a reason. Every ending (signed, completed, declined, cancelled, expired, not your turn) shows the document read-only.
- **Typed signature fonts.** FLOWING, BOLD and CLASSIC are drawn in Great Vibes, Kaushan Script and Allura, the fonts the API uses (SIL Open Font License 1.1). The TTFs and their OFL texts are copied from the web repository's `src/fonts/signature/`; keep them in step if the API changes fonts.
- **Why `pdfx`.** `pdfrx` 2.x compiles a C library for the host even in `flutter test`, which needs Visual Studio on Windows, and `pdfrx` 1.x no longer compiles with this Dart. `pdfx` uses the platform renderers through a plain plugin. Tests use a fake renderer (`FakePdfRenderer`), so no PDF engine runs in tests.

## Conventions

- **Colours come from `context.colors`.** Screens never use raw hex or import `tokens.dart`.
- **Brand styling.** Cards use `BrandCard`: the indigo-to-turquoise gradient outline shows while pressed, focused or hovered, and always on featured listings and sponsored profiles. Section titles use `SectionHeading` (3px gradient rule). The search field uses `BrandSearchField`. Use the logo only through `BrandLogo`; never recolour or retype it.
- **Signing in is two steps.** The password step (`POST /v1/auth/login`, `token_delivery: bearer`) only returns a challenge; the API emails a code, and `POST /v1/auth/login/verify` exchanges it for the bearer token. The code field accepts 4 to 6 digits (staging also takes a shorter demo code), fills from the email with the one-time-code hint, and sends itself when all `code_length` digits are in. A new code can be asked for after 30 seconds, or after the API's `Retry-After`; an expired code goes back to the password step.
- **Sign-up is one side or the other.** The create-account screen first asks "I am looking for a property" or "I work in property, or I own property to sell or let", then shows only that side's roles. The API refuses a registration that mixes Property Seeker roles with any other role. Which roles are seeker roles comes from the API (`requires_verification: false`).
- **Sign-up needs the captcha.** The screen shows the question from `GET /v1/auth/captcha` and sends `captcha: {captcha_id, answer}` with the registration; the API refuses a registration without it. A question lasts ten minutes and one attempt, so the screen fetches a new one after any refused registration and when it expires, and never caches it. If the question cannot be loaded, the screen says the account cannot be created yet and offers a retry.
- **Every dropdown is searchable.** Use `SearchableSelectField` (`lib/core/widgets/searchable_select.dart`) for any pick-one list, short or long; do not use `DropdownButton`. It opens a sheet with a search box: typing matches any part of a label or its keywords, ignoring case and accents; group headings stay while their options match; "No matches" when nothing fits; an "any" row clears the choice where one is allowed; long lists show 100 options and ask for more typing. Pick-many lists (the sign-up roles) filter in place with a search box and keep ticked items ticked. This mirrors the web's `SearchableSelect`.
- **Contact is enquiry-only.** No screen shows a phone number or email address for a listing, agent or profile. Listing enquiries go to `POST /v1/property-requests`; directory enquiries go to `POST /v1/business-enquiries`. There is a test that fails if a profile screen shows contact details.
- **Say only what the system knows.** A saved enquiry is "received". It is never described as delivered or read.
- **Sponsored is always labelled.** Sponsored profiles sort first and carry a "Sponsored" badge.
- **Idempotency.** Enquiry repositories reuse the key when unchanged content is retried and create a new one when the content changes.
- **Sessions.** Sign-in uses `token_delivery: "bearer"`. The token is kept in the Android Keystore / iOS Keychain (`flutter_secure_storage`) and sent as `Authorization: Bearer`. When signed in, enquiries omit name and email and the API uses the account. Roles decide what is shown only; the API authorises every request.
- **Activity is kept on the phone.** Saved properties and the requests sent from this phone are stored with `shared_preferences` (`ActivityStore`). A stored request holds the reference, title, recipient, date and receipt status only, never the message or contact details. The API has no endpoint yet for a customer's own activity, so this does not follow the account to another device and statuses are not refreshed after sending. When that endpoint exists, put an API implementation behind the same screen.
- **Account emails never reveal whether an address is registered.** Registration, resend and reset screens say "if this address has an account", matching the API.
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
- Enquiries Received (the newest 100, with each request's lead stage and who it is assigned to) for Estate Agents, Agency Principals, Solicitors, Landlords, Property Sellers and other professionals, showing the enquiries the API authorises them to see; Agency Principals and Administrators can assign them
- Teams: members and roles, invitations, accepting an invitation
- Leases: list, draft from a template, edit, view the PDF, send for signing, cancel, delete
- Signing: documents to sign, guided signing over the PDF pages, Adopt your signature (type, draw, upload), the emailed code and consent, decline; saved signature and initials
- Solicitors directory (empty until solicitor profiles exist)
- Email confirmation (by link or by pasting it, with resend) and password reset (request and set new password)
- Activity: requests sent from this phone with their references, and saved properties
- Light and dark themes, official launcher icon and splash screen

## Not built yet

These are required by the specification and come later:

- Website links opening the app automatically (App Links and Universal Links). See "Email links" above for what the website and Apple set-up still need.
- Activity synced with the account: live request status, agent replies, applications and viewings. This needs a customer activity endpoint in the API.
- Replying to enquiries, changing their stage, viewing appointments and calendars, rental applications, listing management and listing statistics.
- Team join requests and the team audit trail (the API has them; the website shows them).
- Uploaded-PDF agreements (other than leases), placing fields, and lease templates: done on the website.
- Saving or sharing a PDF to the phone's files; the app shows PDFs on screen only.
- Website signing and invitation links opening the app (they open the website until App Links and Universal Links are set up).
- Directory and listing data from the API. The app still bundles the earlier sample data, so the solicitor firms and other profiles now in the backend do not appear yet.
- Onboarding for professional roles (details and document upload) in the app; it exists in the API and on the website.
- There is no payment in the app, by design: subscriptions are recorded by Platform Administrators on the web
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
