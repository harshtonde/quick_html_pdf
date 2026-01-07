/// Web implementation of QuickHtmlPdf.
///
/// This is the main entry point for web platform, orchestrating
/// template rendering, HTML composition, and PDF generation.
library;

import 'dart:typed_data';

import '../exceptions.dart';
import '../html_composer.dart';
import '../options.dart';
import '../templating.dart';
import 'bytes_strategy.dart';
import 'print_strategy.dart';

/// Generate a PDF from an HTML template with dynamic data.
///
/// This is the web implementation that uses JavaScript interop
/// for PDF generation.
///
/// [htmlTemplate] - HTML template with {{placeholders}}
/// [data] - Dynamic data to inject into template
/// [options] - PDF generation options
///
/// Returns:
/// - `Uint8List` when `options.output == PdfOutput.bytes`
/// - `null` when `options.output == PdfOutput.download` (triggers browser download)
Future<Uint8List?> generatePdf({
  required String htmlTemplate,
  required Map<String, dynamic> data,
  PdfOptions options = const PdfOptions(),
}) async {
  final timings = <String, int>{};
  final startTime = DateTime.now();

  try {
    // Step 1: Render template with data
    final templateStart = DateTime.now();
    final renderedBody = TemplateEngine.render(htmlTemplate, data);
    timings['template'] = DateTime.now()
        .difference(templateStart)
        .inMilliseconds;

    if (options.debug) {
      _log('Template rendered in ${timings['template']}ms');
      _log(
        'Rendered HTML size: ${(renderedBody.length / 1024).toStringAsFixed(1)} KB',
      );
    }

    // Step 2: Compose full HTML document with print CSS
    final composeStart = DateTime.now();
    final fullHtml = HtmlComposer.compose(renderedBody, options);
    timings['compose'] = DateTime.now().difference(composeStart).inMilliseconds;

    if (options.debug) {
      _log('HTML composed in ${timings['compose']}ms');
      _log('Full HTML size: ${(fullHtml.length / 1024).toStringAsFixed(1)} KB');
    }

    // Step 3: Generate PDF based on output mode
    final pdfStart = DateTime.now();
    Uint8List? result;

    switch (options.output) {
      case PdfOutput.download:
        // Fast path: use native browser print
        final strategy = PrintStrategy(options: options, debug: options.debug);
        await strategy.execute(fullHtml);
        result = null;
        break;

      case PdfOutput.bytes:
        // Capture path: use html2canvas + jsPDF
        final strategy = BytesStrategy(options: options, debug: options.debug);
        result = await strategy.execute(fullHtml);
        break;
    }

    timings['pdf'] = DateTime.now().difference(pdfStart).inMilliseconds;

    if (options.debug) {
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      _log('===== Generation Complete =====');
      _log('Total time: ${totalTime}ms');
      _log('  - Template: ${timings['template']}ms');
      _log('  - Compose: ${timings['compose']}ms');
      _log('  - PDF: ${timings['pdf']}ms');
      if (result != null) {
        _log('  - Output: ${(result.length / 1024).toStringAsFixed(1)} KB');
      }
      _log('===============================');
    }

    return result;
  } on TemplateException {
    rethrow;
  } on PdfGenerationException {
    rethrow;
  } catch (e) {
    throw PdfGenerationException(
      'Unexpected error during PDF generation: $e',
      phase: PdfGenerationPhase.unknown,
      cause: e,
    );
  }
}

/// Trigger a download of bytes as a PDF file.
///
/// Use this when you have PDF bytes and want to download them.
void downloadPdfBytes({required Uint8List bytes, required String filename}) {
  BlobDownloader.download(
    bytes: bytes,
    filename: filename,
    mimeType: 'application/pdf',
  );
}

/// Log a debug message.
void _log(String message) {
  // ignore: avoid_print
  print('[QuickHtmlPdf] $message');
}
