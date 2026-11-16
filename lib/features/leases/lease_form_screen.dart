import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/searchable_select.dart';
import '../auth/presentation/auth_screens.dart' show FailureBox, emailPattern;
import '../workspace/workspace.dart';
import 'lease_repository.dart';

final _day = DateFormat('d MMM y');
final _amount = RegExp(r'^\d{1,12}(\.\d{1,2})?$');

class _PartyFields {
  _PartyFields([LeaseParty? party])
    : name = TextEditingController(text: party?.name),
      email = TextEditingController(text: party?.email),
      phone = TextEditingController(text: party?.phone);

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController phone;

  LeaseParty get value =>
      LeaseParty(name: name.text, email: email.text, phone: phone.text);

  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
  }
}

typedef _Choices = ({
  List<LeaseTemplate> templates,
  List<LeaseListing> listings,
  List<WorkOrganisation> organisations,
  Lease? lease,
});

/// Drafting a lease from an approved template, or changing a draft. The API
/// renders the draft PDF on every save and checks every rule again.
class LeaseFormScreen extends StatefulWidget {
  const LeaseFormScreen({super.key, this.leaseId});

  /// Null for a new lease.
  final String? leaseId;

  @override
  State<LeaseFormScreen> createState() => _LeaseFormScreenState();
}

class _LeaseFormScreenState extends State<LeaseFormScreen> {
  Future<_Choices>? _choices;
  final _form = GlobalKey<FormState>();

  String? _templateId;
  String? _listingId;
  String? _organisationId;
  final _address = TextEditingController();
  final _landlords = <_PartyFields>[_PartyFields()];
  final _tenants = <_PartyFields>[_PartyFields()];
  DateTime? _start;
  DateTime? _end;
  bool _periodic = false;
  bool _landlordStamp = false;
  final _rent = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  String _period = 'MONTHLY';
  int _paymentDay = 1;
  final _deposit = TextEditingController();
  final _notice = TextEditingController(text: '30');
  final _clauses = <String>{};
  final _special = TextEditingController();
  bool _saving = false;
  ApiFailure? _failure;

