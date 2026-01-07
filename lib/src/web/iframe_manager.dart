/// Iframe management for rendering HTML content.
///
/// Handles iframe lifecycle, content injection, and resource loading.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../options.dart';

/// Manages iframe creation, content loading, and cleanup.
class IframeManager {
  /// The iframe element.
  web.HTMLIFrameElement? _iframe;

  /// Unique ID for this iframe.
  final String _id;

  /// Whether debug logging is enabled.
  final bool debug;

  /// Create an iframe manager with optional debug logging.
  IframeManager({this.debug = false})
    : _id = 'qhp_${DateTime.now().millisecondsSinceEpoch}';

  /// Get the iframe element.
  web.HTMLIFrameElement? get iframe => _iframe;

  /// Get the iframe's document.
  web.Document? get document => _iframe?.contentDocument;

  /// Get the iframe's window.
  web.Window? get window => _iframe?.contentWindow;

  /// Get the iframe's body element.
  web.HTMLElement? get body => document?.body;

  /// Create and inject an iframe with the given HTML content.
  ///
  /// [html] - Complete HTML document to render
  /// [visible] - Whether iframe should be visible (needed for canvas capture)
  /// [options] - PDF options for sizing
  Future<void> create({
    required String html,
    required bool visible,
    required PdfOptions options,
  }) async {
    final startTime = DateTime.now();

    // Create iframe
    _iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
    _iframe!.id = _id;

    // Style the iframe
    if (visible) {
      // Visible iframe for canvas rendering
      _iframe!.style
        ..position = 'fixed'
        ..top = '0'
        ..left = '0'
        ..width = '${options.effectiveWidthMm}mm'
        ..height = '100vh'
        ..border = 'none'
        ..opacity =
            '0.01' // Nearly invisible but still renders
        ..pointerEvents = 'none'
        ..zIndex = '-9999';
    } else {
      // Hidden iframe for print
      _iframe!.style
        ..position = 'fixed'
        ..top = '-10000px'
        ..left = '-10000px'
        ..width = '${options.effectiveWidthMm}mm'
        ..height = '${options.effectiveHeightMm}mm'
        ..border = 'none'
        ..visibility = 'hidden';
    }

    // Add to document
    web.document.body?.appendChild(_iframe!);

    // Wait for iframe to be ready
    await _waitForIframe();

    // Write content to iframe
    _writeContent(html);

    // Wait for content to load
    await _waitForContentLoad();

    if (debug) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _log('Iframe created and content loaded in ${elapsed}ms');
    }
  }

  /// Wait for iframe to be ready.
  Future<void> _waitForIframe() async {
    final completer = Completer<void>();

    void onLoad(web.Event _) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _iframe!.onLoad.listen(onLoad);

    // Trigger load by setting src or srcdoc
    _iframe!.src = 'about:blank';

    // Timeout after 5 seconds
    await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        // Continue anyway - iframe might be ready
      },
    );
  }

  /// Write HTML content to the iframe.
  void _writeContent(String html) {
    final doc = _iframe?.contentDocument;
    if (doc != null) {
      doc.open();
      doc.write(html.toJS);
      doc.close();
    }
  }

  /// Wait for content, fonts, and images to load.
  Future<void> _waitForContentLoad() async {
    final doc = document;
    if (doc == null) return;

    // Wait for DOM to be ready
    await Future.delayed(const Duration(milliseconds: 50));

    // Wait for fonts
    try {
      await _waitForFonts(doc);
      if (debug) _log('Fonts loaded');
    } catch (e) {
      if (debug) _log('Font loading check failed: $e');
    }

    // Wait for images
    await _waitForImages();
  }

  /// Wait for fonts to load.
  Future<void> _waitForFonts(web.Document doc) async {
    final completer = Completer<void>();

    // Use a timeout-based approach
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Try to wait for fonts via JS
    try {
      final fonts = doc.fonts;
      fonts.ready.toDart
          .then((_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          })
          .catchError((_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          });
    } catch (_) {
      // Fonts API not available, complete immediately
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    await completer.future;
  }

  /// Wait for all images to load.
  Future<void> _waitForImages() async {
    final doc = document;
    if (doc == null) return;

    final images = doc.querySelectorAll('img');
    if (images.length == 0) return;

    final futures = <Future<void>>[];

    for (var i = 0; i < images.length; i++) {
      final img = images.item(i) as web.HTMLImageElement?;
      if (img == null) continue;

      if (img.complete) continue;

      final completer = Completer<void>();

      img.onLoad.first.then((_) {
        if (!completer.isCompleted) completer.complete();
      });

      img.onError.first.then((_) {
        if (!completer.isCompleted) {
          if (debug) _log('Image failed to load: ${img.src}');
          completer.complete(); // Continue anyway
        }
      });

      futures.add(
        completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            if (debug) _log('Image load timed out: ${img.src}');
          },
        ),
      );
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      if (debug) _log('${futures.length} images processed');
    }
  }

  /// Wait for resources with a timeout.
  Future<void> waitForResources({int timeoutMs = 10000}) async {
    final startTime = DateTime.now();

    await Future.any([
      _waitForContentLoad(),
      Future.delayed(Duration(milliseconds: timeoutMs)),
    ]);

    if (debug) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _log('Resources loaded in ${elapsed}ms');
    }
  }

  /// Get the full scrollable height of the content.
  int get contentHeight {
    final body = this.body;
    if (body == null) return 0;
    return body.scrollHeight;
  }

  /// Get the full scrollable width of the content.
  int get contentWidth {
    final body = this.body;
    if (body == null) return 0;
    return body.scrollWidth;
  }

  /// Scroll to a specific position in the iframe.
  void scrollTo(int x, int y) {
    final scrollOptions = web.ScrollToOptions(
      left: x.toDouble(),
      top: y.toDouble(),
    );
    window?.scrollTo(scrollOptions);
  }

  /// Dispose of the iframe and clean up resources.
  void dispose() {
    if (_iframe != null) {
      _iframe!.remove();
      _iframe = null;
      if (debug) _log('Iframe disposed');
    }
  }

  /// Log a debug message.
  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf] $message');
    }
  }
}
