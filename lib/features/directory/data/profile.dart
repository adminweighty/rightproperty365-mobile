import '../../../core/terminology.dart';

/// The six public directories. [slug] is the value used by the web routes and
/// by the API's `recipient.kind`.
enum DirectoryKind {
  agencies('agencies'),
  agents('agents'),
  developers('developers'),
  propertyManagers('property-managers'),
  hosts('hosts'),
  serviceProviders('service-providers'),
  solicitors('solicitors');

  const DirectoryKind(this.slug);
  final String slug;

  static DirectoryKind? fromSlug(String? slug) {
    for (final kind in values) {
      if (kind.slug == slug) return kind;
    }
    return null;
  }
}

/// Title and description of one directory.
class DirectoryInfo {
  const DirectoryInfo({
    required this.kind,
    required this.title,
    required this.singular,
    required this.description,
  });

  factory DirectoryInfo.fromJson(Map<String, dynamic> json) => DirectoryInfo(
    kind: DirectoryKind.fromSlug(json['kind'] as String)!,
    title: directoryTitles[json['kind']]?.title ?? json['title'] as String,
    singular:
        directoryTitles[json['kind']]?.singular ?? json['singular'] as String,
    description: json['description'] as String,
  );

  final DirectoryKind kind;
  final String title;
  final String singular;
  final String description;
}

class Offering {
  const Offering(this.name, this.description);
  final String name;
  final String description;
}

/// A directory entry: an agency, agent, developer, property manager, host or
/// service provider. It deliberately has no phone number or email address;
/// contact is by enquiry only.
class Profile {
  const Profile({
    required this.slug,
    required this.kind,
    required this.name,
    required this.role,
    required this.tagline,
    required this.about,
    required this.city,
    required this.areas,
    required this.services,
    required this.verified,
    this.category,
    this.offerings = const [],
    this.sponsored = false,
    this.since,
    this.agencySlug,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    slug: json['slug'] as String,
    kind: DirectoryKind.fromSlug(json['kind'] as String)!,
    name: json['name'] as String,
    role: json['role'] as String,
    tagline: json['tagline'] as String,
    about: json['about'] as String,
    city: json['city'] as String,
    areas: List<String>.from(json['areas'] as List),
    services: List<String>.from(json['services'] as List),
    category: json['category'] as String?,
    offerings: [
      for (final offering in (json['offerings'] as List?) ?? const [])
        Offering(offering['name'] as String, offering['description'] as String),
    ],
    verified: json['verified'] as bool,
    sponsored: json['sponsored'] as bool? ?? false,
    since: json['since'] as int?,
    agencySlug: json['agencySlug'] as String?,
  );

  final String slug;
  final DirectoryKind kind;
  final String name;

  /// Job title for people, speciality for businesses.
  final String role;
  final String tagline;
  final String about;
  final String city;
  final List<String> areas;
  final List<String> services;

  /// Service providers only: the trade they are listed under.
  final String? category;
  final List<Offering> offerings;
  final bool verified;

  /// Paid placement. Always labelled "Sponsored" wherever it is shown.
  final bool sponsored;
  final int? since;

  /// For agents: the agency they work for.
  final String? agencySlug;

  /// Up to two letters for the avatar, skipping "and".
  String get initials {
    final letters = name
        .split(' ')
        .where((word) => word.isNotEmpty && word.toLowerCase() != 'and')
        .map((word) => word[0])
        .join();
    return (letters.length > 2 ? letters.substring(0, 2) : letters)
        .toUpperCase();
  }
}

/// Service providers of one trade.
class TradeGroup {
  const TradeGroup(this.category, this.entries);
  final String category;
  final List<Profile> entries;
}
