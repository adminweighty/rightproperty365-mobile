/// The real-estate vocabulary of RightProperty365 (functional specification,
/// "Standard Real Estate User Roles"). Every role name shown in the app comes
/// from here, so the wording is the same on every screen.
///
/// Role names are written as titles: "Estate Agent", not "estate agent".
library;

abstract final class Terms {
  // Property Seekers
  static const propertySeeker = 'Property Seeker';
  static const prospectiveBuyer = 'Prospective Buyer';
  static const prospectiveTenant = 'Prospective Tenant';

  // Real Estate Professionals
  static const estateAgent = 'Estate Agent';
  static const estateAgents = 'Estate Agents';
  static const salesAgent = 'Sales Agent';
  static const lettingsAgent = 'Lettings Agent';
  static const propertyManager = 'Property Manager';
  static const solicitor = 'Solicitor';
  static const solicitors = 'Solicitors';

  // Real Estate Businesses
  static const agency = 'Real Estate Agency';
  static const agencies = 'Real Estate Agencies';
  static const agencyPrincipal = 'Agency Principal';
  static const agencyAdministrator = 'Agency Administrator';
  static const agencyStaff = 'Agency Staff';

  // Property Owners
  static const landlord = 'Landlord';
  static const propertySeller = 'Property Seller';

  // Platform Operations
  static const platformAdministrator = 'Platform Administrator';
  static const superAdministrator = 'Super Administrator';
}

/// A role a person can choose for themselves at sign-up.
class AccountRoleOption {
  const AccountRoleOption(this.value, this.label, this.description);

  /// The API's role code.
  final String value;
  final String label;
  final String description;
}

class AccountRoleGroup {
  const AccountRoleGroup(this.legend, this.roles);
  final String legend;
  final List<AccountRoleOption> roles;
}

/// The roles offered at sign-up, in the specification's categories. The codes
/// are the ones the API accepts (`SelectableAccountRole`). Platform
/// administrator roles are never offered; the API rejects them.
///
/// Sales Agent, Lettings Agent and Property Manager have no code of their own
/// in the API yet, so they cannot be chosen separately: an agent registers as
/// an Estate Agent and a property manager under Landlord.
const accountRoleGroups = [
  AccountRoleGroup('Property Seekers', [
    AccountRoleOption(
      'CONSUMER',
      Terms.prospectiveBuyer,
      'Looking for a property to buy.',
    ),
    AccountRoleOption(
      'TENANT',
      Terms.prospectiveTenant,
      'Looking for a property to rent or lease.',
    ),
  ]),
  AccountRoleGroup('Real Estate Professionals', [
    AccountRoleOption(
      'AGENT',
      Terms.estateAgent,
      'Markets properties, manages enquiries and arranges viewings, for sale or to let.',
    ),
    AccountRoleOption(
      'SOLICITOR',
      Terms.solicitor,
      'Handles conveyancing, property transfers, leases and legal advice.',
    ),
  ]),
  AccountRoleGroup('Real Estate Businesses', [
    AccountRoleOption(
      'AGENCY_OWNER',
      Terms.agencyPrincipal,
      'Heads a real estate agency or brokerage and is responsible for its account.',
    ),
    AccountRoleOption(
      'AGENCY_ADMIN',
      Terms.agencyAdministrator,
      "Manages an agency's agents, listings and enquiries.",
    ),
    AccountRoleOption(
      'AGENCY_STAFF',
      Terms.agencyStaff,
      'Works for an agency in a support role.',
    ),
  ]),
  AccountRoleGroup('Property Owners', [
    AccountRoleOption(
      'LANDLORD',
      Terms.landlord,
      'Owns or manages property offered for rent or lease.',
    ),
    AccountRoleOption(
      'PRIVATE_SELLER',
      '${Terms.propertySeller} (Vendor)',
      'Owns a property offered for sale.',
    ),
  ]),
  AccountRoleGroup('Other property businesses', [
    AccountRoleOption(
      'DEVELOPER',
      'Property Developer',
      'Develops estates, homes or commercial projects.',
    ),
    AccountRoleOption(
      'HOST',
      'Host',
      'Offers short stays, showrooms or venues for hire.',
    ),
    AccountRoleOption(
      'SERVICE_PROVIDER',
      'Property Service Provider',
      'Offers a trade or professional service for property.',
    ),
  ]),
];

/// The role codes every version of the API accepts. Used when the live list
/// cannot be loaded. Roles added later, such as SOLICITOR, are offered only
/// once the API lists them (GET /v1/reference/account_roles).
const baselineRoleCodes = {
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
};

/// The sign-up groups limited to the roles the API accepts. A role the API
/// offers that this app has no name for yet is listed last under the API's
/// own label, so a new role is never hidden.
List<AccountRoleGroup> signUpRoleGroups(Map<String, String> accepted) {
  final known = <String>{};
  final groups = <AccountRoleGroup>[];
  for (final group in accountRoleGroups) {
    final roles = group.roles
        .where((r) => accepted.containsKey(r.value))
        .toList();
    known.addAll(group.roles.map((r) => r.value));
    if (roles.isNotEmpty) groups.add(AccountRoleGroup(group.legend, roles));
  }
  final unnamed = [
    for (final entry in accepted.entries)
      if (!known.contains(entry.key))
        AccountRoleOption(entry.key, entry.value, ''),
  ];
  if (unnamed.isNotEmpty) groups.add(AccountRoleGroup('Other roles', unnamed));
  return groups;
}

