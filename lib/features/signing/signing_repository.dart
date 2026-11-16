import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';

DateTime? _at(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// The typed signature styles and the fonts that draw them, bundled from the
/// web repository (SIL Open Font License 1.1). The API draws the same fonts.
const signatureFontFamilies = {
  'FLOWING': 'GreatVibes',
  'BOLD': 'KaushanScript',
  'CLASSIC': 'Allura',
};

class SignatureFont {
  const SignatureFont(this.key, this.label);
  final String key;
  final String label;

  static List<SignatureFont> listFrom(Object? json) => [
    for (final f in (json as List?) ?? const [])
      SignatureFont(f['key'] as String, f['label'] as String),
  ];

  /// When the API does not list them.
  static const fallback = [
    SignatureFont('FLOWING', 'Flowing (Great Vibes)'),
    SignatureFont('BOLD', 'Bold (Kaushan Script)'),
    SignatureFont('CLASSIC', 'Classic (Allura)'),
  ];
}

enum SignatureKind { typed, drawn, uploaded }

/// A signature or initials the signer adopted: typed in a font, drawn, or an
/// uploaded picture (PNG bytes, or JPEG for an upload).
@immutable
class AdoptedSignature {
  const AdoptedSignature.typed(String this.text, {this.font = 'FLOWING'})
    : kind = SignatureKind.typed,
      image = null;
  const AdoptedSignature.image(this.kind, Uint8List this.image)
    : text = null,
      font = null;

  factory AdoptedSignature.fromSaved(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    if (kind == 'TYPED') {
      return AdoptedSignature.typed(
        json['text'] as String? ?? '',
        font: json['font'] as String? ?? 'FLOWING',
      );
    }
    final data = (json['image_base64'] as String? ?? '').replaceFirst(
      RegExp(r'^data:image/[a-z]+;base64,'),
      '',
    );
    return AdoptedSignature.image(
      kind == 'UPLOADED' ? SignatureKind.uploaded : SignatureKind.drawn,
      base64Decode(data),
    );
  }

  final SignatureKind kind;
  final String? text;
  final String? font;
  final Uint8List? image;

  Map<String, dynamic> toJson() => switch (kind) {
    SignatureKind.typed => {'kind': 'TYPED', 'text': text, 'font': font},
    SignatureKind.drawn => {
      'kind': 'DRAWN',
      'image_base64': base64Encode(image!),
    },
    SignatureKind.uploaded => {
      'kind': 'UPLOADED',
      'image_base64': base64Encode(image!),
    },
  };
}

/// The signed-in person's saved signature and initials.
class SavedSignature {
  const SavedSignature({this.signature, this.initials, this.fonts = const []});

  factory SavedSignature.fromJson(Map<String, dynamic> json) => SavedSignature(
    signature: switch (json['signature']) {
      final Map<String, dynamic> s => AdoptedSignature.fromSaved(s),
      _ => null,
    },
    initials: switch (json['initials']) {
      final Map<String, dynamic> s => AdoptedSignature.fromSaved(s),
      _ => null,
    },
    fonts: SignatureFont.listFrom(json['signature_fonts']),
  );

  final AdoptedSignature? signature;
  final AdoptedSignature? initials;
  final List<SignatureFont> fonts;
}

/// A document the signed-in person is a recipient of.
class SigningRequest {
  const SigningRequest({
    required this.recipientId,
    required this.reference,
    required this.name,
    required this.agreementStatus,
    required this.role,
    required this.recipientStatus,
    required this.senderName,
    required this.expiresAt,
    this.sentAt,
    this.completedAt,
    this.canSign = false,
  });

  factory SigningRequest.fromJson(Map<String, dynamic> json) => SigningRequest(
    recipientId: json['recipient_id'] as String,
    reference: json['reference'] as String,
    name: json['name'] as String,
    agreementStatus: json['agreement_status'] as String,
    role: json['role'] as String,
    recipientStatus: json['recipient_status'] as String,
    senderName: json['sender_name'] as String? ?? '',
    sentAt: _at(json['sent_at']),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    completedAt: _at(json['completed_at']),
    canSign: json['can_sign'] == true,
  );

  final String recipientId;
  final String reference;
  final String name;
  final String agreementStatus;
  final String role;
  final String recipientStatus;
  final String senderName;
  final DateTime? sentAt;
  final DateTime expiresAt;
  final DateTime? completedAt;
  final bool canSign;
}

class SigningField {
  const SigningField({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.page,
    required this.rect,
    this.required = true,
    this.label,
    this.value,
  });

  factory SigningField.fromJson(Map<String, dynamic> json) => SigningField(
    id: json['id'] as String,
    recipientId: json['recipient_id'] as String,
    type: json['type'] as String,
    page: json['page'] as int,
    rect: Rect.fromLTWH(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
      (json['w'] as num).toDouble(),
      (json['h'] as num).toDouble(),
    ),
    required: json['required'] != false,
    label: json['label'] as String?,
    value: json['value'] as String?,
  );

  final String id;
  final String recipientId;

  /// SIGNATURE, INITIALS, DATE_SIGNED, NAME, TEXT or CHECKBOX.
  final String type;
  final int page;

  /// In PDF points from the page's top left.
  final Rect rect;
  final bool required;
  final String? label;
  final String? value;

  /// NAME and DATE_SIGNED are filled in by the API.
  bool get selfFilled => type != 'NAME' && type != 'DATE_SIGNED';
}

class OtherRecipient {
  const OtherRecipient(this.name, this.role, this.order, this.status);
  final String name;
  final String role;
  final int order;
  final String status;
}

/// What a signing link shows (`SigningView`).
class SigningView {
  const SigningView({
    required this.reference,
    required this.name,
    required this.status,
    required this.senderName,
    required this.expiresAt,
    required this.recipientId,
    required this.recipientName,
    required this.recipientRole,
    required this.recipientStatus,
    required this.emailMasked,
    required this.fields,
    this.message,
    this.organisationName,
    this.finalSha256,
    this.completedAt,
    this.recipientLabel,
    this.recipientCompletedAt,
    this.others = const [],
    this.canAct = false,
    this.readOnly = true,
    this.codeLength = 6,
    this.consentText = '',
    this.statement = '',
    this.fonts = const [],
    this.pageSizes = const [],
  });

  factory SigningView.fromJson(Map<String, dynamic> json) {
    final agreement = json['agreement'] as Map<String, dynamic>;
    final recipient = json['recipient'] as Map<String, dynamic>;
    return SigningView(
      reference: agreement['reference'] as String,
      name: agreement['name'] as String,
      message: agreement['message'] as String?,
      status: agreement['status'] as String,
      senderName: agreement['sender_name'] as String? ?? '',
      organisationName: agreement['organisation_name'] as String?,
      expiresAt: DateTime.parse(agreement['expires_at'] as String),
      finalSha256: agreement['final_sha256'] as String?,
      completedAt: _at(agreement['completed_at']),
      pageSizes: [
        for (final p in (agreement['pages'] as List?) ?? const [])
          Size((p['width'] as num).toDouble(), (p['height'] as num).toDouble()),
      ],
      recipientId: recipient['id'] as String,
      recipientName: recipient['name'] as String,
      recipientRole: recipient['role'] as String,
      recipientLabel: recipient['label'] as String?,
      recipientStatus: recipient['status'] as String,
      emailMasked: recipient['email_masked'] as String? ?? '',
      recipientCompletedAt: _at(recipient['completed_at']),
      fields: [
        for (final f in (json['fields'] as List?) ?? const [])
          SigningField.fromJson(f as Map<String, dynamic>),
      ],
      others: [
        for (final o in (json['other_recipients'] as List?) ?? const [])
          OtherRecipient(
            o['name'] as String,
            o['role'] as String,
            o['order'] as int? ?? 1,
            o['status'] as String,
          ),
      ],
      canAct: json['can_act'] == true,
      readOnly: json['read_only'] != false,
      codeLength: json['code_length'] as int? ?? 6,
      consentText: json['consent_text'] as String? ?? '',
      statement: json['statement'] as String? ?? '',
      fonts: SignatureFont.listFrom(json['signature_fonts']),
    );
  }

  final String reference;
  final String name;
  final String? message;

  /// OUT_FOR_SIGNATURE, COMPLETED, DECLINED, CANCELLED or EXPIRED.
  final String status;
  final String senderName;
  final String? organisationName;
  final DateTime expiresAt;
  final String? finalSha256;
  final DateTime? completedAt;
  final List<Size> pageSizes;
  final String recipientId;
  final String recipientName;

  /// SIGNER, APPROVER or CC.
  final String recipientRole;
  final String? recipientLabel;

  /// WAITING, ACTIVE, SIGNED, APPROVED, DECLINED or CC.
  final String recipientStatus;
  final String emailMasked;
  final DateTime? recipientCompletedAt;
  final List<SigningField> fields;
  final List<OtherRecipient> others;
  final bool canAct;
  final bool readOnly;
  final int codeLength;
  final String consentText;
  final String statement;
  final List<SignatureFont> fonts;

  bool get approver => recipientRole == 'APPROVER';
  bool get signingNow => canAct && !readOnly;

  /// This person's fields, in reading order: page, then top, then left.
  List<SigningField> get mine =>
      [
        for (final f in fields)
          if (f.recipientId == recipientId) f,
      ]..sort(
        (a, b) => a.page != b.page
            ? a.page - b.page
            : a.rect.top != b.rect.top
            ? a.rect.top.compareTo(b.rect.top)
            : a.rect.left.compareTo(b.rect.left),
      );
}

/// What a signer sends with "Click to sign".
class SigningSubmission {
  const SigningSubmission({
    required this.code,
    this.fieldValues = const {},
    this.signature,
    this.initials,
  });

  final String code;
  final Map<String, String> fieldValues;
  final AdoptedSignature? signature;
  final AdoptedSignature? initials;

  Map<String, dynamic> toJson() => {
    'code': code,
    'consent': true,
    'field_values': [
      for (final e in fieldValues.entries)
        {'field_id': e.key, 'value': e.value},
    ],
    if (signature != null) 'signature': signature!.toJson(),
    if (initials != null) 'initials': initials!.toJson(),
  };
}

String agreementStatusLabel(String status) => switch (status) {
  'DRAFT' => 'Draft',
  'OUT_FOR_SIGNATURE' => 'Out for signature',
  'COMPLETED' => 'Completed',
  'DECLINED' => 'Declined',
  'CANCELLED' => 'Cancelled',
  'EXPIRED' => 'Expired',
  _ => status,
};

String recipientStatusLabel(String status) => switch (status) {
  'WAITING' => 'Waiting for their turn',
  'ACTIVE' => 'Needs to act',
  'SIGNED' => 'Signed',
  'APPROVED' => 'Approved',
  'DECLINED' => 'Declined',
  'CC' => 'Gets a copy',
  _ => status,
};

String recipientRoleLabel(String role) => switch (role) {
  'SIGNER' => 'Signer',
  'APPROVER' => 'Approver',
  'CC' => 'Copy',
  _ => role,
};

/// Plain words for signing failures; other codes keep the API's message.
String signingMessage(ApiFailure failure) => switch (failure.code) {
  'AGREEMENT_NOT_FOUND' =>
    'We could not find that document, or you no longer have access to it.',
  'NOT_OPEN_FOR_SIGNING' =>
    "It is not your turn yet, or the document is no longer out for signature.",
  'ALREADY_SIGNED' => 'This has already been signed or approved.',
  'SIGNING_LINK_NOT_FOUND' => 'We could not find this signing link. Check that you opened the whole link from the email.',
  'SIGNING_LINK_EXPIRED' => 'This signing link has expired.',
  'SIGNING_LINK_NO_LONGER_VALID' => 'This link no longer works: a newer link was sent, the address was changed, or the document was cancelled.',
  'CODE_EXPIRED' => 'That code has expired or was used up. Send a new code.',
  'RATE_LIMITED' =>
    'That was a lot of attempts at once. Please wait a minute and try again.',
  _ => failure.message,
};

abstract interface class SigningRepository {
  Future<List<SigningRequest>> requests();

  /// A signing token for a document the signed-in person is a recipient of.
  Future<String> link(String recipientId);
  Future<SigningView> view(String token);
  Future<Uint8List> pdf(String token);

  /// Emails the code; returns where it went and how many digits it has.
  Future<({String sentTo, int codeLength})> sendCode(String token);
  Future<void> submit(String token, SigningSubmission submission);
  Future<SigningView> decline(String token, String reason);
  Future<SavedSignature> saved();
  Future<SavedSignature> save({
    AdoptedSignature? signature,
    AdoptedSignature? initials,
  });
}

class ApiSigningRepository implements SigningRepository {
  ApiSigningRepository(this._api);

  final ApiClient _api;

  String _sign(String token) => '/v1/signing/${Uri.encodeComponent(token)}';

  @override
  Future<List<SigningRequest>> requests() async {
    final body = (await _api.get('/v1/me/signing-requests')).body;
    return [
      for (final item in (body['items'] as List?) ?? const [])
        SigningRequest.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<String> link(String recipientId) async =>
      (await _api.post(
            '/v1/me/signing-requests/${Uri.encodeComponent(recipientId)}/link',
          )).body['token']
          as String;

  @override
  Future<SigningView> view(String token) async => SigningView.fromJson(
    (await _api.get(_sign(token))).body['signing'] as Map<String, dynamic>,
  );

  @override
  Future<Uint8List> pdf(String token) => _api.getBytes('${_sign(token)}/pdf');

  @override
  Future<({String sentTo, int codeLength})> sendCode(String token) async {
    final body = (await _api.post('${_sign(token)}/code')).body;
    return (
      sentTo: body['sent_to'] as String,
      codeLength: body['code_length'] as int? ?? 6,
    );
  }

  @override
  Future<void> submit(String token, SigningSubmission submission) async {
    await _api.postJson('${_sign(token)}/submit', submission.toJson());
  }

  @override
  Future<SigningView> decline(String token, String reason) async =>
      SigningView.fromJson(
        (await _api.postJson('${_sign(token)}/decline', {
              'reason': reason,
            })).body['signing']
            as Map<String, dynamic>,
      );

  @override
  Future<SavedSignature> saved() async =>
      SavedSignature.fromJson((await _api.get('/v1/me/signature')).body);

  @override
  Future<SavedSignature> save({
    AdoptedSignature? signature,
    AdoptedSignature? initials,
  }) async => SavedSignature.fromJson(
    (await _api.putJson('/v1/me/signature', {
      if (signature != null) 'signature': signature.toJson(),
      if (initials != null) 'initials': initials.toJson(),
    })).body,
  );
}
