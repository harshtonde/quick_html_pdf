#!/usr/bin/env dart
/// Command-line tool to add required JS scripts to index.html.
///
/// Usage:
///   dart run quick_html_pdf:add_scripts [path/to/web/index.html]
///
/// If no path is provided, it will look for web/index.html in the current directory.
library;

import 'dart:io';

const _html2canvasScript =
    '<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>';
const _jspdfScript =
    '<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>';

const _comment = '''
  <!-- Required JS libraries for quick_html_pdf bytes mode -->
  <!-- Only needed if you use PdfOutput.bytes -->''';

void main(List<String> args) {
  // Determine the index.html path
  final indexPath = args.isNotEmpty ? args[0] : 'web/index.html';
  final file = File(indexPath);

  if (!file.existsSync()) {
    stderr.writeln('❌ Error: File not found: $indexPath');
    stderr.writeln('');
    stderr.writeln('Usage: dart run quick_html_pdf:add_scripts [path/to/index.html]');
    stderr.writeln('');
    stderr.writeln('If no path is provided, looks for web/index.html');
    exit(1);
  }

  var content = file.readAsStringSync();

  // Check if scripts are already present
  final hasHtml2canvas = content.contains('html2canvas');
  final hasJspdf = content.contains('jspdf');

  if (hasHtml2canvas && hasJspdf) {
    stdout.writeln('✅ Scripts already present in $indexPath');
    stdout.writeln('   - html2canvas: ✓');
    stdout.writeln('   - jsPDF: ✓');
    exit(0);
  }

  // Find insertion point - before </head>
  final headCloseIndex = content.indexOf('</head>');
  if (headCloseIndex == -1) {
    stderr.writeln('❌ Error: Could not find </head> tag in $indexPath');
    exit(1);
  }

  // Build the scripts to add
  final scriptsToAdd = StringBuffer();

  if (!hasHtml2canvas || !hasJspdf) {
    scriptsToAdd.writeln();
    scriptsToAdd.writeln(_comment);
  }

  if (!hasHtml2canvas) {
    scriptsToAdd.writeln('  $_html2canvasScript');
  }

  if (!hasJspdf) {
    scriptsToAdd.writeln('  $_jspdfScript');
  }

  // Insert scripts before </head>
  content = content.substring(0, headCloseIndex) +
      scriptsToAdd.toString() +
      content.substring(headCloseIndex);

  // Write back
  file.writeAsStringSync(content);

  stdout.writeln('✅ Scripts added to $indexPath');
  if (!hasHtml2canvas) stdout.writeln('   + html2canvas');
  if (!hasJspdf) stdout.writeln('   + jsPDF');
  stdout.writeln('');
  stdout.writeln('These scripts are required for PdfOutput.bytes mode.');
  stdout.writeln('If you only use PdfOutput.download, you can remove them.');
}
