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

### Map tiles

Map search and the listing map need a tile source. Debug builds use OpenStreetMap's public tiles (as the website does outside production; their usage policy does not allow them in a published app). Other builds need it set with `--dart-define`; without it the map is off and search stays a list:

```bash
flutter run --dart-define=MAP_TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png --dart-define="MAP_ATTRIBUTION=© Example contributors"
```

Use the same source and attribution as the website. A provider key, if any, goes in the URL at build time and is never committed.

### Push notifications

Push runs through Firebase Cloud Messaging, configured with `--dart-define`, so no `google-services.json` or `GoogleService-Info.plist` is committed. Without these values push is off and nothing else changes.

```bash
flutter run --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
```

What the owner of the Firebase project supplies:
- a Firebase project with an Android app for `com.rightproperty365.rightproperty365`: its API key, app ID, sender ID and project ID;
- for iOS, an iOS app in the same project (`FIREBASE_IOS_APP_ID`) and an APNs authentication key uploaded to it (needs an Apple developer account), plus the Push Notifications capability in Xcode (needs a Mac);
- the server side (sending, device registration) is the API's.

The phone asks for notification permission only when the person turns notifications on after signing in, never at first launch. The push identifier is removed on sign-out and account deletion.

### Permissions

| Permission | When it is asked | Why |
| --- | --- | --- |
| Notifications (Android 13+, iOS) | When notifications are turned on, after sign-in | Enquiry, appointment and application updates |
| Location (while in use) | When "Near me" is tapped on map search, after the reason is shown | Properties near you; the app works fully if refused |
| Camera, photos | When a receipt, document or maintenance photo is added | Upload; nothing is kept on the phone |

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

`test/live_api_test.dart` runs the app's own repositories against a running API and is skipped unless `RP_LIVE_API` is set. Use it with the backend in development mode (in-memory stores, sample accounts, log mailer; see the backend's `docs/sample-accounts.md`). It changes data: it sends a request, accepts an appointment, moves a lead, signs a lease with a landlord stamp and deletes `sales.agent@example.test`. Restart the API before running it again. Never point it at production.

