import '../../core/api/api_client.dart';
import '../../core/api/idempotency.dart';
import '../../core/branch.dart';

/// Wording for team roles when the API does not send a label.
String teamRoleLabel(String role) => switch (role) {
  'OWNER' => 'Agency Principal',
  'MANAGER' => 'Agency Administrator',
  'AGENT' => 'Estate Agent',
  'STAFF' => 'Agency Staff',
  _ => role,
};

/// What each team role may do, shown when choosing one.
String teamRoleHint(String role) => switch (role) {
  'MANAGER' => 'Runs the team and the inbox. Can invite agents and staff.',
  'AGENT' => 'Handles enquiries and listings given to them.',
  'STAFF' => 'Helps with listings. Is not given enquiries.',
  _ => '',
};

/// One member of an organisation (`TeamMember`). No email or phone number.
class TeamMember {
  const TeamMember({
    required this.userId,
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.status,
    required this.statusLabel,
    this.jobTitle,
    this.branch,
    this.joinedAt,
    this.openLeads = 0,
    this.isYou = false,
    this.canChange = false,
    this.allowedRoles = const [],
    this.canHoldLeads = false,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    userId: json['user_id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    roleLabel:
        json['role_label'] as String? ?? teamRoleLabel(json['role'] as String),
    status: json['status'] as String? ?? 'ACTIVE',
    statusLabel: json['status_label'] as String? ?? '',
    jobTitle: json['job_title'] as String?,
    branch: branchName(json['branch']),
    joinedAt: switch (json['joined_at']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    },
    openLeads: json['open_leads'] as int? ?? 0,
    isYou: json['is_you'] == true,
    canChange: json['can_change'] == true,
    allowedRoles: [
      for (final role in (json['allowed_roles'] as List?) ?? const [])
        role as String,
    ],
    canHoldLeads: json['can_hold_leads'] == true,
  );

  final String userId;
  final String name;
  final String role;
  final String roleLabel;

  /// ACTIVE or SUSPENDED.
  final String status;
  final String statusLabel;
  final String? jobTitle;

  /// The branch the member is pinned to; null sees the whole organisation
  /// (API 0.57.0). Pinning is done on the website.
  final String? branch;
  final DateTime? joinedAt;

  /// Open requests assigned to the member.
  final int openLeads;
  final bool isYou;
  final bool canChange;
  final List<String> allowedRoles;
  final bool canHoldLeads;

  bool get suspended => status == 'SUSPENDED';
}

/// A pending invitation as the team's managers see it. Never its token.
class TeamInvitation {
  const TeamInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.roleLabel,
    required this.invitedBy,
    required this.expiresAt,
    this.jobTitle,
    this.expired = false,
    this.canCancel = false,
  });

