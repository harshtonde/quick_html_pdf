# Changelog

## 3.0.0

Production-grade vector PDF pipeline. Replaces the v2 raster (html2pdf/html2canvas) bytes path. Three output modes with consistent layout. No CDN at runtime.

### Breaking changes

- **`PdfOutput` enum reshape**: `{ bytes, download }` → `{ print, download, bytes }`.
  - `print` — opens the browser print dialog (was `download` in v2).
  - `download` — silent file save, no dialog. Uses the vector pipeline.
  - `bytes` — vector emission, returns `Uint8List`. v2's html2pdf raster path is gone.
- **Default output mode** changed from `download` to `print` (semantics preserved — both default behaviours open the browser print dialog).
- **Vector modes (`download`/`bytes`) require a registered font**. Pass `PdfOptions.fonts: [PdfFont(...)]`. Without registration, generation throws `PdfGenerationException(code: 'no-fonts-registered')` rather than silently substituting wrong glyphs (e.g. ₹ → ¹). `print` mode is unaffected.
- **No CDN at runtime**. jsPDF (~360 KB) is vendored as a Flutter package asset and lazy-loaded on the first vector-mode call. Consumer apps no longer add `<script>` tags to `web/index.html`.
- **Deprecated fields**: `PdfOptions.scale`, `PdfOptions.imageQuality`, `PdfOptions.pageBreakModes` (and `PageBreakMode` enum). Vector pipeline uses CSS `page-break-*` directly. Will be removed in v3.1.

### New

- **`CustomPaginator`** — measure-and-flow paginator written in Dart. Reads `getBoundingClientRect()` deltas off the rendered iframe DOM, slices oversized tables row-by-row (preserving `<thead>`), handles single-table containers AND multi-table flex-row containers (Form 26AS-style "Sections" panels) with a two-phase pass: half-width slices while both children have content, then full-width tail slices once the shorter sibling exhausts. Replaces the previously-considered Paged.js polyfill — 100–200× faster on table-heavy docs (~1 s vs ~4–5 min on a 200-page tax form).
- **`PdfFont`** — describes a TTF for jsPDF registration. Provide font data via either `src` (URL — `fetch`'d at register time) or `bytes` (raw `Uint8List`, e.g. from `rootBundle.load`). Plus `family`, `weight`, `style`.
- **Per-page chrome built by the paginator** — header / footer / watermark slots assembled inside each `<div class="qhp-page">` wrapper from `PdfOptions.headerHtml`, `footerHtml`, `watermarkUrl` (and `watermarkSize` / `watermarkPosition`). `{{page}}`, `{{pages}}`, `{{date}}`, `{{time}}`, `{{datetime}}` substitution is applied per-page.
- **Walker-level content clip** — `DomWalker` honors the `qhp-page-content` slot's `overflow: hidden` so descendants of the content area don't bleed into the footer band even if pagination measurements drift.
- **Pagination safety buffer** — paginator targets `contentHeight − 2 mm` so sub-pixel layout drift between source measurement and per-page re-layout doesn't push the last row past the content rectangle.
- **Fail-loud glyph fallback** in non-debug builds.
- **Background-image emission** in `_emitElementBox` (data: URL only in v3.0; network URLs deferred to v3.1).
- **Width-sanity per-line check** in DOM walker — drops down to per-word emission when jsPDF's metrics drift >5% from the browser's.
- **Per-word + per-character fallback** for high-fidelity text positioning when CSS letter-spacing / font-cascade differences cause drift.
- **`letter-spacing` and `word-spacing` CSS** propagated to jsPDF (`charSpace` parameter / per-word gap measurement).
- New `PdfGenerationPhase` values: `domWalking`, `vectorEmission`.
- New `PdfGenerationException.code` field — stable machine-readable codes for telemetry / consumer branching (`no-fonts-registered`, `glyph-fallback`, `jspdf-bootstrap-failed`, etc.).

### Migration from v2

```dart
// v2
await QuickHtmlPdf.generate(
  htmlTemplate: tpl,
  data: data,
  options: PdfOptions(output: PdfOutput.download),  // ← was: print dialog
);

// v3 — keep the dialog UX
await QuickHtmlPdf.generate(
  htmlTemplate: tpl,
  data: data,
  options: PdfOptions(output: PdfOutput.print),     // explicit
);

// v3 — silent download (new!)
await QuickHtmlPdf.generate(
  htmlTemplate: tpl,
  data: data,
  options: PdfOptions(
    output: PdfOutput.download,
    filename: 'report.pdf',
    fonts: [
      PdfFont(family: 'Liberation Sans', src: 'assets/fonts/LiberationSans-Regular.ttf'),
      PdfFont(family: 'Liberation Sans', src: 'assets/fonts/LiberationSans-Bold.ttf', weight: 'bold'),
    ],
  ),
);
```

### Bundled JS versions

- jsPDF: `2.5.1`

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