```bash
RP_LIVE_API=http://localhost:8080 RP_LIVE_PASSWORD=<DEV_SEED_PASSWORD> RP_LIVE_CODE=1234 flutter test test/live_api_test.dart
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
    location.dart            Near me (geolocator) and the map tile source
    market_time.dart         Times in the market's IANA time zone (package:timezone), named
    widgets/                 Brand outline, card, section heading, logo; badges; Reveal; AsyncView;
                             SearchableSelectField
  features/
    listings/                Listing model and repository; home, search, detail, cards
    directory/               Profile model, directory and business-enquiry repositories; hub, lists, profile
    enquiries/               Shared contact model, receipt and the enquiry form
    property_requests/       Listing request model, repository and screen
    auth/                    User model, auth repository, token store, controller; sign-in, register,
                             account, Account Management and Delete Account, confirm email, forgot and reset password
    applications/            Applying (form, files, autosave), My Applications, the organisation inbox
    venues/                  Hourly venue bookings: availability, estimate, requests, customer and host screens
    contacts/                The agent CRM: books, contacts, notes, stages, reminders, from a request
    analytics/               Listing statistics: the event tracker, impressions, the reports and the statistics screen
    saved/                   Saved properties: repository, the hearts (SavedListings) and the Saved tab
    activity/                ActivityStore (on-device), the account's own requests (my_requests_repository.dart)
                             and the Activity screen: My Enquiries, My Viewings, Saved Properties
    appointments/            Viewings and consultations: the customer's and the received side, one detail screen
    inbox/                   Enquiries received by professionals, assigning, and working a lead (stage, notes)
    workspace/               Dashboard (organisations, capabilities, counters) and the account's "Your work" section
    team/                    Team members, roles, invitations, accepting an invitation, the assign sheet
    leases/                  Lease models and repository; list, detail (send, cancel, delete, PDF) and the draft form
    signing/                 Documents to sign, the guided signing screen, Adopt your signature, Adopt your stamp
                             (stamp.dart, adopt_stamp.dart), My signature,
                             PDF pages (pdf_pages.dart)
    markets/                 Market configuration
    shell/                   Bottom navigation
assets/
  data/                      listings.json, directory.json (mirrored from the web)
  images/                    Sample photos and CREDITS.md (Unsplash licence)
  brand/                     Logo and app icon sources
  fonts/signature/           Great Vibes, Kaushan Script, Allura and their OFL licences (copied from the web)
tool/sync_web_data.mjs       Mirrors the web sample data and photos
test/                        Data, repository, auth and screen tests; live_api_test.dart (opt-in, see Checks)
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

These mirror the website's `/agent/team`, `/agent/leases`, `/account/signing` and `/sign/[token]`, on API 0.26.0 (and 0.26.1's `can_edit` on listings when the API sends it).

- **What shows comes from the dashboard.** `GET /v1/me/dashboard` decides the "Your work" tiles on the Account tab: Documents to sign and My signature for everyone signed in, Leases when `capabilities.creates_leases`, a Team tile per organisation with `can_manage_team`, and Join a team for professional accounts. The API checks every action again.
- **Teams.** Members with their role, job title, open enquiries and status; an Agency Principal or Administrator changes a role (only to the API's `allowed_roles`), the job title, suspends, reactivates or removes, and invites by email with a role (an owner: administrator, agent or staff; an administrator: agent or staff). Pending invitations can be cancelled. Refusals such as `ROLE_NOT_ALLOWED` or `LAST_OWNER` are said in plain words (`teamMessage`).
- **Invitations.** `/invitations/{token}` matches the emailed link, and the Join a team screen accepts a pasted link. It shows the agency, role and inviter before signing in, then accepts with `POST /v1/invitations/{token}/accept`.
- **Assigning enquiries.** In Enquiries Received, someone whose organisation has `can_assign_work` sees Assign or Reassign on each listing enquiry; the sheet lists the members who can hold leads (not staff) and can return it to the agency inbox. The call sends an idempotency key.
- **Leases.** Drafts are made from a published template (`GET /v1/me/lease-templates`): the agency's own templates are listed first under "Your templates", then the platform's "Samples"; a template of another of the caller's organisations is caught before sending. Templates are designed, copied and published on the website. A draft has an optional listing from `GET /v1/me/listings` (48 per page, the API's limit; a listing the agent can see but not edit is refused by the API with plain wording), 1 to 5 landlords and tenants, "Landlords also stamp the lease" (`landlord_stamp`: each landlord gets a STAMP field next to their signature), term, rent, payment day (a weekday for weekly rent), deposit, notice and optional clauses. Each save renders the draft PDF; the detail screen shows it in the app, the history, and Send for signing (message and reminders), Cancel and Delete when the API allows them.
- **Signing, the Adobe Sign way.** Documents to sign lists `GET /v1/me/signing-requests`; opening one asks for a fresh link token and opens `/sign/{token}`, the same path as the emailed link. The pages are drawn by the phone's own PDF renderer (`pdfx`: Android `PdfRenderer`, iOS PDFKit) with the fields placed over them. Start / Next goes through the signer's required fields in reading order (page, top, left); yellow boxes are theirs; name and date fill themselves. A signature or initials box opens **Adopt your signature**: Type (in the three script styles), Draw (a PNG at twice the pad's size, at most 200 KB) or Upload (PNG or JPEG of at most 500 KB, picked from the photo library). A STAMP field opens **Adopt your stamp**: shape (round, oval, rectangle), ink (blue, red, black, green, purple), the name along the top (required, 60 characters), up to 3 middle lines of 30, bottom text and whether to print the signing date. It starts from the signer's saved stamp (`saved_stamp` in the signing view, or `GET /v1/me/signature`) or their name in capitals. The API draws it: `POST /v1/stamp-preview` (no session, rate-limited) is asked for once typing pauses for 0.6 s and the preview stays in view while the text is edited; the adopted stamp is sent as `stamp` with Click to sign. Then the emailed code (resend after 30 seconds or `Retry-After`), the consent, and Click to sign. Declining asks for a reason. Every ending (signed, completed, declined, cancelled, expired, not your turn) shows the document read-only.
- **Typed signature fonts.** FLOWING, BOLD and CLASSIC are drawn in Great Vibes, Kaushan Script and Allura, the fonts the API uses (SIL Open Font License 1.1). The TTFs and their OFL texts are copied from the web repository's `src/fonts/signature/`; keep them in step if the API changes fonts.
- **Saved signature, initials and stamp.** My signature saves them with `PUT /v1/me/signature`. That call removes a signature or initials it does not get, so every save sends both again; the stamp is kept unless it is sent (or `null` to remove it).
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
- **Activity.** Signed in, My Enquiries is `GET /v1/me/property-requests` (the customer status: Received, In progress, Responded, Viewing scheduled, Closed; never the lead stage or notes) with each request's history, and My Viewings is `GET /v1/me/appointments` (upcoming and past) where the customer cancels, proposes another time or accepts the time the professional proposed. Requests sent as a guest are never linked to an account, so the phone also keeps what it sent (`ActivityStore`, `shared_preferences`: reference, title, recipient, date and receipt status, never the message or contact details) and lists those under "Sent from this phone". Saved properties are on the account (API 0.27.0, below).
- **Saved properties (API 0.27.0).** A heart on every listing card (outside the card, so it is its own button) and on the listing page. Saving needs an account: a guest is told why, signs in, comes back to the same page and the property is saved. Hearts come from `GET /v1/me/saved-listings/ids`, changes are `PUT` / `DELETE /v1/me/saved-listings/{id}`, shown at once and undone with a message if refused. Saved Properties in Activity is `GET /v1/me/saved-listings`: available ones open their listing; expired, let, sold or withdrawn ones are greyed with the API's label, never linked, and can be removed. Properties saved on the phone before 0.27 are moved to the account at sign-in and then forgotten on the phone. Nothing saved is kept on the phone after sign-out.
- **Video tours (API 0.28.0).** The listing page asks `GET /v1/listings/{slug}` for its `video` (the bundled sample listings share their slugs with the API) and, when there is one, shows "Video tour": YouTube's thumbnail as a poster and "Play the video tour (YouTube)", which hands over to the YouTube app or youtube.com (YouTube's official player) at the advertiser's start time. Nothing is played, downloaded or re-hosted in the app, and nothing loads from YouTube except the poster. A poster that cannot load (a removed video) becomes "This video can't be shown here" with Watch on YouTube; the privacy note and YouTube's privacy policy are next to it. No section without a video or without the API. An in-app embedded player would need a WebView package; the hand-off was chosen instead. The "Video tour" badge on cards waits for listings from the API (the bundled cards have no `has_video`).
- **Map search (API 0.29.0).** Search has a List / Map switch when there is a tile source; the list is the default and always works. The map searches the API (`GET /v1/listings` with `has_location=true`, then `bbox` from "Search this area" after the map is moved; 48 per page, the API's limit, and it says when there are more). Exact locations are pins; approximate ones (rounded by the API to about 1 km) are a shaded 1 km area with a small button, never a pin. Every pin and area is a button named after its listing and price, and the same results are listed under the map. It says how many results have no location. "Near me" explains why first, then asks for permission (geolocator, low accuracy) and searches the area around the phone; refusal or location turned off is said plainly and nothing else changes. The tile provider's attribution is always shown. The listing page has a small "Location" map that does not move until tapped, with an "Approximate location" note; it is absent without a location or a tile source.
- **Listings from the API, partly.** Home and the list view still browse the bundled sample. Map results come from the API, and a listing the sample does not have (London, Mauritius, short stays) opens from the API (`SampleThenApiListingRepository`), with uploaded photos from the API. Moving browsing and search to the API as well is the next step.
- **Listing statistics (API 0.30.0).** The app sends the four events the API takes from clients, to `POST /v1/analytics/events`: `property_card_impression` (a card at least half on screen for a second, once per card per screen; placement and rank), `listing_detail_view` (once per listing page), `contact_click` (once per request page, when the request is sent) and `youtube_play_intent`. Saves, enquiries, viewing requests and confirmations are counted by the API and never sent. Each event has its own UUID, so a retry is never counted twice; events are batched (at most 50, every 15 s, at 20 waiting, and when the app goes to the background), kept while offline or rate-limited, and dropped when refused or older than the API accepts. The session is a random pseudonym held in memory only, rotating at local midnight, after 24 h and on restart; `source` is `internal` and `device` is `mobile` or `tablet`. Phones send no Do Not Track signal, so Account has "Count my visits anonymously" (on by default, as first-party measurement): off sends nothing at all. Listing statistics (Your work, for those who manage listings) is `GET /v1/analytics/organisations/{id}` for 24 hours (near real time), 7 or 30 days: totals, conversion and contact rate with the API's definitions, a daily views chart with a spoken summary and a table, sources, devices, top listings, the bot and late counts, "How we count" and detailed reports on the website (`WEB_BASE_URL`). Agents see only their assigned listings.
- **Contacts (agent CRM, API 0.31.0).** Contacts (Your work) opens the contact book of each organisation the person belongs to, or an approved landlord's or seller's own book (their user ID). The book is shared across the agency; STAFF read it only. The list searches name, email and phone, filters by lead stage (with counts) and by a reminder due, and pages 25 at a time. A contact shows emails, phones, tags, type, source, relationship owner, marketing permission with when and how it was recorded, linked enquiries and appointments (and whether they were matched by email or phone), linked properties and the history, newest first (an unknown kind shows the API's own sentence). Writers add a note (append-only), move the stage (any to any, with an optional reason) and add or complete reminders. New contact warns when the email or phone is already in the book (`409 CONTACT_DUPLICATE`) and offers to open that contact or create a separate one anyway. "Add to contacts" on a received request and on an appointment creates the contact, or links to the existing one. Import, export, merging, tags editing and reassigning stay on the website (a link for owners and managers).
- **Applications (API 0.32.0).** A listing whose public `applications` is open shows "Apply" (paused or closed intake says so). Applying needs an account: `POST /v1/me/applications` starts or reopens the draft on the form version attached (`409 APPLICATIONS_CLOSED` is shown in the API's words). The form is one step per section, then a review: short and long text, number, date, single and multiple choice, and files (PDF, JPG, PNG, WebP, HEIC, DOCX; 10 MB each, up to the field's limit; a photo from the camera or a file from the phone, asked for only when added). Questions appear and disappear with `visible_if`; hidden ones are not required. Answers save themselves 0.8 s after a change (`PATCH`, merged) and once more when the screen closes; a draft can be reopened from Activity, My Applications. The review shows the purpose, the privacy notice and the retention period; submitting shows the reference (RPA-APP-...). An application waiting for more information shows what was asked and can be sent again; one can be withdrawn. The organisation's Applications (Your work) lists them by status with counts; an application shows the answers in the layout of the version it was submitted on (opening it is audited by the API), lets an Agency Principal, Administrator or the listing's agent move it on as `allowed_transitions` allow, ask for more information and add internal notes. Opening the applicant's files, and building and attaching forms, are on the website. Another organisation's or customer's application is "not found".
- **Hourly venue bookings (API 0.33.0).** A showroom or venue whose public `hourly_booking` is enabled shows "Book by the hour". The booking screen reads `GET /v1/venues/{id}/availability` (62 days): only days with a free slot are offered, start times are on the venue's increment and only where the minimum duration is free, durations run from the minimum to the maximum within one opening range and clear of booked time (which already includes cleaning buffers). Times are in the venue's time zone, named, with the phone's own time noted when it differs. Each choice asks `POST /v1/venues/{id}/quotes` for the itemised estimate, shown in bill order (rate and fixed fees, subtotal, percentage fees such as VAT, total, then the deposit "payable to the host if confirmed") with the no-payment notice, whatever order the API lists the lines in. Sending (signing in first if needed) is `POST /v1/me/venue-bookings` with consent; it is a request, not a booking or a payment. Activity, Hourly Bookings lists the customer's requests; a booking shows its estimate, the cancellation policy with "free until", a proposed time to accept, and Cancel. Hosts (Your work, Hourly bookings; an organisation's or a direct owner's own) confirm, decline or cancel with a reason, and mark completed or no-show, as the API's `actions` allow; `SLOT_TAKEN` is explained. Rates, opening hours, fees and proposing a new time are on the website.
- **Appointments for professionals.** Viewing Appointments (Account, Your work, for professional accounts) is `GET /v1/inbox/appointments` from the start of today, grouped by day. The detail shows the customer's contact and offers exactly what the API's flags allow: confirm (or accept the customer's time), propose another time, it took place, no-show, cancel with a reason. `SLOT_TAKEN` and `INVALID_STATE` are said in plain words. Assigning appointments to a member is on the website.
- **Times.** Appointment times are shown in the market's time zone (`timezone`, for example Africa/Harare) and named, and a new time is picked in that zone and sent as UTC.
- **Working a lead.** Work it on a listing enquiry opens `GET /v1/agent/property-requests/{id}`: move the lead stage to one of `allowed_stages` (`PATCH`, nobody is emailed), add internal notes (never shown to the customer) and read the history.
- **Deleting the account.** Account, Settings, Account Management, Delete Account explains what deletion removes and keeps, asks for the password again and a confirmation, then calls `DELETE /v1/me`. On success the token and everything the phone kept are removed. `INVALID_PASSWORD` is shown on the field; `SOLE_OWNER` (the only owner of an organisation with members) and `ADMIN_ACCOUNT_CANNOT_SELF_DELETE` are explained. Name, email and password changes are on the website.
- **Platform administrators** cannot sign in to the app: the API answers `INVALID_CREDENTIALS` for them at the customer sign-in, and the message says that administrators sign in on the website.
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
- Leases: list, draft from the agency's own or a sample template (optionally with landlord stamps), edit, view the PDF, send for signing, cancel, delete
- Signing: documents to sign, guided signing over the PDF pages, Adopt your signature (type, draw, upload), Adopt your stamp (generated company stamp with a live preview), the emailed code and consent, decline; saved signature, initials and stamp
- Solicitors directory (empty until solicitor profiles exist)
- Email confirmation (by link or by pasting it, with resend) and password reset (request and set new password)
- Activity: My Enquiries with live status and history, My Viewings (cancel, propose a time, accept), requests sent from this phone, and saved properties
- Viewing Appointments for professionals (confirm, propose a time, completed, no-show, cancel) and working a lead (stage and internal notes)
- Account Management and Delete Account (`DELETE /v1/me`)
- Light and dark themes, official launcher icon and splash screen

## Not built yet

These are required by the specification and come later:

- Website links opening the app automatically (App Links and Universal Links). See "Email links" above for what the website and Apple set-up still need.
- Agent replies inside the app (replies go by email, phone or WhatsApp), opening applicants' files in the app, and the application form builder (both on the website).
- A month calendar view for appointments (the list is an agenda by day), assigning appointments, business-enquiry status changes, listing management, and statistics per single listing (on the website).
- Team join requests and the team audit trail (the API has them; the website shows them).
- Uploaded-PDF agreements (other than leases), placing fields, and designing, copying and publishing lease templates: done on the website.
- Saving or sharing a PDF to the phone's files; the app shows PDFs on screen only.
- Website signing and invitation links opening the app (they open the website until App Links and Universal Links are set up).
- Directory and listing data from the API. The app still bundles the earlier sample data, so the solicitor firms and other profiles now in the backend do not appear yet.
- Onboarding for professional roles (details and document upload) in the app; it exists in the API and on the website.
- There is no payment in the app, by design: subscriptions are recorded by Platform Administrators on the web
- Push notifications and device token registration
- Photo galleries
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
