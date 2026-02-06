/// JavaScript interop bindings for html2canvas, jsPDF, and html2pdf.
///
/// These bindings provide typed access to the JS libraries
/// required for byte-mode PDF generation.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Check if html2canvas is available.
@JS('html2canvas')
external JSFunction? get _html2canvasFunction;

/// Check if jsPDF is available.
@JS('jspdf')
external JSObject? get _jspdfModule;

/// Check if html2pdf is available.
@JS('html2pdf')
external JSFunction? get _html2pdfFunction;

/// Call html2canvas to render an element to canvas.
@JS('html2canvas')
external JSPromise<web.HTMLCanvasElement> _html2canvas(
  web.Element element,
  JSObject options,
);

/// Call html2pdf to convert an element to PDF.
@JS('html2pdf')
external Html2PdfBuilder _html2pdf();

/// html2pdf.js builder class for chained API.
@JS()
@staticInterop
class Html2PdfBuilder {}

/// html2pdf.js builder extension methods.
extension Html2PdfBuilderExtension on Html2PdfBuilder {
  @JS('set')
  external Html2PdfBuilder _set(JSObject options);

  @JS('from')
  external Html2PdfBuilder _from(web.Element element);

  @JS('toPdf')
  external Html2PdfBuilder _toPdf();

  @JS('get')
  external JSPromise<JSAny> _get(JSString type);

  @JS('outputPdf')
  external JSPromise<JSAny> _outputPdf(JSString type);

  /// Configure html2pdf options.
  Html2PdfBuilder set(Map<String, dynamic> options) {
    return _set(options.jsify() as JSObject);
  }

  /// Set the source element.
  Html2PdfBuilder from(web.Element element) {
    return _from(element);
  }

  /// Convert to PDF.
  Html2PdfBuilder toPdf() {
    return _toPdf();
  }

  /// Get the jsPDF instance after conversion.
  Future<JsPDF> getPdf() async {
    final result = await _get('pdf'.toJS).toDart;
    return result as JsPDF;
  }

  /// Get PDF as arraybuffer.
  Future<Uint8List> getArrayBuffer() async {
    final result = await _outputPdf('arraybuffer'.toJS).toDart;
    // JavaScript returns ArrayBuffer, convert properly:
    // JSArrayBuffer → ByteBuffer → Uint8List
    final arrayBuffer = result as JSArrayBuffer;
    return arrayBuffer.toDart.asUint8List();
  }
}

/// jsPDF class constructor.
@JS('jspdf.jsPDF')
@staticInterop
class JsPDF {
  external factory JsPDF([JSObject? options]);
}

/// jsPDF instance methods.
extension JsPDFExtension on JsPDF {
  @JS('addImage')
  external void _addImage(
    JSString imageData,
    JSString format,
    JSNumber x,
    JSNumber y,
    JSNumber width,
    JSNumber height,
  );

  @JS('addPage')
  external void _addPage([JSString? format, JSString? orientation]);

  @JS('output')
  external JSArrayBuffer _output(JSString type);

  @JS('save')
  external void _save(JSString filename);

  @JS('internal')
  external JSObject get _internal;

  @JS('setPage')
  external void _setPage(JSNumber pageNumber);

  @JS('getNumberOfPages')
  external JSNumber _getNumberOfPages();

  @JS('text')
  external void _text(
    JSString text,
    JSNumber x,
    JSNumber y, [
    JSObject? options,
  ]);

  @JS('setFontSize')
  external void _setFontSize(JSNumber size);

  @JS('setTextColor')
  external void _setTextColor(
    JSNumber r, [
    JSNumber? g,
    JSNumber? b,
  ]);

  @JS('setDrawColor')
  external void _setDrawColor(
    JSNumber r, [
    JSNumber? g,
    JSNumber? b,
  ]);

  @JS('setLineWidth')
  external void _setLineWidth(JSNumber width);

  @JS('line')
  external void _line(
    JSNumber x1,
    JSNumber y1,
    JSNumber x2,
    JSNumber y2,
  );

  @JS('setFont')
  external void _setFont(
    JSString fontName, [
    JSString? fontStyle,
  ]);

  @JS('getTextWidth')
  external JSNumber _getTextWidth(JSString text);

