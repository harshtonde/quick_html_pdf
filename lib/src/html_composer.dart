/// HTML composition for QuickHtmlPdf v3.
///
/// Builds a complete HTML document for the rendering iframe. The output is
/// consumed two ways:
///
/// - `PdfOutput.print` — written into a hidden iframe and handed to
///   `window.print()`.
/// - `PdfOutput.download` / `PdfOutput.bytes` — written into an off-screen
///   iframe, paginated by [CustomPaginator], then walked by [DomWalker]
///   which emits jsPDF vector primitives.
///
/// The composer no longer injects Paged.js. Pagination is handled by the
/// custom paginator, and per-page header/footer/watermark slots are built
/// inside the page wrappers from `PdfOptions.headerHtml` / `footerHtml` /
/// `watermarkUrl`.
library;

import 'options.dart';

class HtmlComposer {
  HtmlComposer._();

  /// Compose a full HTML document.
  ///
  /// [bodyContent] — rendered HTML body content from `TemplateEngine.render`.
  /// [options] — page format, margins, header/footer, fonts, etc.
  /// [baseHref] — value for the `<base href="...">` tag. Required so that
  ///   relative URLs (e.g. font src paths) resolve against the parent app's
  ///   origin rather than `about:blank`.
  static String compose(
    String bodyContent,
    PdfOptions options, {
    String? baseHref,
  }) {
    final pageSize = _pageSizeCss(options);
    final margins = options.margins.toCss();

    final base = (baseHref != null && baseHref.isNotEmpty)
        ? '  <base href="${_escapeAttr(baseHref)}">\n'
        : '';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
$base  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PDF Document</title>
  <style id="qhp-composer-styles">
    /* Reset and base styles. */
    *, *::before, *::after { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: #fff; }

    /* @page rule — used by `PdfOutput.print` (the browser's print engine
       reads this for page size + margins). The custom paginator computes
       its own geometry from `PdfOptions` and ignores @page. */
    @page {
      size: $pageSize;
      margin: $margins;
    }

    /* Page-break utility classes. */
    .page-break {
      break-after: page;
      page-break-after: always;
      display: block;
      height: 0;
    }
    .page-break-before {
      break-before: page;
      page-break-before: always;
    }
    .no-break {
      break-inside: avoid;
      page-break-inside: avoid;
    }
    .keep-with-next {
      break-after: avoid;
      page-break-after: avoid;
    }

    /* Reasonable defaults for tables — consumers can override. */
    table { border-collapse: collapse; width: 100%; }
    thead { display: table-header-group; }
    tfoot { display: table-footer-group; }
    tr, td, th { page-break-inside: avoid; break-inside: avoid; }

    /* Avoid orphaned headings. */
    h1, h2, h3, h4, h5, h6 {
      page-break-after: avoid;
      break-after: avoid;
    }

    /* Common utility classes. */
    .text-center { text-align: center; }
    .text-right { text-align: right; }
    .text-left { text-align: left; }
    .font-bold { font-weight: bold; }
    .font-normal { font-weight: normal; }
  </style>
</head>
<body>
<div class="pdf-content">
$bodyContent
</div>
</body>
</html>
''';
  }

  /// Convert page format + orientation into a CSS `size` value.
  static String _pageSizeCss(PdfOptions options) {
    final String sizeName;
    switch (options.pageFormat) {
      case PdfPageFormat.a4:
        sizeName = 'A4';
        break;
      case PdfPageFormat.letter:
        sizeName = 'letter';
        break;
      case PdfPageFormat.legal:
        sizeName = 'legal';
        break;
    }
    final orientationName =
        options.orientation == PdfOrientation.landscape ? 'landscape' : 'portrait';
    return '$sizeName $orientationName';
  }

  static String _escapeAttr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');

  /// Helper to build a simple `<table>` from headers + rows.
  static String createTable({
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? tableClass,
    bool striped = false,
  }) {
    final buffer = StringBuffer()
      ..writeln('<table${tableClass != null ? ' class="$tableClass"' : ''}>')
      ..writeln('<thead>')
      ..writeln('<tr>');
    for (final header in headers) {
      buffer.writeln('<th>$header</th>');
    }
    buffer
      ..writeln('</tr>')
      ..writeln('</thead>')
      ..writeln('<tbody>');
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowClass = striped && i.isOdd ? ' class="striped"' : '';
      buffer.writeln('<tr$rowClass>');
      for (final cell in row) {
        buffer.writeln('<td>${cell ?? ''}</td>');
      }
      buffer.writeln('</tr>');
    }
    buffer
      ..writeln('</tbody>')
      ..writeln('</table>');
    return buffer.toString();
  }
}
