/// A role a person can choose for themselves at sign-up.
class AccountRoleOption {
  const AccountRoleOption(this.value, this.label);
  final String value;
  final String label;
}

class AccountRoleGroup {
  const AccountRoleGroup(this.legend, this.roles);
  final String legend;
  final List<AccountRoleOption> roles;
}

/// Mirrors `accountRoleGroups` in the web's src/lib/api/auth.ts. Platform
/// administrator roles are never in this list; the API rejects them.
const accountRoleGroups = [
  AccountRoleGroup('Looking for property', [
    AccountRoleOption('CONSUMER', 'Buyer or renter'),
    AccountRoleOption('TENANT', 'Tenant'),
  ]),
  AccountRoleGroup('Listing or managing property', [
    AccountRoleOption('PRIVATE_SELLER', 'Private seller'),
    AccountRoleOption('LANDLORD', 'Landlord or property manager'),
    AccountRoleOption('HOST', 'Host: short stays and venues'),
    AccountRoleOption('DEVELOPER', 'Property developer'),
    AccountRoleOption('SERVICE_PROVIDER', 'Service provider'),
  ]),
  AccountRoleGroup('Working at an agency', [
    AccountRoleOption('AGENT', 'Estate agent'),
    AccountRoleOption('AGENCY_STAFF', 'Agency staff'),
    AccountRoleOption('AGENCY_ADMIN', 'Agency administrator'),
    AccountRoleOption('AGENCY_OWNER', 'Agency owner'),
  ]),
];

const _labels = {
  // Platform roles
  'SUPER_ADMIN': 'Super admin',
  'PLATFORM_ADMIN': 'Platform admin',
  'MARKET_ADMIN': 'Market admin',
  'FINANCE_ADMIN': 'Finance admin',
  'CONTENT_ADMIN': 'Content admin',
  'MODERATOR': 'Moderator',
  'SUPPORT': 'Support',
  // Membership roles
  'OWNER': 'Owner',
  'MANAGER': 'Manager',
  'STAFF': 'Staff',
  // Organisation kinds
  'AGENCY': 'Agency',
};

/// A readable label for any role or organisation-kind code from the API.
String roleLabel(String code) {
  for (final group in accountRoleGroups) {
    for (final role in group.roles) {
      if (role.value == code) return role.label;
    }
  }
  final known = _labels[code];
  if (known != null) return known;
  final words = code.toLowerCase().split('_').join(' ');
  return words.isEmpty ? code : words[0].toUpperCase() + words.substring(1);
}

/// A self-selected role. A pending role grants no access until it is verified.
class AccountRole {
  const AccountRole(this.role, this.status);
  final String role;
  final String status;
  bool get pending => status == 'PENDING_VERIFICATION';
}

class Membership {
  const Membership({
    required this.organisationName,
    required this.organisationKind,
    required this.marketCode,
    required this.role,
  });
  final String organisationName;
  final String organisationKind;
  final String marketCode;
  final String role;
}

/// The signed-in person, from GET /v1/me. Roles are for choosing what to
/// show only; the API authorises every request.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.emailVerified,
    this.accountRoles = const [],
    this.platformRoles = const [],
    this.memberships = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    emailVerified: json['email_verified'] as bool? ?? false,
    accountRoles: [
      for (final role in (json['account_roles'] as List?) ?? const [])
        AccountRole(role['role'] as String, role['status'] as String),
    ],
    platformRoles: [
      for (final role in (json['platform_roles'] as List?) ?? const [])
        role['role'] as String,
    ],
    memberships: [
      for (final m in (json['memberships'] as List?) ?? const [])
        Membership(
          organisationName: m['organisation_name'] as String,
          organisationKind: m['organisation_kind'] as String,
          marketCode: m['market_code'] as String,
          role: m['role'] as String,
        ),
    ],
  );

  final String id;
  final String name;
  final String email;
  final bool emailVerified;
  final List<AccountRole> accountRoles;
  final List<String> platformRoles;
  final List<Membership> memberships;
}
