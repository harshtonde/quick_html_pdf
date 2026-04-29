/// JavaScript interop bindings for jsPDF — the only JS library used by the
/// vector pipeline. Pagination is handled in Dart by [CustomPaginator]; this
/// file only deals with jsPDF.
///
/// jsPDF is bundled as a Flutter package asset (`assets/jspdf.umd.min.js`)
/// and lazy-loaded into the parent window's globals on the first vector-mode
/// `generate()` call. See [JsLibraries.bootstrapJsPdf].
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import '../exceptions.dart';

// ---------------------------------------------------------------------------
// jsPDF global access
// ---------------------------------------------------------------------------

/// Top-level `jspdf` global once the bundled UMD has been evaluated.
@JS('jspdf')
external JSObject? get _jspdfGlobal;

/// `globalThis.eval` — used once at bootstrap to inject the bundled UMD.
@JS('eval')
external JSAny? _globalEval(JSString source);

// ---------------------------------------------------------------------------
// jsPDF class
// ---------------------------------------------------------------------------

/// jsPDF document class. Construct with [JsLibraries.createPdf].
@JS('jspdf.jsPDF')
@staticInterop
class JsPDF {
  external factory JsPDF([JSObject? options]);
}

extension JsPDFExtension on JsPDF {
  // raw bindings (private)

  @JS('addImage')
  external void _addImage(
    JSAny imageData,
    JSString format,
    JSNumber x,
    JSNumber y,
    JSNumber width,
    JSNumber height,
  );

  @JS('addPage')
  external void _addPage([JSString? format, JSString? orientation]);

  @JS('output')
  external JSAny _output(JSString type);

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
    JSAny text,
    JSNumber x,
    JSNumber y, [
    JSObject? options,
  ]);

  @JS('setFontSize')
  external void _setFontSize(JSNumber size);

  @JS('setTextColor')
  external void _setTextColor(JSNumber r, [JSNumber? g, JSNumber? b]);

  @JS('setDrawColor')
  external void _setDrawColor(JSNumber r, [JSNumber? g, JSNumber? b]);

  @JS('setFillColor')
  external void _setFillColor(JSNumber r, [JSNumber? g, JSNumber? b]);

  @JS('setLineWidth')
  external void _setLineWidth(JSNumber width);

  @JS('line')
  external void _line(JSNumber x1, JSNumber y1, JSNumber x2, JSNumber y2);

  @JS('rect')
  external void _rect(
    JSNumber x,
    JSNumber y,
    JSNumber w,
    JSNumber h, [
    JSString? style,
  ]);

  @JS('setFont')
  external void _setFont(JSString fontName, [JSString? fontStyle]);

  @JS('getTextWidth')
  external JSNumber _getTextWidth(JSString text);

  @JS('getStringUnitWidth')
  external JSNumber _getStringUnitWidth(JSString text);

  @JS('addFileToVFS')
  external void _addFileToVFS(JSString filename, JSString base64);

  @JS('addFont')
  external void _addFont(
    JSString postScriptName,
    JSString fontName,
    JSString fontStyle,
  );

  // friendly wrappers (public)

  /// Add an image given as a base64 data URL or other string accepted by
  /// jsPDF's `addImage` (e.g. `'data:image/png;base64,...'`).
  ///
  /// For `<img>` elements, prefer [addImageElement] — it skips the data-URL
  /// round trip.
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

  /// Add an `<img>` element directly (no fetch / base64 round-trip).
  void addImageElement({
    required web.HTMLImageElement element,
    required String format,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    _addImage(
      element as JSAny,
      format.toJS,
      x.toJS,
      y.toJS,
      width.toJS,
      height.toJS,
    );
  }

  /// Add a new page. Format/orientation default to the document's settings.
  void addPage({String? format, String? orientation}) {
    _addPage(format?.toJS, orientation?.toJS);
  }

  /// Get PDF as `Uint8List` (calls `output('arraybuffer')`).
  Uint8List getBytes() {
    final result = _output('arraybuffer'.toJS);
    return (result as JSArrayBuffer).toDart.asUint8List();
  }

  /// Get PDF as a `Blob` (calls `output('blob')`). Avoids a Uint8List copy
  /// when the consumer wants to download via Blob URL.
  web.Blob getBlob() {
    return _output('blob'.toJS) as web.Blob;
  }

  /// Trigger a browser download via jsPDF's built-in `save()`.
  void save(String filename) => _save(filename.toJS);

  /// Page size in document units (pt for unit:'pt').
  (double width, double height) getPageSize() {
    final pageSize = _internal.getProperty('pageSize'.toJS) as JSObject;
    final width =
        (pageSize.getProperty('width'.toJS) as JSNumber).toDartDouble;
    final height =
        (pageSize.getProperty('height'.toJS) as JSNumber).toDartDouble;
    return (width, height);
  }

  void setPage(int pageNumber) => _setPage(pageNumber.toJS);

  int getNumberOfPages() => _getNumberOfPages().toDartInt;

  /// Emit text at (x, y). Optional jsPDF text options:
  /// - [align]: `'left'` | `'center'` | `'right'` | `'justify'`
  /// - [maxWidth]: wrap to this width if the string is longer
  /// - [charSpace]: extra space between characters in pt (CSS letter-spacing)
  /// - [angle]: rotation in degrees
  /// - [baseline]: jsPDF baseline keyword
  void text(
    String text,
    double x,
    double y, {
    String? align,
    double? maxWidth,
    double? charSpace,
    double? angle,
    String? baseline,
  }) {
    final hasOptions = align != null ||
        maxWidth != null ||
        charSpace != null ||
        angle != null ||
        baseline != null;
    if (hasOptions) {
      final options = <String, dynamic>{};
      if (align != null) options['align'] = align;
      if (maxWidth != null) options['maxWidth'] = maxWidth;
      if (charSpace != null) options['charSpace'] = charSpace;
      if (angle != null) options['angle'] = angle;
      if (baseline != null) options['baseline'] = baseline;
      _text(text.toJS, x.toJS, y.toJS, options.jsify() as JSObject);
    } else {
      _text(text.toJS, x.toJS, y.toJS);
    }
  }

  void setFontSize(double size) => _setFontSize(size.toJS);

  void setTextColor(int r, [int? g, int? b]) {
    if (g != null && b != null) {
      _setTextColor(r.toJS, g.toJS, b.toJS);
    } else {
      _setTextColor(r.toJS);
    }
  }

  void setDrawColor(int r, [int? g, int? b]) {
    if (g != null && b != null) {
      _setDrawColor(r.toJS, g.toJS, b.toJS);
    } else {
      _setDrawColor(r.toJS);
    }
  }

  void setFillColor(int r, [int? g, int? b]) {
    if (g != null && b != null) {
      _setFillColor(r.toJS, g.toJS, b.toJS);
    } else {
      _setFillColor(r.toJS);
    }
  }

  void setLineWidth(double width) => _setLineWidth(width.toJS);

  void line(double x1, double y1, double x2, double y2) =>
      _line(x1.toJS, y1.toJS, x2.toJS, y2.toJS);

  /// Draw a rectangle. [style] is `'S'` (stroke, default), `'F'` (fill), or
  /// `'FD'` (both).
  void rect(double x, double y, double w, double h, {String style = 'S'}) {
    _rect(x.toJS, y.toJS, w.toJS, h.toJS, style.toJS);
  }

  void setFont(String fontName, [String? fontStyle]) {
    if (fontStyle != null) {
      _setFont(fontName.toJS, fontStyle.toJS);
    } else {
      _setFont(fontName.toJS);
    }
  }

  /// Width of the text in current-font units. Useful for width-sanity checks.
  double getTextWidth(String text) => _getTextWidth(text.toJS).toDartDouble;

  /// Width of the text in font's design units (1000ths of em). Multiply by
  /// font size in pt to get measured width in pt.
  double getStringUnitWidth(String text) =>
      _getStringUnitWidth(text.toJS).toDartDouble;

  /// Add a TTF (base64-encoded) to jsPDF's virtual file system.
  void addFileToVFS(String filename, String base64) =>
      _addFileToVFS(filename.toJS, base64.toJS);

  /// Register the loaded VFS file as a font under [fontName] / [fontStyle].
  void addFont(String postScriptName, String fontName, String fontStyle) =>
      _addFont(postScriptName.toJS, fontName.toJS, fontStyle.toJS);
}

