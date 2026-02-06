/// Bytes strategy for PDF generation with html2pdf.js.
///
/// This strategy uses html2pdf.js for intelligent page breaks
/// that respect CSS page-break properties, then overlays
/// headers/footers with dynamic page numbers.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../options.dart';
import 'iframe_manager.dart';
import 'js_interop.dart';

/// Handles PDF generation using html2pdf.js for intelligent page breaks
/// and jsPDF for header/footer overlays.
///
/// Key features:
/// - Respects CSS page-break-inside: avoid
/// - Respects page-break-before: always and page-break-after: always
/// - Finds natural break points between block elements
/// - Supports header/footer with {{page}}/{{pages}} placeholders
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
      // Check which libraries are available
      final useHtml2Pdf = JsLibraries.isHtml2PdfAvailable;

      if (debug) {
        _log('Using ${useHtml2Pdf ? 'html2pdf.js' : 'legacy html2canvas+jsPDF'}');
      }

      // Create iframe with content (visible for canvas capture)
      iframeManager = IframeManager(debug: debug);

      final iframeStart = DateTime.now();
      await iframeManager.create(
        html: html,
        visible: true, // Must be visible for canvas capture
        options: options,
      );
      timings['iframe_create'] =
          DateTime.now().difference(iframeStart).inMilliseconds;

      // Wait for resources
      final resourceStart = DateTime.now();
      await iframeManager.waitForResources(
        timeoutMs: options.resourceTimeoutMs,
      );
      timings['resource_load'] =
          DateTime.now().difference(resourceStart).inMilliseconds;

      // Generate PDF
      final pdfStart = DateTime.now();
      Uint8List bytes;

      if (useHtml2Pdf) {
        bytes = await _generateWithHtml2Pdf(iframeManager);
      } else {
        // Fallback to legacy chunked rendering
        bytes = await _generatePdfChunked(iframeManager);
      }
      timings['pdf_generate'] =
          DateTime.now().difference(pdfStart).inMilliseconds;

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

  /// Generate PDF using html2pdf.js with intelligent page breaks.
  Future<Uint8List> _generateWithHtml2Pdf(IframeManager iframeManager) async {
    final body = iframeManager.body;
    if (body == null) {
      throw PdfGenerationException(
        'Iframe body not available',
        phase: PdfGenerationPhase.canvasRendering,
      );
    }

    // Configure html2pdf options
    final orientation =
        options.orientation == PdfOrientation.landscape ? 'l' : 'p';

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

    // Calculate margins, accounting for header/footer space
    final topMargin = options.margins.topMm + options.effectiveHeaderHeightMm;
    final bottomMargin =
        options.margins.bottomMm + options.effectiveFooterHeightMm;

    final html2pdfOptions = <String, dynamic>{
      'margin': [
        topMargin,
        options.margins.rightMm,
        bottomMargin,
        options.margins.leftMm,
      ],
      'filename': options.filename,
      'image': {
        'type': 'jpeg',
        'quality': options.imageQuality,
      },
      'html2canvas': {
        'scale': options.scale,
        'useCORS': true,
        'allowTaint': false,
        'logging': false,
        'backgroundColor': '#ffffff',
      },
      'jsPDF': {
        'unit': 'mm',
        'format': format,
        'orientation': orientation,
      },
      'pagebreak': {
        'mode': options.pageBreakModeStrings,
        'before': '.page-break-before',
        'after': '.page-break',
        'avoid': '.no-break',
      },
    };

    if (debug) {
      _log('html2pdf options: $html2pdfOptions');
    }

    try {
      // Create html2pdf instance and generate PDF
      final builder = JsLibraries.createHtml2Pdf();
      final configuredBuilder = builder.set(html2pdfOptions).from(body).toPdf();

      // Get the jsPDF instance
      final pdf = await configuredBuilder.getPdf();

      // Add headers and footers if configured (uses html2canvas for Unicode support)
      if (options.hasHeader || options.hasFooter) {
        await _addHeadersAndFootersAsImages(pdf);
      }

      // Get the final bytes
      return pdf.getBytes();
    } catch (e) {
      throw PdfGenerationException(
        'html2pdf.js conversion failed: $e',
        phase: PdfGenerationPhase.canvasRendering,
        cause: e,
      );
    }
  }

  /// Add headers and footers to each page using html2canvas for Unicode support.
  ///
  /// This renders header/footer HTML using the browser's font engine (which
  /// supports Unicode/Hindi/etc), captures it as an image, and adds to PDF.
  Future<void> _addHeadersAndFootersAsImages(JsPDF pdf) async {
    final totalPages = pdf.getNumberOfPages();
    final (pageWidth, pageHeight) = pdf.getPageSize();

    // Get current date/time for placeholders
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateTimeStr = '$dateStr $timeStr';

    // Calculate dimensions
    final contentWidth = pageWidth - options.margins.leftMm - options.margins.rightMm;

    // Pre-render header image (same for all pages except page numbers)
    // For efficiency, we cache the base HTML and only re-render if page numbers change
    String? headerImageCache;
    String? footerImageCache;
    int? cachedPage;

    for (var page = 1; page <= totalPages; page++) {
      pdf.setPage(page);

      // Add header
      if (options.hasHeader) {
        final headerHtml = _replacePlaceholders(
          options.headerHtml!,
          page: page,
          totalPages: totalPages,
          date: dateStr,
          time: timeStr,
          dateTime: dateTimeStr,
        );

        // Re-render if page number changed or first page
        if (cachedPage != page || headerImageCache == null) {
          headerImageCache = await _renderHtmlToImage(
            headerHtml,
            widthMm: contentWidth,
            heightMm: options.headerHeightMm,
            fontSize: options.headerFontSize,
          );
        }

        // Position header at top margin
        final headerY = options.margins.topMm;
        pdf.addImage(
          imageData: headerImageCache,
          format: 'PNG',
          x: options.margins.leftMm,
          y: headerY,
          width: contentWidth,
          height: options.headerHeightMm,
        );

        // Draw separator line if enabled
        if (options.showHeaderLine) {
          final lineY = options.margins.topMm + options.headerHeightMm;
          pdf.setDrawColor(200, 200, 200); // Light gray
          pdf.setLineWidth(0.2);
          pdf.line(
            options.margins.leftMm,
            lineY,
            pageWidth - options.margins.rightMm,
            lineY,
          );
        }
      }

      // Add footer
      if (options.hasFooter) {
        final footerHtml = _replacePlaceholders(
          options.footerHtml!,
          page: page,
          totalPages: totalPages,
          date: dateStr,
          time: timeStr,
          dateTime: dateTimeStr,
        );

        // Re-render if page number changed or first page
        if (cachedPage != page || footerImageCache == null) {
          footerImageCache = await _renderHtmlToImage(
            footerHtml,
            widthMm: contentWidth,
            heightMm: options.footerHeightMm,
            fontSize: options.footerFontSize,
            textColor: '#666666', // Gray for footer
          );
        }

        // Position footer at bottom margin
        final footerY = pageHeight - options.margins.bottomMm - options.footerHeightMm;

        // Draw separator line if enabled (before the footer)
        if (options.showFooterLine) {
          pdf.setDrawColor(200, 200, 200); // Light gray
          pdf.setLineWidth(0.2);
          pdf.line(
            options.margins.leftMm,
            footerY,
            pageWidth - options.margins.rightMm,
            footerY,
          );
        }

        pdf.addImage(
          imageData: footerImageCache,
          format: 'PNG',
          x: options.margins.leftMm,
          y: footerY,
          width: contentWidth,
          height: options.footerHeightMm,
        );
      }

      cachedPage = page;
    }

    if (debug) {
      _log('Added headers/footers as images to $totalPages pages');
    }
  }

  /// Render HTML content to a base64 image using html2canvas.
  ///
  /// This uses the browser's font rendering engine, which properly supports
  /// Unicode characters including Hindi, Chinese, Arabic, etc.
  Future<String> _renderHtmlToImage(
    String htmlContent, {
    required double widthMm,
    required double heightMm,
    required double fontSize,
    String textColor = '#000000',
  }) async {
    // Convert mm to pixels (96 DPI)
    final mmToPixel = 96 / 25.4;
    final widthPx = (widthMm * mmToPixel * options.scale).round();
    final heightPx = (heightMm * mmToPixel * options.scale).round();

    // Create a temporary container element
    final container = web.document.createElement('div') as web.HTMLDivElement;
    container.style
      ..position = 'fixed'
      ..left = '-9999px'
      ..top = '0'
      ..width = '${widthPx}px'
      ..height = '${heightPx}px'
      ..backgroundColor = '#ffffff'
      ..display = 'flex'
      ..alignItems = 'center'
      ..justifyContent = 'center'
      ..fontFamily = "-apple-system, BlinkMacSystemFont, 'Noto Sans', 'Noto Sans Devanagari', 'Segoe UI', Roboto, sans-serif"
      ..fontSize = '${fontSize * options.scale}pt'
      ..color = textColor
      ..overflow = 'hidden'
      ..padding = '0 ${(4 * options.scale).round()}px';

    // Set the HTML content (need .toJS for JS interop)
    container.innerHTML = htmlContent.toJS;

    // Add to document temporarily
    web.document.body?.appendChild(container);

    try {
      // Wait a brief moment for fonts to apply
      await Future.delayed(const Duration(milliseconds: 50));

      // Render to canvas using html2canvas
      final canvas = await JsLibraries.html2canvas(
        container,
        scale: 1.0, // Already scaled the container
        width: widthPx,
        height: heightPx,
        backgroundColor: '#ffffff',
      );

      // Get image as base64 PNG
      final imageData = canvas.toDataURL('image/png');

      // Clean up canvas
      canvas.width = 0;
      canvas.height = 0;

      return imageData;
    } finally {
      // Always remove the temporary container
      container.remove();
    }
  }

  /// Replace placeholders in header/footer text.
  String _replacePlaceholders(
    String text, {
    required int page,
    required int totalPages,
    required String date,
    required String time,
    required String dateTime,
  }) {
    return text
        .replaceAll('{{page}}', page.toString())
        .replaceAll('{{pages}}', totalPages.toString())
        .replaceAll('{{date}}', date)
        .replaceAll('{{time}}', time)
        .replaceAll('{{datetime}}', dateTime);
  }

  /// Legacy: Generate PDF with chunked rendering for memory efficiency.
  /// Used as fallback when html2pdf.js is not available.
  Future<Uint8List> _generatePdfChunked(IframeManager iframeManager) async {
    JsLibraries.ensureAvailable();

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

    // Add headers and footers if configured (uses html2canvas for Unicode support)
    if (options.hasHeader || options.hasFooter) {
      await _addHeadersAndFootersAsImages(pdf);
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
