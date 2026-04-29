/// DOM walker that emits jsPDF vector primitives.
///
/// Given a paginated page (`<div class="qhp-page">` produced by
/// [CustomPaginator]), this walker reads the laid-out coordinates from the
/// browser via `Range.getClientRects()` / `Element.getBoundingClientRect()`
/// and emits vector primitives via [JsPDF].
///
/// Coordinate translation: 1 CSS px = 0.75 pt at 96 DPI. jsPDF is
/// constructed with `unit: 'pt'` so the only math is `pdfPt = cssPx * 0.75`.
///
/// ## Fidelity strategy
///
/// The browser already did layout — line-break positions, character
/// positions, and box dimensions are correct. The risk is jsPDF re-laying
/// out the emitted text using its own font metrics (different from the
/// browser's), causing intra-line drift (CSS letter-spacing not honored,
/// kerning differs, etc.).
///
/// The walker mitigates this with a three-tier strategy per visual line:
///
/// 1. **Per-line emission** (fast path): one `pdf.text(slice, x, y)` per
///    line with `charSpace` set from CSS `letter-spacing`. Then measure
///    the slice's PDF width and compare to the browser's rect width.
/// 2. **Per-word emission** (fallback): if the per-line width drifts >5%,
///    re-emit the line word-by-word, placing each word at its measured
///    `Range.getBoundingClientRect()` position.
/// 3. **Per-character emission** (last resort): if per-word still drifts
///    >5% (rare; happens for very long words with kerning differences),
///    place each character at its individual rect.
library;

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import 'font_registry.dart';
import 'js_interop.dart';
import 'paginated_page.dart';

/// 1 CSS px = 0.75 pt at 96 DPI (the standard CSS reference DPI).
const double _pxToPt = 0.75;

/// Acceptable line-width drift between browser-measured and jsPDF-measured
/// before we drop down to per-word emission. 5% — when fonts match reasonably
/// well (e.g. consumer registered the same family the CSS selects), most
/// lines emit at this fast tier.
const double _lineWidthDriftThreshold = 0.05;

/// Per-word drift threshold before escalating to per-character. Higher than
/// the line threshold because per-word placement already anchors each word
/// to its browser-measured x; intra-word jsPDF metric variation is visually
/// fine until ~20% (after which characters within a word start overflowing
/// into the next word's space).
const double _wordWidthDriftThreshold = 0.20;

class DomWalker {
  final JsPDF pdf;
  final FontRegistry fonts;
  final web.Document iframeDocument;
  final bool debug;

  /// In release builds, throw rather than log when text contains characters
  /// the registered fonts can't render. In debug builds, just log.
  final bool failOnGlyphFallback;

  DomWalker({
    required this.pdf,
    required this.fonts,
    required this.iframeDocument,
    this.debug = false,
    this.failOnGlyphFallback = true,
  });

  /// Render all [pages] into [pdf]. The first page uses jsPDF's initial
  /// page; each subsequent page calls [JsPDF.addPage] first.
  void renderPages(List<PaginatedPage> pages) {
    final start = DateTime.now();
    for (var i = 0; i < pages.length; i++) {
      if (i > 0) pdf.addPage();
      pdf.setPage(i + 1);
      _renderPage(pages[i]);
    }
    if (debug) {
      final ms = DateTime.now().difference(start).inMilliseconds;
      _log('Emitted ${pages.length} pages in ${ms}ms');
    }
  }

  void _renderPage(PaginatedPage page) {
    try {
      final pageRect = page.element.getBoundingClientRect();
      // Default clip = page bottom (effectively no clip). The walker
      // tightens this when entering `.qhp-page-content` so descendants
      // don't bleed into the footer/margin band.
      _walkNode(
        page.element,
        pageRect,
        page.pageNumber,
        page.totalPages,
        pageRect.bottom + 1,
      );
    } catch (e) {
      throw PdfGenerationException(
        'DOM walker failed on page ${page.pageNumber}: $e',
        phase: PdfGenerationPhase.domWalking,
        code: 'walker-page-failed',
        cause: e,
      );
    }
  }

  // -------------------------------------------------------------- traversal

