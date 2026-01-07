/// PDF generation options for QuickHtmlPdf.
///
/// This file contains all configuration classes and enums for PDF generation.
library;

/// Output mode for PDF generation.
enum PdfOutput {
  /// Return PDF as bytes (Uint8List).
  /// Use this when you need to process the PDF in Dart (upload, store, etc.)
  bytes,

  /// Trigger direct browser download.
  /// This is the fastest option - uses native browser print.
  download,
}

/// Page format for the PDF.
enum PdfPageFormat {
  /// A4 paper size (210mm x 297mm)
  a4(210, 297),

  /// US Letter size (215.9mm x 279.4mm)
  letter(215.9, 279.4),

  /// US Legal size (215.9mm x 355.6mm)
  legal(215.9, 355.6);

  const PdfPageFormat(this.widthMm, this.heightMm);

  /// Width in millimeters
  final double widthMm;

  /// Height in millimeters
  final double heightMm;

  /// Width in points (1 point = 1/72 inch)
  double get widthPt => widthMm * 72 / 25.4;

  /// Height in points
  double get heightPt => heightMm * 72 / 25.4;
}

/// Page orientation for the PDF.
enum PdfOrientation {
  /// Portrait orientation (taller than wide)
  portrait,

  /// Landscape orientation (wider than tall)
  landscape,
}

/// Margins for PDF pages in millimeters.
class PdfMargins {
  /// Top margin in millimeters
  final double topMm;

  /// Right margin in millimeters
  final double rightMm;

  /// Bottom margin in millimeters
  final double bottomMm;

  /// Left margin in millimeters
  final double leftMm;

  /// Creates margins with specified values in millimeters.
  const PdfMargins({
    this.topMm = 20,
    this.rightMm = 15,
    this.bottomMm = 20,
    this.leftMm = 15,
  });

  /// Creates uniform margins on all sides.
  const PdfMargins.all(double mm)
    : topMm = mm,
      rightMm = mm,
      bottomMm = mm,
      leftMm = mm;

  /// Creates symmetric margins (vertical and horizontal).
  const PdfMargins.symmetric({double vertical = 20, double horizontal = 15})
    : topMm = vertical,
      bottomMm = vertical,
      leftMm = horizontal,
      rightMm = horizontal;

  /// No margins.
  static const PdfMargins zero = PdfMargins.all(0);

  /// Default margins suitable for most documents.
  static const PdfMargins standard = PdfMargins();

  /// Convert to CSS margin string.
  String toCss() => '${topMm}mm ${rightMm}mm ${bottomMm}mm ${leftMm}mm';

  @override
  String toString() =>
      'PdfMargins(top: ${topMm}mm, right: ${rightMm}mm, bottom: ${bottomMm}mm, left: ${leftMm}mm)';
}

/// Configuration options for PDF generation.
class PdfOptions {
  /// Page format (default: A4)
  final PdfPageFormat pageFormat;

  /// Page orientation (default: portrait)
  final PdfOrientation orientation;

  /// Page margins
  final PdfMargins margins;

  /// Optional HTML for page header.
  /// Will be rendered at the top of each page.
  final String? headerHtml;

  /// Optional HTML for page footer.
  /// Will be rendered at the bottom of each page.
  final String? footerHtml;

  /// Filename for download (default: "document.pdf")
  final String filename;

  /// Output mode: bytes or download
  final PdfOutput output;

  /// Enable debug logging for timing and diagnostics
  final bool debug;

  /// Scale factor for canvas rendering (bytes mode only).
  /// Higher values = better quality but slower.
  /// Default is 1.5 (good balance of quality and speed).
  final double scale;

  /// Image quality for JPEG compression (0.0 to 1.0).
  /// Only used in bytes mode. Default is 0.92.
  final double imageQuality;

  /// Timeout in milliseconds for font/image loading.
  /// Default is 10000 (10 seconds).
  final int resourceTimeoutMs;

  /// Creates PDF options with the specified configuration.
  const PdfOptions({
    this.pageFormat = PdfPageFormat.a4,
    this.orientation = PdfOrientation.portrait,
    this.margins = const PdfMargins(),
    this.headerHtml,
    this.footerHtml,
    this.filename = 'document.pdf',
    this.output = PdfOutput.download,
    this.debug = false,
    this.scale = 1.5,
    this.imageQuality = 0.92,
    this.resourceTimeoutMs = 10000,
  });

  /// Get effective page width considering orientation.
  double get effectiveWidthMm => orientation == PdfOrientation.portrait
      ? pageFormat.widthMm
      : pageFormat.heightMm;

  /// Get effective page height considering orientation.
  double get effectiveHeightMm => orientation == PdfOrientation.portrait
      ? pageFormat.heightMm
      : pageFormat.widthMm;

  /// Get content width (page width minus horizontal margins).
  double get contentWidthMm =>
      effectiveWidthMm - margins.leftMm - margins.rightMm;

  /// Get content height (page height minus vertical margins).
  double get contentHeightMm =>
      effectiveHeightMm - margins.topMm - margins.bottomMm;

  /// Create a copy with modified values.
  PdfOptions copyWith({
    PdfPageFormat? pageFormat,
    PdfOrientation? orientation,
    PdfMargins? margins,
    String? headerHtml,
    String? footerHtml,
    String? filename,
    PdfOutput? output,
    bool? debug,
    double? scale,
    double? imageQuality,
    int? resourceTimeoutMs,
  }) {
    return PdfOptions(
      pageFormat: pageFormat ?? this.pageFormat,
      orientation: orientation ?? this.orientation,
      margins: margins ?? this.margins,
      headerHtml: headerHtml ?? this.headerHtml,
      footerHtml: footerHtml ?? this.footerHtml,
      filename: filename ?? this.filename,
      output: output ?? this.output,
      debug: debug ?? this.debug,
      scale: scale ?? this.scale,
      imageQuality: imageQuality ?? this.imageQuality,
      resourceTimeoutMs: resourceTimeoutMs ?? this.resourceTimeoutMs,
    );
  }

  @override
  String toString() =>
      'PdfOptions('
      'format: $pageFormat, '
      'orientation: $orientation, '
      'margins: $margins, '
      'output: $output, '
      'filename: $filename'
      ')';
}
