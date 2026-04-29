# QuickHtmlPdf

Fast HTML-to-PDF for Flutter Web. Produces vector PDFs (selectable, searchable text) without a CDN dependency.

## Features

- **Three output modes** — `print` (browser dialog), `download` (silent file save), `bytes` (`Uint8List` for upload/processing).
- **Vector PDF output** — text is selectable and searchable; small file sizes; fast generation. Built on a custom Dart-side measure-and-flow paginator that reads layout off the rendered iframe DOM, plus `jsPDF` (vendored) for vector emission, driven by a custom DOM walker.
- **Built for table-heavy docs** — the paginator slices oversized tables row-by-row (preserving `<thead>`) and handles multi-table flex-row layouts with a two-phase pass (side-by-side slices while both halves have content, then full-width tail slices once the shorter sibling exhausts). Empirically 100–200× faster than a generic CSS-Paged-Media polyfill on a 200-page tax form (~1 s vs 4–5 min).
- **Self-contained at runtime** — jsPDF (~360 KB) is vendored as a Flutter package asset and lazy-loaded on the first vector-mode call. No `<script>` tags to add to `web/index.html`. No CDN at runtime.
- **Per-page chrome** — header / footer / watermark slots built inside each `qhp-page` wrapper from `PdfOptions.headerHtml`, `footerHtml`, `watermarkUrl`. Page-counter and date/time placeholders substituted per page.
- **Template engine** — `{{placeholders}}`, dot notation, raw HTML, `{{#each}}` loops, `{{@index}}`.
- **Fail loudly** — vector mode throws clear, coded exceptions when fonts aren't registered or text contains glyphs the registered font can't render. No silent visual loss.

## Platform support

Web only. Throws `UnsupportedError` on mobile and desktop.

## Installation

```yaml
dependencies:
  quick_html_pdf: ^3.0.0
```

That's it — no script-tag setup needed.

## Quick start

### `print` mode — browser dialog (no font setup)

```dart
import 'package:quick_html_pdf/quick_html_pdf.dart';

await QuickHtmlPdf.generate(
  htmlTemplate: '<h1>Hello {{name}}</h1>',
  data: {'name': 'World'},
  options: const PdfOptions(output: PdfOutput.print),
);
// Browser print dialog opens; user picks "Save as PDF".
```

### `download` mode — silent file save (requires fonts)

```dart
await QuickHtmlPdf.generate(
  htmlTemplate: '<h1>Hello {{name}}</h1>',
  data: {'name': 'World'},
  options: const PdfOptions(
    output: PdfOutput.download,
    filename: 'hello.pdf',
    fonts: [
      PdfFont(
        family: 'Liberation Sans',
        src: 'assets/fonts/LiberationSans-Regular.ttf',
      ),
      PdfFont(
        family: 'Liberation Sans',
        src: 'assets/fonts/LiberationSans-Bold.ttf',
        weight: 'bold',
      ),
    ],
  ),
);
// hello.pdf saves directly to the user's downloads folder. No dialog.
```

### `bytes` mode — Uint8List for upload/processing

```dart
final bytes = await QuickHtmlPdf.generate(
  htmlTemplate: '<h1>Report</h1>',
  data: {},
  options: PdfOptions(
    output: PdfOutput.bytes,
    fonts: [/* …same as above… */],
  ),
);
// bytes is a Uint8List — POST to a server, store in IndexedDB, etc.
```

## Output modes summary

| Mode | Returns | Browser dialog | Vector | Speed (100 pages, modern laptop) | When to use |
|---|---|---|---|---|---|
| `print` | `null` | yes | yes | <1 s | User can also send to a physical printer; you don't mind a dialog |
| `download` | `null` | **no** | yes | ~1–3 s | Silent file save — typical PDF download UX |
| `bytes` | `Uint8List` | no | yes | ~1–3 s | Upload to API / store in IndexedDB / process before saving |

## Custom fonts (required for vector modes)

`PdfOutput.download` and `PdfOutput.bytes` require at least one font registered via `PdfOptions.fonts`. Without one, generation throws:

```
PdfGenerationException: Vector PDF mode requires at least one font registered
via PdfOptions.fonts. (phase: vectorEmission, code: no-fonts-registered)
```