  void _walkNode(
    web.Node node,
    web.DOMRect pageRect,
    int pageNumber,
    int totalPages,
    double clipBottom,
  ) {
    final type = node.nodeType;

    if (type == web.Node.ELEMENT_NODE) {
      final el = node as web.Element;
      if (!_shouldRender(el)) return;
      final tag = el.tagName.toUpperCase();

      // Tighten the clip rect for descendants of the page content slot.
      // The slot has `overflow: hidden`, so visual rendering already
      // clips at this y; the walker honors the same boundary so it
      // doesn't emit content that visually got cut.
      var childClipBottom = clipBottom;
      if (el.classList.contains('qhp-page-content')) {
        final r = el.getBoundingClientRect();
        if (r.bottom < childClipBottom) childClipBottom = r.bottom;
      }

      // Drop the element entirely if it begins at or below the active
      // clip — children are guaranteed to start no higher than the
      // parent in normal block/table flow.
      final rect = el.getBoundingClientRect();
      if (rect.top >= clipBottom) return;

      // Element-level emission BEFORE descending: backgrounds and borders
      // sit underneath child content.
      _emitElementBox(el, pageRect);

      if (tag == 'IMG') {
        _emitImage(el as web.HTMLImageElement, pageRect);
        return;
      }
      if (tag == 'HR') {
        _emitHr(el, pageRect);
        return;
      }
      if (tag == 'SVG') {
        // SVG vector emission is out of scope for v3.0 — print mode renders
        // SVG correctly, vector mode does not. Form 26AS doesn't use SVG.
        if (debug) _log('Skipping SVG element (out of scope for v3)');
        return;
      }

      // Recurse into children.
      final children = el.childNodes;
      for (var i = 0; i < children.length; i++) {
        final child = children.item(i);
        if (child == null) continue;
        _walkNode(child, pageRect, pageNumber, totalPages, childClipBottom);
      }
      return;
    }

    if (type == web.Node.TEXT_NODE) {
      _emitText(
        node as web.Text,
        pageRect,
        pageNumber,
        totalPages,
        clipBottom,
      );
    }
    // Other node types (comment, etc.) are ignored.
  }

  bool _shouldRender(web.Element el) {
    final style = iframeDocument.defaultView?.getComputedStyle(el);
    if (style == null) return false;
    if (style.display == 'none') return false;
    if (style.visibility == 'hidden') return false;
    final opacity = double.tryParse(style.opacity);
    if (opacity != null && opacity == 0) return false;
    return true;
  }

  // ------------------------------------------------------------ box / borders

  /// Tracks data-URLs we've already added to jsPDF to dedupe across pages.
  /// Key = data URL string, value = the jsPDF "alias" so subsequent pages
  /// reference the same image bytes (jsPDF auto-dedupes when given the same
  /// imageData object).
  final Set<String> _emittedImageDataUrls = <String>{};

  void _emitElementBox(web.Element el, web.DOMRect pageRect) {
    final style = iframeDocument.defaultView?.getComputedStyle(el);
    if (style == null) return;

    final rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;

    final x = (rect.left - pageRect.left) * _pxToPt;
    final y = (rect.top - pageRect.top) * _pxToPt;
    final w = rect.width * _pxToPt;
    final h = rect.height * _pxToPt;

    // Background color first (under bg-image).
    final bg = _parseColor(style.backgroundColor);
    if (bg != null && bg.alpha > 0) {
      pdf.setFillColor(bg.r, bg.g, bg.b);
      pdf.rect(x, y, w, h, style: 'F');
    }

    // Background image (Form 26AS watermark).
    final bgImage = style.backgroundImage;
    if (bgImage.isNotEmpty && bgImage != 'none') {
      _emitBackgroundImage(el, style, rect, pageRect, bgImage);
    }

    // Borders. Each side independent so styles can differ.
    _emitBorderSide(el, style, rect, pageRect, _BorderSide.top);
    _emitBorderSide(el, style, rect, pageRect, _BorderSide.right);
    _emitBorderSide(el, style, rect, pageRect, _BorderSide.bottom);
    _emitBorderSide(el, style, rect, pageRect, _BorderSide.left);
  }

