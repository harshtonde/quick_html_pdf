# QuickHtmlPdf

A fast, high-performance Flutter Web package for converting HTML templates with dynamic data into PDFs using JavaScript interoperability.

## Features

- **Instant Download Mode**: Uses native browser print for near-instant PDF generation (~50ms)
- **Bytes Mode**: Returns PDF as `Uint8List` for further processing (upload, store, etc.)
- **Template Engine**: Support for `{{placeholders}}`, loops, and raw HTML insertion
- **Print CSS**: Optimized CSS for accurate pagination and table handling
- **Large Documents**: Chunked rendering for 200+ page documents
- **Header/Footer**: Custom header and footer support for each page
- **Multiple Formats**: A4, Letter, Legal with portrait/landscape orientation

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  quick_html_pdf: ^1.0.0
```

### Required: Add JS Libraries (for Bytes Mode)

If you plan to use `PdfOutput.bytes`, add these scripts to your `web/index.html`:

```html
<head>
  <!-- ... other head content ... -->

  <!-- Required for bytes mode only -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
</head>
```

**Note:** These libraries are NOT required for `PdfOutput.download` mode, which uses the browser's native print dialog.

## Quick Start

### Basic Usage

```dart
import 'package:quick_html_pdf/quick_html_pdf.dart';

// Generate PDF and trigger download
await QuickHtmlPdf.generate(
  htmlTemplate: '<h1>Hello {{name}}</h1>',
  data: {'name': 'World'},
  options: PdfOptions(
    output: PdfOutput.download,
    filename: 'hello.pdf',
  ),
);
```

### Get PDF as Bytes

```dart
final bytes = await QuickHtmlPdf.generate(
  htmlTemplate: '<h1>Hello {{name}}</h1>',
  data: {'name': 'World'},
  options: PdfOptions(output: PdfOutput.bytes),
);

if (bytes != null) {
  print('PDF size: ${bytes.length} bytes');
  // Upload, store, or process the bytes

  // Or trigger download manually:
  QuickHtmlPdf.downloadBytes(bytes: bytes, filename: 'hello.pdf');
}
```

## Template Syntax

### Simple Interpolation

```dart
// Template
'<p>Hello {{name}}, you have {{count}} messages.</p>'

// Data
{'name': 'John', 'count': 5}

// Output
'<p>Hello John, you have 5 messages.</p>'
```

### Nested Objects

```dart
// Template
'<p>{{user.name}} works at {{user.company.name}}</p>'

