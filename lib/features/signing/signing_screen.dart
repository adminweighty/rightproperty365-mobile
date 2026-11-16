import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/badge.dart';
import '../../core/widgets/brand.dart';
import 'adopt_signature.dart';
import 'pdf_pages.dart';
import 'signing_repository.dart';

final _when = DateFormat('d MMM y, HH:mm');
String _today() => DateFormat('d MMM y').format(DateTime.now());

/// A token from the API: 43 URL-safe characters, with a little room.
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{20,128}$');

/// The document behind a signing link, signed (or approved) the way Adobe
/// Acrobat Sign does it: Start, Next through each field, adopt a signature,
/// confirm the emailed code, agree, then Click to sign. The path matches the
/// emailed link (`/sign/{token}`).
class SigningScreen extends StatefulWidget {
  const SigningScreen({super.key, required this.token});

  final String token;

  @override
  State<SigningScreen> createState() => _SigningScreenState();
}

class _SigningScreenState extends State<SigningScreen> {
  Future<SigningView>? _view;
  Future<OpenPdf>? _pdf;
  bool _justDone = false;

  bool get _validToken => _tokenPattern.hasMatch(widget.token);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_view == null && _validToken) _load();
  }

  void _load({bool pdfToo = true}) {
    final services = AppScope.of(context);
    final view = services.signing.view(widget.token);
    setState(() {
      _view = view;
      if (pdfToo) {
        _pdf?.then((pdf) => pdf.close(), onError: (_) {});
        _pdf = view.then(
          (_) async =>
              services.pdf.open(await services.signing.pdf(widget.token)),
        );
        // A failed view is shown from _view; the PDF waits on it.
        _pdf!.ignore();
      }
    });
  }

  @override
  void dispose() {
    _pdf?.then((pdf) => pdf.close(), onError: (_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_validToken) {
      return const _Ending(
        title: 'We could not find this document',
        body:
            'Check that you opened the whole link from the email. If it still does not '
            'work, ask the sender for a new link.',
      );
    }
    return FutureBuilder<SigningView>(
      future: _view,
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          return _LinkProblem(
            failure: error is ApiFailure ? error : const ApiFailure.network(),
            onRetry: _load,
          );
        }
        final view = snapshot.data;
        if (view == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Document')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (view.signingNow) {
          return _Guided(
            key: ValueKey(view.recipientStatus),
            token: widget.token,
            view: view,
            pdf: _pdf!,
            onDone: () {
              setState(() => _justDone = true);
              _load();
            },
            onDeclined: () => _load(),
          );
        }
        return _Finished(
          token: widget.token,
          view: view,
          pdf: _pdf!,
          justDone: _justDone,
        );
      },
    );
  }
}

class _Ending extends StatelessWidget {
  const _Ending({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Document')),
    body: MessageView(
      icon: Icons.mark_email_unread_outlined,
      title: title,
      body: body,
    ),
  );
}

class _LinkProblem extends StatelessWidget {
  const _LinkProblem({required this.failure, required this.onRetry});

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failure.code == 'SIGNING_LINK_EXPIRED') {
      return const _Ending(
        title: 'This signing link has expired',
        body:
            'The document can no longer be signed with it. Ask the sender to send it '
            'again if it still needs your signature.',
      );
    }
    if (failure.code == 'SIGNING_LINK_NO_LONGER_VALID') {
      return const _Ending(
        title: 'This link no longer works',
        body:
            'A newer link may have been emailed to you (use the newest email), your address '
            'may have been changed, or the sender cancelled the document. Signed in with that '
            'address? Your documents are also under Documents to sign.',
      );
    }
    if (failure.status == 404) {
      return const _Ending(
        title: 'We could not find this document',
        body:
            'Check that you opened the whole link from the email. If it still does not '
            'work, ask the sender for a new link.',
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Document')),
      body: MessageView(
        icon: Icons.cloud_off_outlined,
        title: 'We could not load the document',
        body: signingMessage(failure),
        actionLabel: 'Try again',
        onAction: onRetry,
      ),
    );
  }
}

/// Who sent it and its reference, under an ending.
class _Summary extends StatelessWidget {
  const _Summary(this.view);