  bool get _creating => widget.leaseId == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _choices ??= _load();
  }

  Future<_Choices> _load() async {
    final services = AppScope.of(context);
    final leaseId = widget.leaseId;
    final results = await Future.wait<Object?>([
      services.leases.templates(),
      _creating ? services.leases.listings() : Future.value(<LeaseListing>[]),
      _creating
          ? services.workspace.load().then<Object?>(
              (w) => w.leaseOrganisations,
              onError: (_) => <WorkOrganisation>[],
            )
          : Future.value(<WorkOrganisation>[]),
      leaseId == null ? Future.value(null) : services.leases.get(leaseId),
    ]);
    final lease = results[3] as Lease?;
    if (lease != null) _fill(lease.toDraft());
    return (
      templates: results[0] as List<LeaseTemplate>,
      listings: results[1] as List<LeaseListing>,
      organisations: results[2] as List<WorkOrganisation>,
      lease: lease,
    );
  }

  void _fill(LeaseDraft draft) {
    _templateId = draft.templateId;
    _address.text = draft.propertyAddress ?? '';
    for (final p in [..._landlords, ..._tenants]) {
      p.dispose();
    }
    _landlords
      ..clear()
      ..addAll(draft.landlords.map(_PartyFields.new));
    _tenants
      ..clear()
      ..addAll(draft.tenants.map(_PartyFields.new));
    _start = draft.startDate;
    _end = draft.endDate;
    _periodic = draft.periodic;
    _landlordStamp = draft.landlordStamp;
    _rent.text = draft.rentAmount;
    _currency.text = draft.rentCurrency;
    _period = draft.rentPeriod;
    _paymentDay = draft.paymentDay;
    _deposit.text = draft.depositAmount ?? '';
    _notice.text = '${draft.noticePeriodDays}';
    _clauses
      ..clear()
      ..addAll(draft.optionalClauses);
    _special.text = draft.specialConditions ?? '';
  }

  @override
  void dispose() {
    for (final c in [_address, _rent, _currency, _deposit, _notice, _special]) {
      c.dispose();
    }
    for (final p in [..._landlords, ..._tenants]) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start
        ? (_start ?? now)
        : (_end ?? (_start ?? now).add(const Duration(days: 365)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 30),
      helpText: start ? 'Lease starts' : 'Lease ends',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save(_Choices choices) async {
    if (!_form.currentState!.validate()) return;
    if (_start == null) {
      setState(
        () => _failure = const ApiFailure(
          status: 400,
          code: 'LOCAL',
          message: 'Choose the date the lease starts.',
        ),
      );
      return;
    }
    if (!_periodic && (_end == null || !_end!.isAfter(_start!))) {
      setState(
        () => _failure = const ApiFailure(
          status: 400,
          code: 'LOCAL',
          message:
              'Choose an end date after the start, or make the lease periodic.',
        ),
      );
      return;
    }
    final organisations = choices.organisations;
    final draft = LeaseDraft(
      templateId: _templateId!,
      listingId: _listingId,
      organisationId: _listingId == null && organisations.length > 1
          ? _organisationId
          : null,
      propertyAddress: _address.text,
      landlords: [for (final p in _landlords) p.value],
      tenants: [for (final p in _tenants) p.value],
      startDate: _start!,
      endDate: _periodic ? null : _end,
      periodic: _periodic,
      rentAmount: _rent.text,
      rentCurrency: _currency.text,
      rentPeriod: _period,
      paymentDay: _paymentDay,
      depositAmount: _deposit.text,
      noticePeriodDays: int.parse(_notice.text.trim()),
      optionalClauses: [
        for (final clause
            in _template(choices)?.optionalClauses ?? const <LeaseClause>[])
          if (_clauses.contains(clause.code)) clause.code,
      ],
      specialConditions: _special.text,
      landlordStamp: _landlordStamp,
    );
    setState(() {
      _saving = true;
      _failure = null;
    });
    final repo = AppScope.of(context).leases;
    try {
      final saved = _creating
          ? await repo.create(draft)
          : await repo.update(widget.leaseId!, draft);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      final detail = failure.fields.entries
          .map((e) => '${_fieldName(e.key)}: ${e.value}')
          .join('\n');
      setState(
        () => _failure = failure.withMessage(
          detail.isEmpty
              ? leaseMessage(failure)
              : '${leaseMessage(failure)}\n$detail',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "tenants[0].email" -> "Tenant 1 email".
  static String _fieldName(String path) {
    final party = RegExp(r'^(landlords|tenants)\[(\d+)\]\.?(.*)$')
        .firstMatch(path);
    if (party != null) {
      final who = party.group(1) == 'landlords' ? 'Landlord' : 'Tenant';
      return '$who ${int.parse(party.group(2)!) + 1} ${party.group(3)}'.trim();
    }
    return path.replaceAll('_', ' ');
  }

  LeaseTemplate? _template(_Choices choices) =>
      choices.templates.where((t) => t.id == _templateId).firstOrNull;

  LeaseListing? _listing(_Choices choices) =>
      choices.listings.where((l) => l.id == _listingId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? 'Draft a lease' : 'Edit the draft'),
      ),
      body: AsyncView<_Choices>(
        future: _choices!,
        onRetry: () => setState(() {
          _choices = _load();
        }),
        builder: (context, choices) {
          if (choices.templates.isEmpty) {
            return const MessageView(
              icon: Icons.description_outlined,
              title: 'No lease templates yet',
              body:
                  'There are no published templates for your country yet. Copy a sample '
                  'template on the website, change it and publish it, then draft the lease here.',
            );
          }
          return _formBody(context, choices);
        },
      ),
    );
  }

  Widget _parties(
    BuildContext context,
    String title,
    List<_PartyFields> parties,
  ) {
    final text = Theme.of(context).textTheme;
    final singular = title.substring(0, title.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title),
        const SizedBox(height: Space.x2),
        for (var i = 0; i < parties.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x3),
            child: BrandOutline(
              active: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$singular ${i + 1}',
                            style: text.titleSmall,
                          ),
                        ),
                        if (parties.length > 1)
                          IconButton(
                            tooltip: 'Remove $singular ${i + 1}',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => parties.removeAt(i).dispose()),
                          ),
                      ],
                    ),
                    TextFormField(
                      key: Key('${title.toLowerCase()}-$i-name'),
                      controller: parties[i].name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter their full name'
                          : null,
                    ),
                    TextFormField(
                      key: Key('${title.toLowerCase()}-$i-email'),
                      controller: parties[i].email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        helperText: 'The signing link is emailed here.',
                      ),
                      validator: (v) => emailPattern.hasMatch((v ?? '').trim())
                          ? null
                          : 'Enter a valid email address',
                    ),
                    const SizedBox(height: Space.x2),
                    TextFormField(
                      controller: parties[i].phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (parties.length < 5)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('add-${title.toLowerCase()}'),
              onPressed: () => setState(() => parties.add(_PartyFields())),
              icon: const Icon(Icons.add),
              label: Text('Add a ${singular.toLowerCase()}'),
            ),
          ),
      ],
    );
  }

  Widget _formBody(BuildContext context, _Choices choices) {
    const gap = SizedBox(height: Space.x4);
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final template = _template(choices);
    final listing = _listing(choices);
    final weekly = _period == 'WEEKLY';

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          SearchableSelectField<String>(
            key: const Key('lease-template'),
            label: 'Template',
            value: _templateId,
            // The organisation's own templates first, then the samples.
            options: [
              for (final sample in [false, true])
                for (final t in choices.templates)
                  if (t.sample == sample)
                    SelectOption(
                      t.id,
                      '${t.name} (v${t.version})',
                      group: sample ? 'Samples' : 'Your templates',
                      keywords: '${t.marketCode} ${t.leaseKind}',
                    ),
            ],
            onChanged: (id) => setState(() {
              _templateId = id;
              _clauses.clear();
            }),
            validator: (id) {
              if (id == null) {
                return 'Choose the template the lease is made from';
              }
              final chosen = choices.templates
                  .where((t) => t.id == id)
                  .firstOrNull;
              if (listing != null &&
                  chosen != null &&
                  listing.countryCode.isNotEmpty &&
                  chosen.marketCode.toUpperCase() !=
                      listing.countryCode.toUpperCase()) {
                return "Choose a template for the property's country (${listing.countryCode}).";
              }
              final organisation =
                  (_listingId == null ? _organisationId : null) ??
                  (choices.organisations.length == 1
                      ? choices.organisations.first.id
                      : null);
              if (chosen != null &&
                  !chosen.sample &&
                  organisation != null &&
                  chosen.organisationId != null &&
                  chosen.organisationId != organisation) {
                return 'That template belongs to another of your organisations. Choose one of '
                    "this organisation's templates or a sample.";
              }
              return null;
            },
          ),
          if (template?.description != null) ...[
            const SizedBox(height: Space.x1),
            Text(template!.description!, style: text.bodySmall),
          ],
          if (template?.reviewedBy != null) ...[
            const SizedBox(height: Space.x1),
            Text('Reviewed by ${template!.reviewedBy}', style: text.bodySmall),
          ],
          gap,
          if (_creating && choices.listings.isNotEmpty) ...[
            SearchableSelectField<String>(
              key: const Key('lease-listing'),
              label: 'Listing (optional)',
              value: _listingId,
              anyLabel: 'No listing: type the address',
              options: [
                for (final l in choices.listings)
                  SelectOption(
                    l.id,
                    l.title,
                    group: l.city,
                    keywords: '${l.reference} ${l.countryCode}',
                  ),
              ],
              onChanged: (id) => setState(() {
                _listingId = id;
                final chosen = _listing(choices);
                if (chosen?.currency != null) {
                  _currency.text = chosen!.currency!;
                }
              }),
            ),
            gap,
          ],
          if (_creating &&
              _listingId == null &&
              choices.organisations.length > 1) ...[
            SearchableSelectField<String>(
              label: 'Agency or organisation',
              value: _organisationId,
              options: [
                for (final o in choices.organisations)
                  SelectOption(o.id, o.name),
              ],
              onChanged: (id) => setState(() => _organisationId = id),
              validator: (id) =>
                  id == null ? 'Choose who the lease is drafted for' : null,
            ),
            gap,
          ],
          TextFormField(
            key: const Key('lease-address'),
            controller: _address,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: listing == null
                  ? 'Property address'
                  : 'Property address (optional)',
              helperText: listing == null ? null : 'Leave empty to use the listing\'s suburb, city and country.',
            ),
            validator: (v) => listing == null && (v ?? '').trim().isEmpty
                ? 'Enter the property address'
                : null,
          ),
          gap,
          _parties(context, 'Landlords', _landlords),
          SwitchListTile(
            key: const Key('lease-landlord-stamp'),
            contentPadding: EdgeInsets.zero,
            value: _landlordStamp,
            onChanged: (v) => setState(() => _landlordStamp = v),
            title: const Text('Landlords also stamp the lease'),
            subtitle: const Text(
              'Each landlord adds a company stamp next to their signature, for a company or trust.',
            ),
          ),
          gap,
          _parties(context, 'Tenants', _tenants),
          gap,
          const SectionHeading('Term'),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            key: const Key('lease-start'),
            onPressed: () => _pickDate(start: true),
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _start == null
                  ? 'Choose the start date'
                  : 'Starts ${_day.format(_start!)}',
            ),
          ),
          SwitchListTile(
            key: const Key('lease-periodic'),
            contentPadding: EdgeInsets.zero,
            value: _periodic,
            onChanged: (v) => setState(() => _periodic = v),
            title: const Text('Periodic (no end date)'),
            subtitle: const Text('Runs until notice is given.'),
          ),
          if (!_periodic)
            OutlinedButton.icon(
              key: const Key('lease-end'),
              onPressed: () => _pickDate(start: false),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _end == null
                    ? 'Choose the end date'
                    : 'Ends ${_day.format(_end!)}',
              ),
            ),
          gap,
          const SectionHeading('Rent'),
          const SizedBox(height: Space.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const Key('lease-rent'),
                  controller: _rent,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Rent amount'),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (!_amount.hasMatch(value) || double.parse(value) <= 0) {
                      return 'An amount above 0, like 850 or 850.50';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: TextFormField(
                  key: const Key('lease-currency'),
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  validator: (v) =>
                      RegExp(r'^[A-Za-z]{3}$').hasMatch((v ?? '').trim())
                      ? null
                      : 'Like USD',
                ),
              ),
            ],
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'MONTHLY', label: Text('Monthly')),
              ButtonSegment(value: 'WEEKLY', label: Text('Weekly')),
              ButtonSegment(value: 'ANNUALLY', label: Text('Yearly')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() {
              _period = s.first;
              if (_period == 'WEEKLY' && _paymentDay > 7) _paymentDay = 1;
            }),
          ),
          gap,
          SearchableSelectField<int>(
            key: ValueKey('payment-day-$weekly'),
            label: weekly ? 'Paid every' : 'Paid on day of the month',
            value: _paymentDay,
            options: [
              for (var d = 1; d <= (weekly ? 7 : 31); d++)
                SelectOption(d, weekly ? weekdays[d - 1] : 'Day $d'),
            ],
            onChanged: (d) => setState(() => _paymentDay = d ?? _paymentDay),
          ),
          gap,
          TextFormField(
            controller: _deposit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Deposit (optional)'),
            validator: (v) {
              final value = (v ?? '').trim();
              return value.isEmpty || _amount.hasMatch(value)
                  ? null
                  : 'An amount like 850 or 850.50';
            },
          ),
          gap,
          TextFormField(
            key: const Key('lease-notice'),
            controller: _notice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Notice period in days',
            ),
            validator: (v) {
              final days = int.tryParse((v ?? '').trim());
              return days == null || days < 1 || days > 365
                  ? 'From 1 to 365 days'
                  : null;
            },
          ),
          if (template != null && template.optionalClauses.isNotEmpty) ...[
            gap,
            const SectionHeading('Optional clauses'),
            for (final clause in template.optionalClauses)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _clauses.contains(clause.code),
                onChanged: (v) => setState(
                  () => v == true
                      ? _clauses.add(clause.code)
                      : _clauses.remove(clause.code),
                ),
                title: Text(clause.title),
                subtitle: clause.text.isEmpty
                    ? null
                    : Text(
                        clause.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
              ),
          ],
          gap,
          TextFormField(
            controller: _special,
            maxLength: 4000,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Special conditions (optional)',
            ),
          ),
          if (_failure != null) ...[gap, FailureBox(_failure!)],
          gap,
          FilledButton(
            key: const Key('lease-save'),
            onPressed: _saving ? null : () => _save(choices),
            child: Text(
              _saving
                  ? 'Saving…'
                  : _creating
                  ? 'Save draft'
                  : 'Save changes',
            ),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'Saving makes the draft PDF with a DRAFT watermark. Nothing is sent until you '
            'choose Send for signing.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x6),
        ],
      ),
    );
  }
}
