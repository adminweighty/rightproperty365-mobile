import 'package:flutter_test/flutter_test.dart';
import 'package:rightproperty365/features/directory/data/profile.dart';

import 'support.dart';

void main() {
  final directory = sampleDirectory();
  final listings = sampleListings().listings;

  test('mirrors the web: six directories and 29 profiles', () {
    expect(directory.directories.map((d) => d.kind), DirectoryKind.values);
    final total = DirectoryKind.values.fold(
      0,
      (sum, kind) => sum + directory.ofKind(kind).length,
    );
    expect(total, 29);
    expect(
      directory.info(DirectoryKind.serviceProviders).title,
      'Property Services',
    );
  });

  test('sponsored profiles come first, then A to Z', () {
    for (final kind in DirectoryKind.values) {
      final profiles = directory.ofKind(kind);
      final firstUnsponsored = profiles.indexWhere((p) => !p.sponsored);
      if (firstUnsponsored >= 0) {
        expect(
          profiles.skip(firstUnsponsored).any((p) => p.sponsored),
          isFalse,
          reason:
              '${kind.slug}: a sponsored profile is listed after an unsponsored one',
        );
      }
      for (final group in [
        profiles.where((p) => p.sponsored).toList(),
        profiles.where((p) => !p.sponsored).toList(),
      ]) {
        final names = group.map((p) => p.name.toLowerCase()).toList();
        expect(names, [...names]..sort());
      }
    }
    expect(directory.ofKind(DirectoryKind.agencies).first.sponsored, isTrue);
  });

  test('service providers are grouped by trade in the web order', () {
    final groups = directory.serviceCategories();
    expect(groups.map((g) => g.category).take(3), [
      'Plumbing',
      'Electrical',
      'Solar power',
    ]);
    expect(
      groups.expand((g) => g.entries).length,
      directory.ofKind(DirectoryKind.serviceProviders).length,
    );
    for (final group in groups) {
      expect(group.entries.every((p) => p.category == group.category), isTrue);
    }
    final plumber = groups.first.entries.first;
    expect(plumber.offerings, isNotEmpty);
    expect(plumber.offerings.first.description, isNotEmpty);
  });

  test('agencies, their agents and their listings are linked', () {
    final agency = directory.find(DirectoryKind.agencies, 'sample-estates')!;
    final agents = directory.agentsOfAgency(agency);
    expect(agents, isNotEmpty);
    expect(agents.every((a) => directory.agencyOfAgent(a) == agency), isTrue);

    final agencyListings = directory.listingsFor(agency, listings);
    expect(agencyListings, isNotEmpty);
    expect(
      agencyListings.every((l) => l.advertiser.name == agency.name),
      isTrue,
    );

    final agent = agents.first;
    expect(
      directory
          .listingsFor(agent, listings)
          .every((l) => l.listedBy == agent.name),
      isTrue,
    );

    final developer = directory.ofKind(DirectoryKind.developers).first;
    expect(directory.listingsFor(developer, listings), isEmpty);
  });

  test('a listing resolves to its agent and agency profiles', () {
    final listing = listings.first; // Sample Estates, Tendai Ncube
    final profiles = directory.profilesFor(listing);
    expect(profiles.agency?.name, listing.advertiser.name);
    expect(profiles.agent?.name, listing.listedBy);
  });

  test('unknown kinds and slugs are not found', () {
    expect(DirectoryKind.fromSlug('nope'), isNull);
    expect(
      DirectoryKind.fromSlug('property-managers'),
      DirectoryKind.propertyManagers,
    );
    expect(directory.find(DirectoryKind.agents, 'nobody'), isNull);
  });
}