  /// Add an image to the current page.
  void addImage({
    required String imageData,
    required String format,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    _addImage(
      imageData.toJS,
      format.toJS,
      x.toJS,
      y.toJS,
      width.toJS,
      height.toJS,
    );
  }

  /// Add a new page to the PDF.
  void addPage({String? format, String? orientation}) {
    _addPage(format?.toJS, orientation?.toJS);
  }

  /// Get PDF as Uint8List.
  Uint8List getBytes() {
    // JavaScript returns ArrayBuffer, convert properly:
    // JSArrayBuffer → ByteBuffer → Uint8List
    final arrayBuffer = _output('arraybuffer'.toJS);
    return arrayBuffer.toDart.asUint8List();
  }

  /// Save PDF to file (triggers download).
  void save(String filename) {
    _save(filename.toJS);
  }

  /// Get page size info.
  (double width, double height) getPageSize() {
    final internal = _internal;
    final pageSize = internal.getProperty('pageSize'.toJS) as JSObject;
    final width = (pageSize.getProperty('width'.toJS) as JSNumber).toDartDouble;
    final height =
        (pageSize.getProperty('height'.toJS) as JSNumber).toDartDouble;
    return (width, height);
  }

  /// Set the current page for editing.
  void setPage(int pageNumber) {
    _setPage(pageNumber.toJS);
  }

  /// Get the total number of pages.
  int getNumberOfPages() {
    return _getNumberOfPages().toDartInt;
  }

  /// Add text to the current page.
  void text(
    String text,
    double x,
    double y, {
    String? align,
    double? maxWidth,
  }) {
    if (align != null || maxWidth != null) {
      final options = <String, dynamic>{};
      if (align != null) options['align'] = align;
      if (maxWidth != null) options['maxWidth'] = maxWidth;
      _text(text.toJS, x.toJS, y.toJS, options.jsify() as JSObject);
    } else {
      _text(text.toJS, x.toJS, y.toJS);
    }
  }

  /// Set font size in points.
  void setFontSize(double size) {
    _setFontSize(size.toJS);
  }

  /// Set text color (RGB values 0-255 or grayscale).
  void setTextColor(int r, [int? g, int? b]) {
    if (g != null && b != null) {
      _setTextColor(r.toJS, g.toJS, b.toJS);
    } else {
      _setTextColor(r.toJS);
    }
  }

  /// Set draw color for lines (RGB values 0-255 or grayscale).
  void setDrawColor(int r, [int? g, int? b]) {
    if (g != null && b != null) {
      _setDrawColor(r.toJS, g.toJS, b.toJS);
    } else {
      _setDrawColor(r.toJS);
    }
  }

  /// Set line width in the document's unit.
  void setLineWidth(double width) {
    _setLineWidth(width.toJS);
  }

  /// Draw a line from (x1, y1) to (x2, y2).
  void line(double x1, double y1, double x2, double y2) {
    _line(x1.toJS, y1.toJS, x2.toJS, y2.toJS);
  }

  /// Set font (name and optionally style).
  void setFont(String fontName, [String? fontStyle]) {
    if (fontStyle != null) {
      _setFont(fontName.toJS, fontStyle.toJS);
    } else {
      _setFont(fontName.toJS);
    }
  }

  /// Get the width of text in the current font.
  double getTextWidth(String text) {
    return _getTextWidth(text.toJS).toDartDouble;
  }
}

/// High-level wrapper for JS library operations.
class JsLibraries {
  /// Check if required JS libraries are loaded (legacy mode).
  static bool get isAvailable {
    return _html2canvasFunction != null && _jspdfModule != null;
  }

  /// Check if html2pdf.js is available (preferred mode).
  static bool get isHtml2PdfAvailable {
    return _html2pdfFunction != null;
  }

  /// Throw if libraries are not available.
  static void ensureAvailable() {
    if (!isAvailable) {
      throw StateError(
        'Required JS libraries not loaded. '
        'Please add html2canvas and jsPDF scripts to your index.html:\n'
        '<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>\n'
        '<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>',
      );
    }
  }

  /// Throw if html2pdf.js is not available.
  static void ensureHtml2PdfAvailable() {
    if (!isHtml2PdfAvailable) {
      throw StateError(
        'html2pdf.js library not loaded. '
        'Please add the html2pdf.js script to your index.html:\n'
        '<script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>',
      );
    }
  }

  /// Create an html2pdf builder instance.
  static Html2PdfBuilder createHtml2Pdf() {
    ensureHtml2PdfAvailable();
    return _html2pdf();
  }

  /// Render an element to canvas using html2canvas.
  static Future<web.HTMLCanvasElement> html2canvas(
    web.Element element, {
    double scale = 1.5,
    bool useCORS = true,
    bool allowTaint = false,
    String backgroundColor = '#ffffff',
    int? width,
    int? height,
    int? x,
    int? y,
    int? windowWidth,
    int? windowHeight,
    int? scrollX,
    int? scrollY,
  }) async {
    ensureAvailable();

    final options = <String, dynamic>{
      'scale': scale,
      'useCORS': useCORS,
      'allowTaint': allowTaint,
      'backgroundColor': backgroundColor,
      'logging': false,
    };

    if (width != null) options['width'] = width;
    if (height != null) options['height'] = height;
    if (x != null) options['x'] = x;
    if (y != null) options['y'] = y;
    if (windowWidth != null) options['windowWidth'] = windowWidth;
    if (windowHeight != null) options['windowHeight'] = windowHeight;
    if (scrollX != null) options['scrollX'] = scrollX;
    if (scrollY != null) options['scrollY'] = scrollY;

    final jsOptions = options.jsify() as JSObject;
    final canvas = await _html2canvas(element, jsOptions).toDart;
    return canvas;
  }

  /// Create a new jsPDF instance.
  static JsPDF createPdf({
    String orientation = 'portrait',
    String unit = 'mm',
    String format = 'a4',
  }) {
    ensureAvailable();

    final options =
        {'orientation': orientation, 'unit': unit, 'format': format}.jsify()
            as JSObject;

    return JsPDF(options);
  }
}
