import '../../core/api/api_client.dart';
import '../applications/applications_repository.dart'
    show ChosenFile, fileContentType;

/// An organisation's own books (a cashbook, API 0.34.0). Separate from its
/// RightProperty365 subscription invoices. Every figure is in one currency:
/// nothing here ever adds two currencies together.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.direction,
    required this.amount,
    required this.signedAmount,
    required this.currency,
    required this.effectiveDate,
    required this.status,
    required this.statusLabel,
    this.categoryLabel,
    this.methodLabel,
    this.description,
    this.reference,
    this.authorName,
    this.contactName,
    this.listingTitle,
    this.reason,
    this.isReversed = false,
    this.reversalOf,
    this.reversedBy,
    this.correctionOf,
    this.transferPair,
    this.cash = true,
    this.reconciledNote,
    this.reconciledBy,
    this.attachmentCount = 0,
    this.noteCount = 0,
    this.canReverse = false,
    this.canAttach = false,
    this.canNote = false,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final can = json['can'] as Map<String, dynamic>? ?? const {};
    final reconciliation = json['reconciliation'] as Map<String, dynamic>?;
    return LedgerEntry(
      id: json['id'] as String,
      type: json['type'] as String,
      typeLabel: json['type_label'] as String? ?? json['type'] as String,
      direction: json['direction'] as String? ?? 'IN',
      amount: json['amount'] as String,
      signedAmount:
          json['signed_amount'] as String? ?? json['amount'] as String,
      currency: json['currency'] as String,
      effectiveDate: json['effective_date'] as String,
      status: json['status'] as String? ?? 'USER_RECORDED_UNVERIFIED',
      statusLabel:
          json['status_label'] as String? ?? 'Recorded by you, not verified',
      categoryLabel: json['category_label'] as String?,
      methodLabel: json['method_label'] as String?,
      description: json['description'] as String?,
      reference: json['reference'] as String?,
      authorName: (json['author'] as Map<String, dynamic>?)?['name'] as String?,
      contactName:
          (json['contact'] as Map<String, dynamic>?)?['name'] as String?,
      listingTitle:
          (json['listing'] as Map<String, dynamic>?)?['title'] as String?,
      reason: json['reason'] as String?,
      isReversed: json['is_reversed'] == true,
      reversalOf: json['reversal_of'] as String?,
      reversedBy: json['reversed_by'] as String?,
      correctionOf: json['correction_of'] as String?,
      transferPair: json['transfer_pair'] as String?,
      cash: json['cash'] != false,
      reconciledNote: reconciliation?['note'] as String?,
      reconciledBy:
          (reconciliation?['by'] as Map<String, dynamic>?)?['name'] as String?,
      attachmentCount: json['attachment_count'] as int? ?? 0,
      noteCount: json['note_count'] as int? ?? 0,
      canReverse: can['reverse'] == true,
      canAttach: can['attach'] == true,
      canNote: can['note'] == true,
    );
  }

  final String id;
  final String type;
  final String typeLabel;
  final String direction;
  final String amount;

  /// `-amount` for money going out.
  final String signedAmount;
  final String currency;
  final String effectiveDate;

  /// USER_RECORDED_UNVERIFIED or RECONCILED (by the organisation itself,
  /// against its own statement: never a bank verification).
  final String status;
  final String statusLabel;
  final String? categoryLabel;
  final String? methodLabel;
  final String? description;
  final String? reference;
  final String? authorName;
  final String? contactName;
  final String? listingTitle;

  /// Why it was reversed or corrected (on the reversal or correction).
  final String? reason;
  final bool isReversed;
  final String? reversalOf;
  final String? reversedBy;
  final String? correctionOf;
  final String? transferPair;

  /// False for the memo types RECEIVABLE and PAYABLE, which never move a
  /// balance.
  final bool cash;
  final String? reconciledNote;
  final String? reconciledBy;
  final int attachmentCount;
  final int noteCount;
  final bool canReverse;
  final bool canAttach;
  final bool canNote;

  bool get isReversal => type == 'REVERSAL';
  bool get reconciled => status == 'RECONCILED';
}

/// The form's choices and the caller's rights (`GET /options`).
class LedgerOptions {
  const LedgerOptions({
    required this.types,
    required this.methods,
    required this.currencies,
    required this.categories,
    this.canWrite = false,
    this.canManage = false,
    this.canExport = false,
  });