This is deliberate — silently falling back to jsPDF's WinAnsi-only built-ins would render any non-Latin-1 character (₹ ™ © Hindi etc.) as the wrong glyph in production output. Better to fail loudly.

`PdfOutput.print` does not need font registration — the browser uses system fonts.

### Two ways to provide font data

`PdfFont` accepts either `src` (URL — fetched at register time) or `bytes` (raw `Uint8List`):

```dart
import 'package:flutter/services.dart' show rootBundle;

// Option A: load via rootBundle (recommended for Flutter-asset fonts).
final regularBytes =
    (await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')).buffer.asUint8List();

PdfFont(family: 'Noto Sans', bytes: regularBytes);

// Option B: same-origin URL (the package will fetch it).
PdfFont(family: 'Noto Sans', src: 'fonts/NotoSans-Regular.ttf');
```

### Recommended choices

- **Liberation Sans** — metric-compatible with Arial, OFL-licensed, includes ₹ and Latin Extended. Best when your CSS uses `font-family: Arial, Helvetica, sans-serif`.
- **Noto Sans Devanagari** — covers Latin + ₹ + Devanagari. Right when content includes Hindi names alongside English / numeric data (e.g. Indian government / financial forms).

For CJK content, register the matching Noto family (Noto Sans CJK SC/JP/KR/TC).

## Template syntax

- `{{key}}` — HTML-escaped interpolation
- `{{nested.path}}` — dot notation
- `{{{rawHtml}}}` — unescaped HTML insertion
- `{{#each items}}…{{/each}}` — loops
- `{{this.field}}` — current item in loop
- `{{@index}}` / `{{@index1}}` — 0-based / 1-based loop index

In `headerHtml` / `footerHtml`:
- `{{page}}`, `{{pages}}` — current and total page numbers (substituted per page by the paginator)
- `{{date}}`, `{{time}}`, `{{datetime}}` — current local date / time

## Page breaks

Use CSS directly — the custom paginator honours `page-break-*` properties:

```css
.no-break       { page-break-inside: avoid; break-inside: avoid; }
.page-break     { page-break-after: always; break-after: page; }
.keep-with-next { page-break-after: avoid; break-after: avoid; }
```

(The `pageBreakModes` option from v2 is deprecated and inert.)

## Error handling

```dart
try {
  await QuickHtmlPdf.generate(...);
} on PdfGenerationException catch (e) {
  // e.phase   — domWalking | vectorEmission | iframeCreation | …
  // e.code    — stable machine-readable: 'no-fonts-registered',
  //             'glyph-fallback', 'jspdf-bootstrap-failed', …
  // e.cause   — underlying error
}
```

## Architecture

```
htmlTemplate + data
  → TemplateEngine.render
  → HtmlComposer.compose (page CSS only — no JS injected)
  → IframeManager.create (off-screen iframe — not visible)
  → wait for fonts/images
  → CustomPaginator.paginate (measure-and-flow over the live DOM;
                              two-phase for multi-table flex containers;
                              builds per-page qhp-page wrappers with
                              header/footer/watermark slots)
  → JsLibraries.bootstrapJsPdf (lazy, once)
  → JsPDF document + FontRegistry.register (consumer fonts)
  → DomWalker.renderPages (vector emission with width-sanity guards
                           and content-area clipping)
  → JsPDF.getBlob() / getBytes()  → BlobDownloader / Uint8List
```

## Limitations (v3.0)

- Web only.
- `print` mode renders SVG; vector modes (`download`/`bytes`) currently skip `<svg>`. Use `print` mode if your template depends on SVG.
- `background-image` data URLs only in v3.0; relative/network URLs deferred.
- Browser fidelity gap with vector mode: the DOM walker reads browser layout coordinates, so positions are correct, but jsPDF re-renders glyphs with its own font metrics. The width-sanity check + per-word fallback handle most cases; for ASCII + Liberation Sans against Arial, drift is usually <1 % per line. CJK / complex Indic scripts may need additional font registration and per-character emission.

## Bundled JS versions

- jsPDF: 2.5.1

## License

MIT.
