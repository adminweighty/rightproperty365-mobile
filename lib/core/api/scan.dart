/// Malware scanning of uploaded documents (API 0.41.0). Off unless the
/// server turns it on: then a document is checked after upload, and its
/// `scan_status` says how it went. Absent (scanning off) and
/// `LEGACY_UNSCANNED` behave exactly as before.
enum ScanStatus {
  none,
  pending,
  clean,
  infected,
  legacy;

  static ScanStatus parse(Object? value) => switch (value) {
    'PENDING' => pending,
    'CLEAN' => clean,
    'INFECTED' => infected,
    'LEGACY_UNSCANNED' => legacy,
    _ => none,
  };

  bool get isPending => this == pending;
  bool get isInfected => this == infected;

  /// What to show beside the file, or null when nothing changes.
  String? get notice => switch (this) {
    pending => 'Being checked for viruses…',
    infected =>
      'Removed: it failed our virus check. Please upload a clean copy.',
    _ => null,
  };
}

/// Plain words for the scan failures of an upload (images are checked
/// before anything is stored).
const scanFailureMessages = {
  // 422: the file itself.
  'FILE_INFECTED':
      'This file failed our virus check and was not saved. Please choose a '
      'different file.',
  // 503: the checker, not the file.
  'SCANNER_UNAVAILABLE':
      'We cannot check files for viruses right now, so it was not saved. '
      'This is not a problem with your file: please try again in a few '
      'minutes.',
  'FILE_TOO_LARGE_TO_SCAN': 'This file is too large to be checked for viruses.',
};