  factory LedgerOptions.fromJson(Map<String, dynamic> json) {
    final p = json['permissions'] as Map<String, dynamic>? ?? const {};
    return LedgerOptions(
      types: [
        for (final t in (json['types'] as List?) ?? const [])
          (
            code: (t as Map<String, dynamic>)['code'] as String,
            label: t['label'] as String,
            direction: t['direction'] as String?,
            cash: t['cash'] != false,
            category: t['category'] as String?,
          ),
      ],
      methods: [
        for (final m in (json['methods'] as List?) ?? const [])
          (
            code: (m as Map<String, dynamic>)['code'] as String,
            label: m['label'] as String,
          ),
      ],
      currencies: {
        for (final c in (json['currencies'] as List?) ?? const [])
          (c as Map<String, dynamic>)['code'] as String:
              c['minor_unit'] as int? ?? 2,
      },
      categories: [
        for (final c in (json['categories'] as List?) ?? const [])
          (
            code: (c as Map<String, dynamic>)['code'] as String,
            label: c['label'] as String,
            kind: c['kind'] as String? ?? 'ANY',
          ),
      ],
      canWrite: p['write'] == true,
      canManage: p['manage'] == true,
      canExport: p['export'] == true,
    );
  }

  final List<
    ({
      String code,
      String label,
      String? direction,
      bool cash,
      String? category,
    })
  >
  types;
  final List<({String code, String label})> methods;

  /// ISO 4217 code to its minor-unit decimals.
  final Map<String, int> currencies;
  final List<({String code, String label, String kind})> categories;
  final bool canWrite;
  final bool canManage;
  final bool canExport;

  /// Why [amount] is not a valid positive amount in [currency], or null.
  String? amountProblem(String amount, String currency) {
    final a = amount.trim();
    if (!RegExp(r'^\d{1,16}(\.\d+)?$').hasMatch(a)) {
      return 'Enter an amount, for example 700.00.';
    }
    if (double.parse(a) <= 0) return 'The amount must be more than zero.';
    final decimals = a.contains('.') ? a.split('.').last.length : 0;
    final allowed = currencies[currency] ?? 2;
    if (decimals > allowed) {
      return allowed == 0
          ? '$currency has no decimals.'
          : 'At most $allowed decimals for $currency.';
    }
    return null;
  }
}

/// One currency's cashbook for a period: opening + in - out = closing.
class CashbookCurrency {
  const CashbookCurrency({
    required this.currency,
    required this.opening,
    required this.moneyIn,
    required this.moneyOut,
    required this.closing,
    required this.count,
    required this.runningBalance,
  });

  final String currency;
  final String opening;
  final String moneyIn;
  final String moneyOut;
  final String closing;
  final int count;

  /// Entry id to the balance after it, in this currency.
  final Map<String, String> runningBalance;
}

class LedgerDraft {
  const LedgerDraft({
    required this.type,
    required this.amount,
    required this.currency,
    required this.effectiveDate,
    this.direction,
    this.category,
    this.method,
    this.transferToMethod,
    this.description,
    this.reference,
  });

  final String type;
  final String? direction;
  final String? category;
  final String? method;
  final String? transferToMethod;
  final String amount;
  final String currency;
  final String effectiveDate;
  final String? description;
  final String? reference;

  Map<String, dynamic> toJson() => {
    'type': type,
    'direction': ?direction,
    'category': ?category,
    'method': ?method,
    if (type == 'TRANSFER' && transferToMethod != null)
      'transfer_to': {'method': transferToMethod, 'branch': null},
    'amount': amount.trim(),
    'currency': currency,
    'effective_date': effectiveDate,
    if (description != null && description!.trim().isNotEmpty)
      'description': description!.trim(),
    if (reference != null && reference!.trim().isNotEmpty)
      'reference': reference!.trim(),
  };
}

typedef LedgerEntryDetail = ({
  LedgerEntry entry,
  List<({String text, String author, DateTime at})> notes,
  List<({String id, String fileName})> attachments,
  List<LedgerEntry> related,
});

/// The books of an organisation, or an approved direct owner's own (their
/// user ID), at `/v1/agent/organisations/{book}/ledger`. Another book is
/// `404 BOOK_NOT_FOUND`.
class LedgerRepository {
  LedgerRepository(this._api);

  final ApiClient _api;

  String _base(String book) =>
      '/v1/agent/organisations/${Uri.encodeComponent(book)}/ledger';

  Future<LedgerOptions> options(String book) async =>
      LedgerOptions.fromJson((await _api.get('${_base(book)}/options')).body);

  Future<({List<LedgerEntry> items, int total})> entries(
    String book, {
    String? currency,
    String? type,
    String? from,
    String? to,
    int page = 1,
  }) async {
    final body = (await _api.get(
      Uri(
        path: '${_base(book)}/entries',
        queryParameters: {
          'currency': ?currency,
          'type': ?type,
          'from': ?from,
          'to': ?to,
          'page': '$page',
          'page_size': '50',
        },
      ).toString(),
    )).body;
    return (
      items: [
        for (final e in (body['items'] as List?) ?? const [])
          LedgerEntry.fromJson(e as Map<String, dynamic>),
      ],
      total: body['total'] as int? ?? 0,
    );
  }

