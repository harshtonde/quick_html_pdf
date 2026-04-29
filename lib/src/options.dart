/// PDF generation options for QuickHtmlPdf.
///
/// This file contains all configuration classes and enums for PDF generation.
library;

import 'dart:typed_data';

/// Output mode for PDF generation.
///
/// `print` uses the browser's native print pipeline. `download` and `bytes`
/// share the vector pipeline (custom paginator + jsPDF) and differ only in
/// how the result is delivered.
enum PdfOutput {
  /// Open the browser's native print dialog. Fastest path, browser native.
  ///
  /// The user sees a print dialog and chooses "Save as PDF" themselves. Best
  /// when you want users to be able to send to a physical printer too.
  print,

  /// Silently save a PDF file to the user's downloads folder.
  ///
  /// Uses the vector pipeline (custom paginator + jsPDF). The browser does
  /// not show any dialog; the file is saved using [PdfOptions.filename].
  /// This is the "I just want a file on disk" path.
  download,

  /// Return PDF content as a [Uint8List] for further processing.
  ///
  /// Uses the same vector pipeline as [download]. Use this when you want to
  /// upload the PDF, store it in IndexedDB, send it via API, etc.
  bytes,
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

/// **Deprecated** in v3. Page breaks are driven by CSS `page-break-*` /
/// `break-*` properties (the custom paginator honors them).
/// Setting [PdfOptions.pageBreakModes] has no effect.
@Deprecated('Use CSS page-break-* properties directly. Will be removed in v3.1.')
enum PageBreakMode {
  css,
  avoidAll,
  legacy,
}

/// A custom font registration for the vector PDF pipeline.
///
/// Vector mode (`PdfOutput.download` and `PdfOutput.bytes`) needs at least
/// one font registered. Without registration, the renderer fails loudly
/// (rather than silently falling back to a built-in font that lacks Unicode
/// coverage and produces wrong glyphs — e.g. ₹ → ¹).
///
/// Provide font data via either [src] (a URL the package will `fetch`) or
/// [bytes] (raw TTF bytes — typically loaded via `rootBundle.load` for
/// Flutter-asset fonts). At least one must be set.
///
/// Example — using `rootBundle` to register a bundled Flutter asset:
/// ```dart
/// final bytes = (await rootBundle.load(
///   'assets/fonts/NotoSans-Regular.ttf',
/// )).buffer.asUint8List();
///
/// PdfOptions(
///   fonts: [
///     PdfFont(family: 'Noto Sans', bytes: bytes),
///     PdfFont(family: 'Noto Sans', bytes: boldBytes, weight: 'bold'),
///   ],
/// );
/// ```
///
/// Example — using a same-origin URL:
/// ```dart
/// PdfFont(family: 'Liberation Sans', src: 'fonts/LiberationSans-Regular.ttf');
/// ```
class PdfFont {
  /// CSS `font-family` name to match. The walker resolves CSS family
  /// declarations against this string (case-insensitive, comma-list aware).
  final String family;

  /// URL of the TTF file. Used when [bytes] is null. Must be CORS-fetchable.
  final String? src;

  /// Raw TTF bytes. Preferred over [src] when both are set — avoids the
  /// fetch round-trip entirely.
  final Uint8List? bytes;

  /// CSS-style weight: `'normal'`, `'bold'`, or any numeric `'100'`–`'900'`.
  /// Resolved internally to jsPDF's style tokens.
  final String weight;

  /// CSS-style: `'normal'`, `'italic'`, or `'oblique'`.
  final String style;

  const PdfFont({
    required this.family,
    this.src,
    this.bytes,
    this.weight = 'normal',
    this.style = 'normal',
  }) : assert(
          src != null || bytes != null,
          'PdfFont requires either src (URL) or bytes (raw TTF data)',
        );
}

/// Configuration options for PDF generation.
class PdfOptions {
  /// Page format (default: A4)
  final PdfPageFormat pageFormat;

  /// Page orientation (default: portrait)
  final PdfOrientation orientation;

  /// Page margins
  final PdfMargins margins;

