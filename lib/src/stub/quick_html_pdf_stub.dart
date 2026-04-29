/// Stub implementation for non-web platforms.
///
/// QuickHtmlPdf v3 uses the browser DOM for layout measurement and jsPDF
/// for vector emission — both browser-only. There is no native equivalent in
/// scope. This stub throws `UnsupportedError` for any entry point.
library;

import 'dart:typed_data';

import '../options.dart';

const _msg =
    'QuickHtmlPdf is only supported on Flutter Web.\n'
    'Vector PDF generation reads layout from the browser DOM and emits via '
    'jsPDF in the parent window — both browser-only. There is no native '
    'equivalent.\n\n'
    'For native platform PDF generation, consider:\n'
    '- pdf (https://pub.dev/packages/pdf)\n'
    '- printing (https://pub.dev/packages/printing)\n'
    '- syncfusion_flutter_pdf (https://pub.dev/packages/syncfusion_flutter_pdf)';

Future<Uint8List?> generatePdf({
  required String htmlTemplate,
  required Map<String, dynamic> data,
  PdfOptions options = const PdfOptions(),
}) async {
  throw UnsupportedError(_msg);
}

void downloadPdfBytes({required Uint8List bytes, required String filename}) {
  throw UnsupportedError(_msg);
}
