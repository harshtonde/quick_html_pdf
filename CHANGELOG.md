# Changelog

## 1.0.0

Initial release of QuickHtmlPdf - a fast HTML to PDF conversion package for Flutter Web.

### Features

- **Hybrid PDF Generation Strategy**

  - `PdfOutput.download`: Instant PDF via native browser print (~50ms)
  - `PdfOutput.bytes`: Returns PDF as `Uint8List` using html2canvas + jsPDF

- **Template Engine**

  - `{{key}}` - HTML-escaped interpolation
  - `{{nested.path}}` - Dot notation for nested objects
  - `{{{rawHtml}}}` - Unescaped HTML insertion
  - `{{#each items}}...{{/each}}` - Loop blocks
  - `{{@index}}`, `{{@index1}}` - Loop index variables

- **PDF Options**

  - Page formats: A4, Letter, Legal
  - Orientations: Portrait, Landscape
  - Custom margins
  - Custom header and footer HTML
  - Configurable scale and image quality

- **Print CSS**

  - Automatic `@page` rules for correct sizing
  - Table header repetition across pages
  - Page break utilities (`.page-break`, `.no-break`)

- **Large Document Support**

  - Chunked rendering for 200+ page documents
  - Memory-efficient sequential page processing

- **Developer Experience**
  - Debug mode with timing logs
  - Clear error messages with phase information
  - `UnsupportedError` on non-web platforms