  void _emitBorderSide(
    web.Element el,
    web.CSSStyleDeclaration style,
    web.DOMRect rect,
    web.DOMRect pageRect,
    _BorderSide side,
  ) {
    final widthCss = style.getPropertyValue('border-${side.name}-width');
    final styleCss = style.getPropertyValue('border-${side.name}-style');
    final colorCss = style.getPropertyValue('border-${side.name}-color');
    final widthPx = _parsePxLength(widthCss);
    if (widthPx <= 0) return;
    if (styleCss.isEmpty || styleCss == 'none' || styleCss == 'hidden') return;

    final color = _parseColor(colorCss) ?? const _Rgb(0, 0, 0);
    pdf.setDrawColor(color.r, color.g, color.b);
    pdf.setLineWidth(widthPx * _pxToPt);

    final x = (rect.left - pageRect.left) * _pxToPt;
    final y = (rect.top - pageRect.top) * _pxToPt;
    final w = rect.width * _pxToPt;
    final h = rect.height * _pxToPt;

    switch (side) {
      case _BorderSide.top:
        pdf.line(x, y, x + w, y);
        break;
      case _BorderSide.right:
        pdf.line(x + w, y, x + w, y + h);
        break;
      case _BorderSide.bottom:
        pdf.line(x, y + h, x + w, y + h);
        break;
      case _BorderSide.left:
        pdf.line(x, y, x, y + h);
        break;
    }
  }

  // ------------------------------------------------------------ background-image

  void _emitBackgroundImage(
    web.Element el,
    web.CSSStyleDeclaration style,
    web.DOMRect rect,
    web.DOMRect pageRect,
    String bgImage,
  ) {
    // Only handle a single url(...) for v3.0. Gradient / multiple-bg deferred.
    final urlMatch =
        RegExp(r'''url\(\s*['"]?(.*?)['"]?\s*\)''').firstMatch(bgImage);
    if (urlMatch == null) return;
    final url = urlMatch.group(1)?.trim() ?? '';
    if (url.isEmpty) return;
    // Only data: URLs are synchronous; relative/absolute network URLs would
    // need an async fetch (deferred — Form 26AS uses data: URLs only).
    if (!url.startsWith('data:image/')) {
      if (debug) {
        _log('Skipping non-data background-image URL: '
            '${_truncate(url, 60)} (network fetch deferred to v3.1)');
      }
      return;
    }

    final format = _detectImageFormat(url);
    final size = _resolveBgSize(style, rect);
    final pos = _resolveBgPosition(style, rect, size);

    final x = (pos.x - pageRect.left) * _pxToPt;
    final y = (pos.y - pageRect.top) * _pxToPt;
    final w = size.width * _pxToPt;
    final h = size.height * _pxToPt;

    try {
      pdf.addImage(
        imageData: url,
        format: format,
        x: x,
        y: y,
        width: w,
        height: h,
      );
      _emittedImageDataUrls.add(url);
    } catch (e) {
      if (debug) {
        _log('background-image emission failed for ${_truncate(url, 60)}: $e');
      }
    }
  }

