/// Bytes strategy for PDF generation with html2canvas + jsPDF.
///
/// This strategy captures the rendered HTML as canvas and converts
/// to PDF bytes. Optimized for large documents with chunked rendering.
library;

import 'dart:async';
import 'dart:typed_data';

import '../exceptions.dart';
import '../options.dart';
import 'iframe_manager.dart';
import 'js_interop.dart';

/// Handles PDF generation by capturing HTML as canvas and converting to PDF.
///
/// Uses chunked rendering to handle large documents efficiently:
/// 1. Render content in iframe
/// 2. Capture visible viewport with html2canvas
/// 3. Add to jsPDF page by page
/// 4. Free memory between captures
class BytesStrategy {
  final PdfOptions options;
  final bool debug;

  BytesStrategy({required this.options, this.debug = false});

  /// Generate PDF bytes from HTML content.
  ///
  /// [html] - Complete HTML document to convert
  ///
  /// Returns the PDF as a Uint8List.
  Future<Uint8List> execute(String html) async {
    final timings = <String, int>{};
    final startTime = DateTime.now();
    IframeManager? iframeManager;

    try {
      // Ensure JS libraries are loaded
      JsLibraries.ensureAvailable();

      // Create iframe with content (visible for canvas capture)
      iframeManager = IframeManager(debug: debug);

      final iframeStart = DateTime.now();
      await iframeManager.create(
        html: html,
        visible: true, // Must be visible for canvas capture
        options: options,
      );
      timings['iframe_create'] = DateTime.now()
          .difference(iframeStart)
          .inMilliseconds;

      // Wait for resources
      final resourceStart = DateTime.now();
      await iframeManager.waitForResources(
        timeoutMs: options.resourceTimeoutMs,
      );
      timings['resource_load'] = DateTime.now()
          .difference(resourceStart)
          .inMilliseconds;

      // Generate PDF with chunked rendering
      final pdfStart = DateTime.now();
      final bytes = await _generatePdfChunked(iframeManager);
      timings['pdf_generate'] = DateTime.now()
          .difference(pdfStart)
          .inMilliseconds;

      if (debug) {
        final totalTime = DateTime.now().difference(startTime).inMilliseconds;
        _log('PDF generation completed in ${totalTime}ms');
        _log('  - Iframe setup: ${timings['iframe_create']}ms');
        _log('  - Resource loading: ${timings['resource_load']}ms');
        _log('  - PDF generation: ${timings['pdf_generate']}ms');
        _log('  - Output size: ${(bytes.length / 1024).toStringAsFixed(1)} KB');
      }

      return bytes;
    } catch (e) {
      if (e is PdfGenerationException) rethrow;
      throw PdfGenerationException(
        'PDF generation failed: $e',
        phase: PdfGenerationPhase.pdfAssembly,
        cause: e,
      );
    } finally {
      iframeManager?.dispose();
    }
  }

  /// Generate PDF with chunked rendering for memory efficiency.
  Future<Uint8List> _generatePdfChunked(IframeManager iframeManager) async {
    final body = iframeManager.body;
    if (body == null) {
      throw PdfGenerationException(
        'Iframe body not available',
        phase: PdfGenerationPhase.canvasRendering,
      );
    }

    // Get page dimensions in pixels (at 96 DPI for screen)
    final pageWidthMm = options.effectiveWidthMm;
    final pageHeightMm = options.effectiveHeightMm;

    // Convert mm to pixels (assuming 96 DPI screen)
    // 1 inch = 25.4mm, 1 inch = 96 pixels at standard DPI
    final mmToPixel = 96 / 25.4;
    final pageWidthPx = (pageWidthMm * mmToPixel).round();
    final pageHeightPx = (pageHeightMm * mmToPixel).round();

    // Get content dimensions
    final contentHeight = iframeManager.contentHeight;
    final contentWidth = iframeManager.contentWidth;

    if (debug) {
      _log('Page size: ${pageWidthMm}mm x ${pageHeightMm}mm');
      _log('Page pixels: ${pageWidthPx}px x ${pageHeightPx}px');
      _log('Content size: ${contentWidth}px x ${contentHeight}px');
    }

    // Calculate number of pages needed
    final totalPages = (contentHeight / pageHeightPx).ceil().clamp(1, 1000);

    if (debug) {
      _log('Rendering $totalPages pages...');
    }

    // Create PDF
    final orientation = options.orientation == PdfOrientation.landscape
        ? 'landscape'
        : 'portrait';

    String format;
    switch (options.pageFormat) {
      case PdfPageFormat.a4:
        format = 'a4';
        break;
      case PdfPageFormat.letter:
        format = 'letter';
        break;
      case PdfPageFormat.legal:
        format = 'legal';
        break;
    }

    final pdf = JsLibraries.createPdf(
      orientation: orientation,
      unit: 'mm',
      format: format,
    );

    // Render each page
    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      if (pageIndex > 0) {
        pdf.addPage();
      }

      // Calculate scroll position for this page
      final scrollY = pageIndex * pageHeightPx;

      // Scroll to position
      iframeManager.scrollTo(0, scrollY);

      // Small delay for scroll to take effect
      await Future.delayed(const Duration(milliseconds: 10));

      try {
        // Capture this page section
        final canvas = await JsLibraries.html2canvas(
          body,
          scale: options.scale,
          width: pageWidthPx,
          height: pageHeightPx,
          x: 0,
          y: scrollY,
          windowWidth: pageWidthPx,
          windowHeight: pageHeightPx,
          scrollX: 0,
          scrollY: scrollY,
        );

        // Get image data from canvas - using default quality
        final imageData = canvas.toDataURL('image/jpeg');

        // Add to PDF
        pdf.addImage(
          imageData: imageData,
          format: 'JPEG',
          x: 0,
          y: 0,
          width: pageWidthMm,
          height: pageHeightMm,
        );

        // Free canvas memory
        canvas.width = 0;
        canvas.height = 0;

        if (debug && (pageIndex + 1) % 10 == 0) {
          _log('Rendered ${pageIndex + 1}/$totalPages pages');
        }
      } catch (e) {
        throw PdfGenerationException(
          'Failed to render page ${pageIndex + 1}: $e',
          phase: PdfGenerationPhase.canvasRendering,
          cause: e,
        );
      }
    }

    // Get PDF bytes
    try {
      return pdf.getBytes();
    } catch (e) {
      throw PdfGenerationException(
        'Failed to get PDF bytes: $e',
        phase: PdfGenerationPhase.pdfAssembly,
        cause: e,
      );
    }
  }

  /// Log a debug message.
  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Bytes] $message');
    }
  }
}
