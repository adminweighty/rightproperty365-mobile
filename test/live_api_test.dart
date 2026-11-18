// Runs the app's own data layer against a running API. Skipped unless
// RP_LIVE_API is set. Meant for the backend in development mode (in-memory
// stores, seeded sample accounts, log mailer); never point it at production.
//
//   RP_LIVE_API=http://localhost:8080 RP_LIVE_PASSWORD=<DEV_SEED_PASSWORD> \
//   RP_LIVE_CODE=1234 flutter test test/live_api_test.dart
//
// It changes data: it accepts an appointment, moves a lead, signs a lease
// and deletes the sample account sales.agent@example.test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/config.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';
import 'package:rightproperty365/features/activity/my_requests_repository.dart';
import 'package:rightproperty365/features/appointments/appointment_repository.dart';
import 'package:rightproperty365/features/analytics/analytics_repository.dart';
import 'package:rightproperty365/features/applications/applications_repository.dart';
import 'package:rightproperty365/features/analytics/analytics_tracker.dart';
import 'package:rightproperty365/features/activity/activity_store.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/contacts/contacts_repository.dart';
import 'package:rightproperty365/features/workspace/workspace.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/lead_repository.dart';
import 'package:rightproperty365/features/leases/lease_repository.dart';
import 'package:rightproperty365/features/signing/signing_repository.dart';
import 'package:rightproperty365/features/listings/data/api_listing_repository.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/data/video_tour.dart';
import 'package:rightproperty365/features/saved/saved_listings_repository.dart';
import 'package:rightproperty365/features/ledger/ledger_repository.dart';
import 'package:rightproperty365/features/signing/stamp.dart';
import 'package:rightproperty365/features/venues/venue_repository.dart';

final _base = Platform.environment['RP_LIVE_API'];
final _password = Platform.environment['RP_LIVE_PASSWORD'] ?? '';
final _code = Platform.environment['RP_LIVE_CODE'] ?? '1234';

final _sessions = <String, ApiClient>{};

/// An API client signed in as [email], the way the app signs in. Each
/// account signs in once: sign-in is rate-limited per IP.
Future<ApiClient> signedIn(String email) async =>
    _sessions[email] ??= await _signIn(email);

Future<ApiClient> _signIn(String email) async {
  final api = ApiClient(baseUrl: _base!);
  final auth = ApiAuthRepository(api);
  final step = await auth.login(email, _password);
  final session = switch (step) {
    CodeRequired(:final challenge) => await auth.verifySignInCode(
      challenge.id,
      _code,
    ),
    SignedIn(:final session) => session,
  };
  api.bearerToken = session.token;
  return api;
}

/// Runs [call]; on a 429 waits as the API asks (Retry-After) and tries once
/// more, as a person would.
Future<T> patiently<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiFailure catch (failure) {
    if (failure.status != 429) rethrow;
    // ignore: avoid_print
    print('rate limited (${failure.message}); waiting ${failure.retryAfter}');
    await Future<void>.delayed(
      (failure.retryAfter ?? const Duration(seconds: 30)) +
          const Duration(seconds: 1),
    );
    return call();
  }
}

