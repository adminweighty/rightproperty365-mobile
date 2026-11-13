import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/core/format.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/data/listing_repository.dart';
import 'package:rightproperty365/features/listings/data/sample_listings.dart';
import 'package:rightproperty365/features/property_requests/data/property_request.dart';

PropertyRequestDraft draft({
  RequestType type = RequestType.enquiry,
  String? phone,
  DateTime? slot,
}) => PropertyRequestDraft(
  listingId: sampleListings.first.id,
  requestType: type,
  message: '  Hello  ',
  contactMethod: ContactMethod.email,
  name: ' Test Customer ',
  email: ' test@example.com ',
  phone: phone,
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
    test('use the ids seeded in the backend dev store', () {
      expect(sampleListings, hasLength(6));
      for (var i = 0; i < 6; i++) {
        expect(
          sampleListings[i].id,
          '0195c0de-0000-7000-8000-00000000000${i + 1}',
        );
      }
    });

    test('filter by deal, category and text', () async {
      const repository = SampleListingRepository();
      expect(
        await repository.search(const ListingFilters(deal: DealType.rent)),
        hasLength(3),
      );
      expect(
        await repository.search(
          const ListingFilters(category: ListingCategory.land),
        ),
        hasLength(1),
      );
      expect(
        await repository.search(const ListingFilters(query: ' bulawayo ')),
        hasLength(1),
      );
      expect(
        await repository.search(const ListingFilters(query: 'nowhere')),
        isEmpty,
      );
      expect(await repository.bySlug('missing'), isNull);
    });
  });

  group('PropertyRequestDraft', () {
    test('serialises to the API contract and trims text', () {
      final json = draft().toJson('key-12345');
      expect(json['listing_id'], sampleListings.first.id);
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
      final contact =
          draft(phone: '+263 (77) 123-4567').toJson('k')['guest_contact']
              as Map;
      expect(contact['phone'], '+263771234567');
      expect(PropertyRequestDraft.normalisePhone('   '), isNull);
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

        final enquiry = draft(
          type: RequestType.enquiry,
          slot: local,
        ).toJson('k');
        expect(enquiry.containsKey('preferred_slot_utc'), isFalse);
      },
    );
  });

  test('receipt parses the API response', () {
    final receipt = PropertyRequestReceipt.fromJson({
      'request_id': 'abc',
      'reference': 'RP-8VXWDQJG',
      'status': 'RECEIVED',
      'created_at': '2026-11-13T09:00:00Z',
    });
    expect(receipt.reference, 'RP-8VXWDQJG');
    expect(receipt.status, 'RECEIVED');
    expect(receipt.createdAt.isUtc, isTrue);
  });
}