  final SigningView view;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: text.bodyMedium)),
          Expanded(child: SelectableText(value, style: text.bodyLarge)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Document', view.name),
        row('Reference', view.reference),
        row('From', [view.senderName, ?view.organisationName].join(', ')),
      ],
    );
  }
}

/// Every state in which this person has nothing (more) to do, with the
/// document under it.
class _Finished extends StatelessWidget {
  const _Finished({
    required this.token,
    required this.view,
    required this.pdf,
    required this.justDone,
  });

  final String token;
  final SigningView view;
  final Future<OpenPdf> pdf;
  final bool justDone;

  ({String title, String body, bool good}) _state() {
    final approver = view.approver;
    final done =
        view.recipientStatus == 'SIGNED' || view.recipientStatus == 'APPROVED';
    if (view.status == 'COMPLETED') {
      return (
        title: justDone
            ? 'Done. Everyone has signed'
            : 'This document is complete',
        body:
            'Everyone has finished'
            '${view.completedAt == null ? '' : ' (${_when.format(view.completedAt!.toLocal())})'}. '
            'The final PDF has every signature and an audit report on its last page. '
            'We have emailed a copy to everyone.',
        good: true,
      );
    }
    if (done) {
      final at = view.recipientCompletedAt;
      return (
        title: justDone
            ? (approver ? 'You approved it' : 'You signed it')
            : (approver
                  ? 'You have approved this document'
                  : 'You have signed this document'),
        body:
            '${approver ? 'You approved' : 'You signed'}'
            '${at == null ? '' : ' on ${_when.format(at.toLocal())}'}. We will email '
            'everyone the completed copy once the others have finished.',
        good: true,
      );
    }
    if (view.recipientStatus == 'DECLINED' || view.status == 'DECLINED') {
      return view.recipientStatus == 'DECLINED'
          ? (
              title: 'You declined this document',
              body:
                  '${view.senderName} has been told. Nothing else is needed from you.',
              good: false,
            )
          : (
              title: 'This document was declined',
              body: 'Someone declined to sign it, so it will not be completed. The sender has been told.',
              good: false,
            );
    }
    if (view.status == 'CANCELLED') {
      return (
        title: 'The sender cancelled this document',
        body: 'It can no longer be signed. Nothing else is needed from you.',
        good: false,
      );
    }
    if (view.status == 'EXPIRED') {
      return (
        title: 'This document has expired',
        body:
            'It could be signed until ${_when.format(view.expiresAt.toLocal())}. Ask the '
            'sender to send it again if it still needs your signature.',
        good: false,
      );
    }
    // Out for signature, but not this person's turn yet.
    final first = [
      for (final o in view.others)
        if (o.status == 'ACTIVE' && o.role != 'CC') o,
    ];
    final names = [for (final o in first) o.name];
    final who = switch (names.length) {
      0 => 'Someone else',
      1 => names.first,
      _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
    };
    final verb = first.isNotEmpty && first.every((o) => o.role == 'APPROVER')
        ? 'approve'
        : 'sign';
    return (
      title: 'It is not your turn yet',
      body:
          '$who must $verb first. We will email you when it is your turn. You can read '
          'the document now.',
      good: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final state = _state();
    return Scaffold(
      appBar: AppBar(title: Text(view.name)),
      backgroundColor: c.sunken,
      body: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Semantics(
            liveRegion: true,
            child: BrandCard(
              emphasised: true,
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      state.good
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 36,
                      color: state.good ? c.success : c.muted,
                    ),
                    const SizedBox(height: Space.x2),
                    Semantics(
                      header: true,
                      child: Text(state.title, style: text.headlineSmall),
                    ),
                    const SizedBox(height: Space.x2),
                    Text(state.body, style: text.bodyLarge),
                    if (view.status == 'COMPLETED' &&
                        view.finalSha256 != null) ...[
                      const SizedBox(height: Space.x2),
                      SelectableText(
                        'SHA-256 of the final PDF: ${view.finalSha256}',
                        style: text.bodySmall,
                      ),
                    ],
                    const SizedBox(height: Space.x3),
                    _Summary(view),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.x5),
          const SectionHeading('The document'),
          const SizedBox(height: Space.x3),
          _DocumentPages(pdf: pdf, view: view),
        ],
      ),
    );
  }
}

/// The pages, with every field's value so far drawn over them (read-only).
class _DocumentPages extends StatelessWidget {
  const _DocumentPages({required this.pdf, required this.view, this.overlay});

