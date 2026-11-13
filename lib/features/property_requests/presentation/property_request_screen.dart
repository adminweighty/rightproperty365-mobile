import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config.dart';
import '../../../core/widgets/async_view.dart';
import '../../listings/data/listing.dart';
import '../data/property_request.dart';

/// Loads the listing for the route, then shows the form.
class PropertyRequestScreen extends StatefulWidget {
  const PropertyRequestScreen({super.key, required this.slug});

  final String slug;

  @override
  State<PropertyRequestScreen> createState() => _PropertyRequestScreenState();
}

class _PropertyRequestScreenState extends State<PropertyRequestScreen> {
  Future<Listing?>? _listing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listing ??= AppScope.of(context).listings.bySlug(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send a request')),
      body: AsyncView<Listing?>(
        future: _listing!,
        builder: (context, listing) => listing == null
            ? const MessageView(
                icon: Icons.home_outlined,
                title: 'This listing is no longer available',
                body: 'It may have expired or been removed.',
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x4),
                child: PropertyRequestForm(listing: listing),
              ),
      ),
    );
  }
}

/// The only way a customer contacts an advertiser. It posts to the
/// RightProperty365 API, never to an agent directly.
class PropertyRequestForm extends StatefulWidget {
  const PropertyRequestForm({super.key, required this.listing});

  final Listing listing;

  @override
  State<PropertyRequestForm> createState() => _PropertyRequestFormState();
}

