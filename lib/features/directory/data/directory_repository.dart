import 'dart:convert';

import '../../../core/terminology.dart';
import '../../listings/data/listing.dart';
import 'profile.dart';

/// Where directory profiles come from. Screens only know this interface, so
/// an implementation backed by the Go API can replace the sample one.
abstract interface class DirectoryRepository {
  List<DirectoryInfo> get directories;
  DirectoryInfo info(DirectoryKind kind);

  /// Sponsored profiles first, then alphabetical.
  List<Profile> ofKind(DirectoryKind kind);
  Profile? find(DirectoryKind kind, String slug);

  /// Service providers grouped by trade, in the order trades are shown.
  List<TradeGroup> serviceCategories();

  List<Profile> agentsOfAgency(Profile agency);
  Profile? agencyOfAgent(Profile agent);

  /// The listings an agency or agent is marketing. Other kinds have none yet.
  List<Listing> listingsFor(Profile profile, List<Listing> listings);

  /// Profile pages for a listing's agency and agent, when they exist.
  ({Profile? agency, Profile? agent}) profilesFor(Listing listing);
}

/// The Solicitors directory, used when the data does not define it yet.
const solicitorsDirectory = DirectoryInfo(
  kind: DirectoryKind.solicitors,
  title: Terms.solicitors,
  singular: Terms.solicitor,
  description: 'Solicitors and conveyancers for property transfers, leases, title checks and legal advice.',
);

/// SAMPLE DATA. Serves assets/data/directory.json, which is mirrored from the
/// web repository by tool/sync_web_data.mjs.
class SampleDirectoryRepository implements DirectoryRepository {
  SampleDirectoryRepository({
    required this.directories,
    required this._profiles,
    required this._tradeOrder,
  });

  factory SampleDirectoryRepository.fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    // A kind this version of the app does not know is skipped, not a crash.
    bool known(dynamic item) =>
        DirectoryKind.fromSlug(item['kind'] as String?) != null;
    final directories = [
      for (final kind in (json['kinds'] as List).where(known))
        DirectoryInfo.fromJson(kind as Map<String, dynamic>),
    ];
    // The Solicitors directory always exists, even before any are listed.
    if (!directories.any((d) => d.kind == DirectoryKind.solicitors)) {
      directories.add(solicitorsDirectory);
    }
    return SampleDirectoryRepository(
      directories: directories,
      profiles: [
        for (final profile in (json['profiles'] as List).where(known))
          Profile.fromJson(profile as Map<String, dynamic>),
      ],
      tradeOrder: List<String>.from(json['tradeOrder'] as List),
    );
  }

  @override
  final List<DirectoryInfo> directories;
  final List<Profile> _profiles;
  final List<String> _tradeOrder;

  @override
  DirectoryInfo info(DirectoryKind kind) =>
      directories.firstWhere((directory) => directory.kind == kind);

  @override
  List<Profile> ofKind(DirectoryKind kind) =>
      _profiles.where((profile) => profile.kind == kind).toList()..sort((a, b) {
        if (a.sponsored != b.sponsored) return a.sponsored ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

  @override
  Profile? find(DirectoryKind kind, String slug) {
    for (final profile in _profiles) {
      if (profile.kind == kind && profile.slug == slug) return profile;
    }
    return null;
  }

  @override
  List<TradeGroup> serviceCategories() {
    final groups = <String, List<Profile>>{};
    for (final profile in ofKind(DirectoryKind.serviceProviders)) {
      groups
          .putIfAbsent(profile.category ?? 'Other services', () => [])
          .add(profile);
    }
    int rank(String category) {
      final index = _tradeOrder.indexOf(category);
      return index < 0 ? _tradeOrder.length : index;
    }

    final categories = groups.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return [
      for (final category in categories)
        TradeGroup(category, groups[category]!),
    ];
  }

  @override
  List<Profile> agentsOfAgency(Profile agency) => _profiles
      .where(
        (p) => p.kind == DirectoryKind.agents && p.agencySlug == agency.slug,
      )
      .toList();

  @override
  Profile? agencyOfAgent(Profile agent) => agent.agencySlug == null
      ? null
      : find(DirectoryKind.agencies, agent.agencySlug!);

  @override
  List<Listing> listingsFor(Profile profile, List<Listing> listings) =>
      switch (profile.kind) {
        DirectoryKind.agencies =>
          listings.where((l) => l.advertiser.name == profile.name).toList(),
        DirectoryKind.agents =>
          listings.where((l) => l.listedBy == profile.name).toList(),
        _ => const [],
      };

  @override
  ({Profile? agency, Profile? agent}) profilesFor(Listing listing) {
    Profile? named(DirectoryKind kind, String name) {
      for (final profile in _profiles) {
        if (profile.kind == kind && profile.name == name) return profile;
      }
      return null;
    }

    return (
      agency: named(DirectoryKind.agencies, listing.advertiser.name),
      agent: named(DirectoryKind.agents, listing.listedBy),
    );
  }
}