  final Future<OpenPdf> pdf;
  final SigningView view;
  final PageOverlay? overlay;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OpenPdf>(
      future: pdf,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'We could not load the PDF. Check your connection and open it again.',
            style: Theme.of(context).textTheme.bodyLarge,
          );
        }
        final document = snapshot.data;
        if (document == null) {
          return const Padding(
            padding: EdgeInsets.all(Space.x8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return PdfPageColumn(
          pdf: document,
          label: view.name,
          overlay:
              overlay ??
              (page, scale) => [
                for (final field in view.fields)
                  if (field.page == page && (field.value ?? '').isNotEmpty)
                    _place(field, scale, _OtherField(field)),
              ],
        );
      },
    );
  }
}

Widget _place(SigningField field, double scale, Widget child) => Positioned(
  left: field.rect.left * scale,
  top: field.rect.top * scale,
  width: field.rect.width * scale,
  height: field.rect.height * scale,
  child: child,
);

/// Someone else's field: a dashed outline with its value once filled.
class _OtherField extends StatelessWidget {
  const _OtherField(this.field);

  final SigningField field;

  @override
  Widget build(BuildContext context) {
    final value = field.value;
    return ExcludeSemantics(
      excluding: value == null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0x0F000000),
          border: Border.all(color: context.colors.lineStrong, width: 0.8),
        ),
        child: value == null
            ? null
            : FittedBox(
                child: Text(
                  field.type == 'CHECKBOX'
                      ? (value == 'true' ? '✓' : '')
                      : value,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
      ),
    );
  }
}

/// The signer's turn: the guided Start / Next flow over the pages, then the
/// code, the consent and Click to sign.
class _Guided extends StatefulWidget {
  const _Guided({
    super.key,
    required this.token,
    required this.view,
    required this.pdf,
    required this.onDone,
    required this.onDeclined,
  });

  final String token;
  final SigningView view;
  final Future<OpenPdf> pdf;
  final VoidCallback onDone;
  final VoidCallback onDeclined;

  @override
  State<_Guided> createState() => _GuidedState();
}

class _GuidedState extends State<_Guided> {
  late final List<SigningField> _mine = widget.view.mine;
  late final _fieldKeys = {for (final f in _mine) f.id: GlobalKey()};
  final _finishKey = GlobalKey();
  final _codeFocus = FocusNode();

