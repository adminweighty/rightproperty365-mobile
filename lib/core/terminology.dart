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

/// A role the API accepts at sign-up, as GET /v1/reference/account_roles
/// describes it.
class SelectableRole {
  const SelectableRole(
    this.code,
    this.label, [
    this.group,
    this.requiresVerification,
  ]);

  final String code;

  /// The API's wording. It is configurable on the server and wins over the
  /// names built into the app.
  final String label;

  /// The heading the API lists the role under, when it gives one.
  final String? group;

  /// From the API: false for Property Seeker roles, which need no approval.
  final bool? requiresVerification;

  /// A Property Seeker role. A registration holds seeker roles only or other
  /// roles only, never both.
  bool get seeker => requiresVerification == null
      ? seekerRoleCodes.contains(code)
      : !requiresVerification!;
}

/// The roles this app knows, in the specification's categories. Used for the
/// descriptions under each role, for naming roles on other screens, and as
/// the sign-up list when the API cannot be reached. Platform administrator
/// roles are never offered; the API rejects them.
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
      'SALES_AGENT',
      Terms.salesAgent,
      'An Estate Agent specialising in properties for sale.',
    ),
    AccountRoleOption(
      'LETTINGS_AGENT',
      Terms.lettingsAgent,
      'An Estate Agent specialising in rentals and leases.',
    ),
    AccountRoleOption(
      'PROPERTY_MANAGER',
      Terms.propertyManager,
      'Manages rental properties, tenants and viewings on behalf of owners.',
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
      'Owns property offered for rent or lease.',
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

/// The roles shown at sign-up before the API has answered, and when it
/// cannot be reached: everything this app knows, in its own grouping.
List<SelectableRole> get builtInRoles => [
  for (final group in accountRoleGroups)
    for (final role in group.roles)
      SelectableRole(role.value, role.label, group.legend),
];

/// The sign-up list for the roles the API accepts, in the API's order.
///
/// Labels and group headings are the API's, so they can be changed on the
/// server without an app update and a role added there (as Solicitor was) is
/// offered straight away. The one-line description under each role is the
/// app's, where it has one. A role the API sends without a heading falls
/// under the app's heading for it, or "Other roles".
List<AccountRoleGroup> signUpRoleGroups(List<SelectableRole> accepted) {
  final descriptions = <String, String>{};
  final headings = <String, String>{};
  for (final group in accountRoleGroups) {
    for (final role in group.roles) {
      descriptions[role.value] = role.description;
      headings[role.value] = group.legend;
    }
  }

  final grouped = <String, List<AccountRoleOption>>{};
  for (final role in accepted) {
    final heading = role.group ?? headings[role.code] ?? 'Other roles';
    grouped
        .putIfAbsent(heading, () => [])
        .add(
          AccountRoleOption(
            role.code,
            role.label,
            descriptions[role.code] ?? '',
          ),
        );
  }
  return [
    for (final entry in grouped.entries)
      AccountRoleGroup(entry.key, entry.value),
  ];
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
  'PROPERTY_MANAGER': Terms.propertyManager,
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
    title: 'Property Managers',
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
