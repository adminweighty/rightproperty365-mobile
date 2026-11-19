# Data safety and App Privacy: DRAFT answers

**DRAFT for the owner to check.** These answers come from what the app's code sends and keeps, as of the "Release preparation" commit. The owner, with whoever is responsible for privacy, must:
- check them against the backend, the privacy policy and any processors (email, storage, Firebase);
- answer the legal questions;
- submit the forms.

They are not legal advice.

## How the app handles data, in short

- Everything goes over HTTPS to the RightProperty365 API (and Firebase for push). There are no advertising SDKs, no third-party analytics and no crash reporting.
- **Listing statistics** are first-party. The session is a random pseudonym held in memory, which changes daily and on restart. There's an in-app switch to turn them off.
- **On the phone:**
  - the session token, in the Keychain or Keystore;
  - the last answers for listings and the person's own activity, for offline reading;
  - saves waiting to be sent;
  - a few settings.
  - All of this is cleared at sign-out, except the settings.
- **Account deletion** is in the app (Account Management, Delete Account) and on the website.
- **Location** is asked for only by Map search's "Near me". Precise or approximate location from the phone is used to centre the map. The API receives the map's visible area for the search, not stored coordinates.

## Google Play: Data safety

| Data type (Play's names) | Collected? | Shared? | Why | Optional? |
|---|---|---|---|---|
| Name | Yes | With the agent, owner or provider the person contacts | Account management; app functionality | Required for an account |
| Email address | Yes | Same | Account management; app functionality | Required for an account |
| Phone number | Yes, when given | With the recipient of an enquiry | App functionality | Optional |
| User IDs | Yes (account ID) | No | Account management | Required for an account |
| Approximate and precise location | Yes, only for "Near me" | No | App functionality | Optional |
| Messages (enquiry text, comments) | Yes | With the recipient | App functionality | Optional per use |
| Photos | Yes, when uploaded (applications, receipts, maintenance, inspections) | With the organisation handling them | App functionality | Optional |
| Files and docs | Yes, when uploaded (application documents, receipts) | Same | App functionality | Optional |
| Financial info: "Other" | Yes, for businesses: rent records, cashbook entries the user types in; no card or bank details | No | App functionality | Optional |
| App interactions | Yes: listing views and impressions, pseudonymous | No | Analytics (the business's own listing statistics) | Can be turned off |
| Device or other IDs | Yes: the push token, only if push is turned on | No (Firebase delivers it) | App functionality (notifications) | Optional |
| Crash logs, diagnostics | No | | | |
| Contacts, calendar, SMS, health, web history | Not collected. Add to calendar hands the event to the phone's calendar and reads nothing | | | |

- Data encrypted in transit: **Yes**.
- People can request deletion: **Yes**, in the app and on the website.
- **"Shared"**: Play counts passing data to the other party a person chooses to contact as part of the app's function. Confirm how Play treats it (it may be "not shared" under user-initiated transfers).

## Apple: App Privacy

| Apple's data type | Collected | Linked to the person | Used for tracking | Purposes |
|---|---|---|---|---|
| Name, Email address | Yes | Yes | No | App Functionality |
| Phone number | Yes (optional) | Yes | No | App Functionality |
| Precise or Coarse location | Yes ("Near me") | No | No | App Functionality |
| Photos or videos | Yes (uploads) | Yes | No | App Functionality |
| Other user content (messages, documents, notes) | Yes | Yes | No | App Functionality |
| Other financial info (rent and cashbook records) | Yes (businesses) | Yes | No | App Functionality |
| User ID | Yes | Yes | No | App Functionality |
| Device ID (push token) | Yes (if push on) | Yes | No | App Functionality |
| Product interaction (listing views) | Yes | No (pseudonymous session) | No | Analytics |

- **Tracking (ATT):** none. The app does not link data with other companies' data for advertising, so no App Tracking Transparency prompt is needed.

## Questions for the owner

1. Do the backend or website add processors not listed here, for example an email provider, storage or maps tiles? List them in the privacy policy.
2. Retention: how long do enquiries, applications, uploaded files and analytics stay after an account is deleted? The answer belongs in the privacy policy.
3. Is the published privacy policy final and live at the URL above?
4. Are children a target audience? The draft assumes no (18+, property transactions).
