import '../../../core/terminology.dart';

/// The question a registration must answer (GET /v1/auth/captcha). It is
/// valid until [expiresAt] and for one attempt only; never cache it.
class Captcha {
  const Captcha({
    required this.id,
    required this.question,
    required this.expiresAt,
  });

  factory Captcha.fromJson(Map<String, dynamic> json) => Captcha(
    id: json['captcha_id'] as String,
    question: json['question'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );

  final String id;

  /// Plain words, for example "What is 7 + 5?".
  final String question;
  final DateTime expiresAt;
}

/// The first step of signing in succeeded: the API emailed a code to the
/// account's address, to be sent back with [id].
class SignInChallenge {
  const SignInChallenge({
    required this.id,
    required this.sentTo,
    required this.expiresAt,
    required this.codeLength,
  });

  factory SignInChallenge.fromJson(Map<String, dynamic> json) =>
      SignInChallenge(
        id: json['challenge_id'] as String,
        sentTo: json['sent_to'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        codeLength: json['code_length'] as int? ?? 6,
      );

  final String id;

  /// The address, masked, for example `u•••@example.com`.
  final String sentTo;
  final DateTime expiresAt;

  /// Digits in the emailed code.
  final int codeLength;
}

/// Where the email-and-password step of signing in leads.
sealed class SignInStep {
  const SignInStep();
}

/// A code was emailed; send it with `AuthRepository.verifySignInCode`.
class CodeRequired extends SignInStep {
  const CodeRequired(this.challenge);
  final SignInChallenge challenge;
}

/// Signed in straight away (a server that does not ask for a code).
class SignedIn extends SignInStep {
  const SignedIn(this.session);
  final ({User user, String token}) session;
}

/// A self-selected role. A professional role grants no access until a
/// Platform Administrator has approved it.
class AccountRole {
  const AccountRole(this.role, this.status, [this.onboardingStatus]);

  /// The API's role code, for example `AGENT`. Show [label], never this.
  final String role;

  /// `ACTIVE`, `PENDING_VERIFICATION` or `REJECTED`.
  final String status;

  /// Status of the role's verification application, when it has one.
  final String? onboardingStatus;

  String get label => roleLabel(role);

  /// Property Seeker roles need no verification.
  bool get isSeeker => seekerRoleCodes.contains(role);
  bool get approved => status == 'ACTIVE';

  /// "Approved", "Under Review", "Pending Verification", ...
  String get verificationLabel =>
      verificationStatusLabel(status, onboardingStatus);
}

class Membership {
  const Membership({
    required this.organisationName,
    required this.organisationKind,
    required this.marketCode,
    required this.role,
    this.apiRoleLabel,
  });
  final String organisationName;
  final String organisationKind;
  final String marketCode;
  final String role;

  /// `role_label` from the API, when it sends one.
  final String? apiRoleLabel;

  /// "Agency Principal", "Estate Agent", ... The API's wording wins.
  String get roleLabel =>
      apiRoleLabel ?? membershipRoleLabel(role, organisationKind);

  /// "Real Estate Agency", "Landlord", ...
  String get kindLabel => organisationKindLabel(organisationKind);
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
        AccountRole(
          role['role'] as String,
          role['status'] as String,
          role['onboarding_status'] as String?,
        ),
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
          apiRoleLabel: m['role_label'] as String?,
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

/// What deleting an account did (`AccountDeleted`).
class AccountDeletion {
  const AccountDeletion({
    this.organisationsLeft = 0,
    this.listingsWithdrawn = 0,
    this.subscriptionsCancelled = 0,
  });

  factory AccountDeletion.fromJson(Map<String, dynamic> json) =>
      AccountDeletion(
        organisationsLeft: json['organisations_left'] as int? ?? 0,
        listingsWithdrawn: json['listings_withdrawn'] as int? ?? 0,
        subscriptionsCancelled: json['subscriptions_cancelled'] as int? ?? 0,
      );

  final int organisationsLeft;
  final int listingsWithdrawn;
  final int subscriptionsCancelled;
}
