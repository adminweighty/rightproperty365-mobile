/// A copy of the person's own data (API 0.55.0): asked for, built by the
/// RightProperty365 worker, kept 7 days, downloaded through the API only.
library;

import 'dart:typed_data';

import '../../../core/api/api_client.dart';

enum ExportStatus {
  requested('REQUESTED'),
  building('BUILDING'),
  ready('READY'),
  expired('EXPIRED'),
  failed('FAILED');

  const ExportStatus(this.wire);
  final String wire;

  static ExportStatus from(Object? wire) => values.firstWhere(
    (s) => s.wire == wire,
    orElse: () => ExportStatus.requested,
  );

  /// Still being prepared.
  bool get pending => this == requested || this == building;
}

class DataExport {
  const DataExport({
    required this.id,
    required this.status,
    this.requestedAt,
    this.readyAt,
    this.expiresAt,
    this.sizeBytes,
    this.downloads = 0,
  });

  factory DataExport.fromJson(Map<String, dynamic> json) => DataExport(
    id: json['id'] as String,
    status: ExportStatus.from(json['status']),
    requestedAt: DateTime.tryParse(json['requested_at'] as String? ?? ''),
    readyAt: DateTime.tryParse(json['ready_at'] as String? ?? ''),
    expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    sizeBytes: (json['size_bytes'] as num?)?.toInt(),
    downloads: (json['downloads'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final ExportStatus status;
  final DateTime? requestedAt;
  final DateTime? readyAt;
  final DateTime? expiresAt;
  final int? sizeBytes;
  final int downloads;

  /// "2.4 MB", "830 KB".
  String? get sizeLabel {
    final b = sizeBytes;
    if (b == null) return null;
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / 1024).ceil()} KB';
  }
}

class DataExportRepository {
  DataExportRepository(this._api);

  final ApiClient _api;

  static const _base = '/v1/me/data-export';

  static DataExport? _export(ApiResponse r) => switch (r.body['export']) {
    final Map<String, dynamic> e => DataExport.fromJson(e),
    _ => null,
  };

  /// The latest request, or null when none was made.
  Future<DataExport?> current() async => _export(await _api.get(_base));

  Future<DataExport?> request() async {
    try {
      return _export(await _api.postJson(_base, const {}));
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'EXPORT_RECENT' => failure.withMessage(
          'You asked for a copy in the last 24 hours. Use that one, or ask '
          'again tomorrow.',
        ),
        'PLATFORM_ACCOUNT' => failure.withMessage(
          'Administrator accounts cannot export their data here. Ask '
          'RightProperty365 support.',
        ),
        _ => failure,
      };
    }
  }

  /// The ZIP, through the API with the sign-in token (never a link).
  Future<Uint8List> download() async {
    try {
      return await _api.getBytes('$_base/download');
    } on ApiFailure catch (failure) {
      throw failure.code == 'EXPORT_NOT_READY'
          ? failure.withMessage(
              'The copy is not ready, or it has expired. Refresh to see where '
              'it stands.',
            )
          : failure;
    }
  }
}