  late final Map<String, String> _values = {
    for (final f in _mine)
      if (f.type == 'TEXT' || f.type == 'CHECKBOX')
        f.id: f.value ?? (f.type == 'CHECKBOX' ? 'false' : ''),
  };
  final _applied = <String>{};
  AdoptedSignature? _signature;
  AdoptedSignature? _initials;
  SavedSignature? _saved;
  bool _showMissing = false;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_saved == null) _loadSaved();
  }

  /// A signed-in recipient's saved signature is ready until they adopt
  /// another.
  Future<void> _loadSaved() async {
    final services = AppScope.of(context);
    if (services.auth.user == null) return;
    try {
      final saved = await services.signing.saved();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _signature ??= saved.signature;
        _initials ??= saved.initials;
        if (saved.signature != null || saved.initials != null) {
          _notice = 'Your saved signature is ready. Tap each signature box to add it; tap it again to change it.';
        }
      });
    } on ApiFailure {
      // Signing works without it.
    }
  }

  @override
  void dispose() {
    _codeFocus.dispose();
    super.dispose();
  }

  List<SignatureFont> get _fonts => widget.view.fonts.isNotEmpty
      ? widget.view.fonts
      : (_saved?.fonts ?? const []);

  bool _filled(SigningField f) => switch (f.type) {
    'SIGNATURE' => _applied.contains(f.id) && _signature != null,
    'INITIALS' => _applied.contains(f.id) && _initials != null,
    'TEXT' => (_values[f.id] ?? '').trim().isNotEmpty,
    'CHECKBOX' => _values[f.id] == 'true',
    _ => true,
  };

  List<SigningField> get _required => [
    for (final f in _mine)
      if (f.selfFilled && f.required) f,
  ];

  int get _remaining => _required.where((f) => !_filled(f)).length;

  bool get _started =>
      _applied.isNotEmpty ||
      _mine.any((f) => (_values[f.id] ?? f.value ?? '') != (f.value ?? '')) ||
      _required.any(_filled);

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.35,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 350),
    );
  }

  /// Start / Next: to the next empty required field, then to the finish.
  void _next() {
    setState(() => _showMissing = true);
    final target = _required.where((f) => !_filled(f)).firstOrNull;
    if (target != null) {
      _scrollTo(_fieldKeys[target.id]!);
      if (target.type == 'TEXT') _editText(target);
      return;
    }
    _scrollTo(_finishKey);
    _codeFocus.requestFocus();
  }

  Future<void> _sign(SigningField field) async {
    final initials = field.type == 'INITIALS';
    final adopted = initials ? _initials : _signature;
    if (adopted != null && !_applied.contains(field.id)) {
      setState(() => _applied.add(field.id));
      return;
    }
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showAdoptSignature(
      context,
      initials: initials,
      name: widget.view.recipientName,
      fonts: _fonts,
      current: adopted,
      canSave: services.auth.user != null,
    );
    if (choice == null || !mounted) return;
    if (choice.save) {
      try {
        final saved = _saved;
        final next = await services.signing.save(
          signature: initials ? saved?.signature : choice.value,
          initials: initials ? choice.value : saved?.initials,
        );
        if (mounted) setState(() => _saved = next);
      } on ApiFailure catch (failure) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'It is used here, but we could not save it to your account: '
              '${signingMessage(failure)}',
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      if (initials) {
        _initials = choice.value;
      } else {
        _signature = choice.value;
      }
      _applied.add(field.id);
    });
  }

  Future<void> _editText(SigningField field) async {
    final controller = TextEditingController(text: _values[field.id]);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(field.label ?? 'Fill in'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: field.label ?? 'Text',
            helperText: field.required ? 'Required' : 'Optional',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) setState(() => _values[field.id] = value);
  }

  SigningSubmission _build(String code) {
    final view = widget.view;
    return SigningSubmission(
      code: code,
      fieldValues: {
        for (final f in _mine)
          if (f.type == 'TEXT' && (_values[f.id] ?? '').trim().isNotEmpty)
            f.id: _values[f.id]!.trim()
          else if (f.type == 'CHECKBOX')
            f.id: _values[f.id] == 'true' ? 'true' : 'false',
      },
      signature: view.approver ? null : _signature,
      initials: !view.approver && _mine.any((f) => f.type == 'INITIALS')
          ? _initials
          : null,
    );
  }

  Future<void> _decline() async {
    final declined = await showDialog<bool>(
      context: context,
      builder: (_) => _DeclineDialog(
        token: widget.token,
        repository: AppScope.of(context).signing,
      ),
    );
    if (declined == true) widget.onDeclined();
  }

  Widget _field(SigningField field, double scale) {
    final mineField = field.recipientId == widget.view.recipientId;
    if (!mineField) return _place(field, scale, _OtherField(field));
    final missing =
        _showMissing && field.selfFilled && field.required && !_filled(field);
    final c = context.colors;
    final fontSize = (field.rect.height * scale * 0.6).clamp(9.0, 22.0);
    final box = switch (field.type) {
      'SIGNATURE' || 'INITIALS' => _SignBox(
        word: field.type == 'SIGNATURE' ? 'Sign' : 'Initial',
        required: field.required,
        adopted: _applied.contains(field.id)
            ? (field.type == 'SIGNATURE' ? _signature : _initials)
            : null,
        missing: missing,
        onTap: () => _sign(field),
      ),
      'NAME' || 'DATE_SIGNED' => Tooltip(
        message: 'Filled in for you',
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          color: c.primarySoft.withValues(alpha: 0.6),
          child: FittedBox(
            child: Text(
              field.type == 'NAME' ? widget.view.recipientName : _today(),
              style: TextStyle(fontSize: fontSize, color: Colors.black87),
            ),
          ),
        ),
      ),
      'CHECKBOX' => Semantics(
        checked: _values[field.id] == 'true',
        label:
            '${field.label ?? 'Checkbox'}${field.required ? ' (required)' : ''}',
        child: InkWell(
          onTap: () => setState(
            () => _values[field.id] = _values[field.id] == 'true'
                ? 'false'
                : 'true',
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: missing ? c.danger : c.warning,
                width: 2,
              ),
            ),
            child: _values[field.id] == 'true'
                ? FittedBox(child: Icon(Icons.check, color: c.primary))
                : null,
          ),
        ),
      ),
      _ => Semantics(
        button: true,
        label:
            '${field.label ?? 'Text'}${field.required ? ' (required)' : ''}: ${_values[field.id]}',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _editText(field),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              border: Border.all(
                color: missing
                    ? c.danger
                    : (_values[field.id] ?? '').trim().isNotEmpty ||
                          !field.required
                    ? c.primary.withValues(alpha: 0.4)
                    : c.warning,
                width: 2,
              ),
            ),
            child: FittedBox(
              child: Text(
                (_values[field.id] ?? '').isEmpty
                    ? (field.label ?? 'Tap to fill in')
                    : _values[field.id]!,
                style: TextStyle(
                  fontSize: fontSize,
                  color: (_values[field.id] ?? '').isEmpty
                      ? Colors.black45
                      : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    };
    return _place(
      field,
      scale,
      KeyedSubtree(key: _fieldKeys[field.id], child: box),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final required = _required;
    final done = required.length - _remaining;
    final nextLabel = _remaining == 0
        ? (view.approver ? 'Approve' : 'Finish')
        : _started
        ? 'Next'
        : 'Start';
    final progress = required.isEmpty
        ? 'No fields to fill in'
        : '$done of ${required.length} required fields';

    return Scaffold(
      backgroundColor: c.sunken,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(view.name, overflow: TextOverflow.ellipsis),
            Text(
              view.reference,
              style: text.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open the PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PdfScreen(
                  title: view.name,
                  load: () => AppScope.of(context).signing.pdf(widget.token),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('signing-more'),
            onSelected: (_) => _decline(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'decline', child: Text('Decline to sign')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: FilledButton(
            key: const Key('signing-next'),
            onPressed: _next,
            child: Semantics(
              liveRegion: true,
              child: Text('$nextLabel · $progress'),
            ),
          ),
        ),
      ),
      // Built in full (not lazily), so Next can scroll to any field.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandCard(
              emphasised: true,
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: view.recipientName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text:
                                ', ${view.senderName}${view.organisationName == null ? '' : ' (${view.organisationName})'} '
                                'asks you to ${view.approver ? 'approve' : 'sign'} this document as ',
                          ),
                        ],
                      ),
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: Space.x1),
                    AppBadge(
                      view.recipientLabel ??
                          recipientRoleLabel(view.recipientRole),
                      tone: BadgeTone.primary,
                    ),
                    if (view.message != null &&
                        view.message!.trim().isNotEmpty) ...[
                      const SizedBox(height: Space.x3),
                      Container(
                        padding: const EdgeInsets.only(left: Space.x3),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: c.accent, width: 3),
                          ),
                        ),
                        child: Text(view.message!, style: text.bodyMedium),
                      ),
                    ],
                    const SizedBox(height: Space.x3),
                    Text(
                      '${view.approver ? 'Read it, then approve it at the end. You do not sign it.' : 'Press Start to go to each field you need to fill in. Yellow boxes are yours. Your name and the date are filled in for you.'} '
                      'It can be signed until ${_when.format(view.expiresAt.toLocal())}.',
                      style: text.bodyMedium,
                    ),
                    if (_notice != null) ...[
                      const SizedBox(height: Space.x3),
                      Text(
                        _notice!,
                        style: text.bodyMedium?.copyWith(color: c.primaryInk),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.x4),
            _DocumentPages(
              pdf: widget.pdf,
              view: view,
              overlay: (page, scale) => [
                for (final field in view.fields)
                  if (field.page == page) _field(field, scale),
              ],
            ),
            const SizedBox(height: Space.x2),
            KeyedSubtree(
              key: _finishKey,
              child: _FinishPanel(
                token: widget.token,
                view: view,
                remaining: _remaining,
                codeFocus: _codeFocus,
                onJump: _next,
                build: _build,
                onSigned: widget.onDone,
              ),
            ),
            if (view.statement.isNotEmpty) ...[
              const SizedBox(height: Space.x3),
              Text(view.statement, style: text.bodySmall),
            ],
            const SizedBox(height: Space.x6),
          ],
        ),
      ),
    );
  }
}

