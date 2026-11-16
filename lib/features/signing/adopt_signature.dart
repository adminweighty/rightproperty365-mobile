import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import 'signing_repository.dart';

/// Ink for drawn signatures and typed previews: a dark blue, as on paper.
const _ink = Color(0xFF1B2A6B);

/// "Jane van der Berg" -> "JB".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '';
  final first = words.first.characters.first;
  final last = words.length > 1 ? words.last.characters.first : '';
  return (first + last).toUpperCase();
}

/// An adopted signature drawn inside its box: typed text in its script font,
/// or the drawn or uploaded picture.
class SignaturePreview extends StatelessWidget {
  const SignaturePreview(this.value, {super.key, this.color = _ink});

  final AdoptedSignature value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final image = value.image;
    if (image != null) {
      return Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          value.text ?? '',
          style: TextStyle(
            fontFamily: signatureFontFamilies[value.font] ?? 'GreatVibes',
            fontSize: 40,
            color: color,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// What the person chose in the sheet.
typedef Adoption = ({AdoptedSignature value, bool save});

/// The "Adopt your signature" sheet, as in Adobe Acrobat Sign: type it in a
/// script style, draw it, or upload a picture of it.
Future<Adoption?> showAdoptSignature(
  BuildContext context, {
  required bool initials,
  required String name,
  required List<SignatureFont> fonts,
  AdoptedSignature? current,
  bool canSave = false,
}) => showModalBottomSheet<Adoption>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Swiping the sheet away would fight with drawing a signature.
  enableDrag: false,
  builder: (_) => AdoptSignatureSheet(
    initials: initials,
    name: name,
    fonts: fonts.isEmpty ? SignatureFont.fallback : fonts,
    current: current,
    canSave: canSave,
  ),
);

class AdoptSignatureSheet extends StatefulWidget {
  const AdoptSignatureSheet({
    super.key,
    required this.initials,
    required this.name,
    required this.fonts,
    this.current,
    this.canSave = false,
  });

  final bool initials;
  final String name;
  final List<SignatureFont> fonts;
  final AdoptedSignature? current;
  final bool canSave;

  @override
  State<AdoptSignatureSheet> createState() => _AdoptSignatureSheetState();
}

class _AdoptSignatureSheetState extends State<AdoptSignatureSheet>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: switch (widget.current?.kind) {
      SignatureKind.drawn => 1,
      SignatureKind.uploaded => 2,
      _ => 0,
    },
  );
  late final _typed = TextEditingController(
    text: widget.current?.kind == SignatureKind.typed
        ? widget.current!.text
        : widget.initials
        ? initialsOf(widget.name)
        : widget.name,
  );
  late String _font = widget.current?.font ?? widget.fonts.first.key;
  final _strokes = <List<Offset>>[];
  Size _padSize = Size.zero;
  Uint8List? _uploaded;
  bool _save = false;
  String? _problem;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    if (widget.current?.kind == SignatureKind.uploaded) {
      _uploaded = widget.current!.image;
    }
    _tabs.addListener(() => setState(() => _problem = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _typed.dispose();
    super.dispose();
  }

  String get _what => widget.initials ? 'initials' : 'signature';

  /// The drawing as a PNG, on a transparent background, at twice the pad's
  /// size (inside the API's 2000 x 1000 pixel limit).
  Future<Uint8List> _drawnPng() async {
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    _SignaturePainter(_strokes).paint(canvas, _padSize);
    final picture = recorder.endRecording();
    final width = (_padSize.width * scale).round().clamp(20, 2000);
    final height = (_padSize.height * scale).round().clamp(10, 1000);
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _pick() async {
    final bytes = await AppScope.of(context).pickSignatureImage();
    if (bytes == null || !mounted) return;
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final jpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    setState(() {
      if (!png && !jpeg) {
        _problem = 'Use a PNG or JPEG picture.';
      } else if (bytes.length > 500 * 1024) {
        _problem = 'That picture is larger than 500 KB. Crop it or choose a smaller one.';
      } else {
        _problem = null;
        _uploaded = bytes;
      }
    });
  }

  Future<void> _adopt() async {
    setState(() => _problem = null);
    AdoptedSignature? value;
    switch (_tabs.index) {
      case 0:
        final text = _typed.text.trim();
        if (text.isEmpty) {
          setState(() => _problem = 'Type your $_what.');
          return;
        }
        if (text.characters.length > 120) {
          setState(() => _problem = 'Use 120 characters or fewer.');
          return;
        }
        value = AdoptedSignature.typed(text, font: _font);
      case 1:
        if (_strokes.every((s) => s.length < 2)) {
          setState(() => _problem = 'Draw your $_what in the box.');
          return;
        }
        setState(() => _working = true);
        final png = await _drawnPng();
        if (!mounted) return;
        setState(() => _working = false);
        if (png.length > 200 * 1024) {
          setState(
            () => _problem =
                'The drawing is too detailed. Clear it and draw again.',
          );
          return;
        }
        value = AdoptedSignature.image(SignatureKind.drawn, png);
      case 2:
        final picture = _uploaded;
        if (picture == null) {
          setState(() => _problem = 'Choose a picture of your $_what.');
          return;
        }
        value = AdoptedSignature.image(SignatureKind.uploaded, picture);
    }
    if (mounted) Navigator.pop(context, (value: value!, save: _save));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // The tabs take what the title and the button leave, at any text size.
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x2,
                Space.x1,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initials
                          ? 'Adopt your initials'
                          : 'Adopt your signature',
                      style: text.titleLarge,
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
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Type'),
                Tab(text: 'Draw'),
                Tab(text: 'Upload'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                // Swiping would fight with drawing.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _typeTab(context),
                  _drawTab(context),
                  _uploadTab(context),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Space.x4,
                  0,
                  Space.x4,
                  Space.x4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_problem != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.x2),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _problem!,
                            style: text.bodyMedium?.copyWith(color: c.danger),
                          ),
                        ),
                      ),
                    if (widget.canSave)
                      CheckboxListTile(
                        key: const Key('adopt-save'),
                        value: _save,
                        onChanged: (value) =>
                            setState(() => _save = value ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Save to my account for next time'),
                      ),
                    Text(
                      'By choosing Adopt and sign, I agree that this $_what is the electronic '
                      'representation of my $_what for all purposes when I use it on documents.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: Space.x3),
                    FilledButton(
                      key: const Key('adopt-confirm'),
                      onPressed: _working ? null : _adopt,
                      child: const Text('Adopt and sign'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTab(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        TextField(
          key: const Key('adopt-typed'),
          controller: _typed,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.initials ? 'Your initials' : 'Your full name',
          ),
        ),
        RadioGroup<String>(
          groupValue: _font,
          onChanged: (value) => setState(() => _font = value!),
          child: Column(
            children: [
              for (final font in widget.fonts)
                RadioListTile<String>(
                  key: Key('adopt-font-${font.key}'),
                  value: font.key,
                  contentPadding: EdgeInsets.zero,
                  title: SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SignaturePreview(
                        AdoptedSignature.typed(
                          _typed.text.trim().isEmpty
                              ? widget.name
                              : _typed.text.trim(),
                          font: font.key,
                        ),
                      ),
                    ),
                  ),
                  subtitle: Text(font.label, style: TextStyle(color: c.muted)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawTab(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Draw your $_what with your finger.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.x2),
          Expanded(
            child: Semantics(
              label: 'Drawing area for your $_what',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _padSize = constraints.biggest;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: c.lineStrong),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: ClipRect(
                      child: GestureDetector(
                        key: const Key('adopt-pad'),
                        onPanStart: (d) =>
                            setState(() => _strokes.add([d.localPosition])),
                        onPanUpdate: (d) =>
                            setState(() => _strokes.last.add(d.localPosition)),
                        child: CustomPaint(
                          painter: _SignaturePainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('adopt-clear'),
              onPressed: () => setState(_strokes.clear),
              icon: const Icon(Icons.refresh),
              label: const Text('Clear'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadTab(BuildContext context) {
    final c = context.colors;
    final picture = _uploaded;
    return Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'A photo of your $_what on white paper. PNG or JPEG, at most 500 KB.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.x3),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: c.lineStrong),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: picture == null
                  ? Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: 40,
                        color: c.subtle,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(Space.x2),
                      child: Image.memory(picture, fit: BoxFit.contain),
                    ),
            ),
          ),
          const SizedBox(height: Space.x3),
          OutlinedButton.icon(
            key: const Key('adopt-pick'),
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              picture == null ? 'Choose a picture' : 'Choose another',
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.4, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
