import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/searchable_select.dart';
import '../data/listing_reports.dart';

/// "Report this listing": a reason and a note, sent to the moderators.
Future<void> reportListing(BuildContext context, String slug) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = await showDialog<bool>(
    context: context,
    builder: (context) => _ReportDialog(slug: slug),
  );
  if (sent != true) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Thank you. Our moderators will look at this listing.'),
      ),
    );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.slug});

  final String slug;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await AppScope.of(context).listingReports
          .report(widget.slug, _reason!, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final failure = _failure;
    return AlertDialog(
      title: const Text('Report this listing'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell our moderators what is wrong. The advertiser is not '
                'told who reported it.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.x3),
              SearchableSelectField<ReportReason>(
                key: const Key('report-reason'),
                label: 'What is wrong?',
                value: _reason,
                options: [
                  for (final r in ReportReason.values) SelectOption(r, r.label),
                ],
                onChanged: (r) => setState(() => _reason = r),
                validator: (r) => r == null
                    ? 'Choose what is wrong'
                    : switch (failure?.fields['reason']) {
                        final String p => 'Reason $p',
                        _ => null,
                      },
              ),
              const SizedBox(height: Space.x3),
              TextFormField(
                key: const Key('report-note'),
                controller: _note,
                maxLength: reportNoteMax,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: _reason?.needsNote == true
                      ? 'What is wrong'
                      : 'More details (optional)',
                ),
                validator: (v) =>
                    _reason?.needsNote == true && (v ?? '').trim().isEmpty
                    ? 'Say what is wrong'
                    : switch (failure?.fields['note']) {
                        final String p => 'Note $p',
                        _ => null,
                      },
              ),
              if (failure != null && failure.fields.isEmpty) ...[
                const SizedBox(height: Space.x2),
                Text(
                  failure.message,
                  key: const Key('report-failure'),
                  style: TextStyle(color: c.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('report-send'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send report'),
        ),
      ],
    );
  }
}
