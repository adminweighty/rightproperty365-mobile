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
import 'package:rightproperty365/features/notifications/marketing_repository.dart';
import 'package:rightproperty365/features/notifications/notifications_repository.dart';
import 'package:rightproperty365/features/properties/inspection_repository.dart';
import 'package:rightproperty365/features/directory/data/reviews_repository.dart';
import 'package:rightproperty365/features/properties/maintenance_repository.dart';
import 'package:rightproperty365/features/properties/properties_repository.dart';
import 'package:rightproperty365/features/properties/rent_repository.dart';
import 'package:rightproperty365/features/team/team_repository.dart';
import 'package:rightproperty365/features/signing/stamp.dart';
import 'package:rightproperty365/features/venues/venue_repository.dart';
import 'package:rightproperty365/core/api/scan.dart';
import 'package:rightproperty365/features/legal/legal.dart';

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
      // API 0.41.0 with the scanner off (the default): no scan_status.
      expect(app.files.map((f) => f.scan), everyElement(ScanStatus.none));
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
    expect(detail.attachments.single.scan, ScanStatus.none);
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

  test('notifications, preferences and this phone (API 0.35.0)', () async {
    // agent-b is not in Sample Estates: an invitation to an existing
    // account gives it an in-app TEAM_INVITATION item at once (other kinds
    // come from the worker, which a memory-store API does not run).
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final invitation = await ApiTeamRepository(owner)
        .invite(org.id, email: 'agent-b@example.test', role: 'AGENT');
    final api = await signedIn('agent-b@example.test');
    final repo = NotificationsRepository(api);
    final page = await repo.list();
    final item = page.items.firstWhere((n) => n.type == 'TEAM_INVITATION');
    expect(item.link, '/account');
    expect(item.unread, isTrue);
    // Safe text only: no email address in what a lock screen would show.
    expect('${item.title} ${item.body}', isNot(contains('@')));
    expect(await repo.unreadCount(), page.unreadCount);
    final read = await repo.markRead(item.id);
    expect(read.notification.unread, isFalse);
    expect(await repo.markAllRead(), 0);
    await expectLater(
      repo.markRead('00000000-0000-7000-8000-000000000000'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          'NOTIFICATION_NOT_FOUND',
        ),
      ),
    );
    await ApiTeamRepository(owner).cancelInvitation(org.id, invitation.id);

    // Preferences: one switch changes; essential types cannot be turned off.
    final before = await repo.preferences();
    expect(before.first.type, 'NEW_LEAD');
    final security = before.firstWhere((p) => p.type == 'SECURITY');
    expect(security.essential, isTrue);
    expect(security.essentialReason, isNotNull);
    final saved = await repo.setPreference('NEW_LEAD', email: false);
    expect(saved.first.email, isFalse);
    expect(saved.first.changedAt, isNotNull);
    await expectLater(
      repo.setPreference('SECURITY', push: false),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'VALIDATION_FAILED'),
      ),
    );
    await repo.setPreference('NEW_LEAD', email: true);

    // This phone: registered, then dropped with the logout.
    final token = 'live-check-${DateTime.now().microsecondsSinceEpoch}';
    final phone = await signedIn('agent@example.test');
    final devices = NotificationsRepository(phone);
    final id = await devices.registerDevice(
      token: token,
      platform: 'ANDROID',
      appVersion: '1.0.0',
      locale: 'en-ZW',
    );
    expect(id, isNotEmpty);
    final listed = (await phone.get('/v1/me/devices')).body['items'] as List;
    expect(
      listed.map((d) => (d as Map)['token_hint']),
      contains('…${token.substring(token.length - 4)}'),
    );
    expect(listed.toString(), isNot(contains(token)));
    // A fresh session, so the shared one stays signed in.
    final session = await _signIn('agent@example.test');
    await NotificationsRepository(session)
        .registerDevice(token: token, platform: 'ANDROID', appVersion: '1.0.0');
    await ApiAuthRepository(session).logout(deviceToken: token);
    final after = (await phone.get('/v1/me/devices')).body['items'] as List;
    expect(after.map((d) => (d as Map)['id']), isNot(contains(id)));
    // ignore: avoid_print
    print(
      'notifications: "${item.title}" read; ${saved.length} preference types; '
      'device registered and removed with the logout',
    );
  }, skip: skip);

  test('properties, units and tenancies (API 0.36.0)', () async {
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final repo = PropertiesRepository(owner);
    final options = await repo.tenancyOptions(org.id);
    expect(options.canWrite, isTrue);
    expect(options.frequencies.keys, contains('MONTHLY'));

    final seeded = await repo.properties(org.id);
    final avondale = seeded.items.firstWhere((p) => p.name == 'Avondale Court');
    expect(avondale.units.map((u) => u.label), ['Flat 1', 'Flat 2', 'Flat 3']);
    expect(avondale.occupiedUnits, 1);
    final active = await repo.tenancies(org.id, status: 'ACTIVE');
    expect(active.statusCounts['ACTIVE'], greaterThanOrEqualTo(2));

    // A new property with a unit, a draft tenancy, active, then ended.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final made = await repo.createProperty(
      org.id,
      name: 'Live check $stamp',
      address: '1 Test Road, Harare',
      marketCode: 'ZW',
      units: ['Room A'],
    );
    final contacts = await ContactsRepository(owner).list(org.id);
    // Not the sample tenant's contact, so their view stays their own.
    final tenant = contacts.items.firstWhere(
      (c) => !c.emails.contains('tenant@example.test'),
    );
    final draft = await repo.createTenancy(
      org.id,
      TenancyDraft(
        propertyId: made.id,
        unitId: made.units.single.id,
        tenantIds: [tenant.id],
        rentAmount: '120.00',
        currency: 'USD',
        frequency: 'WEEKLY',
        dueDay: 5,
        startDate: '2026-12-01',
        endDate: '2027-11-30',
      ),
    );
    expect(draft.status, 'DRAFT');
    expect(draft.rent.toString(), 'USD 120.00 weekly, due each Friday');
    final second = await repo.createTenancy(
      org.id,
      TenancyDraft(
        propertyId: made.id,
        unitId: made.units.single.id,
        tenantIds: [tenant.id],
        rentAmount: '130.00',
        currency: 'USD',
        frequency: 'MONTHLY',
        dueDay: 1,
        startDate: '2026-12-01',
      ),
    );
    final live = await repo.activate(org.id, draft.id);
    expect(live.status, 'ACTIVE');
    await expectLater(
      repo.activate(org.id, second.id),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'UNIT_OCCUPIED')),
    );
    await repo.deleteTenancy(org.id, second.id);
    await expectLater(
      repo.removeUnit(org.id, made.id, made.units.single.id),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'UNIT_IN_USE')),
    );
    final ended = await repo.end(
      org.id,
      draft.id,
      endDate: '2027-03-31',
      reason: 'Live check',
    );
    // Before the agreed end date: terminated early.
    expect(ended.status, 'TERMINATED');
    expect(ended.endedOn, '2027-03-31');
    await repo.deleteProperty(org.id, made.id);

    // Staff read only; another agency's book is not found.
    final staff = PropertiesRepository(
      await signedIn('agency.staff@example.test'),
    );
    expect((await staff.tenancyOptions(org.id)).canWrite, isFalse);
    expect((await staff.properties(org.id)).items, isNotEmpty);
    await expectLater(
      PropertiesRepository(await signedIn('agent-b@example.test'))
          .properties(org.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
      ),
    );

    // The sample tenant sees their own tenancy; nobody else's.
    final tenantApi = PropertiesRepository(
      await signedIn('tenant@example.test'),
    );
    final mine = await tenantApi.myTenancies();
    expect(mine.single.place, 'Avondale Court, Flat 1');
    expect(mine.single.managedBy, isNotEmpty);
    await expectLater(
      tenantApi.myTenancy(ended.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'TENANCY_NOT_FOUND'),
      ),
    );
    // ignore: avoid_print
    print(
      'properties: ${seeded.total} seeded; draft, active, UNIT_OCCUPIED, '
      'ended ${ended.status}; tenant sees ${mine.single.place}',
    );
  }, skip: skip);

  test('rent: schedule, receipts, waivers and arrears (API 0.36.1)', () async {
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final rent = RentRepository(owner);
    final active = (await PropertiesRepository(
      owner,
    ).tenancies(org.id, status: 'ACTIVE')).items;
    final cottage = active.firstWhere(
      (t) => t.propertyName == 'Borrowdale Cottage',
    );
    final scope = RentScope.manager(org.id, cottage.id);

    // Seeded: one due exactly 45 days overdue, one part paid.
    final schedule = await rent.schedule(scope);
    expect(schedule.rule, startsWith('Monthly on day'));
    expect(schedule.summary.outstanding.currency, 'USD');
    final part = schedule.dues.firstWhere((d) => d.status == 'PART_PAID');
    final owed = schedule.dues.firstWhere(
      (d) => d.status == 'DUE' && d.overdue,
    );
    expect(owed.daysOverdue, 45);

    final arrears = await rent.arrears(org.id);
    final usd = arrears.currencies.firstWhere((c) => c.currency == 'USD');
    expect(usd.buckets.map((b) => b.bucket), ['0-30', '31-60', '61-90', '90+']);
    expect(usd.tenancies.map((t) => t.tenancyId), contains(cottage.id));

    // Another currency is refused; the rent's is recorded, oldest first.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await expectLater(
      rent.record(
        org.id,
        cottage.id,
        amount: '10.00',
        currency: 'ZAR',
        method: 'CASH',
        receivedOn: today,
      ),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.fields.keys,
          'fields',
          contains('currency'),
        ),
      ),
    );
    final done = await rent.record(
      org.id,
      cottage.id,
      amount: '700.00',
      currency: 'USD',
      method: 'CASH',
      receivedOn: today,
      reference: 'Live check',
    );
    expect(done.receipt.ledgerStatusLabel, 'Recorded by you, not verified');
    expect(done.dues.first.id, owed.id);

    // Reversing it in the ledger puts the due back.
    await LedgerRepository(owner)
        .reverse(org.id, done.receipt.ledgerEntryId!, 'Live check');
    final again = await rent.schedule(scope);
    expect(again.dues.firstWhere((d) => d.id == owed.id).status, 'DUE');
    final receipts = await rent.receipts(scope);
    expect(
      receipts.firstWhere((r) => r.id == done.receipt.id).reversed,
      isTrue,
    );

    // Waive what is left on the part-paid due.
    final waived = await rent.waive(org.id, part.id, 'Live check');
    expect(waived.status, 'WAIVED');
    expect(waived.outstanding.amount, '0.00');

    final statement = await rent.statement(scope);
    expect(statement.currencies.map((c) => c.currency), ['USD']);
    final pdf = await rent.statementPdf(scope);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');

    // Staff cannot record; another agency's book is not found.
    await expectLater(
      RentRepository(await signedIn('agency.staff@example.test')).record(
        org.id,
        cottage.id,
        amount: '1.00',
        currency: 'USD',
        method: 'CASH',
        receivedOn: today,
      ),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 403)),
    );
    await expectLater(
      RentRepository(await signedIn('agent-b@example.test')).arrears(org.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
      ),
    );

    // The sample tenant sees their own dues and receipts, nobody else's.
    final tenantApi = await signedIn('tenant@example.test');
    final mine = (await PropertiesRepository(tenantApi).myTenancies()).single;
    final myRent = RentRepository(tenantApi);
    final myDues = await myRent.schedule(RentScope.tenant(mine.id));
    expect(myDues.dues.where((d) => d.status == 'PAID'), hasLength(2));
    expect(myDues.dues.every((d) => !d.canWaive), isTrue);
    final myReceipts = await myRent.receipts(RentScope.tenant(mine.id));
    expect(myReceipts.every((r) => r.ledgerEntryId == null), isTrue);
    await expectLater(
      myRent.schedule(RentScope.tenant(cottage.id)),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'TENANCY_NOT_FOUND'),
      ),
    );
    // ignore: avoid_print
    print(
      'rent: ${cottage.place} ${schedule.summary.outstanding} outstanding; '
      'receipt recorded and reversed, due waived; '
      'tenant sees ${myDues.dues.length} dues, ${myReceipts.length} receipts',
    );
  }, skip: skip);

  test('maintenance requests (API 0.36.2)', () async {
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final repo = MaintenanceRepository(owner);
    final options = await repo.options(org.id);
    expect(options.canWrite, isTrue);
    expect(options.categories['plumbing'], 'Plumbing');

    // The seed: four requests, one of each of four statuses.
    final seeded = await repo.list(org.id);
    expect(seeded.total, greaterThanOrEqualTo(4));
    final tap = seeded.items.firstWhere(
      (r) => r.reference == 'RPM-2026-900001',
    );
    final one = await repo.get(org.id, tap.id);
    expect(one.timeline.length, greaterThanOrEqualTo(7));
    expect(one.costTotals.single.toString(), 'USD 85.00');
    expect(one.costs.single.ledgerStatusLabel, 'Recorded by you, not verified');

    // A new request on the cottage: triage, assign (once), cost, comment.
    final cottage = (await PropertiesRepository(owner).properties(org.id)).items
        .firstWhere((p) => p.name == 'Borrowdale Cottage');
    final made = await repo.create(
      org.id,
      propertyId: cottage.id,
      category: 'plumbing',
      priority: 'normal',
      title: 'Live check: dripping outside tap',
    );
    expect(made.status, 'NEW');
    expect(made.transitions, containsAll(['TRIAGED', 'CANCELLED']));
    await repo.setStatus(org.id, made.id, 'TRIAGED');
    final providers = await repo.providers(org.id, query: 'plumb');
    expect(providers, isNotEmpty);
    final first = await repo.assign(org.id, made.id, providers.first.id);
    expect(first.request.status, 'ASSIGNED');
    expect(first.enquiryReference, startsWith('BE-'));
    final again = await repo.assign(org.id, made.id, providers.first.id);
    // Assigning the same provider again sends no second enquiry.
    expect(again.request.enquiryReference, first.enquiryReference);
    final costed = await repo.addCost(
      org.id,
      made.id,
      amount: '12.50',
      currency: 'USD',
      description: 'Live check washer',
      method: 'CASH',
      incurredOn: DateTime.now().toIso8601String().substring(0, 10),
    );
    expect(costed.costTotals.single.toString(), 'USD 12.50');
    await repo.comment(org.id, made.id, 'Live check note', internal: true);
    await repo.addPhoto(org.id, made.id, (
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      ),
      name: 'tap.png',
    ));
    final withPhoto = await repo.get(org.id, made.id);
    expect(withPhoto.photos, hasLength(1));
    final jpeg = await repo.photo(withPhoto.photos.single.url);
    expect(jpeg.take(2), [0xFF, 0xD8]);
    await repo.setStatus(org.id, made.id, 'CANCELLED', note: 'Live check');

    // Staff read only; another agency's book is not found.
    final staff = MaintenanceRepository(
      await signedIn('agency.staff@example.test'),
    );
    final staffView = await staff.get(org.id, tap.id);
    expect(staffView.canAssign || staffView.canAddCost, isFalse);
    expect(staffView.transitions, isEmpty);
    await expectLater(
      MaintenanceRepository(await signedIn('agent-b@example.test'))
          .list(org.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
      ),
    );

    // The tenant: their tenancy's requests only, no costs or internal notes.
    final tenantApi = await signedIn('tenant@example.test');
    final mine = (await PropertiesRepository(tenantApi).myTenancies()).single;
    final theirs = MaintenanceRepository(tenantApi);
    final list = await theirs.mine(mine.id);
    expect(
      list.map((r) => r.reference),
      containsAll(['RPM-2026-900001', 'RPM-2026-900003']),
    );
    final seen = await theirs.myRequest(mine.id, tap.id);
    expect(seen.costs, isEmpty);
    expect(
      seen.timeline.where((t) => t.type == 'COST_ADDED' || t.internal),
      isEmpty,
    );
    expect(seen.providerName, isNotNull);
    final reported = await theirs.report(
      mine.id,
      category: 'appliances',
      priority: 'low',
      title: 'Live check: fridge light',
    );
    expect(reported.raisedByYou, isTrue);
    await expectLater(
      theirs.myRequest(mine.id, made.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // A tenant has no cost route at all.
    await expectLater(
      tenantApi.postJson(
        '/v1/me/tenancies/${mine.id}/maintenance/${tap.id}/costs',
        {'amount': '1.00', 'currency': 'USD', 'description': 'x'},
      ),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // ignore: avoid_print
    print(
      'maintenance: ${seeded.total} requests; ${tap.reference} ${one.timeline.length} '
      'timeline items, ${one.costTotals.single}; new request triaged, assigned '
      '(${first.enquiryReference}, once), costed, photographed, cancelled; '
      'tenant sees ${list.length}',
    );
  }, skip: skip);

  test('inspections (API 0.36.3)', () async {
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final repo = InspectionRepository(owner);
    final options = await repo.options(org.id);
    expect(options.templates.map((t) => t.code), ['residential', 'commercial']);
    expect(options.templates.first.items, 32);

    final seeded = await repo.list(org.id);
    final moveIn = seeded.items.firstWhere(
      (i) => i.reference == 'RPI-2026-900001',
    );
    final routine = seeded.items.firstWhere(
      (i) => i.reference == 'RPI-2026-900002',
    );
    expect(moveIn.status, 'COMPLETED');
    expect(routine.status, 'SCHEDULED');

    // A move-out of the Flat 1 tenancy, compared with its move-in.
    final flat1 = (await PropertiesRepository(owner).tenancies(
      org.id,
      status: 'ACTIVE',
    )).items.firstWhere((t) => t.place == 'Avondale Court, Flat 1');
    final made = await repo.create(
      org.id,
      propertyId: flat1.propertyId!,
      tenancyId: flat1.id,
      type: 'MOVE_OUT',
      scheduledFor: DateTime.now().add(const Duration(hours: 1)),
      template: 'residential',
    );
    expect(made.status, 'SCHEDULED');
    expect(made.baselineReference, 'RPI-2026-900001');
    final items = [for (final a in made.areas) ...a.items];
    final sink = made.areas
        .firstWhere((a) => a.label == 'Kitchen')
        .items
        .firstWhere((i) => i.label == 'Sink and taps');
    expect(sink.baselineNote, 'Cold tap drips slightly');

    // The first finding starts it; a bad file is refused; a PNG becomes JPEG.
    final started = await repo.saveFindings(org.id, made.id, [
      FindingChange(sink.id, status: 'ATTENTION', note: 'Live check'),
    ]);
    expect(started.status, 'IN_PROGRESS');
    await expectLater(
      repo.addPhoto(org.id, made.id, sink.id, (
        bytes: utf8.encode('not an image'),
        name: 'x.jpg',
      )),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 415)),
    );
    await repo.addPhoto(org.id, made.id, sink.id, (
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      ),
      name: 'sink.png',
    ));
    final withPhoto = await repo.get(org.id, made.id);
    final photo = [for (final a in withPhoto.areas) ...a.items]
        .firstWhere((i) => i.id == sink.id)
        .photos
        .single;
    expect((await repo.bytes(photo.url)).take(2), [0xFF, 0xD8]);

    // Refused while items are missing; then every item, then complete.
    await expectLater(
      repo.complete(org.id, made.id),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          'INSPECTION_INCOMPLETE',
        ),
      ),
    );
    await repo.saveFindings(org.id, made.id, [
      for (final i in items)
        if (i.id != sink.id) FindingChange(i.id, status: 'OK'),
    ]);
    final done = await repo.complete(
      org.id,
      made.id,
      summary: 'Live check',
      agentName: 'Live check',
    );
    expect(done.status, 'COMPLETED');
    expect(done.canRecord, isFalse);
    await expectLater(
      repo.saveFindings(org.id, made.id, [
        FindingChange(sink.id, status: 'OK'),
      ]),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 409)),
    );
    final pdf = await repo.bytes(done.reportUrl!);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    final draft = await repo.get(org.id, routine.id);
    expect(
      String.fromCharCodes((await repo.bytes(draft.reportUrl!)).take(4)),
      '%PDF',
    );

    // Staff read only; another agency's book is not found.
    final staff = await InspectionRepository(
      await signedIn('agency.staff@example.test'),
    ).get(org.id, routine.id);
    expect(staff.canRecord || staff.canComplete || staff.canStart, isFalse);
    await expectLater(
      InspectionRepository(await signedIn('agent-b@example.test')).list(org.id),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'BOOK_NOT_FOUND'),
      ),
    );

    // The tenant: completed ones only, with the PDF; not the scheduled one.
    final tenantApi = await signedIn('tenant@example.test');
    final mine = (await PropertiesRepository(tenantApi).myTenancies()).single;
    final theirs = InspectionRepository(tenantApi);
    final reports = await theirs.mine(mine.id);
    expect(
      reports.map((i) => i.reference),
      containsAll(['RPI-2026-900001', done.reference]),
    );
    expect(reports.every((i) => i.status == 'COMPLETED'), isTrue);
    final theirPdf = await theirs.bytes(reports.first.reportUrl!);
    expect(String.fromCharCodes(theirPdf.take(4)), '%PDF');
    await expectLater(
      theirs.myInspection(mine.id, routine.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // ignore: avoid_print
    print(
      'inspections: ${seeded.total} seeded; move-out ${done.reference} '
      'compared with ${done.baselineReference}, 415 refused, JPEG back, '
      'incomplete refused, completed, frozen (409), PDFs; tenant sees '
      '${reports.length}',
    );
  }, skip: skip);

  test('reviews of service providers (API 0.36.4)', () async {
    const kind = 'service-providers';
    const slug = 'sample-plumbers';
    // Public: the rating and published reviews, reviewers by short name.
    final public = await ReviewsRepository(ApiClient(baseUrl: _base!))
        .published(kind, slug);
    expect(public.rating.average, '4.5');
    expect(public.rating.count, 2);
    expect(
      public.items.map((r) => r.reviewerName),
      containsAll(['Sample Estates', 'Casey C.']),
    );
    final casey = public.items.firstWhere((r) => r.reviewerName == 'Casey C.');

    // The tenant's replied enquiry can be reviewed, once.
    final tenant = ReviewsRepository(await signedIn('tenant@example.test'));
    final mine = await tenant.eligibility(kind, slug);
    final basis = mine.bases.firstWhere((b) => b.label.contains('BE-RVW4TNNT'));
    final written = await tenant.write(
      profileId: mine.profileId,
      basis: basis,
      rating: 4,
      text: 'Live check: came quickly and cleared the drain.',
    );
    expect(written.statusLabel, 'Awaiting moderation');
    await expectLater(
      tenant.write(
        profileId: mine.profileId,
        basis: basis,
        rating: 5,
        text: 'Live check: a second review of the same enquiry.',
      ),
      throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'REVIEW_EXISTS')),
    );
    expect((await tenant.written()).map((r) => r.id), contains(written.id));
    // The tenant already reported Casey's review: a second is refused.
    await expectLater(
      tenant.report(casey.id, 'Live check'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          'REVIEW_ALREADY_REPORTED',
        ),
      ),
    );
    await tenant.delete(written.id);

    // Other kinds are not reviewable.
    final agency = await tenant.eligibility('agencies', 'sample-estates');
    expect(agency.reviewable, isFalse);

    // A book reviews its maintenance job; the seeded one is already done.
    final owner = await signedIn('estates.owner@example.test');
    final org = (await ApiWorkspaceRepository(
      owner,
    ).load()).organisations.first;
    final book = await ReviewsRepository(owner)
        .eligibility(kind, slug, book: org.id);
    expect(book.reviewedCount, greaterThanOrEqualTo(1));

    // The provider: received reviews, one reply each; marking replied.
    final providerApi = await signedIn('sample-plumbers@example.test');
    final providerOrg = (await ApiWorkspaceRepository(
      providerApi,
    ).load()).organisations.single;
    expect(providerOrg.kind, 'SERVICE_PROVIDER');
    final provider = ReviewsRepository(providerApi);
    final received = await provider.received(providerOrg.id);
    expect(received.items, hasLength(2));
    expect(received.canReply, isTrue);
    final replied = received.items.firstWhere((r) => r.reply != null);
    await expectLater(
      provider.reply(providerOrg.id, replied.id, 'Live check'),
      throwsA(
        isA<ApiFailure>().having((f) => f.code, 'code', 'REVIEW_REPLY_EXISTS'),
      ),
    );
    final inbox =
        (await providerApi.get('/v1/inbox/business-enquiries')).body['items']
            as List;
    final open = inbox.cast<Map<String, dynamic>>().firstWhere(
      (e) => e['replied_at'] == null,
    );
    await provider.markReplied(open['enquiry_id'] as String);
    await provider.markReplied(open['enquiry_id'] as String);
    final after =
        ((await providerApi.get('/v1/inbox/business-enquiries')).body['items']
                as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((e) => e['id'] == open['id']);
    expect(after['replied_at'], isNotNull);
    // Another organisation cannot read the provider's reviews.
    await expectLater(
      ReviewsRepository(owner).received(providerOrg.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );
    // ignore: avoid_print
    print(
      'reviews: ${public.rating.average} from ${public.rating.count}; tenant '
      'review PENDING, second REVIEW_EXISTS, report once; provider sees '
      '${received.items.length}, second reply refused, enquiry marked replied',
    );
  }, skip: skip);

  test('marketing preferences (API 0.37.1)', () async {
    // The seed: the tenant opted in at registration, then out in the app.
    final tenant = MarketingRepository(await signedIn('tenant@example.test'));
    final seeded = await tenant.get();
    expect(seeded.optIn, isFalse);
    expect(seeded.consentText, isNotEmpty);
    expect(seeded.history.length, greaterThanOrEqualTo(2));
    expect(seeded.last!.where, 'in the app');

    // An account that never chose: off, no record. Opt in to the wording
    // the API served, from the app; the same value again changes nothing.
    final fresh = MarketingRepository(await signedIn('landlord@example.test'));
    final before = await fresh.get();
    expect(before.optIn, isFalse);
    expect(before.last, isNull);
    final on = await fresh.set(true, version: before.currentVersion);
    expect(on.optIn, isTrue);
    expect(on.last!.where, 'in the app');
    final again = await fresh.set(true, version: before.currentVersion);
    expect(again.history.length, on.history.length);
    expect(again.last!.changedAt, on.last!.changedAt);

    // A stale wording version is refused and explained.
    await expectLater(
      fresh
          .set(false)
          .then((_) => fresh.set(true, version: 'marketing-1999-01')),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          contains('wording has changed'),
        ),
      ),
    );
    final off = await fresh.get();
    expect(off.optIn, isFalse);
    expect(off.history.length, 2);
    // ignore: avoid_print
    print(
      'marketing: tenant ${seeded.history.length} records; fresh account '
      'on (${before.currentVersion}), no-op repeat, off, stale version refused',
    );
  }, skip: skip);

  test('calendar files (API 0.39.0)', () async {
    String text(List<int> bytes) => utf8.decode(bytes);

    // The customer's own appointment.
    final consumer = await signedIn('consumer@example.test');
    final mine = ApiMyAppointmentsRepository(consumer);
    final upcoming = (await mine.list()).items;
    final appointment = upcoming.firstWhere(
      (a) => a.status == 'CONFIRMED',
      orElse: () => upcoming.first,
    );
    final ics = text(await mine.calendarFile(appointment.id));
    expect(ics, startsWith('BEGIN:VCALENDAR'));
    expect(ics, contains('METHOD:PUBLISH'));
    expect(
      ics,
      contains('UID:appointment-${appointment.id}@rightproperty365.com'),
    );
    expect(ics, contains('SEQUENCE:'));
    expect(ics, contains(appointment.reference));
    expect(ics, contains('\r\n'));

    // The professional's side of the same appointment.
    final agent = ApiReceivedAppointmentsRepository(
      await signedIn('agent@example.test'),
    );
    final theirs = text(await agent.calendarFile(appointment.id));
    expect(
      theirs,
      contains('UID:appointment-${appointment.id}@rightproperty365.com'),
    );
    expect(theirs, isNot(contains('consumer@example.test')));

    // Nobody else's.
    await expectLater(
      ApiMyAppointmentsRepository(await signedIn('tenant@example.test'))
          .calendarFile(appointment.id),
      throwsA(isA<ApiFailure>().having((f) => f.status, 'status', 404)),
    );

    // A customer's hourly booking, when they have one.
    final venues = VenueRepository(consumer);
    final bookings = await venues.mine();
    String? booking;
    if (bookings.isNotEmpty) {
      final b = bookings.first;
      final file = text(await venues.myCalendarFile(b.id));
      expect(file, contains('UID:venue-booking-${b.id}@rightproperty365.com'));
      booking = b.reference;
    }
    // ignore: avoid_print
    print(
      'calendar: appointment ${appointment.reference} (${appointment.status}) '
      'for customer and professional, same UID, 404 for another user; '
      'booking ${booking ?? "none to check"}',
    );
  }, skip: skip);

  test('legal documents to accept again (API 0.43.0)', () async {
    // Run after publishing a GLOBAL TERMS version with
    // requires_reacceptance (as admin.content, outside the app); without
    // one, nothing is pending and the seeded version is accepted instead.
    final api = await signedIn('consumer@example.test');
    api.acceptLanguage = () => 'sn-ZW, en;q=0.9';
    final legal = LegalRepository(api);
    final pending = await legal.pending();
    final checked = <String>[];
    for (final item in pending) {
      final doc = await legal.document(item);
      expect(doc.kind, item.kind);
      expect(doc.version, item.version);
      expect(doc.body, isNotEmpty);
      await legal.accept(item);
      await legal.accept(item); // Accepting twice is fine.
      checked.add('${item.kind} ${item.version} draft=${doc.draftNotice}');
    }
    expect(await legal.pending(), isEmpty);

    // The seeded placeholder: a draft, in English whatever the phone asks.
    const seeded = PendingLegal(
      kind: 'TERMS',
      title: 'Terms and Conditions',
      version: '2026-11-14',
      marketCode: 'GLOBAL',
    );
    final terms = await legal.document(seeded);
    expect(terms.draftNotice, isTrue);
    expect(terms.body, contains('DRAFT'));
    await legal.accept(seeded);
    await expectLater(
      legal.accept(
        const PendingLegal(
          kind: 'TERMS',
          title: 'Terms',
          version: 'no-such-version',
          marketCode: 'GLOBAL',
        ),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          contains('no longer available'),
        ),
      ),
    );
    // ignore: avoid_print
    print(
      'legal: pending ${checked.isEmpty ? "none" : checked.join(", ")}, '
      'accepted and cleared; seeded TERMS draft accepted; unknown version 404',
    );
  }, skip: skip);
}