  factory TeamInvitation.fromJson(Map<String, dynamic> json) => TeamInvitation(
    id: json['id'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    roleLabel:
        json['role_label'] as String? ?? teamRoleLabel(json['role'] as String),
    jobTitle: json['job_title'] as String?,
    invitedBy:
        (json['invited_by'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    expiresAt: DateTime.parse(json['expires_at'] as String),
    expired: json['expired'] == true,
    canCancel: json['can_cancel'] == true,
  );

  final String id;
  final String email;
  final String role;
  final String roleLabel;
  final String? jobTitle;
  final String invitedBy;
  final DateTime expiresAt;
  final bool expired;
  final bool canCancel;
}

class Team {
  const Team({
    required this.organisationId,
    required this.organisationName,
    required this.members,
  });

  final String organisationId;
  final String organisationName;
  final List<TeamMember> members;
}

/// What an invitation link is for, shown before accepting it.
class PublicInvitation {
  const PublicInvitation({
    required this.organisationName,
    required this.organisationKind,
    required this.role,
    required this.roleLabel,
    required this.invitedByName,
    required this.emailMasked,
    required this.expiresAt,
    this.jobTitle,
  });

  factory PublicInvitation.fromJson(Map<String, dynamic> json) {
    final organisation = json['organisation'] as Map<String, dynamic>;
    return PublicInvitation(
      organisationName: organisation['name'] as String,
      organisationKind: organisation['kind'] as String? ?? '',
      role: json['role'] as String,
      roleLabel:
          json['role_label'] as String? ??
          teamRoleLabel(json['role'] as String),
      jobTitle: json['job_title'] as String?,
      invitedByName: json['invited_by_name'] as String? ?? '',
      emailMasked: json['email_masked'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String organisationName;
  final String organisationKind;
  final String role;
  final String roleLabel;
  final String? jobTitle;
  final String invitedByName;
  final String emailMasked;
  final DateTime expiresAt;
}

/// A change to a member: any of role, status and job title.
class MemberChange {
  const MemberChange({this.role, this.status, this.jobTitle});
  final String? role;
  final String? status;
  final String? jobTitle;

  Map<String, dynamic> toJson() => {
    'role': ?role,
    'status': ?status,
    'job_title': ?jobTitle,
  };
}

/// The plain words for a team failure; other codes keep the API's message.
String teamMessage(ApiFailure failure) => switch (failure.code) {
  'ROLE_NOT_ALLOWED' => 'You cannot give that role. Only an Agency Principal makes someone an administrator.',
  'OWNER_PROTECTED' => 'An Agency Principal cannot be changed here.',
  'LAST_OWNER' => 'The agency needs at least one active Agency Principal.',
  'SELF_CHANGE_FORBIDDEN' => 'You cannot change your own membership.',
  'MEMBER_NOT_FOUND' => 'That person is no longer on the team.',
  'ALREADY_A_MEMBER' => 'That person is already on the team.',
  'INVITATION_NOT_FOUND' =>
    'We could not find that invitation. Check that you used the whole link.',
  'INVITATION_EXPIRED' => 'This invitation has expired. Ask the person who invited you to send a new one.',
  'INVITATION_NO_LONGER_VALID' => 'This invitation no longer works: it was used, cancelled or replaced by a newer one.',
  'INVITATION_EMAIL_MISMATCH' => 'This invitation was sent to another email address. Sign in with that address to accept it.',
  'SEEKER_ACCOUNT_CANNOT_JOIN' => 'A Property Seeker account cannot join a team. Create a professional account with the invited address.',
  'FORBIDDEN' => 'Only the Agency Principal and administrators can do this.',
  _ => failure.message,
};

abstract interface class TeamRepository {
  Future<Team> members(String organisationId);
  Future<List<TeamInvitation>> invitations(String organisationId);
  Future<TeamInvitation> invite(
    String organisationId, {
    required String email,
    required String role,
    String? jobTitle,
  });
  Future<void> cancelInvitation(String organisationId, String invitationId);
  Future<TeamMember> change(
    String organisationId,
    String userId,
    MemberChange change,
  );
  Future<void> remove(String organisationId, String userId);

  /// Gives a received request to a member, or back to the inbox with null.
  Future<void> assign(String requestId, String? userId);

  Future<PublicInvitation> invitation(String token);
  Future<String> accept(String token);
}

class ApiTeamRepository implements TeamRepository {
  ApiTeamRepository(this._api, {String Function()? newKey})
    : _newKey = newKey ?? IdempotencyKeys.randomKey;

  final ApiClient _api;
  final String Function() _newKey;

  String _org(String id) =>
      '/v1/agent/organisations/${Uri.encodeComponent(id)}';

  @override
  Future<Team> members(String organisationId) async {
    final body = (await _api.get('${_org(organisationId)}/members')).body;
    final organisation = body['organisation'] as Map<String, dynamic>;
    return Team(
      organisationId: organisation['id'] as String,
      organisationName: organisation['name'] as String,
      members: [
        for (final item in (body['items'] as List?) ?? const [])
          TeamMember.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  @override
  Future<List<TeamInvitation>> invitations(String organisationId) async {
    final body = (await _api.get('${_org(organisationId)}/invitations')).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        TeamInvitation.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<TeamInvitation> invite(
    String organisationId, {
    required String email,
    required String role,
    String? jobTitle,
  }) async {
    final body = (await _api.postJson('${_org(organisationId)}/invitations', {
      'email': email.trim().toLowerCase(),
      'role': role,
      if (jobTitle != null && jobTitle.trim().isNotEmpty)
        'job_title': jobTitle.trim(),
    })).body;
    return TeamInvitation.fromJson(body['invitation'] as Map<String, dynamic>);
  }

  @override
  Future<void> cancelInvitation(
    String organisationId,
    String invitationId,
  ) async {
    await _api.delete(
      '${_org(organisationId)}/invitations/${Uri.encodeComponent(invitationId)}',
    );
  }

  @override
  Future<TeamMember> change(
    String organisationId,
    String userId,
    MemberChange change,
  ) async {
    final body = (await _api.patchJson(
      '${_org(organisationId)}/members/${Uri.encodeComponent(userId)}',
      change.toJson(),
    )).body;
    return TeamMember.fromJson(body['member'] as Map<String, dynamic>);
  }

  @override
  Future<void> remove(String organisationId, String userId) async {
    await _api.delete(
      '${_org(organisationId)}/members/${Uri.encodeComponent(userId)}',
    );
  }

  @override
  Future<void> assign(String requestId, String? userId) async {
    await _api.postJson(
      '/v1/agent/property-requests/${Uri.encodeComponent(requestId)}/assign',
      {'user_id': userId},
      headers: {'Idempotency-Key': _newKey()},
    );
  }

  @override
  Future<PublicInvitation> invitation(String token) async {
    final body = (await _api.get(
      '/v1/invitations/${Uri.encodeComponent(token)}',
    )).body;
    return PublicInvitation.fromJson(
      body['invitation'] as Map<String, dynamic>,
    );
  }

  /// Returns the organisation's name.
  @override
  Future<String> accept(String token) async {
    final body = (await _api.post(
      '/v1/invitations/${Uri.encodeComponent(token)}/accept',
    )).body;
    return (body['organisation'] as Map<String, dynamic>)['name'] as String;
  }
}

/// The token from a pasted invitation link (`.../invitations/{token}`), or
/// the text itself when it already is a token. Null when it is neither.
String? invitationTokenFrom(String text) {
  final trimmed = text.trim();
  final match = RegExp(r'invitations/([A-Za-z0-9_-]{20,128})')
      .firstMatch(trimmed);
  if (match != null) return match.group(1);
  return RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(trimmed) ? trimmed : null;
}