  /// Optional HTML/text for page header.
  /// Will be rendered at the top of each page via CSS `@page` margin boxes.
  ///
  /// Supported placeholders:
  /// - `{{page}}` - Current page number (1, 2, 3...)
  /// - `{{pages}}` - Total page count
  /// - `{{date}}` - Current date (YYYY-MM-DD)
  /// - `{{time}}` - Current time (HH:MM)
  /// - `{{datetime}}` - Current date and time
  ///
  /// Example: `'Document Title | Page {{page}} of {{pages}}'`
  final String? headerHtml;

  /// Optional HTML/text for page footer.
  /// Same placeholder support as [headerHtml].
  final String? footerHtml;

  /// Height of the header area in millimeters. Default 15mm.
  final double headerHeightMm;

  /// Height of the footer area in millimeters. Default 15mm.
  final double footerHeightMm;

  /// Font size for header text in points. Default 10pt.
  final double headerFontSize;

  /// Font size for footer text in points. Default 9pt.
  final double footerFontSize;

  /// Whether to draw a separator line below the header. Default true.
  final bool showHeaderLine;

  /// Whether to draw a separator line above the footer. Default true.
  final bool showFooterLine;

  /// Filename used by [PdfOutput.download] when saving. Default `'document.pdf'`.
  final String filename;

  /// Output mode (default: [PdfOutput.print]).
  final PdfOutput output;

  /// Enable per-stage debug logging.
  final bool debug;

  /// **Deprecated** in v3. Vector text is not rasterized, so this scale value
  /// has no effect. Will be removed in v3.1.
  @Deprecated('No longer used by the vector renderer. Will be removed in v3.1.')
  final double scale;

  /// **Deprecated** in v3. JPEG quality is irrelevant for vector text;
  /// embedded raster images preserve their source quality. Will be removed in v3.1.
  @Deprecated('No longer used by the vector renderer. Will be removed in v3.1.')
  final double imageQuality;

  /// Timeout in milliseconds for font/image loading inside the rendering
  /// iframe.
  /// Default is 10000 (10 seconds).
  final int resourceTimeoutMs;

  /// **Deprecated** in v3. Page breaks are driven by CSS `page-break-*`
  /// properties (the custom paginator honors them). Setting this has no effect.
  @Deprecated('Use CSS page-break-* properties directly. Will be removed in v3.1.')
  final List<PageBreakMode> pageBreakModes;

  /// Fonts to register with the PDF renderer for vector text emission.
  ///
  /// **Required for vector modes** (`PdfOutput.download` and `PdfOutput.bytes`).
  /// Without at least one registered font, the renderer throws
  /// `PdfGenerationException(code: 'no-fonts-registered')` rather than silently
  /// falling back to jsPDF built-ins (which lack non-Latin-1 glyph coverage).
  ///
  /// Not used by [PdfOutput.print] (that goes through the browser's native
  /// print engine, which uses system fonts).
  final List<PdfFont> fonts;

  /// Optional watermark image URL (typically a `data:image/png;base64,...`
  /// data URL). When set, the vector pipeline paints the image as the
  /// background of every page so it shows behind content.
  ///
  /// Must already include any opacity in the image itself — the renderer
  /// does not apply alpha. Sized to 50 % of the page width and centred by
  /// default; override via [watermarkSize] / [watermarkPosition].
  ///
  /// Not used by [PdfOutput.print] — for that mode put the watermark in
  /// the template HTML's `body { background-image: ... }` instead.
  final String? watermarkUrl;

  /// CSS `background-size` value for the watermark image. Default `'50%'`
  /// (matches the original Form 26AS template intent).
  final String watermarkSize;

  /// CSS `background-position` value for the watermark. Default
  /// `'50% 50%'` (centred).
  final String watermarkPosition;