class _PropertyRequestFormState extends State<PropertyRequestForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late final _message = TextEditingController(
    text:
        'Hello, I am interested in ${widget.listing.reference}. Please send me more details.',
  );

  RequestType _type = RequestType.enquiry;
  ContactMethod _method = ContactMethod.email;
  DateTime? _slot;
  bool _consent = false;
  bool _consentMissing = false;
  bool _sending = false;
  ApiFailure? _failure;
  PropertyRequestReceipt? _receipt;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^\+[1-9][0-9]{6,14}$');

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _message]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// A problem the API reported for [field], phrased with the control's label.
  String? _apiError(String field, String label) {
    final problem = _failure?.fields[field];
    return problem == null ? null : '$label $problem';
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _slot ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _slot ?? DateTime(now.year, now.month, now.day, 10),
      ),
    );
    if (time == null) return;
    setState(
      () => _slot = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _consentMissing = !_consent);
    if (!valid || !_consent) return;

    setState(() {
      _sending = true;
      _failure = null;
    });

    final draft = PropertyRequestDraft(
      listingId: widget.listing.id,
      requestType: _type,
      message: _message.text,
      contactMethod: _method,
      name: _name.text,
      email: _email.text,
      phone: _phone.text,
      preferredSlot: _slot,
      consentAccepted: _consent,
      privacyVersion: AppConfig.privacyNoticeVersion,
    );

    final repository = AppScope.of(context).propertyRequests;
    try {
      final receipt = await repository.submit(draft);
      if (!mounted) return;
      setState(() => _receipt = receipt);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
      // Re-run validators so API field errors appear under their controls.
      _form.currentState!.validate();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt != null) {
      return _Receipt(
        receipt: receipt,
        advertiser: widget.listing.advertiser.name,
      );
    }

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.x4);

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.listing.title, style: text.titleLarge),
          Text(
            '${widget.listing.location} · ${widget.listing.advertiser.name}',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.x6),
          DropdownButtonFormField<RequestType>(
            key: const Key('request-type'),
            // Expanded with free item height, so large text wraps, not clips.
            isExpanded: true,
            itemHeight: null,
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'What would you like to do?',
            ),
            items: [
              for (final type in RequestType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (value) => setState(() {
              _type = value!;
              if (!_type.allowsSlot) _slot = null;
            }),
          ),
          if (_type.allowsSlot) ...[
            gap,
            OutlinedButton.icon(
              onPressed: _pickSlot,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _slot == null
                    ? 'Choose a preferred date and time (optional)'
                    : DateFormat('EEE d MMM y, HH:mm').format(_slot!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.x1, left: Space.x3),
              child: Text(
                _apiError('preferred_slot_utc', 'The preferred time') ?? 'In your local time. The agent will confirm or suggest another slot.',
                style: TextStyle(
                  fontSize: 14,
                  color: _failure?.fields['preferred_slot_utc'] == null
                      ? c.muted
                      : c.danger,
                ),
              ),
            ),
          ],
          gap,
          TextFormField(
            key: const Key('name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Full name',
              counterText: '',
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Enter your full name'
                : _apiError('guest_contact.name', 'Full name'),
          ),
          gap,
          TextFormField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email address'),
            validator: (value) => !_emailPattern.hasMatch((value ?? '').trim())
                ? 'Enter a valid email address'
                : _apiError('guest_contact.email', 'Email address'),
          ),
          gap,
          DropdownButtonFormField<ContactMethod>(
            key: const Key('contact-method'),
            isExpanded: true,
            itemHeight: null,
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'How should they reply?',
            ),
            items: [
              for (final method in ContactMethod.values)
                DropdownMenuItem(value: method, child: Text(method.label)),
            ],
            onChanged: (value) => setState(() => _method = value!),
          ),
          gap,
          TextFormField(
            key: const Key('phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: _method.needsPhone
                  ? 'Phone number'
                  : 'Phone number (optional)',
              helperText:
                  'Include the country code, for example +263 77 123 4567.',
            ),
            validator: (value) {
              final phone = PropertyRequestDraft.normalisePhone(value);
              if (phone == null) {
                return _method.needsPhone
                    ? 'Enter a phone number so they can reach you by ${_method.label.toLowerCase()}'
                    : null;
              }
              if (!_phonePattern.hasMatch(phone)) {
                return 'Enter the number with its country code, for example +263 77 123 4567';
              }
              return _apiError('guest_contact.phone', 'Phone number');
            },
          ),
          gap,
          TextFormField(
            key: const Key('message'),
            controller: _message,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Write a short message'
                : _apiError('message', 'The message'),
          ),
          const SizedBox(height: Space.x2),
          CheckboxListTile(
            key: const Key('consent'),
            value: _consent,
            onChanged: (value) => setState(() {
              _consent = value ?? false;
              if (_consent) _consentMissing = false;
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'I agree that RightProperty365 may share these details with '
              '${widget.listing.advertiser.name} so they can answer this request.',
              style: text.bodyMedium,
            ),
            subtitle: _consentMissing
                ? Text(
                    'Tick the box to send your request',
                    style: TextStyle(fontSize: 14, color: c.danger),
                  )
                : null,
          ),
          if (_failure != null) ...[
            gap,
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _failure!.fields.isEmpty
                          ? _failure!.message
                          : 'Check the highlighted fields and try again.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.danger,
                      ),
                    ),
                    if (_failure!.traceId != null)
                      Text(
                        'Support reference: ${_failure!.traceId}',
                        style: TextStyle(fontSize: 12, color: c.danger),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.x5),
          FilledButton(
            key: const Key('submit'),
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending…' : 'Send request'),
          ),
        ],
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.receipt, required this.advertiser});

  final PropertyRequestReceipt receipt;
  final String advertiser;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    // A live region, so screen readers announce the receipt when it appears.
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.x5),
        decoration: BoxDecoration(
          color: c.successSoft,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.check_circle_outline, color: c.success),
                ),
                const SizedBox(width: Space.x2),
                Text(
                  'Request received',
                  style: text.titleMedium?.copyWith(color: c.success),
                ),
              ],
            ),
            const SizedBox(height: Space.x3),
            // "Received" is all the system knows. Never say delivered or read.
            Text(
              'We have saved your request and are passing it to $advertiser. '
              'Keep this reference in case you need to follow up:',
              style: text.bodyLarge,
            ),
            const SizedBox(height: Space.x3),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    receipt.reference,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy reference',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: receipt.reference),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reference copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
