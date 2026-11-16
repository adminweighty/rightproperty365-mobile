import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/async_view.dart';

/// An opened PDF: its page sizes in points and a way to draw each page.
abstract interface class OpenPdf {
  List<Size> get pageSizes;

  /// Page [index] (from 0) drawn [pixelWidth] pixels wide, or null when it
  /// cannot be drawn.
  Future<ui.Image?> render(int index, int pixelWidth);

  Future<void> close();
}

/// Opens PDF bytes. Replaced in tests, where no PDF engine is loaded.
abstract interface class PdfRenderer {
  Future<OpenPdf> open(Uint8List bytes);
}

/// The phone's own PDF renderer (Android PdfRenderer, iOS PDFKit) through
/// `package:pdfx`.
class PlatformPdfRenderer implements PdfRenderer {
  const PlatformPdfRenderer();

  @override
  Future<OpenPdf> open(Uint8List bytes) async {
    final document = await pdfx.PdfDocument.openData(bytes);
    final sizes = <Size>[];
    for (var number = 1; number <= document.pagesCount; number++) {
      final page = await document.getPage(number);
      sizes.add(Size(page.width, page.height));
      await page.close();
    }
    return _PlatformDocument(document, sizes);
  }
}

class _PlatformDocument implements OpenPdf {
  _PlatformDocument(this._document, this.pageSizes);

  final pdfx.PdfDocument _document;

  @override
  final List<Size> pageSizes;

  @override
  Future<ui.Image?> render(int index, int pixelWidth) async {
    if (_document.isClosed) return null;
    final size = pageSizes[index];
    final page = await _document.getPage(index + 1);
    try {
      final rendered = await page.render(
        width: pixelWidth.toDouble(),
        height: (pixelWidth * size.height / size.width).roundToDouble(),
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (rendered == null) return null;
      final codec = await ui.instantiateImageCodec(rendered.bytes);
      return (await codec.getNextFrame()).image;
    } finally {
      await page.close();
    }
  }

  @override
  Future<void> close() async {
    if (!_document.isClosed) await _document.close();
  }
}

/// Builds what lies over one page. [scale] turns PDF points into pixels on
/// screen; the origin is the page's top left.
typedef PageOverlay = List<Widget> Function(int pageNumber, double scale);

/// Every page of [pdf], one under the other, at the available width, with an
/// optional [overlay] (the signing fields).
class PdfPageColumn extends StatelessWidget {
  const PdfPageColumn({
    super.key,
    required this.pdf,
    required this.label,
    this.overlay,
  });

  final OpenPdf pdf;
  final String label;
  final PageOverlay? overlay;

  @override
  Widget build(BuildContext context) {
    final sizes = pdf.pageSizes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          children: [
            for (var i = 0; i < sizes.length; i++) ...[
              Semantics(
                container: true,
                // The fields over the page stay their own buttons.
                explicitChildNodes: true,
                label: '$label, page ${i + 1} of ${sizes.length}',
                child: _Page(
                  pdf: pdf,
                  index: i,
                  width: width,
                  size: sizes[i],
                  overlay: overlay?.call(i + 1, width / sizes[i].width),
                ),
              ),
              const SizedBox(height: Space.x3),
            ],
          ],
        );
      },
    );
  }
}

class _Page extends StatefulWidget {
  const _Page({
    required this.pdf,
    required this.index,
    required this.width,
    required this.size,
    this.overlay,
  });

  final OpenPdf pdf;
  final int index;
  final double width;
  final Size size;
  final List<Widget>? overlay;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  ui.Image? _image;
  int _drawnWidth = 0;
  bool _drawing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _draw();
  }

  @override
  void didUpdateWidget(_Page old) {
    super.didUpdateWidget(old);
    if (old.pdf != widget.pdf || old.width != widget.width) _draw();
  }

  Future<void> _draw() async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // Sharp on a phone without drawing posters: at most 1600 pixels wide.
    final pixels = (widget.width * ratio).clamp(200, 1600).round();
    if (pixels == _drawnWidth && _image != null) return;
    _drawnWidth = pixels;
    setState(() => _drawing = true);
    final image = await widget.pdf.render(widget.index, pixels);
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _drawing = false;
      _image?.dispose();
      _image = image;
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * widget.size.height / widget.size.width;
    final image = _image;
    return Container(
      width: widget.width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: context.colors.line),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: image != null
                ? RawImage(image: image, fit: BoxFit.fill)
                : _drawing
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          ),
          ...?widget.overlay,
        ],
      ),
    );
  }
}

/// A PDF on its own screen: a lease draft, a signed document.
class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.title, required this.load});

  final String title;
  final Future<Uint8List> Function() load;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  Future<OpenPdf>? _pdf;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pdf ??= _open();
  }

  Future<OpenPdf> _open() async =>
      AppScope.of(context).pdf.open(await widget.load());

  @override
  void dispose() {
    _pdf?.then((pdf) => pdf.close(), onError: (_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: context.colors.sunken,
      body: FutureBuilder<OpenPdf>(
        future: _pdf,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return MessageView(
              icon: Icons.picture_as_pdf_outlined,
              title: 'We could not open the PDF',
              body: error is ApiFailure
                  ? error.message
                  : 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: () => setState(() {
                _pdf = _open();
              }),
            );
          }
          final pdf = snapshot.data;
          if (pdf == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            maxScale: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x3),
              child: PdfPageColumn(pdf: pdf, label: widget.title),
            ),
          );
        },
      ),
    );
  }
}
