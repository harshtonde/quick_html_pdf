/// JavaScript interop bindings for html2canvas and jsPDF.
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

/// Call html2canvas to render an element to canvas.
@JS('html2canvas')
external JSPromise<web.HTMLCanvasElement> _html2canvas(
  web.Element element,
  JSObject options,
);

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
  external JSUint8Array _output(JSString type);

  @JS('save')
  external void _save(JSString filename);

  @JS('internal')
  external JSObject get _internal;

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
    final jsArray = _output('arraybuffer'.toJS);
    return jsArray.toDart;
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
}

/// High-level wrapper for JS library operations.
class JsLibraries {
  /// Check if required JS libraries are loaded.
  static bool get isAvailable {
    return _html2canvasFunction != null && _jspdfModule != null;
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
