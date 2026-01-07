/// HTML composition with print CSS for QuickHtmlPdf.
///
/// Builds a complete HTML document with proper print styles
/// for accurate PDF generation.
library;

import 'options.dart';

/// Composes a complete HTML document with print CSS.
class HtmlComposer {
  /// Compose a full HTML document with print CSS from the rendered content.
  ///
  /// [bodyContent] - The rendered HTML body content
  /// [options] - PDF options including page format, margins, header/footer
  static String compose(String bodyContent, PdfOptions options) {
    final pageSize = _getPageSizeCSS(options);
    final margins = options.margins.toCss();

    // Calculate header/footer heights for content padding
    final hasHeader =
        options.headerHtml != null && options.headerHtml!.isNotEmpty;
    final hasFooter =
        options.footerHtml != null && options.footerHtml!.isNotEmpty;

    // Estimate header/footer heights (can be customized)
    const headerHeight = 25; // mm
    const footerHeight = 20; // mm

    final contentPaddingTop = hasHeader ? headerHeight : 0;
    final contentPaddingBottom = hasFooter ? footerHeight : 0;

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PDF Document</title>
  <style>
    /* Reset and base styles */
    *, *::before, *::after {
      box-sizing: border-box;
    }
    
    html, body {
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      font-size: 12pt;
      line-height: 1.4;
      color: #000;
      background: #fff;
    }
    
    /* Print-specific styles */
    @page {
      size: $pageSize;
      margin: $margins;
    }
    
    @media print {
      html, body {
        width: ${options.effectiveWidthMm}mm;
        margin: 0;
        padding: 0;
      }
      
      /* Table pagination */
      table {
        border-collapse: collapse;
        width: 100%;
      }
      
      thead {
        display: table-header-group;
      }
      
      tfoot {
        display: table-footer-group;
      }
      
      tbody {
        display: table-row-group;
      }
      
      tr {
        page-break-inside: avoid;
      }
      
      td, th {
        page-break-inside: avoid;
      }
      
      /* Prevent orphaned headings */
      h1, h2, h3, h4, h5, h6 {
        page-break-after: avoid;
        break-after: avoid;
      }
      
      /* Page break utilities */
      .page-break {
        break-after: page;
        page-break-after: always;
      }
      
      .page-break-before {
        break-before: page;
        page-break-before: always;
      }
      
      .no-break {
        break-inside: avoid;
        page-break-inside: avoid;
      }
      
      /* Avoid breaking inside important elements */
      img, figure, pre, blockquote {
        page-break-inside: avoid;
        break-inside: avoid;
      }
      
${hasHeader ? _generateHeaderCSS(headerHeight, options.margins) : ''}
${hasFooter ? _generateFooterCSS(footerHeight, options.margins) : ''}
    }
    
    /* Screen preview styles (for iframe rendering) */
    @media screen {
      body {
        max-width: ${options.effectiveWidthMm}mm;
        margin: 0 auto;
        padding: ${options.margins.topMm}mm ${options.margins.rightMm}mm ${options.margins.bottomMm}mm ${options.margins.leftMm}mm;
      }
    }
    
    /* Content container padding for header/footer space */
    .pdf-content {
      padding-top: ${contentPaddingTop}mm;
      padding-bottom: ${contentPaddingBottom}mm;
    }
    
    /* Common utility classes */
    .text-center { text-align: center; }
    .text-right { text-align: right; }
    .text-left { text-align: left; }
    .font-bold { font-weight: bold; }
    .font-normal { font-weight: normal; }
    
    /* Table styling defaults */
    table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 1em;
    }
    
    th, td {
      padding: 8px 12px;
      text-align: left;
      border-bottom: 1px solid #ddd;
    }
    
    th {
      background-color: #f5f5f5;
      font-weight: 600;
    }
    
    tbody tr:hover {
      background-color: #fafafa;
    }
  </style>
</head>
<body>
${hasHeader ? _generateHeaderHTML(options.headerHtml!) : ''}
<div class="pdf-content">
$bodyContent
</div>
${hasFooter ? _generateFooterHTML(options.footerHtml!) : ''}
</body>
</html>
''';
  }

  /// Get CSS page size string.
  static String _getPageSizeCSS(PdfOptions options) {
    final format = options.pageFormat;
    final orientation = options.orientation;

    String sizeName;
    switch (format) {
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

    final orientationName = orientation == PdfOrientation.landscape
        ? 'landscape'
        : 'portrait';
    return '$sizeName $orientationName';
  }

  /// Generate CSS for fixed header.
  static String _generateHeaderCSS(int heightMm, PdfMargins margins) {
    return '''
      /* Fixed header styles */
      .pdf-header {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        height: ${heightMm}mm;
        padding: 5mm ${margins.rightMm}mm 5mm ${margins.leftMm}mm;
        background: #fff;
        border-bottom: 1px solid #eee;
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
''';
  }

  /// Generate CSS for fixed footer.
  static String _generateFooterCSS(int heightMm, PdfMargins margins) {
    return '''
      /* Fixed footer styles */
      .pdf-footer {
        position: fixed;
        bottom: 0;
        left: 0;
        right: 0;
        height: ${heightMm}mm;
        padding: 5mm ${margins.rightMm}mm 5mm ${margins.leftMm}mm;
        background: #fff;
        border-top: 1px solid #eee;
        display: flex;
        align-items: center;
        justify-content: space-between;
        font-size: 10pt;
        color: #666;
      }
''';
  }

  /// Generate header HTML wrapper.
  static String _generateHeaderHTML(String headerContent) {
    return '''
<header class="pdf-header">
$headerContent
</header>
''';
  }

  /// Generate footer HTML wrapper.
  static String _generateFooterHTML(String footerContent) {
    return '''
<footer class="pdf-footer">
$footerContent
</footer>
''';
  }

  /// Create a simple table from data for common use cases.
  static String createTable({
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? tableClass,
    bool striped = false,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '<table${tableClass != null ? ' class="$tableClass"' : ''}>',
    );

    // Header
    buffer.writeln('<thead>');
    buffer.writeln('<tr>');
    for (final header in headers) {
      buffer.writeln('<th>$header</th>');
    }
    buffer.writeln('</tr>');
    buffer.writeln('</thead>');

    // Body
    buffer.writeln('<tbody>');
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowClass = striped && i.isOdd ? ' class="striped"' : '';
      buffer.writeln('<tr$rowClass>');
      for (final cell in row) {
        buffer.writeln('<td>${cell ?? ''}</td>');
      }
      buffer.writeln('</tr>');
    }
    buffer.writeln('</tbody>');

    buffer.writeln('</table>');

    return buffer.toString();
  }
}
