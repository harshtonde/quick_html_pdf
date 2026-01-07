/// Stub implementation for non-web platforms.
///
/// This throws UnsupportedError on all non-web platforms
/// since this package is web-only.
library;

import 'dart:typed_data';

import '../options.dart';

/// Generate a PDF from an HTML template with dynamic data.
///
/// This is the stub implementation that throws UnsupportedError
/// on non-web platforms.
Future<Uint8List?> generatePdf({
  required String htmlTemplate,
  required Map<String, dynamic> data,
  PdfOptions options = const PdfOptions(),
}) async {
  throw UnsupportedError(
    'QuickHtmlPdf is only supported on Flutter Web.\n'
    'This package uses JavaScript interoperability to generate PDFs '
    'in the browser and cannot run on mobile or desktop platforms.\n\n'
    'For native platform PDF generation, consider using packages like:\n'
    '- pdf (https://pub.dev/packages/pdf)\n'
    '- printing (https://pub.dev/packages/printing)\n'
    '- syncfusion_flutter_pdf (https://pub.dev/packages/syncfusion_flutter_pdf)',
  );
}

/// Trigger a download of bytes as a PDF file.
///
/// This is the stub implementation that throws UnsupportedError
/// on non-web platforms.
void downloadPdfBytes({required Uint8List bytes, required String filename}) {
  throw UnsupportedError(
    'QuickHtmlPdf.downloadPdfBytes is only supported on Flutter Web.\n'
    'File downloads via browser APIs are not available on native platforms.',
  );
}