  /// Creates PDF options with the specified configuration.
  const PdfOptions({
    this.pageFormat = PdfPageFormat.a4,
    this.orientation = PdfOrientation.portrait,
    this.margins = const PdfMargins(),
    this.headerHtml,
    this.footerHtml,
    this.headerHeightMm = 15,
    this.footerHeightMm = 15,
    this.headerFontSize = 10,
    this.footerFontSize = 9,
    this.showHeaderLine = true,
    this.showFooterLine = true,
    this.filename = 'document.pdf',
    this.output = PdfOutput.print,
    this.debug = false,
    @Deprecated(
      'No longer used by the vector renderer. Will be removed in v3.1.',
    )
    this.scale = 1.5,
    @Deprecated(
      'No longer used by the vector renderer. Will be removed in v3.1.',
    )
    this.imageQuality = 0.92,
    this.resourceTimeoutMs = 10000,
    @Deprecated(
      'Use CSS page-break-* properties directly. Will be removed in v3.1.',
    )
    this.pageBreakModes = const [],
    this.fonts = const [],
    this.watermarkUrl,
    this.watermarkSize = '50%',
    this.watermarkPosition = '50% 50%',
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

  /// Whether header is enabled.
  bool get hasHeader => headerHtml != null && headerHtml!.isNotEmpty;

  /// Whether footer is enabled.
  bool get hasFooter => footerHtml != null && footerHtml!.isNotEmpty;

  /// Get the effective header height (0 if no header).
  double get effectiveHeaderHeightMm => hasHeader ? headerHeightMm : 0;

  /// Get the effective footer height (0 if no footer).
  double get effectiveFooterHeightMm => hasFooter ? footerHeightMm : 0;

  /// Get the available content height after header/footer are considered.
  double get availableContentHeightMm =>
      contentHeightMm - effectiveHeaderHeightMm - effectiveFooterHeightMm;

  /// Create a copy with modified values.
  PdfOptions copyWith({
    PdfPageFormat? pageFormat,
    PdfOrientation? orientation,
    PdfMargins? margins,
    String? headerHtml,
    String? footerHtml,
    double? headerHeightMm,
    double? footerHeightMm,
    double? headerFontSize,
    double? footerFontSize,
    bool? showHeaderLine,
    bool? showFooterLine,
    String? filename,
    PdfOutput? output,
    bool? debug,
    double? scale,
    double? imageQuality,
    int? resourceTimeoutMs,
    // ignore: deprecated_member_use_from_same_package
    List<PageBreakMode>? pageBreakModes,
    List<PdfFont>? fonts,
    String? watermarkUrl,
    String? watermarkSize,
    String? watermarkPosition,
  }) {
    return PdfOptions(
      pageFormat: pageFormat ?? this.pageFormat,
      orientation: orientation ?? this.orientation,
      margins: margins ?? this.margins,
      headerHtml: headerHtml ?? this.headerHtml,
      footerHtml: footerHtml ?? this.footerHtml,
      headerHeightMm: headerHeightMm ?? this.headerHeightMm,
      footerHeightMm: footerHeightMm ?? this.footerHeightMm,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      footerFontSize: footerFontSize ?? this.footerFontSize,
      showHeaderLine: showHeaderLine ?? this.showHeaderLine,
      showFooterLine: showFooterLine ?? this.showFooterLine,
      filename: filename ?? this.filename,
      output: output ?? this.output,
      debug: debug ?? this.debug,
      // ignore: deprecated_member_use_from_same_package
      scale: scale ?? this.scale,
      // ignore: deprecated_member_use_from_same_package
      imageQuality: imageQuality ?? this.imageQuality,
      resourceTimeoutMs: resourceTimeoutMs ?? this.resourceTimeoutMs,
      // ignore: deprecated_member_use_from_same_package
      pageBreakModes: pageBreakModes ?? this.pageBreakModes,
      fonts: fonts ?? this.fonts,
      watermarkUrl: watermarkUrl ?? this.watermarkUrl,
      watermarkSize: watermarkSize ?? this.watermarkSize,
      watermarkPosition: watermarkPosition ?? this.watermarkPosition,
    );
  }

  @override
  String toString() =>
      'PdfOptions('
      'format: $pageFormat, '
      'orientation: $orientation, '
      'margins: $margins, '
      'output: $output, '
      'filename: $filename, '
      'fonts: ${fonts.length} registered'
      ')';
}