  /// Compute the laid-out size of the bg image given CSS background-size.
  /// Defaults to the element's own size for `cover` / `contain` since we
  /// don't have intrinsic image dimensions handy.
  ({double width, double height}) _resolveBgSize(
    web.CSSStyleDeclaration style,
    web.DOMRect rect,
  ) {
    final raw = style.backgroundSize.trim();
    if (raw.isEmpty || raw == 'auto' || raw == 'cover' || raw == 'contain') {
      return (width: rect.width, height: rect.height);
    }
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final v = _parsePxLength(parts[0]);
      return (width: v > 0 ? v : rect.width, height: rect.height);
    }
    final w = _parsePxLength(parts[0]);
    final h = _parsePxLength(parts[1]);
    return (
      width: w > 0 ? w : rect.width,
      height: h > 0 ? h : rect.height,
    );
  }

  ({double x, double y}) _resolveBgPosition(
    web.CSSStyleDeclaration style,
    web.DOMRect rect,
    ({double width, double height}) size,
  ) {
    final raw = style.backgroundPosition.trim();
    if (raw.isEmpty) return (x: rect.left, y: rect.top);
    final parts = raw.split(RegExp(r'\s+'));

    double resolveAxis(String part, double containerExtent, double imageExtent) {
      if (part.endsWith('%')) {
        final pct = double.tryParse(part.substring(0, part.length - 1)) ?? 0;
        return (containerExtent - imageExtent) * (pct / 100.0);
      }
      if (part == 'left' || part == 'top') return 0;
      if (part == 'center') return (containerExtent - imageExtent) / 2;
      if (part == 'right' || part == 'bottom') {
        return containerExtent - imageExtent;
      }
      return _parsePxLength(part);
    }

    final dx = parts.isNotEmpty
        ? resolveAxis(parts[0], rect.width, size.width)
        : 0.0;
    final dy = parts.length > 1
        ? resolveAxis(parts[1], rect.height, size.height)
        : 0.0;
    return (x: rect.left + dx, y: rect.top + dy);
  }

  // ---------------------------------------------------------------- image

  void _emitImage(web.HTMLImageElement img, web.DOMRect pageRect) {
    final rect = img.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    final x = (rect.left - pageRect.left) * _pxToPt;
    final y = (rect.top - pageRect.top) * _pxToPt;
    final w = rect.width * _pxToPt;
    final h = rect.height * _pxToPt;
    final format = _detectImageFormat(img.src);

    try {
      pdf.addImageElement(
        element: img,
        format: format,
        x: x,
        y: y,
        width: w,
        height: h,
      );
      return;
    } catch (e1) {
      // Fallback: data: URLs can be passed as strings (jsPDF parses them).
      if (img.src.startsWith('data:image')) {
        try {
          pdf.addImage(
            imageData: img.src,
            format: format,
            x: x,
            y: y,
            width: w,
            height: h,
          );
          return;
        } catch (e2) {
          if (debug) {
            _log('Image emission failed (element + data-URL paths) for '
                '${_truncate(img.src, 60)}: $e2');
          }
        }
      } else if (debug) {
        _log('Image emission failed for ${_truncate(img.src, 60)}: $e1');
      }
    }
  }

  // ----------------------------------------------------------------- hr

  void _emitHr(web.Element hr, web.DOMRect pageRect) {
    final style = iframeDocument.defaultView?.getComputedStyle(hr);
    if (style == null) return;
    final rect = hr.getBoundingClientRect();
    if (rect.width <= 0) return;
    final color = _parseColor(style.borderTopColor) ??
        _parseColor(style.color) ??
        const _Rgb(180, 180, 180);
    final widthPx = _parsePxLength(style.borderTopWidth);
    pdf.setDrawColor(color.r, color.g, color.b);
    pdf.setLineWidth((widthPx > 0 ? widthPx : 1) * _pxToPt);
    final y = ((rect.top + rect.height / 2) - pageRect.top) * _pxToPt;
    final x1 = (rect.left - pageRect.left) * _pxToPt;
    final x2 = (rect.right - pageRect.left) * _pxToPt;
    pdf.line(x1, y, x2, y);
  }

  // ---------------------------------------------------------------- text

  /// Already-warned/-thrown family|style keys, so we report each problem
  /// once per render rather than per text node.
  final Set<String> _glyphFallbackReported = <String>{};

  void _emitText(
    web.Text textNode,
    web.DOMRect pageRect,
    int pageNumber,
    int totalPages,
    double clipBottom,
  ) {
    final raw = textNode.data;
    if (raw.trim().isEmpty) return;

    final parent = textNode.parentElement;
    if (parent == null) return;
    final style = iframeDocument.defaultView?.getComputedStyle(parent);
    if (style == null) return;
    if (style.display == 'none' || style.visibility == 'hidden') return;

    final range = iframeDocument.createRange();
    range.selectNodeContents(textNode);
    final rects = range.getClientRects();
    if (rects.length == 0) return;

    // Honor the active clip — drop text whose first line begins at or
    // below the clip. Multi-line text whose first line is in-bounds is
    // emitted as-is; per-line clipping is overkill for the cases that
    // currently need this guard (single-row table headers below the
    // content area).
    if (rects.item(0)!.top >= clipBottom) return;

    final content = _resolvePageCounters(raw, pageNumber, totalPages);

    final fontSizePt = _parsePxLength(style.fontSize) * _pxToPt;
    final color = _parseColor(style.color) ?? const _Rgb(0, 0, 0);
    final cssWeight = style.fontWeight;
    final cssStyle = style.fontStyle;
    final letterSpacingPt =
        _parsePxLength(style.letterSpacing) * _pxToPt;
    final wordSpacingPt =
        _parsePxLength(style.wordSpacing) * _pxToPt;

    final font = fonts.resolve(
      cssFontFamily: style.fontFamily,
      weight: int.tryParse(cssWeight) ?? (cssWeight == 'bold' ? 700 : 400),
      style: cssStyle,
    );

    pdf.setFont(font.family, font.style);
    pdf.setFontSize(fontSizePt);
    pdf.setTextColor(color.r, color.g, color.b);

    _checkGlyphCoverage(content: content, font: font, parent: parent);

    final lines = _groupRectsByLine(rects);
    _emitTextByLines(
      textNode: textNode,
      content: content,
      lines: lines,
      pageRect: pageRect,
      style: style,
      fontSizePt: fontSizePt,
      letterSpacingPt: letterSpacingPt,
      wordSpacingPt: wordSpacingPt,
    );

    final decoration = style.textDecorationLine;
    if (decoration.isNotEmpty && decoration != 'none') {
      _emitTextDecorations(
        rects: rects,
        pageRect: pageRect,
        decoration: decoration,
        color: color,
        fontSizePt: fontSizePt,
      );
    }
  }

  /// Group rects from `getClientRects()` into visual lines (same `top` ±1 px).
  List<List<web.DOMRect>> _groupRectsByLine(web.DOMRectList rects) {
    final lines = <List<web.DOMRect>>[];
    for (var i = 0; i < rects.length; i++) {
      final r = rects.item(i)!;
      if (lines.isEmpty || (r.top - lines.last.first.top).abs() > 1.0) {
        lines.add([r]);
      } else {
        lines.last.add(r);
      }
    }
    return lines;
  }

  ({double left, double top, double right, double bottom}) _lineBounds(
    List<web.DOMRect> line,
  ) {
    var left = line.first.left;
    var right = line.first.right;
    var top = line.first.top;
    var bottom = line.first.bottom;
    for (final r in line) {
      if (r.left < left) left = r.left;
      if (r.right > right) right = r.right;
      if (r.top < top) top = r.top;
      if (r.bottom > bottom) bottom = r.bottom;
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  void _emitTextByLines({
    required web.Text textNode,
    required String content,
    required List<List<web.DOMRect>> lines,
    required web.DOMRect pageRect,
    required web.CSSStyleDeclaration style,
    required double fontSizePt,
    required double letterSpacingPt,
    required double wordSpacingPt,
  }) {
    if (lines.isEmpty) return;

    // Single visual line — emit the whole content once at the line's
    // leftmost x.
    if (lines.length == 1) {
      _emitLine(
        textNode: textNode,
        content: content.trimRight(),
        startChar: 0,
        endChar: content.length,
        line: lines.single,
        pageRect: pageRect,
        fontSizePt: fontSizePt,
        letterSpacingPt: letterSpacingPt,
        wordSpacingPt: wordSpacingPt,
      );
      return;
    }

    // Multi-line case — slice content per visual line via per-character
    // probing (binary search). For very long content (>1500 chars) the
    // probing cost dominates; fall back to per-line at-best-effort.
    var charIndex = 0;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final endChar = (lineIndex == lines.length - 1)
          ? content.length
          : _findLineBreakIndex(
              textNode: textNode,
              startChar: charIndex,
              maxChar: content.length,
              nextLineTop: _lineBounds(lines[lineIndex + 1]).top,
            );

      _emitLine(
        textNode: textNode,
        content: content.substring(charIndex, endChar).trimRight(),
        startChar: charIndex,
        endChar: endChar,
        line: lines[lineIndex],
        pageRect: pageRect,
        fontSizePt: fontSizePt,
        letterSpacingPt: letterSpacingPt,
        wordSpacingPt: wordSpacingPt,
      );

      charIndex = endChar;
      while (charIndex < content.length &&
          _isLineBreakWhitespace(content[charIndex])) {
        charIndex++;
      }
    }
  }

  /// Emit a single visual line. Tries per-line fast path first, falls back
  /// to per-word and finally per-character if width drift exceeds threshold.
  void _emitLine({
    required web.Text textNode,
    required String content,
    required int startChar,
    required int endChar,
    required List<web.DOMRect> line,
    required web.DOMRect pageRect,
    required double fontSizePt,
    required double letterSpacingPt,
    required double wordSpacingPt,
  }) {
    if (content.isEmpty) return;
    final bounds = _lineBounds(line);
    final lineLeftPt = (bounds.left - pageRect.left) * _pxToPt;
    final yTop = (bounds.top - pageRect.top) * _pxToPt;
    final baselineY = yTop + fontSizePt * 0.8;
    final browserWidthPt = (bounds.right - bounds.left) * _pxToPt;

    // Tier 1: per-line emission with charSpace.
    final pdfWidthPt = _measurePdfWidth(content, fontSizePt) +
        letterSpacingPt * (content.length - 1).clamp(0, content.length);
    final drift = browserWidthPt > 0
        ? ((pdfWidthPt - browserWidthPt).abs() / browserWidthPt)
        : 0.0;

    if (drift <= _lineWidthDriftThreshold && wordSpacingPt == 0) {
      _emitTextChunk(
        text: content,
        x: lineLeftPt,
        y: baselineY,
        charSpace: letterSpacingPt,
      );
      return;
    }

    // Tier 2: per-word emission (measure-then-emit so an escalation to
    // per-character doesn't paint over per-word output).
    final perWordOk = _emitPerWord(
      textNode: textNode,
      content: content,
      startChar: startChar,
      pageRect: pageRect,
      baselineY: baselineY,
      fontSizePt: fontSizePt,
      letterSpacingPt: letterSpacingPt,
    );
    if (perWordOk) return;

    // Tier 3: per-character. Slow but correct.
    _emitPerCharacter(
      textNode: textNode,
      content: content,
      startChar: startChar,
      pageRect: pageRect,
      baselineY: baselineY,
      fontSizePt: fontSizePt,
    );
  }

  /// Measure-then-emit. Returns `true` (and emits) when per-word drift is
  /// within tolerance; returns `false` (and emits NOTHING) otherwise so the
  /// caller can escalate to per-character without overlapping the previous
  /// emission.
  bool _emitPerWord({
    required web.Text textNode,
    required String content,
    required int startChar,
    required web.DOMRect pageRect,
    required double baselineY,
    required double fontSizePt,
    required double letterSpacingPt,
  }) {
    // Walk content collecting [start, end) word ranges (non-whitespace runs).
    final words = <({int start, int end})>[];
    var i = 0;
    while (i < content.length) {
      while (i < content.length && _isLineBreakWhitespace(content[i])) {
        i++;
      }
      final wordStart = i;
      while (i < content.length && !_isLineBreakWhitespace(content[i])) {
        i++;
      }
      if (i > wordStart) words.add((start: wordStart, end: i));
    }
    if (words.isEmpty) return false;

    // PASS 1: measure each word and pre-compute its `charSpace`. Don't
    // emit yet — if any word's drift escalates beyond what charSpace can
    // reasonably absorb, the caller falls through to per-character.
    //
    // The `charSpace` formula compensates for the gap between the browser's
    // natural word width (using whatever font the browser picked, typically
    // Arial) and jsPDF's natural width using the registered font. Setting
    // `charSpace = (browserWidth - pdfNaturalWidth) / (wordChars - 1)`
    // makes the rendered word width match the browser-measured width
    // exactly, which prevents the word from overrunning into the gap before
    // the next word (the visible "PermanentAccount" / "mentionedabove"
    // merging effect).
    final measured = <({String word, double xPt, double charSpace, double drift})>[];
    var totalDrift = 0.0;
    for (final w in words) {
      final word = content.substring(w.start, w.end);
      final rect =
          _rangeRect(textNode, startChar + w.start, startChar + w.end);
      if (rect == null || rect.width <= 0) continue;
      final wx = (rect.left - pageRect.left) * _pxToPt;
      final pdfNatural = _measurePdfWidth(word, fontSizePt);
      final browserW = rect.width * _pxToPt;
      final pdfWithLs = pdfNatural +
          letterSpacingPt * (word.length - 1).clamp(0, word.length);
      final drift =
          browserW > 0 ? (pdfWithLs - browserW).abs() / browserW : 0.0;
      totalDrift += drift;

      // Per-word charSpace = letterSpacing + metric compensation.
      var charSpacePt = letterSpacingPt;
      if (word.length > 1 && browserW > 0) {
        charSpacePt += (browserW - pdfNatural) / (word.length - 1);
      }
      // Clamp to prevent intra-word character overlap (the column-header
      // issue we saw before — too-negative charSpace makes adjacent ASCII
      // characters visually merge at small font sizes).
      if (charSpacePt < -0.6) charSpacePt = -0.6;
      if (charSpacePt > 3.0) charSpacePt = 3.0;

      measured.add((
        word: word,
        xPt: wx,
        charSpace: charSpacePt,
        drift: drift,
      ));
    }
    if (measured.isEmpty) return false;
    final avg = totalDrift / measured.length;
    if (avg > _wordWidthDriftThreshold) return false; // escalate to per-char

    // PASS 2: emit each word with its tuned charSpace.
    for (final m in measured) {
      _emitTextChunk(
        text: m.word,
        x: m.xPt,
        y: baselineY,
        charSpace: m.charSpace,
      );
    }
    return true;
  }

  void _emitPerCharacter({
    required web.Text textNode,
    required String content,
    required int startChar,
    required web.DOMRect pageRect,
    required double baselineY,
    required double fontSizePt,
  }) {
    for (var i = 0; i < content.length; i++) {
      final ch = content[i];
      if (_isLineBreakWhitespace(ch)) continue;
      final rect = _rangeRect(textNode, startChar + i, startChar + i + 1);
      if (rect == null || rect.width <= 0) continue;
      final x = (rect.left - pageRect.left) * _pxToPt;
      pdf.text(ch, x, baselineY);
    }
  }

  void _emitTextChunk({
    required String text,
    required double x,
    required double y,
    double charSpace = 0,
  }) {
    if (text.isEmpty) return;
    pdf.text(text, x, y, charSpace: charSpace == 0 ? null : charSpace);
  }

  void _emitTextDecorations({
    required web.DOMRectList rects,
    required web.DOMRect pageRect,
    required String decoration,
    required _Rgb color,
    required double fontSizePt,
  }) {
    final lines = _groupRectsByLine(rects);
    final decorations = decoration.split(' ');
    pdf.setDrawColor(color.r, color.g, color.b);
    pdf.setLineWidth(fontSizePt * 0.05);

    for (final line in lines) {
      final b = _lineBounds(line);
      final x1 = (b.left - pageRect.left) * _pxToPt;
      final x2 = (b.right - pageRect.left) * _pxToPt;
      final yTop = (b.top - pageRect.top) * _pxToPt;
      final yBaseline = yTop + fontSizePt * 0.8;
      for (final d in decorations) {
        switch (d) {
          case 'underline':
            pdf.line(x1, yBaseline + fontSizePt * 0.1, x2,
                yBaseline + fontSizePt * 0.1);
            break;
          case 'overline':
            pdf.line(x1, yTop, x2, yTop);
            break;
          case 'line-through':
            pdf.line(x1, yTop + fontSizePt * 0.5, x2, yTop + fontSizePt * 0.5);
            break;
        }
      }
    }
  }

  // -------------------------------------------------------------- helpers

  /// Binary-search the character index where the rect's top crosses
  /// [nextLineTop]. Reduces forced layouts vs. linear scan.
  int _findLineBreakIndex({
    required web.Text textNode,
    required int startChar,
    required int maxChar,
    required double nextLineTop,
  }) {
    int lo = startChar;
    int hi = maxChar;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final rect = _rangeRect(textNode, mid, mid + 1);
      if (rect == null) {
        lo = mid + 1;
        continue;
      }
      if (rect.top + 0.5 >= nextLineTop) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Get the bounding rect of `[start, end)` in [textNode]. `null` on failure.
  web.DOMRect? _rangeRect(web.Text textNode, int start, int end) {
    final len = textNode.data.length;
    if (start < 0 || end <= start || end > len) return null;
    final range = iframeDocument.createRange();
    try {
      range.setStart(textNode, start);
      range.setEnd(textNode, end);
      return range.getBoundingClientRect();
    } catch (_) {
      return null;
    }
  }

  /// Measure [text]'s width in pt at [fontSizePt] using the CURRENTLY-SET
  /// font. Caller must `pdf.setFont` and `pdf.setFontSize` first.
  double _measurePdfWidth(String text, double fontSizePt) {
    if (text.isEmpty) return 0;
    // jsPDF: width = getStringUnitWidth(text) * fontSize.
    // (getTextWidth() returns in document units which is fontSize-dependent
    //  too — same formula either way; getStringUnitWidth is a touch faster.)
    return pdf.getStringUnitWidth(text) * fontSizePt;
  }

  bool _isLineBreakWhitespace(String char) =>
      char == ' ' || char == '\n' || char == '\t';

  String _resolvePageCounters(String text, int page, int total) {
    if (!text.contains('{{')) return text;
    return text
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{pages}}', '$total');
  }

  // ------------------------------------------------------------ glyph fallback

  void _checkGlyphCoverage({
    required String content,
    required ResolvedFont font,
    required web.Element parent,
  }) {
    if (!_hasNonLatin1(content)) return;
    if (!fonts.isLikelyMissingCoverage(content, font)) return;

    final key = '${font.family.toLowerCase()}|${font.style}';
    if (_glyphFallbackReported.contains(key)) return;
    _glyphFallbackReported.add(key);

    final samples = <String>{};
    for (final cu in content.codeUnits) {
      if (cu > 0xFF) {
        samples.add('U+${cu.toRadixString(16).toUpperCase().padLeft(4, '0')}');
        if (samples.length >= 5) break;
      }
    }
    final sampleStr =
        samples.join(', ') + (samples.length >= 5 ? ', ...' : '');

    final msg =
        'Text contains characters ($sampleStr) likely outside the registered '
        'font "${font.family}" coverage. They will render as wrong glyphs '
        '(e.g. ₹ → ¹). Register a font with broader coverage via PdfOptions.fonts.';

    if (failOnGlyphFallback) {
      throw PdfGenerationException(msg,
          phase: PdfGenerationPhase.vectorEmission,
          code: 'glyph-fallback');
    } else if (debug) {
      _log('GLYPH FALLBACK: $msg');
    }
  }

  static bool _hasNonLatin1(String text) {
    for (final cu in text.codeUnits) {
      if (cu > 0xFF) return true;
    }
    return false;
  }

  static String _detectImageFormat(String src) {
    final lc = src.toLowerCase();
    if (lc.startsWith('data:image/jpeg') ||
        lc.startsWith('data:image/jpg') ||
        lc.endsWith('.jpg') ||
        lc.endsWith('.jpeg')) {
      return 'JPEG';
    }
    if (lc.startsWith('data:image/webp') || lc.endsWith('.webp')) {
      return 'WEBP';
    }
    return 'PNG';
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Walker] $message');
    }
  }
}

