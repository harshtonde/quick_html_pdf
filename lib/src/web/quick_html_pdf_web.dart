/// Web implementation of QuickHtmlPdf.
///
/// Orchestrates template rendering, HTML composition, and dispatch to the
/// appropriate output strategy:
/// - [PdfOutput.print]    → [PrintStrategy]   (window.print, browser dialog)
/// - [PdfOutput.download] → [VectorStrategy]  (custom paginator + jsPDF, silent)
/// - [PdfOutput.bytes]    → [VectorStrategy]  (custom paginator + jsPDF, returns bytes)
library;

import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../html_composer.dart';
import '../options.dart';
import '../templating.dart';
import 'print_strategy.dart';
import 'vector_strategy.dart';

/// Generate a PDF from an HTML template with dynamic data.
Future<Uint8List?> generatePdf({
  required String htmlTemplate,
  required Map<String, dynamic> data,
  PdfOptions options = const PdfOptions(),
}) async {
  final timings = <String, int>{};
  final startTime = DateTime.now();

  try {
    // Step 1: Render template with data.
    final templateStart = DateTime.now();
    final renderedBody = TemplateEngine.render(htmlTemplate, data);
    timings['template'] =
        DateTime.now().difference(templateStart).inMilliseconds;

    if (options.debug) {
      _log('Template rendered in ${timings['template']}ms');
      _log(
        'Rendered HTML size: ${(renderedBody.length / 1024).toStringAsFixed(1)} KB',
      );
    }

    // Step 2: Compose HTML.
    //
    // The composed HTML uses `document.write` into an `about:blank` iframe
    // (see IframeManager). That makes the iframe's base URI `about:blank`,
    // so we pass the parent app's location.href as `baseHref` for relative
    // URL resolution (e.g. consumer-bundled font src paths).
    final composeStart = DateTime.now();
    final fullHtml = HtmlComposer.compose(
      renderedBody,
      options,
      baseHref: web.window.location.href,
    );
    timings['compose'] =
        DateTime.now().difference(composeStart).inMilliseconds;

    if (options.debug) {
      _log('HTML composed in ${timings['compose']}ms');
      _log('Full HTML size: ${(fullHtml.length / 1024).toStringAsFixed(1)} KB');
    }

    // Step 3: Generate PDF based on output mode.
    final pdfStart = DateTime.now();
    Uint8List? result;

    switch (options.output) {
      case PdfOutput.print:
        // Native browser print dialog — no JS dep, fastest.
        final strategy = PrintStrategy(options: options, debug: options.debug);
        await strategy.execute(fullHtml);
        result = null;
        break;

      case PdfOutput.download:
      case PdfOutput.bytes:
        // Vector pipeline: CustomPaginator + jsPDF + DOM walker.
        final strategy =
            VectorStrategy(options: options, debug: options.debug);
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

/// Trigger a download of bytes as a PDF file. Use when you have PDF bytes
/// from elsewhere (e.g. a server) and want to save them via the browser.
///
/// For new code, prefer `PdfOutput.download` mode in [generatePdf] — it
/// skips the Uint8List round-trip.
void downloadPdfBytes({required Uint8List bytes, required String filename}) {
  BlobDownloader.download(
    bytes: bytes,
    filename: filename,
    mimeType: 'application/pdf',
  );
}

void _log(String message) {
  // ignore: avoid_print
  print('[QuickHtmlPdf] $message');
}
