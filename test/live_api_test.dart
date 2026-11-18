// Runs the app's own data layer against a running API. Skipped unless
// RP_LIVE_API is set. Meant for the backend in development mode (in-memory
// stores, seeded sample accounts, log mailer); never point it at production.
//
//   RP_LIVE_API=http://localhost:8080 RP_LIVE_PASSWORD=<DEV_SEED_PASSWORD> \
//   RP_LIVE_CODE=1234 flutter test test/live_api_test.dart
//
// It changes data: it accepts an appointment, moves a lead, signs a lease
// and deletes the sample account sales.agent@example.test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/core/api/api_client.dart';
import 'package:rightproperty365/core/config.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';
import 'package:rightproperty365/features/property_requests/data/property_request_repository.dart';
import 'package:rightproperty365/features/activity/my_requests_repository.dart';
import 'package:rightproperty365/features/appointments/appointment_repository.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/data/auth_repository.dart';
import 'package:rightproperty365/features/inbox/inbox_repository.dart';
import 'package:rightproperty365/features/inbox/lead_repository.dart';
import 'package:rightproperty365/features/leases/lease_repository.dart';
import 'package:rightproperty365/features/signing/signing_repository.dart';
import 'package:rightproperty365/features/listings/data/video_tour.dart';
import 'package:rightproperty365/features/saved/saved_listings_repository.dart';
import 'package:rightproperty365/features/signing/stamp.dart';

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
}