/// A signature or initials box: yellow "Sign" until adopted, then the
/// signature itself.
class _SignBox extends StatelessWidget {
  const _SignBox({
    required this.word,
    required this.required,
    required this.adopted,
    required this.missing,
    required this.onTap,
  });

  final String word;
  final bool required;
  final AdoptedSignature? adopted;
  final bool missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = adopted;
    final noun = word == 'Sign' ? 'Signature' : 'Initials';
    return Semantics(
      button: true,
      label: value != null
          ? '$noun added. Change it'
          : '$word here${required ? ' (required)' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: value != null
                ? Colors.white.withValues(alpha: 0.6)
                : c.warningSoft.withValues(alpha: 0.95),
            border: Border.all(
              color: missing
                  ? c.danger
                  : value != null
                  ? c.primary.withValues(alpha: 0.4)
                  : c.warning,
              width: 2,
            ),
          ),
          child: value != null
              ? SignaturePreview(value)
              : FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.draw_outlined, color: c.warning, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          word,
                          style: TextStyle(
                            color: c.warning,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Step 1, the emailed code; step 2, the consent; then Click to sign.
class _FinishPanel extends StatefulWidget {
  const _FinishPanel({
    required this.token,
    required this.view,
    required this.remaining,
    required this.codeFocus,
    required this.onJump,
    required this.build,
    required this.onSigned,
  });

  final String token;
  final SigningView view;
  final int remaining;
  final FocusNode codeFocus;
  final VoidCallback onJump;
  final SigningSubmission Function(String code) build;
  final VoidCallback onSigned;

  @override
  State<_FinishPanel> createState() => _FinishPanelState();
}

class _FinishPanelState extends State<_FinishPanel> {
  static const _resendWait = Duration(seconds: 30);

  final _code = TextEditingController();
  String? _sentTo;
  bool _sending = false;
  int _waitSeconds = 0;
  Timer? _tick;
  String? _codeError;
  bool _consent = false;
  String? _consentError;
  String? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _wait(Duration wait) {
    _tick?.cancel();
    setState(() => _waitSeconds = wait.inSeconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _waitSeconds--);
      if (_waitSeconds <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_sending || _waitSeconds > 0) return;
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      final sent = await AppScope.of(context).signing.sendCode(widget.token);
      if (!mounted) return;
      setState(() {
        _sentTo = sent.sentTo;
        _codeError = null;
      });
      _wait(_resendWait);
      widget.codeFocus.requestFocus();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      if (failure.status == 429) {
        _wait(failure.retryAfter ?? _resendWait);
        setState(
          () => _failure = 'You asked for a code a moment ago. Please wait a little before asking again.',
        );
      } else {
        setState(() => _failure = signingMessage(failure));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (widget.remaining > 0) {
      setState(
        () => _failure = widget.remaining == 1
            ? 'Fill in the last required field first.'
            : 'Fill in the ${widget.remaining} required fields first.',
      );
      widget.onJump();
      return;
    }
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    final demo = AppConfig.demoSigningCode.isNotEmpty;
    final codeProblem = _sentTo == null && !demo
        ? 'Send yourself the code first.'
        : code.isEmpty
        ? 'Enter the code from the email.'
        : code.length < 4 || code.length > 8
        ? 'The code is ${widget.view.codeLength} numbers.'
        : null;
    setState(() {
      _codeError = codeProblem;
      _consentError = _consent
          ? null
          : 'Tick the box to agree to sign electronically.';
    });
    if (codeProblem != null) {
      widget.codeFocus.requestFocus();
      return;
    }
    if (!_consent) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).signing
          .submit(widget.token, widget.build(code));
      if (mounted) widget.onSigned();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'CODE_EXPIRED') {
        _tick?.cancel();
        setState(() {
          _codeError = 'That code has expired or was used up. Send a new code.';
          _waitSeconds = 0;
        });
      } else if (failure.fields.containsKey('code')) {
        setState(
          () => _codeError =
              'That code is not right. Check the email and try again.',
        );
        _code.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _code.text.length,
        );
        widget.codeFocus.requestFocus();
      } else if (failure.code == 'ALREADY_SIGNED' ||
          failure.code == 'NOT_OPEN_FOR_SIGNING') {
        widget.onSigned();
      } else {
        final detail = failure.fields.values.join(' ');
        setState(
          () => _failure =
              '${signingMessage(failure)}${detail.isEmpty ? '' : ' $detail'}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final approver = view.approver;
    final length = view.codeLength;
    return BrandOutline(
      active: true,
      // The outline paints the surface; the tiles need their own Material.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                approver ? 'Approve the document' : 'Finish signing',
                style: text.titleLarge,
              ),
              const SizedBox(height: Space.x1),
              if (widget.remaining > 0)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.remaining == 1
                            ? '1 required field is still empty.'
                            : '${widget.remaining} required fields are still empty.',
                        style: text.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onJump,
                      child: const Text('Go to it'),
                    ),
                  ],
                )
              else
                Text(
                  'Every required field is filled in. Confirm it is you, then '
                  '${approver ? 'approve' : 'sign'}.',
                  style: text.bodyMedium,
                ),
              const SizedBox(height: Space.x4),
              Text('1. Confirm your email address', style: text.titleSmall),
              const SizedBox(height: Space.x1),
              Text(
                _sentTo == null
                    ? 'We will email a $length-digit code to ${view.emailMasked}.'
                    : 'We sent a $length-digit code to $_sentTo. It works for 10 minutes.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.x2),
              TextField(
                key: const Key('signing-code'),
                controller: _code,
                focusNode: widget.codeFocus,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
                style: text.headlineSmall?.copyWith(letterSpacing: 6),
                decoration: InputDecoration(
                  labelText: 'Code from the email',
                  errorText: _codeError,
                  helperText: AppConfig.demoSigningCode.isEmpty
                      ? null
                      : 'Test site: you can use the demo code ${AppConfig.demoSigningCode}.',
                ),
              ),
              const SizedBox(height: Space.x2),
              OutlinedButton(
                key: const Key('signing-send-code'),
                onPressed: _sending || _waitSeconds > 0 ? null : _sendCode,
                child: Text(
                  _sending
                      ? 'Sending…'
                      : _waitSeconds > 0
                      ? 'Send a new code in $_waitSeconds s'
                      : _sentTo == null
                      ? 'Email me a code'
                      : 'Send a new code',
                ),
              ),
              const SizedBox(height: Space.x4),
              Text('2. Agree to sign electronically', style: text.titleSmall),
              CheckboxListTile(
                key: const Key('signing-consent'),
                value: _consent,
                onChanged: (value) => setState(() {
                  _consent = value ?? false;
                  _consentError = null;
                }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  view.consentText.isEmpty
                      ? 'I agree to use electronic records and signatures.'
                      : view.consentText,
                  style: text.bodyMedium,
                ),
                subtitle: _consentError == null
                    ? null
                    : Text(_consentError!, style: TextStyle(color: c.danger)),
              ),
              if (_failure != null) ...[
                const SizedBox(height: Space.x2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _failure!,
                    style: text.bodyMedium?.copyWith(color: c.danger),
                  ),
                ),
              ],
              const SizedBox(height: Space.x4),
              FilledButton.icon(
                key: const Key('signing-submit'),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.check),
                label: Text(
                  _busy
                      ? (approver ? 'Approving…' : 'Signing…')
                      : (approver ? 'Approve' : 'Click to sign'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog({required this.token, required this.repository});

  final String token;
  final SigningRepository repository;

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _decline() async {
    final text = _reason.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error =
            'Write why you are declining. The sender is emailed this reason.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.decline(widget.token, text);
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.fields['reason'] ?? signingMessage(failure);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Decline to sign?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'The document will not be completed by anyone. The sender is emailed your reason.',
        ),
        const SizedBox(height: Space.x3),
        TextField(
          key: const Key('decline-reason'),
          controller: _reason,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: 'Reason', errorText: _error),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Keep it'),
      ),
      FilledButton(
        key: const Key('decline-confirm'),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: _busy ? null : _decline,
        child: Text(_busy ? 'Declining…' : 'Decline'),
      ),
    ],
  );
}

/// Opens a document from "Documents to sign" through a fresh signing link.
Future<void> openSigningRequest(
  BuildContext context,
  SigningRequest request,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final token = await AppScope.of(context).signing.link(request.recipientId);
    if (context.mounted) await context.push(Routes.sign(token));
  } on ApiFailure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(signingMessage(failure))));
  }
}
