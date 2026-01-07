/// QuickHtmlPdf - Fast HTML to PDF conversion for Flutter Web.
///
/// A high-performance Flutter Web package that converts HTML templates
/// with dynamic data into PDFs using JavaScript interoperability.
///
/// ## Features
///
/// - **Fast download mode**: Uses native browser print for instant PDF generation
/// - **Bytes mode**: Returns PDF as Uint8List for further processing
/// - **Template engine**: Support for {{placeholders}}, loops, and raw HTML
/// - **Print CSS**: Optimized CSS for accurate pagination
/// - **Large documents**: Chunked rendering for 200+ page documents
///
/// ## Quick Start
///
/// ```dart
/// import 'package:quick_html_pdf/quick_html_pdf.dart';
///
/// // Generate PDF and trigger download
/// await QuickHtmlPdf.generate(
///   htmlTemplate: '<h1>Hello {{name}}</h1>',
///   data: {'name': 'World'},
///   options: PdfOptions(output: PdfOutput.download),
/// );
///
/// // Generate PDF and get bytes
/// final bytes = await QuickHtmlPdf.generate(
///   htmlTemplate: '<h1>Hello {{name}}</h1>',
///   data: {'name': 'World'},
///   options: PdfOptions(output: PdfOutput.bytes),
/// );
/// ```
///
/// ## Template Syntax
///
/// - `{{key}}` - HTML-escaped interpolation
/// - `{{nested.path}}` - Dot notation for nested objects
/// - `{{{rawHtml}}}` - Unescaped HTML insertion
/// - `{{#each items}}...{{/each}}` - Loop blocks
/// - `{{this.field}}` - Access current item in loop
/// - `{{@index}}` - Current loop index (0-based)
///
/// ## Platform Support
///
/// This package is **web-only**. It throws `UnsupportedError` on
/// mobile and desktop platforms.
library;

import 'dart:typed_data';

import 'src/options.dart';

// Conditional imports for platform-specific implementation
import 'src/stub/quick_html_pdf_stub.dart'
    if (dart.library.js_interop) 'src/web/quick_html_pdf_web.dart'
    as platform;

// Export all public types
export 'src/options.dart';
export 'src/exceptions.dart';
export 'src/templating.dart' show TemplateEngine;
export 'src/html_composer.dart' show HtmlComposer;

/// QuickHtmlPdf - Fast HTML to PDF conversion for Flutter Web.
///
/// This is the main entry point for the package. Use the static
/// [generate] method to create PDFs from HTML templates.
class QuickHtmlPdf {
  QuickHtmlPdf._(); // Private constructor to prevent instantiation

  /// Generate a PDF from an HTML template with dynamic data.
  ///
  /// [htmlTemplate] - HTML template string with {{placeholders}}
  /// [data] - Map of dynamic data to inject into the template
  /// [options] - PDF generation options (page format, margins, output mode, etc.)
  ///
  /// Returns:
  /// - `Uint8List` when `options.output == PdfOutput.bytes`
  /// - `null` when `options.output == PdfOutput.download` (triggers browser download)
  ///
  /// Throws:
  /// - `UnsupportedError` on non-web platforms
  /// - `TemplateException` for invalid template syntax
  /// - `PdfGenerationException` for PDF generation failures
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Simple template
  /// final bytes = await QuickHtmlPdf.generate(
  ///   htmlTemplate: '<h1>Invoice #{{invoiceNumber}}</h1>',
  ///   data: {'invoiceNumber': '12345'},
  /// );
  ///
  /// // With loops
  /// final template = '''
  ///   <table>
  ///     <tr><th>Item</th><th>Price</th></tr>
  ///     {{#each items}}
  ///     <tr><td>{{this.name}}</td><td>{{this.price}}</td></tr>
  ///     {{/each}}
  ///   </table>
  /// ''';
  ///
  /// await QuickHtmlPdf.generate(
  ///   htmlTemplate: template,
  ///   data: {
  ///     'items': [
  ///       {'name': 'Widget', 'price': '\$10'},
  ///       {'name': 'Gadget', 'price': '\$20'},
  ///     ],
  ///   },
  ///   options: PdfOptions(
  ///     output: PdfOutput.download,
  ///     filename: 'invoice.pdf',
  ///   ),
  /// );
  /// ```
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

  /// Download PDF bytes as a file in the browser.
  ///
  /// Use this when you already have PDF bytes and want to trigger
  /// a browser download.
  ///
  /// [bytes] - The PDF content as bytes
  /// [filename] - The filename for the download (should end with .pdf)
  ///
  /// Throws:
  /// - `UnsupportedError` on non-web platforms
  ///
  /// ## Example
  ///
  /// ```dart
  /// final bytes = await QuickHtmlPdf.generate(
  ///   htmlTemplate: '<h1>Report</h1>',
  ///   data: {},
  ///   options: PdfOptions(output: PdfOutput.bytes),
  /// );
  ///
  /// if (bytes != null) {
  ///   QuickHtmlPdf.downloadBytes(
  ///     bytes: bytes,
  ///     filename: 'report.pdf',
  ///   );
  /// }
  /// ```
  static void downloadBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    platform.downloadPdfBytes(bytes: bytes, filename: filename);
  }
}