// ============================================================================
// Color & length parsing
// ============================================================================

class _Rgb {
  final int r;
  final int g;
  final int b;
  final double alpha;
  const _Rgb(this.r, this.g, this.b, [this.alpha = 1.0]);
}

_Rgb? _parseColor(String css) {
  if (css.isEmpty) return null;
  final trimmed = css.trim().toLowerCase();
  if (trimmed == 'transparent' || trimmed == 'none') return null;

  if (trimmed.startsWith('rgb')) {
    final inside = trimmed
        .substring(trimmed.indexOf('(') + 1, trimmed.lastIndexOf(')'))
        .replaceAll(' ', '');
    final parts = inside.split(',');
    if (parts.length < 3) return null;

    int parseChannel(String s) {
      if (s.endsWith('%')) {
        final v = double.tryParse(s.substring(0, s.length - 1)) ?? 0;
        return ((v / 100) * 255).round().clamp(0, 255);
      }
      return (int.tryParse(s) ?? 0).clamp(0, 255);
    }

    final r = parseChannel(parts[0]);
    final g = parseChannel(parts[1]);
    final b = parseChannel(parts[2]);
    final a = parts.length > 3 ? (double.tryParse(parts[3]) ?? 1.0) : 1.0;
    return _Rgb(r, g, b, a);
  }

  if (trimmed.startsWith('#')) {
    final hex = trimmed.substring(1);
    if (hex.length == 3) {
      final r = int.parse('${hex[0]}${hex[0]}', radix: 16);
      final g = int.parse('${hex[1]}${hex[1]}', radix: 16);
      final b = int.parse('${hex[2]}${hex[2]}', radix: 16);
      return _Rgb(r, g, b);
    }
    if (hex.length == 6) {
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      return _Rgb(r, g, b);
    }
    if (hex.length == 8) {
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      final a = int.parse(hex.substring(6, 8), radix: 16) / 255;
      return _Rgb(r, g, b, a);
    }
  }

  switch (trimmed) {
    case 'black':
      return const _Rgb(0, 0, 0);
    case 'white':
      return const _Rgb(255, 255, 255);
    case 'red':
      return const _Rgb(255, 0, 0);
    case 'green':
      return const _Rgb(0, 128, 0);
    case 'blue':
      return const _Rgb(0, 0, 255);
    case 'gray':
    case 'grey':
      return const _Rgb(128, 128, 128);
  }
  return null;
}

double _parsePxLength(String css) {
  if (css.isEmpty) return 0;
  final trimmed = css.trim();
  if (trimmed.endsWith('px')) {
    return double.tryParse(trimmed.substring(0, trimmed.length - 2)) ?? 0;
  }
  if (trimmed.endsWith('pt')) {
    final pt = double.tryParse(trimmed.substring(0, trimmed.length - 2)) ?? 0;
    return pt / _pxToPt;
  }
  return double.tryParse(trimmed) ?? 0;
}

enum _BorderSide { top, right, bottom, left }