// Data
{
  'user': {
    'name': 'Alice',
    'company': {'name': 'Acme Corp'}
  }
}
```

### Loops with `{{#each}}`

```dart
// Template
'''
<table>
  <tr><th>Item</th><th>Price</th></tr>
  {{#each items}}
  <tr>
    <td>{{this.name}}</td>
    <td>{{this.price}}</td>
  </tr>
  {{/each}}
</table>
'''

// Data
{
  'items': [
    {'name': 'Widget', 'price': '\$10'},
    {'name': 'Gadget', 'price': '\$20'},
  ]
}
```

### Loop Variables

- `{{this}}` - Current item value
- `{{this.field}}` - Field of current item
- `{{@index}}` - Zero-based loop index
- `{{@index1}}` - One-based loop index
- `{{@first}}` - True if first iteration
- `{{@last}}` - True if last iteration

### Raw HTML (Unescaped)

```dart
// Template - triple braces for raw HTML
'<div>{{{htmlContent}}}</div>'

// Data
{'htmlContent': '<strong>Bold</strong>'}

// Output (HTML is not escaped)
'<div><strong>Bold</strong></div>'
```

### HTML Escaping

Regular `{{}}` automatically escapes HTML entities:

```dart
// Template
'<p>{{userInput}}</p>'

// Data
{'userInput': '<script>alert("xss")</script>'}

// Output (safely escaped)
'<p>&lt;script&gt;alert("xss")&lt;/script&gt;</p>'
```

## Configuration Options

```dart
PdfOptions(
  // Page format (default: A4)
  pageFormat: PdfPageFormat.a4,  // or .letter, .legal

  // Orientation (default: portrait)
  orientation: PdfOrientation.portrait,  // or .landscape

  // Margins in millimeters
  margins: PdfMargins(
    topMm: 20,
    rightMm: 15,
    bottomMm: 20,
    leftMm: 15,
  ),

  // Output mode
  output: PdfOutput.download,  // or .bytes

  // Filename for download
  filename: 'document.pdf',

  // Optional header HTML (appears on each page)
  headerHtml: '<div>Company Name</div>',

  // Optional footer HTML (appears on each page)
  footerHtml: '<div>Page footer</div>',

  // Debug logging
  debug: false,

  // Advanced: Scale for canvas rendering (bytes mode only)
  scale: 1.5,  // Higher = better quality, slower

  // Advanced: JPEG quality (bytes mode only)
  imageQuality: 0.92,

  // Advanced: Resource loading timeout
  resourceTimeoutMs: 10000,
)
```

## Sample Templates

### Simple Invoice (Single Page)

```dart
const invoiceTemplate = '''
<div style="font-family: Arial, sans-serif; padding: 40px;">
  <div style="display: flex; justify-content: space-between;">
    <div>
      <h1 style="margin: 0;">INVOICE</h1>
      <p>{{company.name}}</p>
    </div>
    <div style="text-align: right;">
      <p><strong>Invoice #:</strong> {{invoiceNumber}}</p>
      <p><strong>Date:</strong> {{date}}</p>
    </div>
  </div>

  <div style="margin: 30px 0;">
    <h3>Bill To:</h3>
    <p>{{customer.name}}<br>{{customer.address}}</p>
  </div>

  <table style="width: 100%; border-collapse: collapse;">
    <thead>
      <tr style="background: #f5f5f5;">
        <th style="padding: 12px; text-align: left; border-bottom: 2px solid #ddd;">Item</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #ddd;">Qty</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #ddd;">Price</th>
        <th style="padding: 12px; text-align: right; border-bottom: 2px solid #ddd;">Total</th>
      </tr>
    </thead>
    <tbody>
      {{#each items}}
      <tr>
        <td style="padding: 12px; border-bottom: 1px solid #eee;">{{this.name}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #eee;">{{this.qty}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #eee;">{{this.price}}</td>
        <td style="padding: 12px; text-align: right; border-bottom: 1px solid #eee;">{{this.total}}</td>
      </tr>
      {{/each}}
    </tbody>
  </table>

  <div style="text-align: right; margin-top: 20px;">
    <p style="font-size: 20px;"><strong>Total: {{grandTotal}}</strong></p>
  </div>
</div>
''';

// Generate invoice
await QuickHtmlPdf.generate(
  htmlTemplate: invoiceTemplate,
  data: {
    'company': {'name': 'Acme Corp'},
    'invoiceNumber': 'INV-001',
    'date': 'January 8, 2024',
    'customer': {
      'name': 'John Smith',
      'address': '123 Main St, City, ST 12345',
    },
    'items': [
      {'name': 'Widget', 'qty': 2, 'price': '\$50.00', 'total': '\$100.00'},
      {'name': 'Gadget', 'qty': 1, 'price': '\$75.00', 'total': '\$75.00'},
    ],
    'grandTotal': '\$175.00',
  },
  options: PdfOptions(
    output: PdfOutput.download,
    filename: 'invoice.pdf',
  ),
);
```

### Large Report (Multi-Page with Table)

```dart
const reportTemplate = '''
<div style="font-family: Arial, sans-serif;">
  <h1 style="text-align: center;">{{title}}</h1>
  <p style="text-align: center; color: #666;">Generated: {{date}}</p>

  <table style="width: 100%; border-collapse: collapse; font-size: 11px;">
    <thead>
      <tr style="background: #1e40af; color: white;">
        <th style="padding: 8px;">#</th>
        <th style="padding: 8px;">Date</th>
        <th style="padding: 8px;">Customer</th>
        <th style="padding: 8px;">Product</th>
        <th style="padding: 8px; text-align: right;">Amount</th>
      </tr>
    </thead>
    <tbody>
      {{#each rows}}
      <tr style="{{this.rowStyle}}">
        <td style="padding: 6px; border-bottom: 1px solid #eee;">{{@index1}}</td>
        <td style="padding: 6px; border-bottom: 1px solid #eee;">{{this.date}}</td>
        <td style="padding: 6px; border-bottom: 1px solid #eee;">{{this.customer}}</td>
        <td style="padding: 6px; border-bottom: 1px solid #eee;">{{this.product}}</td>
        <td style="padding: 6px; border-bottom: 1px solid #eee; text-align: right;">{{this.amount}}</td>
      </tr>
      {{/each}}
    </tbody>
  </table>
</div>
''';

// Generate 1000 rows of data
final rows = List.generate(1000, (i) => {
  'date': '2024-01-${(i % 28 + 1).toString().padLeft(2, '0')}',
  'customer': 'Customer ${i + 1}',
  'product': 'Product ${(i % 10) + 1}',
  'amount': '\$${(i * 10 + 99).toStringAsFixed(2)}',
  'rowStyle': i.isOdd ? 'background: #f9f9f9;' : '',
});

await QuickHtmlPdf.generate(
  htmlTemplate: reportTemplate,
  data: {
    'title': 'Sales Report 2024',
    'date': 'January 8, 2024',
    'rows': rows,
  },
  options: PdfOptions(
    output: PdfOutput.download,
    filename: 'sales-report.pdf',
    headerHtml: '<div><strong>Sales Report</strong></div>',
    footerHtml: '<div style="color: #666;">Confidential</div>',
  ),
);
```

## Performance Tips for Large PDFs

### Use Download Mode When Possible

`PdfOutput.download` is significantly faster than `PdfOutput.bytes`:

| Document Size | Download Mode | Bytes Mode |
| ------------- | ------------- | ---------- |
| 10 pages      | ~50ms         | ~500ms     |
| 100 pages     | ~50ms         | ~3s        |
| 300 pages     | ~50ms         | ~8s        |

Download mode leverages the browser's native PDF engine, while bytes mode must render each page as a canvas.

### Optimize Table Structure

```html
<!-- Good: thead repeats on each page -->
<table>
  <thead>
    <tr>
      <th>Header</th>
    </tr>
  </thead>
  <tbody>
    {{#each rows}}
    <tr>
      <td>{{this.value}}</td>
    </tr>
    {{/each}}
  </tbody>
</table>
```

### Use Page Breaks Strategically

```html
<!-- Force page break after a section -->
<div class="page-break"></div>

<!-- Keep content together -->
<div class="no-break">
  <h2>Section Title</h2>
  <p>This content stays together</p>
</div>
```

### Reduce Image Quality for Bytes Mode

```dart
PdfOptions(
  output: PdfOutput.bytes,
  scale: 1.0,        // Lower scale = faster (default 1.5)
  imageQuality: 0.8, // Lower quality = smaller file
)
```

### Pre-render Template for Multiple Outputs

```dart
// Render template once
final renderedHtml = TemplateEngine.render(template, data);

// Compose full HTML
final fullHtml = HtmlComposer.compose(renderedHtml, options);

// Generate multiple PDFs from same rendered content
// (Avoid re-rendering template each time)
```

## Limitations

1. **Web Only**: This package only works on Flutter Web. It throws `UnsupportedError` on mobile and desktop platforms.

2. **External Images**: Images from external URLs may not render correctly due to CORS restrictions. Use base64-encoded images or self-hosted images when possible.

3. **Custom Fonts**: Web fonts must be loaded before PDF generation. The package waits for `document.fonts.ready`, but ensure fonts are properly linked in your HTML.

4. **Complex CSS**: Some advanced CSS features (flexbox with wrapping, CSS grid) may not paginate perfectly. Test your templates with large datasets.

5. **JavaScript Libraries**: Bytes mode requires html2canvas and jsPDF libraries to be loaded in `index.html`.

## Platform Support

| Platform | Supported |
| -------- | --------- |
| Web      | ✅        |
| Android  | ❌        |
| iOS      | ❌        |
| macOS    | ❌        |
| Windows  | ❌        |
| Linux    | ❌        |

For native platform PDF generation, consider using:

- [pdf](https://pub.dev/packages/pdf)
- [printing](https://pub.dev/packages/printing)
- [syncfusion_flutter_pdf](https://pub.dev/packages/syncfusion_flutter_pdf)

## Error Handling

```dart
try {
  await QuickHtmlPdf.generate(
    htmlTemplate: template,
    data: data,
    options: PdfOptions(output: PdfOutput.bytes),
  );
} on UnsupportedError catch (e) {
  // Platform not supported
  print('Web only: $e');
} on TemplateException catch (e) {
  // Template syntax error
  print('Template error: ${e.message}');
} on PdfGenerationException catch (e) {
  // PDF generation failed
  print('PDF error: ${e.message} (phase: ${e.phase})');
}
```

## Debug Mode

Enable debug logging to see timing information:

```dart
await QuickHtmlPdf.generate(
  htmlTemplate: template,
  data: data,
  options: PdfOptions(debug: true),
);

// Console output:
// [QuickHtmlPdf] Template rendered in 5ms
// [QuickHtmlPdf] Rendered HTML size: 125.3 KB
// [QuickHtmlPdf] HTML composed in 2ms
// [QuickHtmlPdf] Full HTML size: 128.7 KB
// [QuickHtmlPdf:Bytes] Page size: 210mm x 297mm
// [QuickHtmlPdf:Bytes] Rendering 42 pages...
// [QuickHtmlPdf:Bytes] Rendered 10/42 pages
// ...
// [QuickHtmlPdf] ===== Generation Complete =====
// [QuickHtmlPdf] Total time: 3250ms
// [QuickHtmlPdf] Output: 2.4 MB
```

## License

MIT License - see [LICENSE](LICENSE) for details.
