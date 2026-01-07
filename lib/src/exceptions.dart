/// Custom exceptions for QuickHtmlPdf.
library;

/// Exception thrown when template parsing or rendering fails.
class TemplateException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// Optional details about the location of the error.
  final String? details;

  /// Creates a template exception with the given message.
  const TemplateException(this.message, [this.details]);

  @override
  String toString() {
    if (details != null) {
      return 'TemplateException: $message\nDetails: $details';
    }
    return 'TemplateException: $message';
  }
}

/// Exception thrown when PDF generation fails.
class PdfGenerationException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// The phase during which the error occurred.
  final PdfGenerationPhase phase;

  /// The underlying error, if any.
  final Object? cause;

  /// Creates a PDF generation exception.
  const PdfGenerationException(
    this.message, {
    this.phase = PdfGenerationPhase.unknown,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer('PdfGenerationException: $message');
    buffer.writeln(' (phase: ${phase.name})');
    if (cause != null) {
      buffer.writeln('Caused by: $cause');
    }
    return buffer.toString();
  }
}

/// Phases of PDF generation where errors can occur.
enum PdfGenerationPhase {
  /// Template rendering phase
  templateRendering,

  /// HTML composition phase
  htmlComposition,

  /// Iframe creation phase
  iframeCreation,

  /// Font loading phase
  fontLoading,

  /// Image loading phase
  imageLoading,

  /// Canvas rendering phase (bytes mode)
  canvasRendering,

  /// PDF assembly phase
  pdfAssembly,

  /// File download phase
  download,

  /// Unknown phase
  unknown,
}
