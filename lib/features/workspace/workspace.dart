import '../../core/api/api_client.dart';

/// One organisation the signed-in person belongs to, with what they may do in
/// it, from `GET /v1/me/dashboard`.
class WorkOrganisation {
  const WorkOrganisation({
    required this.id,
    required this.name,
    required this.kind,
    required this.marketCode,
    required this.role,
    required this.roleLabel,
    this.canManageTeam = false,
    this.canAssignWork = false,
    this.canCreateLeases = false,
    this.canManageListings = false,
  });

  factory WorkOrganisation.fromJson(Map<String, dynamic> json) =>
      WorkOrganisation(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String? ?? '',
        marketCode: json['market_code'] as String? ?? '',
        role: json['role'] as String? ?? '',
        roleLabel: json['role_label'] as String? ?? '',
        canManageTeam: json['can_manage_team'] == true,
        canAssignWork: json['can_assign_work'] == true,
        canCreateLeases: json['can_create_leases'] == true,
        canManageListings: json['can_manage_listings'] == true,
      );

  final String id;
  final String name;
  final String kind;
  final String marketCode;

  /// OWNER, MANAGER, AGENT or STAFF.
  final String role;
  final String roleLabel;
  final bool canManageTeam;
  final bool canAssignWork;
  final bool canCreateLeases;

  /// The person manages listings here, so may read their statistics.
  final bool canManageListings;

  /// The roles this person may invite someone to: an owner any but owner, a
  /// manager agents and staff. The API checks it again.
  List<String> get invitableRoles => switch (role) {
    'OWNER' => const ['MANAGER', 'AGENT', 'STAFF'],
    'MANAGER' => const ['AGENT', 'STAFF'],
    _ => const [],
  };
}

/// What the signed-in person's work area offers.
class Workspace {
  const Workspace({
    this.organisations = const [],
    this.createsLeases = false,
    this.managesListings = false,
    this.directOwner = false,
    this.documentsWaitingForYou = 0,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final capabilities =
        json['capabilities'] as Map<String, dynamic>? ?? const {};
    // Counters are a list of {key, label, value, ...}.
    int count(String key) {
      for (final item in (json['counters'] as List?) ?? const []) {
        if (item is Map && item['key'] == key && item['value'] is int) {
          return item['value'] as int;
        }
      }
      return 0;
    }

    return Workspace(
      organisations: [
        for (final item in (json['organisations'] as List?) ?? const [])
          WorkOrganisation.fromJson(item as Map<String, dynamic>),
      ],
      createsLeases: capabilities['creates_leases'] == true,
      managesListings: capabilities['manages_listings'] == true,
      directOwner: json['direct_owner'] == true,
      documentsWaitingForYou: count('agreements.waiting_for_you'),
    );
  }

  final List<WorkOrganisation> organisations;
  final bool createsLeases;

  /// `/v1/me/listings` is open to the person (an agency member or an
  /// approved owner).
  final bool managesListings;

  /// An approved landlord or property seller, who pays their own
  /// subscription.
  final bool directOwner;
  final int documentsWaitingForYou;

  /// Renewal invoices go to a direct owner, and to an organisation's owners
  /// and managers (API 0.47.0).
  bool get receivesInvoices =>
      directOwner ||
      organisations.any((o) => o.role == 'OWNER' || o.role == 'MANAGER');

  List<WorkOrganisation> get teamsToManage => [
    for (final o in organisations)
      if (o.canManageTeam) o,
  ];
  List<WorkOrganisation> get assigningOrganisations => [
    for (final o in organisations)
      if (o.canAssignWork) o,
  ];
  List<WorkOrganisation> get statisticsOrganisations => [
    for (final o in organisations)
      if (o.canManageListings) o,
  ];
  List<WorkOrganisation> get leaseOrganisations => [
    for (final o in organisations)
      if (o.canCreateLeases) o,
  ];
}

abstract interface class WorkspaceRepository {
  /// Throws [ApiFailure].
  Future<Workspace> load();
}

class ApiWorkspaceRepository implements WorkspaceRepository {
  ApiWorkspaceRepository(this._api);

  final ApiClient _api;

  @override
  Future<Workspace> load() async =>
      Workspace.fromJson((await _api.get('/v1/me/dashboard')).body);
}
