import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rightproperty365/core/terminology.dart';
import 'package:rightproperty365/features/auth/data/auth_models.dart';
import 'package:rightproperty365/features/auth/presentation/auth_screens.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';
import 'package:rightproperty365/features/listings/data/listing.dart';
import 'package:rightproperty365/features/listings/presentation/listing_detail_screen.dart';

import 'support.dart';

void main() {
  group('role names', () {
    test('every API role code has its real-estate name', () {
      expect(
        {
          for (final code in [
            'CONSUMER',
            'TENANT',
            'AGENT',
            'AGENCY_OWNER',
            'AGENCY_ADMIN',
            'AGENCY_STAFF',
            'LANDLORD',
            'PRIVATE_SELLER',
            'DEVELOPER',
            'HOST',
            'SERVICE_PROVIDER',
            'PLATFORM_ADMIN',
            'SUPER_ADMIN',
          ])
            code: roleLabel(code),
        },
        {
          'CONSUMER': 'Prospective Buyer',
          'TENANT': 'Prospective Tenant',
          'AGENT': 'Estate Agent',
          'AGENCY_OWNER': 'Agency Principal',
          'AGENCY_ADMIN': 'Agency Administrator',
          'AGENCY_STAFF': 'Agency Staff',
          'LANDLORD': 'Landlord',
          'PRIVATE_SELLER': 'Property Seller (Vendor)',
          'DEVELOPER': 'Property Developer',
          'HOST': 'Host',
          'SERVICE_PROVIDER': 'Property Service Provider',
          'PLATFORM_ADMIN': 'Platform Administrator',
          'SUPER_ADMIN': 'Super Administrator',
        },
      );
    });

    test(
      'sign-up groups follow the specification and cover every API code once',
      () {
        expect(accountRoleGroups.map((g) => g.legend), [
          'Property Seekers',
          'Real Estate Professionals',
          'Real Estate Businesses',
          'Property Owners',
          'Other property businesses',
        ]);
        final codes = accountRoleGroups
            .expand((g) => g.roles)
            .map((r) => r.value)
            .toList();
        expect(codes.toSet(), hasLength(codes.length));
        expect(codes.toSet(), {
          'CONSUMER',
          'TENANT',
          'PRIVATE_SELLER',
          'LANDLORD',
          'HOST',
          'DEVELOPER',
          'SERVICE_PROVIDER',
          'AGENT',
          'AGENCY_STAFF',
          'AGENCY_ADMIN',
          'AGENCY_OWNER',
          'SOLICITOR',
          'SALES_AGENT',
          'LETTINGS_AGENT',
          'PROPERTY_MANAGER',
        });
        for (final role in accountRoleGroups.expand((g) => g.roles)) {
          expect(role.description, isNotEmpty);
        }
      },
    );

    test('membership names depend on the kind of organisation', () {
      expect(membershipRoleLabel('OWNER', 'AGENCY'), 'Agency Principal');
      expect(membershipRoleLabel('MANAGER', 'AGENCY'), 'Agency Administrator');
      expect(membershipRoleLabel('AGENT', 'AGENCY'), 'Estate Agent');
      expect(membershipRoleLabel('STAFF', 'AGENCY'), 'Agency Staff');
      expect(membershipRoleLabel('MANAGER', 'LANDLORD'), 'Property Manager');
      expect(organisationKindLabel('AGENCY'), 'Real Estate Agency');
      expect(organisationKindLabel('LANDLORD'), 'Landlord');
    });

    test('verification statuses use the onboarding vocabulary', () {
      expect(
        const AccountRole('AGENT', 'ACTIVE', 'APPROVED').verificationLabel,
        'Approved',
      );
      expect(
        const AccountRole('AGENT', 'PENDING_VERIFICATION').verificationLabel,
        'Pending Verification',
      );
      expect(
        const AccountRole(
          'AGENT',
          'PENDING_VERIFICATION',
          'DRAFT',
        ).verificationLabel,
        'Pending Verification',
      );
      expect(
        const AccountRole(
          'AGENT',
          'PENDING_VERIFICATION',
          'SUBMITTED',
        ).verificationLabel,
        'Under Review',
      );
      expect(
        const AccountRole(
          'AGENT',
          'PENDING_VERIFICATION',
          'CHANGES_REQUESTED',
        ).verificationLabel,
        'Changes Requested',
      );
      expect(
        const AccountRole('AGENT', 'REJECTED', 'REJECTED').verificationLabel,
        'Rejected',
      );
      expect(const AccountRole('CONSUMER', 'ACTIVE').isSeeker, isTrue);
      expect(const AccountRole('LANDLORD', 'ACTIVE').isSeeker, isFalse);
    });

    test('enquiry statuses use the lead vocabulary', () {
      expect(enquiryStatusLabel('RECEIVED'), 'New Enquiry');
      expect(enquiryStatusLabel('ROUTED'), 'Assigned');
      expect(enquiryStatusLabel('RESPONDED'), 'Contacted');
      expect(enquiryStatusLabel('VIEWING_SCHEDULED'), 'Viewing Scheduled');
      expect(enquiryStatusLabel('FOLLOW_UP_REQUIRED'), 'Follow-up Required');
      expect(enquiryStatusLabel('CONVERTED'), 'Converted');
      expect(enquiryStatusLabel('CLOSED'), 'Closed');
    });
  });

  group('listings', () {
    final listings = sampleListings().listings;
    Listing first(bool Function(Listing) test) => listings.firstWhere(test);

    test('the contact is a Sales Agent, Lettings Agent, Property Seller or Landlord', () {
      final agencySale = first(
        (l) =>
            l.advertiser.kind == AdvertiserKind.agency &&
            l.deal == DealType.sale,
      );
      final agencyRent = first(
        (l) =>
            l.advertiser.kind == AdvertiserKind.agency &&
            l.deal == DealType.rent,
      );
      final ownerSale = first(
        (l) =>
            l.advertiser.kind == AdvertiserKind.privateSeller &&
            l.deal == DealType.sale,
      );

      expect(agencySale.contactTitle, 'Sales Agent');
      expect(agencyRent.contactTitle, 'Lettings Agent');
      expect(ownerSale.contactTitle, 'Property Seller');
      expect(listingOwnerTitle(forSale: false), 'Landlord');
    });

    testWidgets(
      'a rental listing names its Lettings Agent and Real Estate Agency',
      (tester) async {
        final test = TestServices();
        final rental = first(
          (l) =>
              l.advertiser.kind == AdvertiserKind.agency &&
              l.deal == DealType.rent,
        );
        await pumpInApp(
          tester,
          test,
          ListingDetailScreen(slug: rental.slug),
          size: const Size(390, 5000),
        );
        await tester.pumpAndSettle();

        expect(find.text('Contact the Lettings Agent'), findsOneWidget);
        expect(find.text('Lettings Agent'), findsOneWidget);
        expect(find.text('Real Estate Agency'), findsOneWidget);
        expect(find.text('Agent'), findsNothing);
        expect(find.text('Private seller'), findsNothing);
      },
    );

    testWidgets('an owner listing for sale names the Property Seller', (
      tester,
    ) async {
      final test = TestServices();
      final owner = first(
        (l) =>
            l.advertiser.kind == AdvertiserKind.privateSeller &&
            l.deal == DealType.sale,
      );
      await pumpInApp(
        tester,
        test,
        ListingDetailScreen(slug: owner.slug),
        size: const Size(390, 5000),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contact the Property Seller'), findsOneWidget);
    });
  });

  test('directories are titled in the same vocabulary', () {
    final directory = sampleDirectory();
    expect(
      directory.info(DirectoryKind.agencies).title,
      'Real Estate Agencies',
    );
    expect(
      directory.info(DirectoryKind.agencies).singular,
      'Real Estate Agency',
    );
    expect(directory.info(DirectoryKind.agents).title, 'Estate Agents');
    expect(
      directory.info(DirectoryKind.propertyManagers).title,
      'Property Managers',
    );
  });

  testWidgets('sign-up offers the roles under their categories', (
    tester,
  ) async {
    final test = TestServices();
    await pumpInApp(
      tester,
      test,
      const RegisterScreen(),
      size: const Size(390, 4200),
    );

    for (final label in [
      'Property Seekers',
      'Prospective Buyer',
      'Prospective Tenant',
      'Real Estate Professionals',
      'Estate Agent',
      'Real Estate Businesses',
      'Agency Principal',
      'Agency Administrator',
      'Property Owners',
      'Landlord',
      'Property Seller (Vendor)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Buyer or renter'), findsNothing);
    expect(find.text('Private seller'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
