import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/async_view.dart';
import '../data/data_export.dart';
import 'auth_screens.dart' show FailureBox;

final _when = DateFormat('d MMM y, HH:mm');

/// Account Management → Download your data (API 0.55.0).
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  Future<DataExport?>? _loading;
  DataExport? _export;
  bool _busy = false;
  ApiFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
  }

  Future<DataExport?> _load() =>
      AppScope.of(context).dataExport.current().then((e) => _export = e);

  void _refresh() => setState(() {
    _failure = null;
    _loading = _load();
  });

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final next = await AppScope.of(context).dataExport.request();
      if (mounted) setState(() => _export = next);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await services.dataExport.download();
      final saved = await services.saveFile(
        name: 'rightproperty365-data.zip',
        bytes: bytes,
        mimeType: 'application/zip',
      );
      if (saved) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Your data is saved on this phone.')),
          );
      }
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download your data')),
      body: AsyncView<DataExport?>(
        future: _loading!,
        onRetry: _refresh,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final e = _export;
    final canAsk =
        e == null || !(e.status.pending || e.status == ExportStatus.ready);
    final String? state = switch (e?.status) {
      null => null,
      ExportStatus.requested || ExportStatus.building =>
        'Being prepared. We email you and tell you here when it is ready, '
            'usually within minutes.',
      ExportStatus.ready =>
        'Ready${e!.expiresAt == null ? '' : ' until ${_when.format(e.expiresAt!.toLocal())}'}'
            '${e.sizeLabel == null ? '' : ' · ${e.sizeLabel}'}.',
      ExportStatus.expired =>
        'Your last copy has expired and was deleted. Ask for a new one.',
      ExportStatus.failed =>
        'We could not prepare your last copy. Ask for a new one.',
    };
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await _loading;
      },
      child: ListView(
        padding: const EdgeInsets.all(Space.x4),
        children: [
          Text(
            'Get a copy of what RightProperty365 holds about you: your '
            'account, settings, saved listings and searches, your requests '
            'and their conversations, appointments, applications, reviews, '
            'bookings and invoices. It is a ZIP file of JSON files with a '
            'README. Other people\'s contact details are not included.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.x2),
          Text(
            'A copy is kept for 7 days and is only downloaded through your '
            'signed-in account. You can ask once every 24 hours.',
            style: text.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.x5),
          if (state != null)
            Semantics(
              liveRegion: true,
              child: Container(
                key: const Key('export-state'),
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: e!.status == ExportStatus.failed
                      ? c.dangerSoft
                      : c.infoSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state, style: text.bodyLarge),
                    if (e.requestedAt != null)
                      Text(
                        'Asked for ${_when.format(e.requestedAt!.toLocal())}',
                        style: text.bodyMedium,
                      ),
                  ],
                ),
              ),
            ),
          if (_failure != null) ...[
            const SizedBox(height: Space.x3),
            FailureBox(_failure!),
          ],
          const SizedBox(height: Space.x4),
          if (e?.status == ExportStatus.ready)
            FilledButton.icon(
              key: const Key('export-download'),
              onPressed: _busy ? null : _download,
              icon: const Icon(Icons.download),
              label: Text(_busy ? 'Downloading…' : 'Download (ZIP)'),
            ),
          if (e != null && e.status.pending)
            OutlinedButton.icon(
              key: const Key('export-refresh'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
          if (canAsk)
            FilledButton(
              key: const Key('export-request'),
              onPressed: _busy ? null : _request,
              child: Text(_busy ? 'Asking…' : 'Ask for a copy of my data'),
            ),
        ],
      ),
    );
  }
}