// ---------------------------------------------------------------------------
// Library bootstrap & factory
// ---------------------------------------------------------------------------

class JsLibraries {
  JsLibraries._();

  static bool _bootstrapped = false;
  static Future<void>? _bootstrapFuture;

  /// Whether jsPDF has been loaded into the parent window globals.
  static bool get isJsPdfAvailable => _jspdfGlobal != null;

  /// Load the bundled jsPDF UMD into the parent window once.
  ///
  /// Idempotent and concurrency-safe: subsequent / concurrent calls await
  /// the same future and return when bootstrap completes.
  ///
  /// The bundled UMD checks for `module.exports` (not present in the browser
  /// global scope), so it falls through to the global-attach branch and sets
  /// `globalThis.jspdf = { jsPDF: ... }`.
  static Future<void> bootstrapJsPdf() {
    if (_bootstrapped) return Future.value();
    return _bootstrapFuture ??= _doBootstrap();
  }

  static Future<void> _doBootstrap() async {
    if (isJsPdfAvailable) {
      _bootstrapped = true;
      return;
    }
    try {
      final src = await rootBundle.loadString(
        'packages/quick_html_pdf/assets/jspdf.umd.min.js',
      );
      _globalEval(src.toJS);
    } catch (e) {
      throw PdfGenerationException(
        'Failed to load jsPDF from package assets',
        phase: PdfGenerationPhase.pdfAssembly,
        code: 'jspdf-bootstrap-failed',
        cause: e,
      );
    }
    if (!isJsPdfAvailable) {
      throw const PdfGenerationException(
        'jsPDF UMD evaluated but global "jspdf" is missing',
        phase: PdfGenerationPhase.pdfAssembly,
        code: 'jspdf-bootstrap-failed',
      );
    }
    _bootstrapped = true;
  }

  /// Create a new jsPDF instance. Must call [bootstrapJsPdf] first.
  ///
  /// Defaults match v3's vector pipeline expectations:
  /// - `unit: 'pt'` so coordinate math (`cssPx * 0.75`) is a direct multiply.
  /// - `compress: false` for faster generation; user can set true via raw
  ///   options if they want smaller files.
  /// - `putOnlyUsedFonts: true` keeps file size down when many fonts are
  ///   registered.
  static JsPDF createPdf({
    String orientation = 'portrait',
    String unit = 'pt',
    String format = 'a4',
    bool compress = false,
    bool putOnlyUsedFonts = true,
  }) {
    if (!isJsPdfAvailable) {
      throw const PdfGenerationException(
        'jsPDF not loaded — call JsLibraries.bootstrapJsPdf() first',
        phase: PdfGenerationPhase.pdfAssembly,
        code: 'jspdf-not-bootstrapped',
      );
    }
    final options = <String, dynamic>{
      'orientation': orientation,
      'unit': unit,
      'format': format,
      'compress': compress,
      'putOnlyUsedFonts': putOnlyUsedFonts,
    }.jsify() as JSObject;
    return JsPDF(options);
  }
}
