# Store listing (draft for the owner)

Wording follows the app's own: "enquiry", "viewing", "listing". Nothing here promises what the app does not do. For example, there are no payments in the app, and no claim that bank transfers are verified.

## Names

- **App name** (Play ≤ 30, Apple ≤ 30): RightProperty365
- **Apple subtitle** (≤ 30): Property, agents and rentals
- **Play short description** (≤ 80): Find property to buy or rent, contact agents, and manage viewings and lets.

## Full description (Play ≤ 4000; also the App Store description)

RightProperty365 is a property marketplace launching in Zimbabwe.

For people looking for a home or premises:
- Search houses, flats, commercial property, land and holiday stays by area, price and type, on a list or a map.
- Save properties to come back to, even before you sign in.
- Send an enquiry or ask for a viewing; your contact details go only to the agent or owner.
- Follow your enquiries, viewings and rental applications in one place, and get notified when something changes.
- Apply for a rental with the agent's own form, and sign leases on your phone.
- Book showrooms and venues by the hour.
- Tenants see their tenancy, rent dues and payments as the landlord or agent records them, report repairs with photos, and read inspection reports.

For agents, landlords and property businesses:
- Answer enquiries and manage viewing appointments.
- Keep your contacts and their history in one book.
- See how your listings perform.
- Review rental applications, send leases for signing and manage your team.
- Track properties, tenancies, rent due and arrears, maintenance jobs and inspections.
- Keep your own cashbook per currency. Every amount stays in its own currency.

For service providers: receive enquiries and reviews, and reply to them.

Your account works the same on the website and in the app.

## Keywords (Apple, ≤ 100 characters, comma-separated)

property,rent,rental,house,flat,estate agent,landlord,tenant,Zimbabwe,Harare,lease,viewing

## Category and contacts

- **Category:** House & Home (Play); Lifestyle, or Business as the secondary (Apple).
- **Privacy policy URL:** https://rightproperty365.com/legal/privacy-policy (check it is live and final).
- **Support URL / email:** the owner to supply. Never a personal address.
- **Marketing URL:** https://rightproperty365.com

## Screenshots

Render them from real widgets with sample data only (no real people, emails or phone numbers):

```bash
RENDER_PITCH=1 flutter test test/pitch/render_pitch_screens_test.dart
```

They land in `build/pitch-screens` at 1170×2532 (iPhone 6.1" at @3x). Apple's required 6.9" set is 1320×2868 or 1290×2796: change the size in `_pumpApp` in the render test, or let App Store Connect scale them. Google Play takes 1080×1920 or larger, 16:9 or 9:16.

Suggested order, up to 8 per store:

1. `00-home.png`: Home and search
2. `03-map-search.png`: Map search
3. `02-listing-video-tour.png`: A listing with its video tour
4. `01-saved-properties.png`: Saved properties
5. `06-application-form-step.png`: Applying for a rental
6. `09-notifications-centre.png`: Notifications
7. `10-rent-schedule.png`: Rent schedule (landlords and agents)
8. `10-maintenance-request.png`: A maintenance job with its provider and costs

Spares: 05 (contacts), 07 (venue booking), 08 (books), 10-inspection-move-out, 10-reviews-profile.

Optional captions (short, plain): "Find your next home", "Search on the map", "Save what you like", "Apply in minutes", "Never miss an update", "Rent at a glance", "Repairs, sorted".
