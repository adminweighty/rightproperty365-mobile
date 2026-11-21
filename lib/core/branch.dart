/// Organisation branches (API 0.57.0). A member pinned to a branch sees the
/// organisation's items with no branch or their own branch; lists leave the
/// others out, and opening one of them is `403 BRANCH_FORBIDDEN`. Branches
/// are administered on the website only.
library;

import 'api/api_client.dart';

/// The branch's name from `branch: {id, name} | null`; a personal book's
/// ledger entry may still carry free text.
String? branchName(Object? json) => switch (json) {
  {'name': final String name} when name.trim().isNotEmpty => name.trim(),
  final String name when name.trim().isNotEmpty => name.trim(),
  _ => null,
};

/// The item belongs to another branch of the organisation.
bool isBranchForbidden(Object? error) =>
    error is ApiFailure && error.code == branchForbiddenCode;
