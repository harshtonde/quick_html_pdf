# Changelog

## 2.0.1

### Bug Fixes

- **Fixed NativeByteBuffer to Uint8List conversion error**
  - `jsPDF.output('arraybuffer')` returns JavaScript `ArrayBuffer`, not `Uint8Array`
  - Fixed conversion: `JSArrayBuffer` → `ByteBuffer` → `Uint8List` using `.toDart.asUint8List()`
  - Resolved `TypeError: type 'NativeByteBuffer' is not a subtype of type 'NativeUint8List'`

- **Fixed Unicode/Hindi text not rendering in headers and footers**
  - Previous implementation used `pdf.text()` which relies on jsPDF's built-in fonts (Helvetica, Times, Courier) without Unicode support
  - Now renders headers/footers using html2canvas (same as main content)
  - Browser's font rendering engine properly handles Hindi, Chinese, Arabic, and all Unicode characters
  - Added 'Noto Sans Devanagari' to default font stack for Hindi support

### Improvements

- Headers and footers now use the same rendering pipeline as main content for consistent output
- Temporary DOM elements used for header/footer rendering are properly cleaned up

## 2.0.0

### New Features

- **Intelligent Page Breaks for Bytes Mode**
  - Integrated html2pdf.js for smart content splitting
  - Respects CSS `page-break-inside: avoid` on elements
  - Respects CSS `page-break-before: always` and `page-break-after: always`
  - Respects `orphans` and `widows` CSS properties
  - Finds natural break points between block elements
  - Falls back to legacy html2canvas + jsPDF if html2pdf.js is not available
  - Configurable `pageBreakModes` option: `css`, `avoidAll`, `legacy`

- **Headers/Footers with Dynamic Page Numbers**
  - `{{page}}` placeholder replaced with current page number (1, 2, 3...)
  - `{{pages}}` placeholder replaced with total page count
  - `{{date}}` placeholder for current date
  - `{{time}}` placeholder for current time
  - `{{datetime}}` placeholder for date and time
  - Headers/footers render on every page at consistent positions
  - Configurable `headerHeightMm` and `footerHeightMm`
  - Configurable `headerFontSize` and `footerFontSize`
  - Optional separator lines with `showHeaderLine` and `showFooterLine`
  - Content area automatically adjusted for header/footer space

### Breaking Changes

- Bytes mode now requires html2pdf.js for intelligent page breaks (recommended)
- Update your `web/index.html` to use the new script:
  ```html
  <script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
  ```

### Improvements

- Added utility CSS classes: `.page-break-before`, `.keep-with-next`
- Cards, sections, and invoice items now have `page-break-inside: avoid` by default
- Better orphan/widow handling for paragraphs and list items

## 1.0.2

- Add repository metadata

## 1.0.1

- Documentation improvements

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
