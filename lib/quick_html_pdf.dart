/// QuickHtmlPdf — fast HTML to vector PDF for Flutter Web.
///
/// Converts HTML templates with dynamic data into PDFs via:
///
/// - **`PdfOutput.print`**    → browser's native print dialog (user picks
///   "Save as PDF"). No JS deps invoked at runtime, no asset bootstrap.
/// - **`PdfOutput.download`** → silent file save. Uses a custom measure-and-
///   flow paginator + jsPDF (vendored) for vector emission, driven by a
///   custom DOM walker.
/// - **`PdfOutput.bytes`**    → returns `Uint8List` for upload / processing.
///   Same pipeline as `download`; only delivery differs.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:quick_html_pdf/quick_html_pdf.dart';
///
/// // Print mode — no setup beyond pub get.
/// await QuickHtmlPdf.generate(
///   htmlTemplate: '<h1>Hello {{name}}</h1>',
///   data: {'name': 'World'},
///   options: PdfOptions(output: PdfOutput.print),
/// );
///
/// // Download mode — silent save. Requires a registered font.
/// await QuickHtmlPdf.generate(
///   htmlTemplate: '<h1>Hello {{name}}</h1>',
///   data: {'name': 'World'},
///   options: PdfOptions(
///     output: PdfOutput.download,
///     filename: 'hello.pdf',
///     fonts: [
///       PdfFont(
///         family: 'Liberation Sans',
///         src: 'assets/fonts/LiberationSans-Regular.ttf',
///       ),
///     ],
///   ),
/// );
///
/// // Bytes mode — for upload / processing.
/// final bytes = await QuickHtmlPdf.generate(
///   htmlTemplate: '<h1>Hello {{name}}</h1>',
///   data: {'name': 'World'},
///   options: PdfOptions(output: PdfOutput.bytes, fonts: [/*…*/]),
/// );
/// // bytes is a Uint8List
/// ```
///
/// ## Template Syntax
///
/// - `{{key}}` — HTML-escaped interpolation
/// - `{{nested.path}}` — dot notation for nested objects
/// - `{{{rawHtml}}}` — unescaped HTML insertion
/// - `{{#each items}}…{{/each}}` — loop blocks
/// - `{{this.field}}` — current item in loop
/// - `{{@index}}` — 0-based loop index
///
/// In header/footer:
/// - `{{page}}`, `{{pages}}` — current and total page numbers
/// - `{{date}}`, `{{time}}`, `{{datetime}}` — current local date/time
///
/// ## Custom Fonts (required for vector modes)
///
/// `PdfOutput.download` and `PdfOutput.bytes` require at least one font
/// registered via `PdfOptions.fonts`. Without a registered font, the
/// renderer throws `PdfGenerationException(code: 'no-fonts-registered')`.
///
/// `PdfOutput.print` does not require font registration — it uses the
/// browser's native print engine which has access to system fonts.
///
/// ## Platform Support
///
/// Web only. Throws `UnsupportedError` on mobile and desktop.
library;

import 'dart:typed_data';

import 'src/options.dart';

// Conditional imports for platform-specific implementation.
import 'src/stub/quick_html_pdf_stub.dart'
    if (dart.library.js_interop) 'src/web/quick_html_pdf_web.dart' as platform;

// Export public types.
export 'src/options.dart';
export 'src/exceptions.dart';
export 'src/templating.dart' show TemplateEngine;
export 'src/html_composer.dart' show HtmlComposer;

class QuickHtmlPdf {
  QuickHtmlPdf._();

  /// Generate a PDF from an HTML template with dynamic data.
  ///
  /// Returns:
  /// - `Uint8List` when `options.output == PdfOutput.bytes`
  /// - `null` when `options.output` is `print` or `download` (side-effect: dialog or file save)
  ///
  /// Throws:
  /// - `UnsupportedError` on non-web platforms
  /// - `TemplateException` for invalid template syntax
  /// - `PdfGenerationException` for PDF generation failures (carries `phase`
  ///   and stable `code` for telemetry / consumer branching)
  ///
  /// See library-level docs for examples and API contract.
  static Future<Uint8List?> generate({
    required String htmlTemplate,
    required Map<String, dynamic> data,
    PdfOptions options = const PdfOptions(),
  }) {
    return platform.generatePdf(
      htmlTemplate: htmlTemplate,
      data: data,
      options: options,
    );
  }

  /// Trigger a browser download of an existing `Uint8List`. Use this when
  /// the bytes came from elsewhere (e.g. a server-rendered PDF). For new
  /// code that just wants to render-and-save, prefer
  /// `PdfOutput.download` in [generate].
  static void downloadBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    platform.downloadPdfBytes(bytes: bytes, filename: filename);
  }
}