/// Self-selected role codes that need no verification.
const seekerRoleCodes = {'CONSUMER', 'TENANT'};

const _platformRoles = {
  'SUPER_ADMIN': Terms.superAdministrator,
  'PLATFORM_ADMIN': Terms.platformAdministrator,
  'MARKET_ADMIN': 'Market Administrator',
  'FINANCE_ADMIN': 'Finance Administrator',
  'CONTENT_ADMIN': 'Content Administrator',
  'MODERATOR': 'Moderator',
  'SUPPORT': 'Support',
};

const _organisationKinds = {
  'AGENCY': Terms.agency,
  'LAW_FIRM': 'Law Firm',
  'LANDLORD': Terms.landlord,
  'HOST': 'Host',
  'DEVELOPER': 'Property Developer',
  'SERVICE_PROVIDER': 'Property Service Provider',
};

String _titleCase(String code) => code
    .toLowerCase()
    .split('_')
    .where((word) => word.isNotEmpty)
    .map((word) => word[0].toUpperCase() + word.substring(1))
    .join(' ');

/// The name of a self-selected account role or a platform role.
String roleLabel(String code) {
  for (final group in accountRoleGroups) {
    for (final role in group.roles) {
      if (role.value == code) return role.label;
    }
  }
  return _platformRoles[code] ?? _titleCase(code);
}

/// The name of an organisation kind: "Real Estate Agency", "Landlord".
String organisationKindLabel(String kind) =>
    _organisationKinds[kind] ?? _titleCase(kind);

/// What someone's membership of an organisation is called. In a Real Estate
/// Agency the owner is the Agency Principal and a manager is an Agency
/// Administrator; elsewhere the plain words are used.
String membershipRoleLabel(String role, String organisationKind) {
  final inAgency = organisationKind == 'AGENCY';
  return switch (role) {
    'OWNER' => inAgency ? Terms.agencyPrincipal : 'Principal',
    'MANAGER' => inAgency ? Terms.agencyAdministrator : Terms.propertyManager,
    'AGENT' => Terms.estateAgent,
    'STAFF' => inAgency ? Terms.agencyStaff : 'Staff',
    _ => _titleCase(role),
  };
}

/// The agent behind a listing: a Sales Agent for a property for sale, a
/// Lettings Agent for one to rent.
String listingAgentTitle({required bool forSale}) =>
    forSale ? Terms.salesAgent : Terms.lettingsAgent;

/// The owner behind a listing with no agency: a Property Seller for a sale,
/// a Landlord for a rental.
String listingOwnerTitle({required bool forSale}) =>
    forSale ? Terms.propertySeller : Terms.landlord;

/// How each directory is titled, in the specification's vocabulary. Keyed by
/// the directory's slug; kinds not listed keep the title from the data.
const directoryTitles = {
  'agencies': (title: Terms.agencies, singular: Terms.agency),
  'agents': (title: Terms.estateAgents, singular: Terms.estateAgent),
  'developers': (title: 'Property Developers', singular: 'Property Developer'),
  'property-managers': (
    title: 'Landlords and Property Managers',
    singular: Terms.propertyManager,
  ),
  'hosts': (title: 'Hosts and Venues', singular: 'Host'),
  'solicitors': (title: Terms.solicitors, singular: Terms.solicitor),
  'service-providers': (
    title: 'Property Services',
    singular: 'Property Service Provider',
  ),
};

/// Where a professional role stands with Platform Administrators.
String verificationStatusLabel(String status, String? onboardingStatus) =>
    switch ((status, onboardingStatus)) {
      ('ACTIVE', _) => 'Approved',
      ('REJECTED', _) => 'Rejected',
      ('SUSPENDED', _) => 'Suspended',
      (_, 'SUBMITTED') => 'Under Review',
      (_, 'CHANGES_REQUESTED') => 'Changes Requested',
      (_, 'REJECTED') => 'Rejected',
      _ => 'Pending Verification',
    };

/// The status of an enquiry as a Property Seeker sees it. The API's internal
/// statuses are mapped onto the specification's lead statuses; codes already
/// in that vocabulary pass straight through.
String enquiryStatusLabel(String status) => switch (status) {
  'RECEIVED' || 'NEW_ENQUIRY' => 'New Enquiry',
  'ROUTED' || 'ASSIGNED' => 'Assigned',
  'IN_PROGRESS' || 'RESPONDED' || 'CONTACTED' => 'Contacted',
  'VIEWING_REQUESTED' => 'Viewing Requested',
  'VIEWING_SCHEDULED' => 'Viewing Scheduled',
  'FOLLOW_UP_REQUIRED' => 'Follow-up Required',
  'CONVERTED' => 'Converted',
  'CLOSED' => 'Closed',
  'ROUTING_EXCEPTION' => 'Awaiting Assignment',
  _ => 'New Enquiry',
};
