/// Reporting a public listing to the moderators (API 0.54.0). Anyone may
/// report, signed in or not; moderation is on the website.
library;

import '../../../core/api/api_client.dart';

enum ReportReason {
  fraud('FRAUD', 'Fraud or a scam'),
  misleading('MISLEADING', 'Misleading details or photos'),
  alreadyGone('ALREADY_SOLD_OR_LET', 'Already sold or let'),
  wrongPrice('WRONG_PRICE', 'Wrong price'),
  duplicate('DUPLICATE', 'Listed more than once'),
  offensive('OFFENSIVE', 'Offensive content'),
  other('OTHER', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  /// OTHER needs a note saying what is wrong.
  bool get needsNote => this == other;
}

/// The longest note the API accepts.
const reportNoteMax = 1000;

class ListingReportsRepository {
  ListingReportsRepository(this._api);

  final ApiClient _api;

  /// Sends the report (`202`). A repeat by the same signed-in person gets
  /// the same answer.
  Future<void> report(String slug, ReportReason reason, {String? note}) async {
    final text = (note ?? '').trim();
    try {
      await _api.postJson('/v1/listings/${Uri.encodeComponent(slug)}/reports', {
        'reason': reason.wire,
        if (text.isNotEmpty) 'note': text,
      });
    } on ApiFailure catch (failure) {
      throw failure.status == 404
          ? failure.withMessage(
              'This listing is no longer public, so it cannot be reported.',
            )
          : failure;
    }
  }
}