void main() {
  final skip = _base == null ? 'RP_LIVE_API is not set' : null;

  test('a Property Seeker follows requests and viewings', () async {
    final api = await signedIn('consumer@example.test');
    // Listing 1 is Tendai Ncube's (agent@example.test), so the next test
    // finds it in the agent's inbox.
    final receipt = await ApiPropertyRequestRepository(api).submit(
      const PropertyRequestDraft(
        listingId: '0195c0de-0000-7000-8000-000000000001',
        requestType: RequestType.enquiry,
        message: 'Live check: is the house still available?',
        contactMethod: ContactMethod.email,
        contact: EnquiryContact(),
        consentAccepted: true,
        privacyVersion: AppConfig.privacyNoticeVersion,
      ),
    );
    final requests = await ApiMyRequestsRepository(api).list();
    expect(requests.items.map((r) => r.reference), contains(receipt.reference));
    for (final r in requests.items.take(1)) {
      final one = await ApiMyRequestsRepository(api).get(r.id);
      expect(one.timeline, isNotEmpty);
    }
    final mine = ApiMyAppointmentsRepository(api);
    final upcoming = await mine.list();
    expect(upcoming.items, isNotEmpty);
    final proposal = upcoming.items.firstWhere((a) => a.canAccept);
    final accepted = await mine.accept(proposal.id);
    expect(accepted.status, 'CONFIRMED');
    expect(accepted.timeline, isNotEmpty);
    // ignore: avoid_print
    print(
      'seeker: ${requests.total} requests, ${upcoming.total} upcoming; '
      'accepted ${accepted.reference}',
    );
  }, skip: skip);

  test('an Estate Agent works a lead and an appointment', () async {
    final api = await signedIn('agent@example.test');
    final received = ApiReceivedAppointmentsRepository(api);
    final page = await received.list(from: DateTime.now().toUtc());
    expect(page.items, isNotEmpty);
    final one = await received.get(page.items.first.id);
    expect(one.contactName, isNotNull);

    final enquiries = await ApiInboxRepository(api).received();
    final lead = enquiries.firstWhere((e) => e.requestId != null);
    final leads = ApiLeadRepository(api);
    final opened = await leads.get(lead.requestId!);
    expect(opened.allowedStages, isNotEmpty);
    final moved = await leads.moveTo(
      lead.requestId!,
      opened.allowedStages.first.stage,
    );
    expect(moved.stage, opened.allowedStages.first.stage);
    final noted = await leads.addNote(lead.requestId!, 'Live check note');
    expect(noted.notes.last.mine, isTrue);
    // ignore: avoid_print
    print(
      'agent: ${page.total} appointments; moved ${lead.reference} to '
      '${moved.stage}',
    );
  }, skip: skip);

  test(
    'a lease with landlord stamps is signed and stamped',
    () async {
      final agent = await signedIn('agent@example.test');
      final leases = ApiLeaseRepository(agent);
      final listing = (await leases.listings()).first;
      final template = (await leases.templates(market: listing.countryCode))
          .first;
      final draft = await leases.create(
        LeaseDraft(
          templateId: template.id,
          listingId: listing.id,
          landlords: const [
            LeaseParty(name: 'Lara Landlord', email: 'landlord@example.test'),
          ],
          tenants: const [
            LeaseParty(name: 'Tom Tenant', email: 'tenant@example.test'),
          ],
          startDate: DateTime.now().add(const Duration(days: 30)),
          endDate: DateTime.now().add(const Duration(days: 395)),
          rentAmount: '500.00',
          rentCurrency: listing.currency ?? 'USD',
          rentPeriod: 'MONTHLY',
          paymentDay: 1,
          noticePeriodDays: 30,
          landlordStamp: true,
        ),
      );
      expect(draft.landlordStamp, isTrue);
      await leases.send(draft.id);

      var stamped = 0;
      // Signers act in their order; go round until nobody can sign.
      for (var round = 0; round < 3; round++) {
        for (final email in ['landlord@example.test', 'tenant@example.test']) {
          final signing = ApiSigningRepository(await signedIn(email));
          for (final request in await signing.requests()) {
            if (!request.canSign) continue;
            final token = await patiently(
              () => signing.link(request.recipientId),
            );
            final view = await patiently(() => signing.view(token));
            final hasStamp = view.mine.any((f) => f.type == 'STAMP');
            if (hasStamp) {
              final png = await signing.stampPreview(
                const Stamp(topText: 'Lara Properties'),
              );
              expect(png.sublist(1, 4), 'PNG'.codeUnits);
            }
            await patiently(() => signing.sendCode(token));
            await patiently(
              () => signing.submit(
                token,
                SigningSubmission(
                  code: _code,
                  fieldValues: {
                    for (final f in view.mine)
                      if (f.type == 'TEXT')
                        f.id: 'Live check'
                      else if (f.type == 'CHECKBOX')
                        f.id: 'true',
                  },
                  signature: const AdoptedSignature.typed('Live Check'),
                  initials: const AdoptedSignature.typed('LC'),
                  stamp: hasStamp
                      ? const Stamp(
                          topText: 'Lara Properties',
                          bottomText: 'Harare',
                        )
                      : null,
                ),
              ),
            );
            if (hasStamp) stamped++;
          }
        }
      }
      expect(stamped, greaterThan(0));
      final done = await leases.get(draft.id);
      // ignore: avoid_print
      print('lease ${draft.id}: ${done.status}, $stamped stamped');
      expect(done.status, 'SIGNED');
      // Optional: keep the completed PDF to look at (RP_LIVE_PDF_OUT=path).
      final out = Platform.environment['RP_LIVE_PDF_OUT'];
      if (out != null) File(out).writeAsBytesSync(await leases.pdf(draft.id));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test('deleting an account: refused for a sole owner, then done', () async {
    final owner = ApiAuthRepository(
      await signedIn('estates.owner@example.test'),
    );
    await expectLater(
      owner.deleteAccount(_password),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'SOLE_OWNER')),
    );
    final agent = ApiAuthRepository(await signedIn('sales.agent@example.test'));
    await expectLater(
      agent.deleteAccount('not the password'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.fields['password'],
          'field',
          isNotNull,
        ),
      ),
    );
    final result = await agent.deleteAccount(_password);
    expect(result.organisationsLeft, 1);
    await expectLater(
      ApiAuthRepository(ApiClient(baseUrl: _base!))
          .login('sales.agent@example.test', _password),
      throwsA(isA<ApiFailure>()),
    );
  }, skip: skip);

  test('saved properties follow the account (API 0.27.0)', () async {
    final saved = ApiSavedListingsRepository(
      await signedIn('tenant@example.test'),
    );
    const id = '0195c0de-0000-7000-8000-000000000002';
    await saved.save(id);
    await saved.save(id); // Saving again changes nothing.
    expect(await saved.ids(), contains(id));
    final page = await saved.list();
    final item = page.items.firstWhere((i) => i.listingId == id);
    expect(item.available, isTrue);
    expect(item.slug, isNotNull);
    await expectLater(
      saved.save('0195c0de-0000-7000-8000-0000000000ff'),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    await saved.remove(id);
    await saved.remove(id); // Removing again is not an error.
    expect(await saved.ids(), isNot(contains(id)));
    // ignore: avoid_print
    print('saved: ${item.title} (${item.reference}) saved and removed');
  }, skip: skip);

  test('a listing with a video tour (API 0.28.0)', () async {
    final details = ApiListingDetailsRepository(ApiClient(baseUrl: _base!));
    // The seeded London house has a stand-in tour starting 30 s in.
    final tour = await details.videoTour(
      'three-bedroom-terraced-house-kensington',
    );
    expect(tour, isNotNull);
    expect(tour!.openUrl.queryParameters['t'], '30s');
    expect(tour.thumbnailUrl.host, 'i.ytimg.com');
    expect(
      await details.videoTour('four-bedroom-family-home-borrowdale'),
      isNull,
    );
    // ignore: avoid_print
    print('video: ${tour.id} opens ${tour.openUrl}');
  }, skip: skip);

  test('map search and positions (API 0.29.0)', () async {
    final search = ApiListingSearch(
      ApiClient(baseUrl: _base!),
      apiBase: _base!,
    );
    const all = ListingFilters();
    final mappable = await search.mappable(all);
    expect(mappable.listings, isNotEmpty);
    expect(mappable.listings.every((l) => l.position != null), isTrue);
    final counts = await search.counts(all);
    expect(counts.mappable, lessThanOrEqualTo(counts.total));

    // Harare only: everything returned lies inside the box.
    const harare = MapBounds(
      west: 30.9,
      south: -17.95,
      east: 31.2,
      north: -17.7,
    );
    final inBox = await search.mappable(all, bounds: harare);
    expect(inBox.listings, isNotEmpty);
    for (final l in inBox.listings) {
      expect(l.position!.latitude, inInclusiveRange(-17.95, -17.7));
      expect(l.position!.longitude, inInclusiveRange(30.9, 31.2));
    }

    // The approximate sample is rounded to 2 decimals; the unplaced one has
    // no position.
    final plot = (await search.bySlug('one-acre-plot-murambi-mutare'))!;
    expect(plot.position!.approximate, isTrue);
    expect(plot.position!.latitude, -18.95);
    final ruwa = await search.bySlug('residential-stand-ruwa');
    expect(ruwa?.position, isNull);
    // A bundled listing's position comes from the listing page call.
    final details = ApiListingDetailsRepository(ApiClient(baseUrl: _base!));
    expect(await details.location('four-bedroom-house-highlands'), isNotNull);
    // ignore: avoid_print
    print(
      'map: ${mappable.listings.length} mappable of ${counts.total}; '
      '${inBox.listings.length} in Harare',
    );
  }, skip: skip);

  test('listing statistics: events in, report out (API 0.30.0)', () async {
    const listing = '0195c0de-0000-7000-8000-000000000001'; // Tendai's
    final guest = ApiClient(baseUrl: _base!);
    final tracker = AnalyticsTracker(
      guest,
      store: MemoryStore(),
      interval: Duration.zero,
    );
    tracker.record(AnalyticsEventType.detailView, listing);
    tracker.record(
      AnalyticsEventType.impression,
      listing,
      placement: AnalyticsPlacement.search,
      rank: 0,
    );
    tracker.record(AnalyticsEventType.contactClick, listing);
    await tracker.flush();
    expect(tracker.queued, isEmpty);

    // The same body straight to the API shows it is accepted, and that a
    // repeated event_id is a duplicate.
    final body = {
      'schema': 1,
      'events': [
        {
          'event_id': newEventId(),
          'type': 'listing_detail_view',
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'listing_id': listing,
          'source': 'internal',
          'device': 'mobile',
          'session': 'live-check-session-0001',
          'consent': {'analytics': true},
        },
      ],
    };
    final first = await guest.postJson('/v1/analytics/events', body);
    final again = await guest.postJson('/v1/analytics/events', body);
    expect(first.status, 202);
    expect(again.body['duplicates'], 1);

    final agent = await signedIn('agent@example.test');
    final work = await ApiWorkspaceRepository(agent).load();
    final org = work.statisticsOrganisations.first;
    final report = await ApiAnalyticsRepository(agent)
        .organisation(org.id, '24h');
    expect(report.nearRealTime, isTrue);
    expect(report.total('views'), greaterThanOrEqualTo(1));
    expect(report.total('contact_clicks'), greaterThanOrEqualTo(1));
    expect(report.assignedOnly, isTrue);
    // Another organisation's report is not this agent's to read.
    await expectLater(
      ApiAnalyticsRepository(agent)
          .organisation('0195c0de-0000-7000-8000-00000000b099', '30d'),
      throwsA(isA<ApiFailure>()),
    );
    // ignore: avoid_print
    print(
      'analytics: ${report.total("views")} views, '
      '${report.total("contact_clicks")} contact clicks in 24h for ${org.name}',
    );
  }, skip: skip);

  test('the contact book (API 0.31.0)', () async {
    final agent = await signedIn('agent@example.test');
    final org = (await ApiWorkspaceRepository(
      agent,
    ).load()).organisations.first;
    final crm = ContactsRepository(agent);

    final all = await crm.list(org.id);
    expect(all.total, greaterThanOrEqualTo(8));
    expect(all.stageCounts.keys, containsAll(contactStages.keys));
    final found = await crm.list(org.id, query: 'tariro');
    final tariro = found.items.firstWhere((c) => c.name.contains('Tariro'));
    final detail = await crm.get(org.id, tariro.id);
    expect(detail.linkedItems.any((i) => i.kind == 'APPOINTMENT'), isTrue);

    // Her email is already in the book.
    await expectLater(
      crm.create(
        org.id,
        const ContactDraft(
          name: 'Tariro again',
          type: 'tenant',
          emails: ['tariro@example.com'],
        ),
      ),
      throwsA(isA<DuplicateContacts>()),
    );

    await crm.addNote(org.id, tariro.id, 'Live check note');
    final reminder = await crm.addReminder(
      org.id,
      tariro.id,
      DateTime.now().add(const Duration(days: 1)),
      'Live check reminder',
    );
    expect(
      (await crm.setReminderDone(org.id, tariro.id, reminder.id, true)).done,
      isTrue,
    );
    final moved = await crm.moveStage(
      org.id,
      tariro.id,
      tariro.stage == 'NEGOTIATING' ? 'CONTACTED' : 'NEGOTIATING',
      note: 'Live check',
    );
    expect(moved.contact.stage, isNot(tariro.stage));
    final events = await crm.timeline(org.id, tariro.id);
    expect(events.any((e) => e.kind == 'STAGE_CHANGED'), isTrue);
    expect(events.any((e) => e.kind == 'NOTE_ADDED'), isTrue);

    // One click from an appointment in the agent's inbox.
    final appointments = await ApiReceivedAppointmentsRepository(agent)
        .list(from: DateTime.now().toUtc().subtract(const Duration(days: 30)));
    final linked = await crm.fromRequest(
      org.id,
      appointments.items.first.id,
      kind: 'APPOINTMENT',
    );
    expect(linked.detail.contact.name, isNotEmpty);

    // Another agency's book is not found.
    final other = await signedIn('agent-b@example.test');
    final otherOrg = (await ApiWorkspaceRepository(
      other,
    ).load()).organisations.first;
    expect((await ContactsRepository(other).list(otherOrg.id)).total, 2);
    await expectLater(
      crm.list(otherOrg.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // ignore: avoid_print
    print(
      'contacts: ${all.total} in ${org.name}; ${tariro.name} moved to '
      '${moved.contact.stageLabel}; from appointment: '
      '${linked.created ? "created" : "linked"} ${linked.detail.contact.name}',
    );
  }, skip: skip);

  test(
    'applying, and the agency deciding (API 0.32.0)',
    () async {
      final tenant = await signedIn('tenant@example.test');
      final mine = MyApplicationsRepository(tenant);
      final draft = (await mine.list()).firstWhere((a) => a.status == 'DRAFT');
      var app = await mine.get(draft.id);
      final form = app.form!;

      // Answer every question that shows, as a person would.
      final answers = <String, Object?>{};
      for (final f in form.fields) {
        if (f.type == 'file') continue;
        answers[f.key] = switch (f.type) {
          'number' => f.min ?? 1,
          'date' => '2030-06-01',
          'single_choice' => f.options.last.value,
          'multiple_choice' => [f.options.first.value],
          _ => 'Live check answer',
        };
      }
      app = await mine.save(app.id, answers);
      for (final f in form.fields.where((f) => f.type == 'file')) {
        if (!form.visible(f, app.answers)) continue;
        app = await mine.upload(app.id, f.key, (
          bytes: '%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n'.codeUnits,
          name: 'payslip.pdf',
        ));
      }
      expect(form.problems(app.answers), isEmpty);
      final sent = await mine.submit(app.id);
      expect(sent.reference, matches(RegExp(r'^RPA-APP-\d{4}-\d{6}$')));

      final owner = await signedIn('estates.owner@example.test');
      final org = (await ApiWorkspaceRepository(
        owner,
      ).load()).organisations.first;
      final agency = AgentApplicationsRepository(owner);
      final inbox = await agency.list(org.id, status: 'SUBMITTED');
      expect(inbox.items.map((a) => a.id), contains(sent.id));
      final opened = await agency.get(org.id, sent.id);
      expect(opened.rendered, isNotEmpty);
      expect(opened.applicantName, isNotNull);
      await agency.decide(org.id, sent.id, 'UNDER_REVIEW', note: 'Live');
      await agency.requestInfo(org.id, sent.id, 'A second payslip, please');

      final asked = await mine.get(sent.id);
      expect(asked.status, 'MORE_INFO');
      expect(asked.infoRequest, 'A second payslip, please');
      final again = await mine.submit(sent.id);
      expect(again.status, 'SUBMITTED');
      final shortlisted = await agency.decide(org.id, sent.id, 'SHORTLISTED');
      expect(shortlisted.status, 'SHORTLISTED');

      // Not another agency's, and not another customer's.
      final other = await signedIn('agent-b@example.test');
      final otherOrg = (await ApiWorkspaceRepository(
        other,
      ).load()).organisations.first;
      await expectLater(
        AgentApplicationsRepository(other).get(otherOrg.id, sent.id),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
      await expectLater(
        MyApplicationsRepository(await signedIn('consumer@example.test'))
            .get(sent.id),
        throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
      );
      // ignore: avoid_print
      print(
        'applications: ${sent.reference} on ${form.name} v${form.version}; '
        'more info asked, sent again, now ${shortlisted.statusLabel}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('booking a showroom by the hour (API 0.33.0)', () async {
    final guest = ApiClient(baseUrl: _base!);
    final showroom = (await ApiListingSearch(
      guest,
      apiBase: _base!,
    ).bySlug('glass-fronted-showroom-eastlea'))!;
    final details = ApiListingDetailsRepository(guest);
    final offer = (await details.hourly(showroom.slug))!;
    expect(offer.enabled, isTrue);

    final tenant = await signedIn('tenant@example.test');
    final venues = VenueRepository(tenant);
    final venue = await venues.availability(showroom.id, from: DateTime.now());
    VenueQuote? quote;
    for (final day in venue.days.where((d) => d.bookable)) {
      final starts = venue.starts(day);
      if (starts.isEmpty) continue;
      final start = starts.last;
      quote = await venues.quote(
        showroom.id,
        start,
        start.add(Duration(minutes: venue.minMinutes)),
      );
      break;
    }
    expect(quote, isNotNull);
    expect(quote!.lines.first.code, 'RATE');
    expect(quote.notice, venueNoPaymentNotice);
    final sent = await venues.request(
      quote.id,
      message: 'Live check',
      attendees: 5,
      privacyVersion: AppConfig.privacyNoticeVersion,
    );
    expect(sent.status, 'REQUESTED');
    expect(sent.reference, startsWith('VB-'));
    expect((await venues.mine()).map((b) => b.id), contains(sent.id));
    final cancelled = await venues.cancelMine(sent.id, reason: 'Live check');
    expect(cancelled.status, 'CANCELLED');

    // The host: confirming the request that overlaps a confirmed booking
    // loses, and the host can decline it.
    final host = await signedIn('sample-showrooms@example.test');
    final org = (await ApiWorkspaceRepository(host).load()).organisations.first;
    final hosting = VenueRepository(host);
    final requests = await hosting.hosted(org.id, status: 'REQUESTED');
    var clashes = 0;
    for (final r in requests) {
      try {
        await hosting.hostAction(org.id, r.id, 'confirm');
      } on ApiFailure catch (failure) {
        if (failure.code != 'SLOT_TAKEN') rethrow;
        clashes++;
        final declined = await hosting.hostAction(
          org.id,
          r.id,
          'decline',
          reason: 'That time is already booked',
        );
        expect(declined.status, 'DECLINED');
      }
    }
    expect(clashes, greaterThanOrEqualTo(1));

    // Not another customer's, not another organisation's.
    await expectLater(
      VenueRepository(await signedIn('consumer@example.test'))
          .myBooking(sent.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    final other = await signedIn('agent-b@example.test');
    final otherOrg = (await ApiWorkspaceRepository(
      other,
    ).load()).organisations.first;
    await expectLater(
      VenueRepository(other).hostedBooking(otherOrg.id, sent.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // ignore: avoid_print
    print(
      'venues: quoted ${quote.currency} ${quote.total} for '
      '${quote.durationMinutes} min, sent ${sent.reference}, cancelled; '
      '$clashes overlapping request(s) refused with SLOT_TAKEN and declined',
    );
  }, skip: skip);

  test('the books (API 0.34.0)', () async {
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final books = LedgerRepository(owner);
    final options = await books.options(org.id);
    expect(options.canExport, isTrue);

    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final from = iso(DateTime(now.year - 1));
    final to = iso(now);
    final cashbook = await books.cashbook(org.id, from: from, to: to);
    // One table per currency, never a combined figure.
    expect(cashbook.map((c) => c.currency).toSet().length, cashbook.length);
    expect(cashbook.map((c) => c.currency), containsAll(['USD', 'ZAR']));

    final entry = await books.create(
      org.id,
      LedgerDraft(
        type: 'EXPENSE',
        category: 'maintenance',
        method: 'CASH',
        amount: '12.5',
        currency: 'USD',
        effectiveDate: iso(now),
        description: 'Live check: light bulbs',
      ),
    );
    expect(entry.status, 'USER_RECORDED_UNVERIFIED');
    expect(entry.statusLabel, 'Recorded by you, not verified');
    expect(entry.signedAmount, '-12.50');
    await books.attach(org.id, entry.id, (
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      ),
      name: 'receipt.png',
    ));
    final reversal = await books.reverse(org.id, entry.id, 'Live check');
    expect(reversal.type, 'REVERSAL');
    final detail = await books.entry(org.id, entry.id);
    expect(detail.entry.isReversed, isTrue);
    expect(detail.related.map((r) => r.id), contains(reversal.id));
    expect(detail.attachments.single.fileName, 'receipt.png');
    await expectLater(
      books.reverse(org.id, entry.id, 'Again'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          contains('already'),
        ),
      ),
    );

    // Staff read only; agents write but do not export.
    final staff = await LedgerRepository(
      await signedIn('agency.staff@example.test'),
    ).options(org.id);
    expect(staff.canWrite, isFalse);
    final agent = await LedgerRepository(await signedIn('agent@example.test'))
        .options(org.id);
    expect(agent.canWrite, isTrue);
    expect(agent.canExport, isFalse);
    // Another agency's books are not found.
    await expectLater(
      LedgerRepository(await signedIn('agent-b@example.test')).options(org.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
      ),
    );
    // ignore: avoid_print
    print(
      'books: ${cashbook.map((c) => '${c.currency} ${c.closing}').join(', ')}; '
      'recorded, receipt added and reversed ${entry.currency} ${entry.amount}',
    );
  }, skip: skip);
}
