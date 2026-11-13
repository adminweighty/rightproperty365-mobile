import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/core/format.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/enquiries/data/enquiry.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';

import 'support.dart';

PropertyRequestDraft draft({
  RequestType type = RequestType.enquiry,
  EnquiryContact contact = const EnquiryContact(
    name: ' Test Customer ',
    email: ' test@example.com ',
  ),
  DateTime? slot,
}) => PropertyRequestDraft(
  listingId: '0195c0de-0000-7000-8000-000000000001',
  requestType: type,
  message: '  Hello  ',
  contactMethod: ContactMethod.email,
  contact: contact,
  preferredSlot: slot,
  consentAccepted: true,
  privacyVersion: 'v1',
);

void main() {
  group('formatting', () {
    test('money always shows the ISO currency code', () {
      expect(formatMoney(const Money('385000.00', 'USD')), 'USD 385,000');
      expect(formatMoney(const Money('950.00', 'ZAR')), 'ZAR 950');
    });

    test('area uses square metres', () => expect(formatArea(2000), '2,000 m²'));
  });

  group('sample listings', () {
    final repository = sampleListings();

    test('mirror the 18 web listings with the backend dev-store ids', () {
      expect(repository.listings, hasLength(18));
      for (var i = 0; i < 18; i++) {
        expect(
          repository.listings[i].id,
          '0195c0de-0000-7000-8000-${'${i + 1}'.padLeft(12, '0')}',
        );
      }
    });

    test('each has a bundled photo with alt text, an agent or owner and a publish date', () {
      for (final listing in repository.listings) {
        expect(
          File(listing.image.asset).existsSync(),
          isTrue,
          reason: listing.image.asset,
        );
        expect(listing.image.alt, isNotEmpty);
        expect(listing.listedBy, isNotEmpty);
        expect(listing.publishedAt.isUtc, isTrue);
      }
    });

    test('filter by deal, category and text', () async {
      final rentals = await repository.search(
        const ListingFilters(deal: DealType.rent),
      );
      expect(rentals, isNotEmpty);
      expect(rentals.every((l) => l.deal == DealType.rent), isTrue);

      final land = await repository.search(
        const ListingFilters(category: ListingCategory.land),
      );
      expect(land.every((l) => l.category == ListingCategory.land), isTrue);

      final bulawayo = await repository.search(
        const ListingFilters(query: ' bulawayo '),
      );
      expect(bulawayo, isNotEmpty);
      expect(bulawayo.every((l) => l.city == 'Bulawayo'), isTrue);

      expect(
        await repository.search(const ListingFilters(query: 'nowhere')),
        isEmpty,
      );
      expect(await repository.bySlug('missing'), isNull);
      expect(
        (await repository.bySlug('four-bedroom-family-home-borrowdale'))
            ?.reference,
        'RP-ZW-10001',
      );
    });
  });

  group('PropertyRequestDraft', () {
    test('serialises to the API contract and trims text', () {
      final json = draft().toJson('key-12345');
      expect(json['listing_id'], '0195c0de-0000-7000-8000-000000000001');
      expect(json['request_type'], 'ENQUIRY');
      expect(json['message'], 'Hello');
      expect(json['preferred_contact_method'], 'EMAIL');
      expect(json['idempotency_key'], 'key-12345');
      expect(json['guest_contact'], {
        'name': 'Test Customer',
        'email': 'test@example.com',
      });
      expect(json['consent'], {'privacy_version': 'v1', 'accepted': true});
      expect(json.containsKey('preferred_slot_utc'), isFalse);
    });

    test('normalises the phone number to E.164 characters', () {
      final json = draft(
        contact: const EnquiryContact(
          name: 'A',
          email: 'a@b.co',
          phone: '+263 (77) 123-4567',
        ),
      ).toJson('k');
      expect((json['guest_contact'] as Map)['phone'], '+263771234567');
      expect(EnquiryContact.normalisePhone('   '), isNull);
    });

    test('a signed-in customer sends no name or email', () {
      final withPhone = draft(
        contact: const EnquiryContact(phone: '+263771234567'),
      ).toJson('k');
      expect(withPhone['guest_contact'], {'phone': '+263771234567'});

      final nothing = draft(contact: const EnquiryContact()).toJson('k');
      expect(nothing.containsKey('guest_contact'), isFalse);
    });

    test(
      'sends the preferred slot in UTC, and only for types that allow it',
      () {
        final local = DateTime.parse('2030-05-01T10:00:00+02:00');
        final viewing = draft(
          type: RequestType.viewingRequest,
          slot: local,
        ).toJson('k');
        expect(viewing['preferred_slot_utc'], '2030-05-01T08:00:00.000Z');

        final enquiry = draft(slot: local).toJson('k');
        expect(enquiry.containsKey('preferred_slot_utc'), isFalse);
      },
    );
  });

  test('receipt parses both id field names', () {
    final body = {
      'reference': 'RP-8VXWDQJG',
      'status': 'RECEIVED',
      'created_at': '2026-11-13T09:00:00Z',
    };
    final request = EnquiryReceipt.fromJson({
      ...body,
      'request_id': 'abc',
    }, 'request_id');
    final enquiry = EnquiryReceipt.fromJson({
      ...body,
      'enquiry_id': 'def',
    }, 'enquiry_id');
    expect(request.id, 'abc');
    expect(enquiry.id, 'def');
    expect(request.createdAt.isUtc, isTrue);
  });

  test('profile initials skip "and" and stop at two letters', () {
    Profile named(String name) => Profile(
      slug: 's',
      kind: DirectoryKind.agencies,
      name: name,
      role: '',
      tagline: '',
      about: '',
      city: '',
      areas: const [],
      services: const [],
      verified: true,
    );
    expect(named('Sample Estates').initials, 'SE');
    expect(named('Moyo and Dube Attorneys').initials, 'MD');
    expect(named('Tendai').initials, 'T');
  });
}
