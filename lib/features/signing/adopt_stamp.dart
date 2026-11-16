import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import 'stamp.dart';

/// A stamp as the API draws it (`POST /v1/stamp-preview`). It is fetched
/// again when the stamp changes; with a [debounce], only once typing pauses,
/// because the preview is rate-limited.
class StampImage extends StatefulWidget {
  const StampImage(
    this.stamp, {
    super.key,
    this.date,
    this.debounce = Duration.zero,
    this.initial,
    this.onLoaded,
  });

  final Stamp stamp;

  /// The day printed when the stamp includes the date; the API's sample date
  /// when null.
  final DateTime? date;
  final Duration debounce;

  /// An image already drawn for this stamp, so it is not fetched again.
  final Uint8List? initial;

  /// Told which stamp each drawn image is of.
  final void Function(Stamp stamp, Uint8List image)? onLoaded;

  @override
  State<StampImage> createState() => _StampImageState();
}

class _StampImageState extends State<StampImage> {
  late Uint8List? _bytes = widget.initial;
  String? _shownKey;
  String? _problem;
  bool _loading = false;
  Timer? _wait;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (_bytes != null) _shownKey = widget.stamp.key;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shownKey == null && _wait == null && !_loading) _schedule();
  }

  @override
  void didUpdateWidget(StampImage old) {
    super.didUpdateWidget(old);
    if (old.stamp.key != widget.stamp.key) _schedule();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _schedule() {
    _wait?.cancel();
    _wait = null;
    if (widget.stamp.problem != null) return;
    if (widget.debounce == Duration.zero) {
      _fetch();
    } else {
      _wait = Timer(widget.debounce, _fetch);
    }
  }

  Future<void> _fetch() async {
    _wait = null;
    final stamp = widget.stamp;
    final generation = ++_generation;
    final signing = AppScope.of(context).signing;
    setState(() => _loading = true);
    try {
      final bytes = await signing.stampPreview(stamp, date: widget.date);
      if (!mounted || generation != _generation) return;
      setState(() {
        _bytes = bytes;
        _shownKey = stamp.key;
        _problem = null;
      });
      widget.onLoaded?.call(stamp, bytes);
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _problem = failure.status == 429
            ? 'Too many previews at once. Wait a moment, then change something to see it again.'
            : failure.isNetwork
            ? 'The preview needs a connection.'
            : failure.fields.values.firstOrNull ?? failure.message,
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bytes = _bytes;
    final problem = widget.stamp.problem ?? _problem;
    return Semantics(
      image: true,
      label: 'Stamp: ${widget.stamp.toJson()['top_text']}',
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (bytes != null)
            Positioned.fill(
              child: Opacity(
                opacity: _shownKey == widget.stamp.key ? 1 : 0.45,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (bytes == null && problem != null)
            Padding(
              padding: const EdgeInsets.all(Space.x2),
              child: Text(
                problem,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ),
          if (_loading && bytes == null)
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// What the person chose in the stamp sheet, with its drawn image.
typedef StampAdoption = ({Stamp value, bool save, Uint8List? image});

/// "Adopt your stamp": the person types the stamp's text, chooses its shape
/// and ink, and sees it as it will be printed.
Future<StampAdoption?> showAdoptStamp(
  BuildContext context, {
  required String name,
  Stamp? current,
  bool canSave = false,
  DateTime? date,
  String action = 'Adopt and stamp',
}) => showModalBottomSheet<StampAdoption>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  builder: (_) => AdoptStampSheet(
    current: current ?? Stamp.forName(name),
    canSave: canSave,
    date: date,
    action: action,
  ),
);

class AdoptStampSheet extends StatefulWidget {
  const AdoptStampSheet({
    super.key,
    required this.current,
    this.canSave = false,
    this.date,
    this.action = 'Adopt and stamp',
  });

  final Stamp current;
  final bool canSave;
  final DateTime? date;
  final String action;

  @override
  State<AdoptStampSheet> createState() => _AdoptStampSheetState();
}

class _AdoptStampSheetState extends State<AdoptStampSheet> {
  late String _shape = widget.current.shape;
  late String _colour = widget.current.colour;
  late bool _date = widget.current.includeDate;
  late final _top = TextEditingController(text: widget.current.topText);
  late final _bottom = TextEditingController(text: widget.current.bottomText);
  late final List<TextEditingController> _lines = [
    for (final line in widget.current.centreLines)
      TextEditingController(text: line),
  ];
  late bool _save = widget.canSave;
  bool _tried = false;
  Uint8List? _image;
  String? _imageKey;

  @override
  void dispose() {
    for (final c in [_top, _bottom, ..._lines]) {
      c.dispose();
    }
    super.dispose();
  }

  Stamp get _stamp => Stamp(
    shape: _shape,
    colour: _colour,
    topText: _top.text,
    centreLines: [for (final c in _lines) c.text],
    bottomText: _bottom.text,
    includeDate: _date,
  );

  void _adopt() {
    final stamp = _stamp;
    if (stamp.problem != null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop<StampAdoption>(context, (
      value: stamp,
      save: widget.canSave && _save,
      image: _imageKey == stamp.key ? _image : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final stamp = _stamp;
    final topProblem = _tried && _top.text.trim().isEmpty
        ? 'Type the name on the stamp.'
        : null;
    void changed([_]) => setState(() {});

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Adopt your stamp', style: text.titleLarge),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Kept in view while the text below is edited.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              padding: const EdgeInsets.all(Space.x2),
              child: StampImage(
                stamp,
                key: const Key('stamp-preview'),
                date: widget.date,
                debounce: const Duration(milliseconds: 600),
                onLoaded: (drawn, bytes) {
                  _image = bytes;
                  _imageKey = drawn.key;
                },
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                0,
                Space.x4,
                Space.x4,
              ),
              children: [
                Text(
                  'Type what your company stamp says. We draw it like a rubber stamp; '
                  'text is printed in capitals.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.x4),
                Text('Shape', style: text.titleSmall),
                const SizedBox(height: Space.x2),
                SegmentedButton<String>(
                  key: const Key('stamp-shape'),
                  segments: [
                    for (final s in stampShapes)
                      ButtonSegment(value: s, label: Text(stampShapeLabel(s))),
                  ],
                  selected: {_shape},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _shape = s.first),
                ),
                const SizedBox(height: Space.x4),
                Text('Ink', style: text.titleSmall),
                const SizedBox(height: Space.x2),
                Wrap(
                  spacing: Space.x2,
                  runSpacing: Space.x2,
                  children: [
                    for (final ink in stampInks.entries)
                      ChoiceChip(
                        key: Key('stamp-ink-${ink.key}'),
                        avatar: CircleAvatar(backgroundColor: ink.value),
                        label: Text(stampInkLabel(ink.key)),
                        selected: _colour == ink.key,
                        onSelected: (_) => setState(() => _colour = ink.key),
                      ),
                  ],
                ),
                const SizedBox(height: Space.x4),
                TextField(
                  key: const Key('stamp-top'),
                  controller: _top,
                  maxLength: StampLimits.text,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: changed,
                  decoration: InputDecoration(
                    labelText: 'Name on the stamp',
                    helperText: _shape == 'RECTANGLE'
                        ? 'The first line, in bold'
                        : 'Runs around the top',
                    errorText: topProblem,
                  ),
                ),
                const SizedBox(height: Space.x2),
                for (var i = 0; i < _lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: Key('stamp-line-$i'),
                            controller: _lines[i],
                            maxLength: StampLimits.line,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: changed,
                            decoration: InputDecoration(
                              labelText: 'Middle line ${i + 1}',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove middle line ${i + 1}',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              setState(() => _lines.removeAt(i).dispose()),
                        ),
                      ],
                    ),
                  ),
                if (_lines.length < StampLimits.lines)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('stamp-add-line'),
                      onPressed: () =>
                          setState(() => _lines.add(TextEditingController())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a middle line, such as the town'),
                    ),
                  ),
                const SizedBox(height: Space.x2),
                TextField(
                  key: const Key('stamp-bottom'),
                  controller: _bottom,
                  maxLength: StampLimits.text,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: changed,
                  decoration: InputDecoration(
                    labelText: 'Bottom text (optional)',
                    helperText: _shape == 'RECTANGLE'
                        ? 'The last line, such as a registration number'
                        : 'Runs around the bottom, such as a registration number',
                  ),
                ),
                SwitchListTile(
                  key: const Key('stamp-date'),
                  contentPadding: EdgeInsets.zero,
                  value: _date,
                  onChanged: (v) => setState(() => _date = v),
                  title: const Text('Print the date it is stamped'),
                  subtitle: const Text(
                    'The signing date goes in the middle, like 16 NOV 2026.',
                  ),
                ),
                if (_tried && stamp.problem != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      stamp.problem!,
                      style: text.bodyMedium?.copyWith(color: c.danger),
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.canSave)
                      CheckboxListTile(
                        key: const Key('stamp-save'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _save,
                        onChanged: (v) => setState(() => _save = v ?? false),
                        title: const Text('Save it to my account'),
                      ),
                    FilledButton(
                      key: const Key('stamp-adopt'),
                      onPressed: _adopt,
                      child: Text(widget.action),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
