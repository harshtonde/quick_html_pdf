/// Print strategy for fast PDF download via native browser print.
///
/// This is the fastest path - leverages the browser's native PDF engine.
/// No external JS libraries required.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../options.dart';
import 'iframe_manager.dart';

/// Handles PDF generation via native browser print dialog.
///
/// This strategy is instant because it delegates all rendering
/// to the browser's native print/PDF engine.
class PrintStrategy {
  final PdfOptions options;
  final bool debug;

  PrintStrategy({required this.options, this.debug = false});

  /// Trigger a print dialog for PDF download.
  ///
  /// [html] - Complete HTML document to print
  ///
  /// The browser will show its native print dialog where the user
  /// can save as PDF. This is the fastest approach because the
  /// browser handles all rendering natively.
  Future<void> execute(String html) async {
    final startTime = DateTime.now();
    IframeManager? iframeManager;

    try {
      // Create iframe with content
      iframeManager = IframeManager(debug: debug);
      await iframeManager.create(
        html: html,
        visible: false, // Hidden iframe for print
        options: options,
      );

      // Wait for resources to load
      await iframeManager.waitForResources(
        timeoutMs: options.resourceTimeoutMs,
      );

      if (debug) {
        final setupTime = DateTime.now().difference(startTime).inMilliseconds;
        _log('Setup completed in ${setupTime}ms, triggering print...');
      }

      // Trigger print dialog
      await _triggerPrint(iframeManager);

      if (debug) {
        final totalTime = DateTime.now().difference(startTime).inMilliseconds;
        _log('Print triggered in ${totalTime}ms total');
      }
    } catch (e) {
      throw PdfGenerationException(
        'Failed to trigger print dialog: $e',
        phase: PdfGenerationPhase.download,
        cause: e,
      );
    } finally {
      // Small delay before cleanup to ensure print dialog captures content
      await Future.delayed(const Duration(milliseconds: 100));
      iframeManager?.dispose();
    }
  }

  /// Trigger the print dialog on the iframe.
  Future<void> _triggerPrint(IframeManager iframeManager) async {
    final window = iframeManager.window;
    if (window == null) {
      throw PdfGenerationException(
        'Iframe window not available',
        phase: PdfGenerationPhase.download,
      );
    }

    // Focus the iframe window and trigger print
    window.focus();

    // Small delay to ensure focus
    await Future.delayed(const Duration(milliseconds: 50));

    // Trigger print
    window.print();
  }

  /// Log a debug message.
  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Print] $message');
    }
  }
}

/// Direct download strategy using Blob.
///
/// This provides a way to trigger download without print dialog
/// when bytes are already available.
class BlobDownloader {
  /// Download bytes as a file.
  static void download({
    required List<int> bytes,
    required String filename,
    String mimeType = 'application/pdf',
  }) {
    // Create typed array from bytes
    final uint8List = Uint8List.fromList(bytes);
    final jsArray = uint8List.toJS;

    // Create blob from bytes
    final blob = web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));

    // Create object URL
    final url = web.URL.createObjectURL(blob);

    // Create and click download link
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();

    // Cleanup
    Future.delayed(const Duration(milliseconds: 100), () {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    });
  }
}