  /// The cashbook per currency for the period (never combined).
  Future<List<CashbookCurrency>> cashbook(
    String book, {
    required String from,
    required String to,
    String? currency,
  }) async {
    final body = (await _api.get(
      Uri(
        path: '${_base(book)}/reports/cashbook',
        queryParameters: {'from': from, 'to': to, 'currency': ?currency},
      ).toString(),
    )).body;
    return [
      for (final c in (body['currencies'] as List?) ?? const [])
        CashbookCurrency(
          currency: (c as Map<String, dynamic>)['currency'] as String,
          opening: c['opening_balance'] as String,
          moneyIn: c['in'] as String,
          moneyOut: c['out'] as String,
          closing: c['closing_balance'] as String,
          count: c['entry_count'] as int? ?? 0,
          runningBalance: {
            for (final line in (c['entries'] as List?) ?? const [])
              ((line as Map<String, dynamic>)['entry']
                          as Map<String, dynamic>)['id']
                      as String:
                  line['running_balance'] as String,
          },
        ),
    ];
  }

  Future<LedgerEntryDetail> entry(String book, String id) async {
    final body = (await _api.get(
      '${_base(book)}/entries/${Uri.encodeComponent(id)}',
    )).body;
    return (
      entry: LedgerEntry.fromJson(body['entry'] as Map<String, dynamic>),
      notes: [
        for (final n in (body['notes'] as List?) ?? const [])
          (
            text: (n as Map<String, dynamic>)['text'] as String,
            author:
                (n['author'] as Map<String, dynamic>?)?['name'] as String? ??
                '',
            at: DateTime.parse(n['created_at'] as String),
          ),
      ],
      attachments: [
        for (final a in (body['attachments'] as List?) ?? const [])
          (
            id: (a as Map<String, dynamic>)['id'] as String,
            fileName: a['file_name'] as String? ?? 'file',
          ),
      ],
      related: [
        for (final r in (body['related'] as List?) ?? const [])
          LedgerEntry.fromJson(r as Map<String, dynamic>),
      ],
    );
  }

  /// Posts an entry (a transfer posts its two legs). Throws [ApiFailure].
  Future<LedgerEntry> create(String book, LedgerDraft draft) async {
    try {
      return LedgerEntry.fromJson(
        (await _api.postJson(
              '${_base(book)}/entries',
              draft.toJson(),
            )).body['entry']
            as Map<String, dynamic>,
      );
    } on ApiFailure catch (failure) {
      throw failure.code == 'LEDGER_OPENING_BALANCE_EXISTS'
          ? failure.withMessage(
              'There is already an opening balance for this currency and method. Reverse it first to change it.',
            )
          : failure;
    }
  }

  /// Reverses an entry with a reason; both stay visible. Throws
  /// [ApiFailure].
  Future<LedgerEntry> reverse(String book, String id, String reason) async {
    try {
      return LedgerEntry.fromJson(
        (await _api.postJson(
              '${_base(book)}/entries/${Uri.encodeComponent(id)}/reverse',
              {'reason': reason.trim()},
            )).body['entry']
            as Map<String, dynamic>,
      );
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'LEDGER_ENTRY_ALREADY_REVERSED' => failure.withMessage(
          'This entry has already been reversed.',
        ),
        'LEDGER_ENTRY_NOT_REVERSIBLE' => failure.withMessage(
          'A reversal cannot itself be reversed.',
        ),
        _ => failure,
      };
    }
  }

  Future<void> addNote(String book, String id, String text) => _api.postJson(
    '${_base(book)}/entries/${Uri.encodeComponent(id)}/notes',
    {'text': text.trim()},
  );

  /// A photo or PDF of the receipt (pdf, jpg, png, webp; 10 MB).
  Future<void> attach(String book, String id, ChosenFile file) async {
    try {
      await _api.postFile(
        '${_base(book)}/entries/${Uri.encodeComponent(id)}/attachments',
        field: 'file',
        bytes: file.bytes,
        fileName: file.name,
        contentType: fileContentType(file.name),
      );
    } on ApiFailure catch (failure) {
      throw switch (failure.code) {
        'UNSUPPORTED_FILE_TYPE' => failure.withMessage(
          'Use a photo (JPG, PNG, WebP) or a PDF.',
        ),
        'FILE_TOO_LARGE' => failure.withMessage('That file is over 10 MB.'),
        _ => failure,
      };
    }
  }
}
