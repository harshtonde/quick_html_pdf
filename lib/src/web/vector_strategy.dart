/// Vector PDF strategy: HTML → CustomPaginator → DomWalker → jsPDF.
///
/// Pipeline:
///   1. Bootstrap jsPDF (lazy, once).
///   2. Inject composed HTML into an off-screen iframe and wait for fonts.
///   3. Run `CustomPaginator` — measure-and-flow pagination over the live
///      iframe DOM. Fast on table-heavy docs (no JS pagination polyfill).
///   4. Construct the jsPDF document, register fonts, walk pages.
///   5. Deliver:
///      - `download` → `JsPDF.getBlob` → `BlobDownloader.downloadBlob`
///      - `bytes`    → `JsPDF.getBytes`
///      - `print`    → caller error (route should have gone to PrintStrategy)
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../options.dart';
import 'custom_paginator.dart';
import 'dom_walker.dart';
import 'font_registry.dart';
import 'iframe_manager.dart';
import 'js_interop.dart';
import 'print_strategy.dart' show BlobDownloader;

class VectorStrategy {
  final PdfOptions options;
  final bool debug;

  VectorStrategy({required this.options, this.debug = false});

  /// Run the vector pipeline. Returns:
  /// - `Uint8List` for `PdfOutput.bytes`.
  /// - `null` for `PdfOutput.download` (the file is saved as a side effect).
  Future<Uint8List?> execute(String html) async {
    final timings = <String, int>{};
    final start = DateTime.now();
    IframeManager? iframeManager;

    try {
      // 1) Bootstrap jsPDF (lazy, idempotent).
      final bootStart = DateTime.now();
      await JsLibraries.bootstrapJsPdf();
      timings['bootstrap'] =
          DateTime.now().difference(bootStart).inMilliseconds;

      // 2) Iframe — composed HTML written into an off-screen, rendered iframe.
      final iframeStart = DateTime.now();
      iframeManager = IframeManager(debug: debug);
      await iframeManager.create(
        html: html,
        visible: true, // off-screen but rendered (see IframeManager)
        options: options,
      );
      timings['iframe'] =
          DateTime.now().difference(iframeStart).inMilliseconds;

      // 3) Wait for resource (font/image) loading.
      final resStart = DateTime.now();
      await iframeManager.waitForResources(
        timeoutMs: options.resourceTimeoutMs,
      );
      timings['resources'] =
          DateTime.now().difference(resStart).inMilliseconds;

      final iframe = iframeManager.iframe;
      if (iframe == null) {
        throw const PdfGenerationException(
          'Iframe disposed before pagination',
          phase: PdfGenerationPhase.iframeCreation,
          code: 'iframe-detached',
        );
      }

      // 4) Paginate — measure-and-flow over the live DOM.
      final pageStart = DateTime.now();
      final paginator = CustomPaginator(
        iframe: iframe,
        options: options,
        debug: debug,
      );
      final pages = await paginator.paginate();
      timings['paginate'] =
          DateTime.now().difference(pageStart).inMilliseconds;
      if (debug) _log('Paginated ${pages.length} page(s)');

      // 5) jsPDF setup.
      final pdfStart = DateTime.now();
      final orientation = options.orientation == PdfOrientation.landscape
          ? 'landscape'
          : 'portrait';
      final format = _formatString(options.pageFormat);
      final pdf = JsLibraries.createPdf(
        orientation: orientation,
        unit: 'pt',
        format: format,
      );

      // 6) Font registration. Throws if `options.fonts` is empty — that's
      // surfaced unmodified to the caller.
      final registry = FontRegistry(declared: options.fonts, debug: debug);
      await registry.register(pdf);

      // 7) Walk pages.
      final iframeDoc = iframe.contentDocument;
      if (iframeDoc == null) {
        throw const PdfGenerationException(
          'Iframe document gone before walking',
          phase: PdfGenerationPhase.domWalking,
          code: 'iframe-detached',
        );
      }
      final walker = DomWalker(
        pdf: pdf,
        fonts: registry,
        iframeDocument: iframeDoc,
        debug: debug,
        // In the consumer's release build, fail loudly. In debug mode
        // (which usually means the consumer is iterating on the template),
        // log instead so the developer can see all problems at once.
        failOnGlyphFallback: !debug,
      );
      walker.renderPages(pages);
      timings['walk'] =
          DateTime.now().difference(pdfStart).inMilliseconds;

      // 8) Deliver.
      final deliverStart = DateTime.now();
      Uint8List? result;
      switch (options.output) {
        case PdfOutput.print:
          throw const PdfGenerationException(
            'PdfOutput.print should not reach VectorStrategy',
            phase: PdfGenerationPhase.unknown,
            code: 'wrong-strategy',
          );
        case PdfOutput.download:
          final web.Blob blob = pdf.getBlob();
          BlobDownloader.downloadBlob(blob: blob, filename: options.filename);
          result = null;
          break;
        case PdfOutput.bytes:
          result = pdf.getBytes();
          break;
      }
      timings['deliver'] =
          DateTime.now().difference(deliverStart).inMilliseconds;

      if (debug) {
        final total = DateTime.now().difference(start).inMilliseconds;
        _log('===== Vector pipeline complete (${total}ms) =====');
        timings.forEach((k, v) => _log('  $k: ${v}ms'));
      }

      return result;
    } on PdfGenerationException {
      rethrow;
    } catch (e) {
      throw PdfGenerationException(
        'Unexpected failure in vector pipeline: $e',
        phase: PdfGenerationPhase.pdfAssembly,
        code: 'vector-pipeline-failed',
        cause: e,
      );
    } finally {
      iframeManager?.dispose();
    }
  }

  static String _formatString(PdfPageFormat fmt) {
    switch (fmt) {
      case PdfPageFormat.a4:
        return 'a4';
      case PdfPageFormat.letter:
        return 'letter';
      case PdfPageFormat.legal:
        return 'legal';
    }
  }

  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Vector] $message');
    }
  }
}
