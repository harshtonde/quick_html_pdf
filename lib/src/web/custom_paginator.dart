/// Fast measure-and-flow paginator. Replaces Paged.js for table-heavy
/// documents.
///
/// Paged.js is a general-purpose CSS Paged Media polyfill — it handles
/// orphans/widows, complex break decisions, footnotes, and more. For the
/// content this package targets (tax forms, invoices: tables of records
/// with row-level break boundaries), most of that machinery is overhead.
/// This paginator does only what's needed:
///
/// 1. Measure the body content's children once via `offsetHeight`.
/// 2. Greedy-pack them into A4 pages.
/// 3. For tables that don't fit, slice by rows and repeat `<thead>` per
///    slice.
/// 4. Wrap each page with absolute-positioned header / content / footer
///    slots, populated from `PdfOptions.headerHtml` / `footerHtml`.
///
/// Empirically 100–200× faster than Paged.js on a 200-page table doc
/// (~1 s vs ~4–5 min). Trade-offs:
///
/// - No `@page` margin-box CSS support — use `PdfOptions.headerHtml` and
///   `footerHtml` instead. The paginator substitutes `{{page}}` and
///   `{{pages}}` per-page.
/// - No mid-paragraph orphan/widow control. (Form 26AS-style row-major
///   content doesn't need this.)
/// - No CSS multi-column / regions / footnote support.
///
/// Output: a `List<PaginatedPage>`, each pointing at a `qhp-page` wrapper in
/// the iframe DOM. Consumed downstream by the DOM walker.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../options.dart';
import 'paginated_page.dart';

class CustomPaginator {
  final web.HTMLIFrameElement iframe;
  final PdfOptions options;
  final bool debug;

  CustomPaginator({
    required this.iframe,
    required this.options,
    this.debug = false,
  });

  /// Convert mm to CSS px (1 px = 1/96 in; 1 in = 25.4 mm).
  static const double _mmToPx = 96.0 / 25.4;

  /// Measure the content and split into pages.
  Future<List<PaginatedPage>> paginate() async {
    final start = DateTime.now();
    final doc = iframe.contentDocument;
    final win = iframe.contentWindow;
    if (doc == null || win == null) {
      throw const PdfGenerationException(
        'Iframe has no document/window — cannot paginate',
        phase: PdfGenerationPhase.iframeCreation,
        code: 'iframe-detached',
      );
    }
    final body = doc.body;
    if (body == null) {
      throw const PdfGenerationException(
        'Iframe has no body',
        phase: PdfGenerationPhase.iframeCreation,
        code: 'iframe-empty',
      );
    }
    final content = doc.querySelector('.pdf-content') as web.HTMLElement?;
    if (content == null) {
      throw const PdfGenerationException(
        'Could not find .pdf-content wrapper in iframe — '
        'the package expects HtmlComposer-composed content.',
        phase: PdfGenerationPhase.htmlComposition,
        code: 'no-content-wrapper',
      );
    }

    // Page dimensions in CSS px.
    final pageWidthPx = options.effectiveWidthMm * _mmToPx;
    final pageHeightPx = options.effectiveHeightMm * _mmToPx;
    final marginTopPx = options.margins.topMm * _mmToPx;
    final marginBottomPx = options.margins.bottomMm * _mmToPx;
    final marginLeftPx = options.margins.leftMm * _mmToPx;
    final marginRightPx = options.margins.rightMm * _mmToPx;
    final headerHeightPx =
        options.hasHeader ? options.headerHeightMm * _mmToPx : 0.0;
    final footerHeightPx =
        options.hasFooter ? options.footerHeightMm * _mmToPx : 0.0;

    final contentWidth = pageWidthPx - marginLeftPx - marginRightPx;
    // Geometric content rectangle — what `qhp-page-content` is rendered at.
    final contentRectHeight = pageHeightPx -
        marginTopPx -
        marginBottomPx -
        headerHeightPx -
        footerHeightPx;

    if (contentRectHeight <= 0) {
      throw PdfGenerationException(
        'Content area height is non-positive (${contentRectHeight}px). '
        'Check page size + margins + header/footer heights.',
        phase: PdfGenerationPhase.htmlComposition,
        code: 'invalid-content-area',
      );
    }

    // Pagination budget < geometric height. The slice's "claimed" height
    // is summed from per-row rect deltas measured in the source layout;
    // when the cloned slice is re-laid-out inside the per-page wrapper,
    // sub-pixel rounding, font-metric drift and table-layout re-compute
    // can push the rendered slice 2–6 px past its claimed height. With a
    // budget == geometric rectangle, that drift spills into the footer
    // band. Reserving ~2 mm of slack in the budget keeps the rendered
    // content inside the rectangle and gives the page counter breathing
    // room above it.
    const budgetSafetyPx = 8.0;
    final contentHeight = contentRectHeight - budgetSafetyPx;

    // Resize content wrapper to page width so children measure correctly.
    content.style
      ..width = '${contentWidth.round()}px'
      ..boxSizing = 'border-box';
    await _waitForLayout(win);

    if (debug) {
      _log('Content area: ${contentWidth.round()}×${contentRectHeight.round()}px '
          '(budget ${contentHeight.round()}px after ${budgetSafetyPx.toInt()}px safety)');
    }

    // Walk children, fill pages.
    final fragments = _splitChildren(content, contentHeight, doc);
    if (debug) {
      _log('Pagination produced ${fragments.length} pages from '
          '${content.children.length} top-level elements');
    }

    if (fragments.isEmpty) {
      throw const PdfGenerationException(
        'Content was empty — no pages produced',
        phase: PdfGenerationPhase.htmlComposition,
        code: 'empty-content',
      );
    }

    // Build per-page wrappers.
    final pagesContainer = doc.createElement('div') as web.HTMLElement;
    pagesContainer.id = 'qhp-pages';
    pagesContainer.style
      ..position = 'relative'
      ..width = '${pageWidthPx.round()}px';
    body.appendChild(pagesContainer);

    final pageElements = <web.HTMLElement>[];
    for (var i = 0; i < fragments.length; i++) {
      final pageWrapper = _buildPageWrapper(
        doc: doc,
        pageNumber: i + 1,
        totalPages: fragments.length,
        pageWidthPx: pageWidthPx,
        pageHeightPx: pageHeightPx,
        marginTopPx: marginTopPx,
        marginBottomPx: marginBottomPx,
        marginLeftPx: marginLeftPx,
        marginRightPx: marginRightPx,
        headerHeightPx: headerHeightPx,
        footerHeightPx: footerHeightPx,
        contentElements: fragments[i],
      );
      pagesContainer.appendChild(pageWrapper);
      pageElements.add(pageWrapper);
    }

    // Hide the now-empty source content so it doesn't paint twice.
    content.style.display = 'none';
    await _waitForLayout(win);

    if (debug) {
      final ms = DateTime.now().difference(start).inMilliseconds;
      _log('Pagination complete: ${pageElements.length} page(s) in ${ms}ms');
    }

    return [
      for (var i = 0; i < pageElements.length; i++)
        PaginatedPage(
          element: pageElements[i],
          pageNumber: i + 1,
          totalPages: pageElements.length,
        ),
    ];
  }

  // ----------------------------------------------------------- pagination

  /// Walk children of [content] and pack into pages.
  ///
  /// All page-fill decisions use _pre-computed_ heights (`_Sized.height`)
  /// rather than `offsetHeight`. This is critical because the cloned slices
  /// produced by `_splitOversized` are NOT in the DOM yet — `offsetHeight`
  /// would return 0, causing every slice to be packed onto a single page.
  List<List<web.Element>> _splitChildren(
    web.HTMLElement content,
    double contentHeight,
    web.Document doc,
  ) {
    final pages = <List<web.Element>>[];
    var current = <web.Element>[];
    var currentH = 0.0;

    final children = <web.Element>[
      for (var i = 0; i < content.children.length; i++)
        content.children.item(i)!,
    ];

    // Use rect-delta heights (which include each child's contribution to
    // vertical space INCLUDING margin-top/bottom with browser-applied
    // margin-collapse). `offsetHeight` excludes margins, which leads to
    // systematic under-counting when stacking siblings — and the
    // accumulated under-count is what was clipping the bottom row of
    // pages at section boundaries.
    final occupiedHeights = _measureSiblingOccupiedHeights(content, children);

    for (var ci = 0; ci < children.length; ci++) {
      final child = children[ci];
      final h = occupiedHeights[ci];
      if (h <= 0) continue; // hidden / collapsed

      if (h <= contentHeight) {
        // Fits as a unit — add to current page or roll over.
        if (currentH + h > contentHeight && current.isNotEmpty) {
          pages.add(current);
          current = [child];
          currentH = h;
        } else {
          current.add(child);
          currentH += h;
        }
        continue;
      }

      // Oversized child — produce per-page slices with KNOWN heights.
      // If the current page already has content, tell the slicer to size
      // its FIRST slice to the leftover space so it packs into page 1
      // instead of being flushed onto a fresh page.
      //
      // Only worthwhile when the leftover is meaningful — below ~120 px
      // a "first slice" can fit at most one or two rows, and the slice
      // overhead (thead, frame) eats most of it. In that case skip the
      // first-slice trick and let the page flush as normal.
      const minUsefulRemainingPx = 120.0;
      final remainingOnPage = contentHeight - currentH;
      final firstBudget =
          (current.isNotEmpty && remainingOnPage >= minUsefulRemainingPx)
              ? remainingOnPage
              : null;
      final slices = _splitOversized(
        child,
        contentHeight,
        doc,
        firstBudget: firstBudget,
      );

      for (final slice in slices) {
        if (slice.height <= 0) continue; // defensive — never expected
        if (currentH + slice.height > contentHeight && current.isNotEmpty) {
          pages.add(current);
          current = [];
          currentH = 0;
        }
        current.add(slice.element);
        currentH += slice.height;
      }
    }

    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  /// Try to split a too-tall element into page-sized slices, returning each
  /// with its pre-computed height (so the page-packer doesn't have to read
  /// `offsetHeight` on a detached clone).
  ///
  /// Handles three shapes:
  /// 1. Element IS a `<table>` → split rows directly.
  /// 2. Element contains exactly ONE descendant table (anywhere in the
  ///    sub-tree) → slice the table, clone the surrounding wrapper for
  ///    each slice. Non-table siblings (e.g. a `.part-header`) are
  ///    repeated on every slice.
  /// 3. Element contains MULTIPLE descendant tables in different children
  ///    (e.g. a flex layout with two side-by-side tables) → paginate each
  ///    wrapper independently, then recombine into per-page container
  ///    clones. Slice height = max of children's slice heights when the
  ///    container is `display: flex` (row); sum otherwise.
  List<_Sized> _splitOversized(
    web.Element el,
    double contentHeight,
    web.Document doc, {
    double? firstBudget,
  }) {
    final tag = el.tagName.toUpperCase();
    if (tag == 'TABLE') {
      return _paginateTable(
        el as web.HTMLTableElement,
        contentHeight,
        doc,
        firstBudget: firstBudget,
      ).slices;
    }
    return _paginateContainer(
      el,
      contentHeight,
      doc,
      firstBudget: firstBudget,
    );
  }

  /// Recursively find the first descendant `<table>` of [el] (or [el] itself).
  web.HTMLTableElement? _findDescendantTable(web.Element el) {
    if (el.tagName.toUpperCase() == 'TABLE') {
      return el as web.HTMLTableElement;
    }
    for (var i = 0; i < el.children.length; i++) {
      final c = el.children.item(i);
      if (c == null) continue;
      final t = _findDescendantTable(c);
      if (t != null) return t;
    }
    return null;
  }

  /// Deep-clone [el] but substitute the FIRST descendant table with
  /// [newTable]. Avoids cloning the original (full) table's contents.
  web.Element _cloneReplacingTable(
    web.Element el,
    web.HTMLTableElement newTable,
  ) {
    final clone = el.cloneNode(false) as web.Element;
    for (var i = 0; i < el.childNodes.length; i++) {
      final child = el.childNodes.item(i);
      if (child == null) continue;
      if (child.nodeType != web.Node.ELEMENT_NODE) {
        clone.appendChild(child.cloneNode(true));
        continue;
      }
      final childEl = child as web.Element;
      if (childEl.tagName.toUpperCase() == 'TABLE') {
        clone.appendChild(newTable);
        continue;
      }
      if (_findDescendantTable(childEl) != null) {
        clone.appendChild(_cloneReplacingTable(childEl, newTable));
        continue;
      }
      clone.appendChild(child.cloneNode(true));
    }
    return clone;
  }

  /// Slice a `<table>` by rows. Each slice is a clone of the table that
  /// includes `<thead>` / `<colgroup>` / etc. and a tbody with a subset of
  /// the original rows. Returned alongside its pre-computed height
  /// (theadH + sum of group row heights) and the row-index list each
  /// slice covers (so a caller can later identify "tail" rows for
  /// re-pagination at a different budget).
  _TablePagination _paginateTable(
    web.HTMLTableElement table,
    double contentHeight,
    web.Document doc, {
    double? firstBudget,
  }) {
    final thead = table.querySelector('thead') as web.HTMLElement?;
    // `getBoundingClientRect().height` matches `offsetHeight` for thead
    // (no margin in tables), but using rect-bottom as the reference
    // point for row deltas keeps the math consistent.
    final tableTop = (table as web.HTMLElement).getBoundingClientRect().top;
    final theadH = thead == null
        ? 0.0
        : thead.getBoundingClientRect().height.toDouble();

    final rows = table.querySelectorAll('tbody > tr');
    final allRows = <web.HTMLTableRowElement>[
      for (var i = 0; i < rows.length; i++)
        rows.item(i) as web.HTMLTableRowElement,
    ];
    if (allRows.isEmpty) {
      final h = table.getBoundingClientRect().height.toDouble();
      return _TablePagination([_Sized(table, h)], const [[]]);
    }

    // Rect-delta measurement: each row's occupied vertical space
    // = its bottom minus the previous row's bottom (or thead's bottom
    // for the first row). Includes any tr margins / border-spacing the
    // browser added — `offsetHeight` would miss those, accumulating an
    // error that clipped the last row at page boundaries.
    final firstRowTop = thead != null
        ? thead.getBoundingClientRect().bottom
        : tableTop;
    final rowHeights = <double>[];
    var prevBottom = firstRowTop;
    for (final r in allRows) {
      final rect = r.getBoundingClientRect();
      final delta = rect.bottom - prevBottom;
      rowHeights.add(delta > 0 ? delta : 0);
      prevBottom = rect.bottom > prevBottom ? rect.bottom : prevBottom;
    }

    final pageGroups = _packRowsIntoGroups(
      rowHeights,
      theadH,
      contentHeight,
      firstBudget: firstBudget,
    );

    final slices = _buildSlicesFromGroups(
      table: table,
      allRows: allRows,
      pageGroups: pageGroups,
      theadH: theadH,
      rowHeights: rowHeights,
      doc: doc,
    );
    return _TablePagination(slices, pageGroups);
  }

  /// Replace the longer child's `[minSlices..]` slices with new
  /// full-width slices, so the rendered tail pages pack rows tightly
  /// instead of carrying the half-width row counts.
  ///
  /// Mechanism: temporarily switch the container to `display: block`
  /// (which lets the inner table flow at full-width), re-measure the
  /// tail rows, re-pack at the full-width budget, build new wrapped
  /// slices, then restore the container's display.
  ///
  /// Mutates [perChildSlices] in place at `longerIdx`.
  void _replaceTailWithFullWidthSlices({
    required web.HTMLElement container,
    required _ChildContext ctx,
    required int minSlices,
    required double contentHeight,
    required List<List<_Sized>> perChildSlices,
    required int longerIdx,
    required web.Document doc,
  }) {
    final tailRowIndices = <int>[];
    for (var sliceIdx = minSlices;
        sliceIdx < ctx.rowGroups.length;
        sliceIdx++) {
      tailRowIndices.addAll(ctx.rowGroups[sliceIdx]);
    }
    if (tailRowIndices.isEmpty) return;

    final allRows = ctx.table.querySelectorAll('tbody > tr');
    final tailRows = <web.HTMLTableRowElement>[
      for (final idx in tailRowIndices)
        allRows.item(idx) as web.HTMLTableRowElement,
    ];
    if (tailRows.isEmpty) return;

    // Switch to block layout, force reflow, measure, then restore.
    final originalDisplay = container.style.display;
    container.style.display = 'block';
    // Force synchronous layout so subsequent offsetHeight reads reflect
    // the new flow.
    // ignore: unused_local_variable
    final _ = container.offsetHeight;

    final theadEl = ctx.table.querySelector('thead') as web.HTMLElement?;
    final fullTheadH = theadEl?.offsetHeight.toDouble() ?? 0;
    final fullRowHeights = <double>[
      for (final r in tailRows) r.offsetHeight.toDouble(),
    ];
    final isDirectTable = identical(ctx.child, ctx.table);
    final fullChildH =
        (ctx.child as web.HTMLElement).offsetHeight.toDouble();
    final fullTableH =
        (ctx.table as web.HTMLElement).offsetHeight.toDouble();
    final fullFrameH = isDirectTable ? 0.0 : (fullChildH - fullTableH);
    final tailBudget = contentHeight - fullFrameH;

    List<_Sized>? tailWrapped;
    if (tailBudget > 0) {
      final tailGroups = _packRowsIntoGroups(
        fullRowHeights,
        fullTheadH,
        tailBudget,
      );
      final tailSlices = _buildSlicesFromGroups(
        table: ctx.table,
        allRows: tailRows,
        pageGroups: tailGroups,
        theadH: fullTheadH,
        rowHeights: fullRowHeights,
        doc: doc,
      );
      tailWrapped = <_Sized>[
        for (final ts in tailSlices)
          if (isDirectTable)
            ts
          else
            _Sized(
              _cloneReplacingTable(
                ctx.child,
                ts.element as web.HTMLTableElement,
              ),
              fullFrameH + ts.height,
            ),
      ];
    }

    // Restore container display BEFORE returning so the rest of
    // pagination sees the original layout.
    container.style.display = originalDisplay;
    // ignore: unused_local_variable
    final reflushHeight = container.offsetHeight;

    if (tailWrapped == null || tailWrapped.isEmpty) return;
    perChildSlices[longerIdx] = <_Sized>[
      ...perChildSlices[longerIdx].sublist(0, minSlices),
      ...tailWrapped,
    ];
  }

  /// Apply [overhead] to a first-slice budget. Returns null if the
  /// budget would become non-positive (caller should treat as "no
  /// first-slice trick — fall back to flushing").
  static double? _adjustFirstBudget(double? firstBudget, double overhead) {
    if (firstBudget == null) return null;
    final adjusted = firstBudget - overhead;
    return adjusted > 0 ? adjusted : null;
  }

  /// Compute the actual vertical contribution of each [siblings] element
  /// inside its parent — using `getBoundingClientRect()` deltas rather
  /// than `offsetHeight`. The delta for child[i] is
  /// `child[i].rect.bottom - prev.bottom` (or `child[i].rect.bottom -
  /// parent.rect.top` for i=0), which automatically includes the
  /// element's margins (with browser-applied margin-collapse).
  ///
  /// `offsetHeight` excludes margins, so summing offsetHeights
  /// systematically under-counts occupied space and lets the paginator
  /// over-pack pages — the last row gets clipped at the page boundary.
  /// Rect deltas give the actual occupied space the next sibling will
  /// land after.
  ///
  /// Returns a list parallel to [siblings] with each element's occupied
  /// height (>= 0). Elements with non-positive size return 0.
  List<double> _measureSiblingOccupiedHeights(
    web.Element parent,
    List<web.Element> siblings,
  ) {
    if (siblings.isEmpty) return const [];
    final result = List<double>.filled(siblings.length, 0);
    var prevBottom = parent.getBoundingClientRect().top;
    for (var i = 0; i < siblings.length; i++) {
      final rect = siblings[i].getBoundingClientRect();
      // Hidden / collapsed elements: rect height of 0. Their bottom
      // equals their top equals the previous bottom (or close to it),
      // so the delta is ~0. Clamp to >= 0 just in case.
      final delta = rect.bottom - prevBottom;
      result[i] = delta > 0 ? delta : 0;
      prevBottom = rect.bottom > prevBottom ? rect.bottom : prevBottom;
    }
    return result;
  }

  /// Pack [rowHeights] into per-page groups so that each group's
  /// (theadH + sum) fits within [budget]. Single-row groups exceeding
  /// budget are accepted as-is (overflow rather than data loss).
  ///
  /// [firstBudget] (when non-null and smaller than [budget]) is applied
  /// to the FIRST group only — used by `_splitChildren` when an oversized
  /// child meets a partially-filled current page: the first slice is
  /// shrunk to fit the leftover space, subsequent slices use full [budget].
  List<List<int>> _packRowsIntoGroups(
    List<double> rowHeights,
    double theadH,
    double budget, {
    double? firstBudget,
  }) {
    final pageGroups = <List<int>>[];
    var current = <int>[];
    var currentSumH = 0.0;
    var activeBudget = firstBudget ?? budget;
    for (var i = 0; i < rowHeights.length; i++) {
      final h = rowHeights[i];
      if (theadH + currentSumH + h > activeBudget && current.isNotEmpty) {
        pageGroups.add(current);
        current = [i];
        currentSumH = h;
        // After flushing the first group, switch to full budget.
        activeBudget = budget;
      } else {
        current.add(i);
        currentSumH += h;
      }
    }
    if (current.isNotEmpty) pageGroups.add(current);
    return pageGroups;
  }

  /// Build a list of `_Sized` table slices given pre-computed row groups.
  /// Used both by [_paginateTable] (initial half-width pass) and by the
  /// tail full-width re-pagination in [_paginateContainer].
  List<_Sized> _buildSlicesFromGroups({
    required web.HTMLTableElement table,
    required List<web.HTMLTableRowElement> allRows,
    required List<List<int>> pageGroups,
    required double theadH,
    required List<double> rowHeights,
    required web.Document doc,
  }) {
    final slices = <_Sized>[];
    for (var groupIdx = 0; groupIdx < pageGroups.length; groupIdx++) {
      final group = pageGroups[groupIdx];
      final clone = table.cloneNode(false) as web.HTMLTableElement;

      // Copy non-tbody children (thead, colgroup, caption, etc.) as deep
      // clones — repeating thead per slice is the desired behaviour.
      for (var i = 0; i < table.childNodes.length; i++) {
        final child = table.childNodes.item(i);
        if (child == null) continue;
        if (child.nodeType != web.Node.ELEMENT_NODE) continue;
        final el = child as web.Element;
        if (el.tagName.toUpperCase() == 'TBODY') continue;
        clone.appendChild(child.cloneNode(true));
      }

      // Add a tbody with this group's (cloned) rows. Cloning is intentional:
      // the original table is hidden but kept in the DOM, so moving rows
      // would cause the original DOM to reflow during pagination.
      final tbody = doc.createElement('tbody');
      var groupH = theadH;
      for (final rowIdx in group) {
        tbody.appendChild(allRows[rowIdx].cloneNode(true));
        groupH += rowHeights[rowIdx];
      }
      clone.appendChild(tbody);
      slices.add(_Sized(clone, groupH));
    }
    return slices;
  }

  /// General container paginator. Handles single-table containers
  /// (`.part-container` shape) and multi-table flex containers
  /// (`.s73` / `.s78` Sections / Minor-Major shape) uniformly:
  ///
  /// - For each immediate child that contains a descendant table, slice
  ///   the table within an appropriate budget (page area minus the child's
  ///   non-table "frame" overhead) and produce one cloned-child per slice.
  /// - For each immediate child WITHOUT a table (e.g. a heading), keep
  ///   the child as a single fragment that gets repeated on every page.
  /// - Recombine into per-page container clones. Per-page slice height is
  ///   `max(children)` when the container is `display: flex` row, `sum`
  ///   for normal block flow.
  List<_Sized> _paginateContainer(
    web.Element container,
    double contentHeight,
    web.Document doc, {
    double? firstBudget,
  }) {
    final win = iframe.contentWindow;
    final containerEl = container as web.HTMLElement;
    final containerStyle = win?.getComputedStyle(container);
    final isFlexRow = containerStyle != null &&
        containerStyle.display.contains('flex') &&
        (containerStyle.flexDirection.isEmpty ||
            !containerStyle.flexDirection.startsWith('column'));

    final children = <web.Element>[
      for (var i = 0; i < container.children.length; i++)
        container.children.item(i)!,
    ];

    // Pre-measure all children's actual occupied heights via rect deltas
    // (includes margins). `offsetHeight` would under-count by the
    // margin between siblings, leading to overflow at page boundaries.
    final childHeights =
        _measureSiblingOccupiedHeights(container, children);

    // For BLOCK-flow containers, table-paginated children share each page
    // slice vertically with their non-table siblings (typically a heading
    // like `.part-header`/`.s1` that gets repeated on every slice). We
    // need to subtract those sibling heights from each table's budget,
    // otherwise the resulting slice = (heading + table_slice) overflows
    // the page by `heading.h` — which is exactly why Page 1 was leaving
    // the summary's leftover space empty: Part 1's first slice was sized
    // for full contentHeight, so heading + slice exceeded the leftover.
    //
    // For FLEX-row containers (`.s73`, `.s78`), siblings sit BESIDE
    // the table-bearing child, not above/below — they don't consume
    // vertical budget, so the overhead is 0.
    var siblingOverhead = 0.0;
    if (!isFlexRow) {
      for (var ci = 0; ci < children.length; ci++) {
        if (_findDescendantTable(children[ci]) == null) {
          siblingOverhead += childHeights[ci];
        }
      }
    }

    // Per child: the list of slices. Single-element list = repeated on
    // every page (e.g. a heading). Multi-element list = page-specific.
    final perChildSlices = <List<_Sized>>[];
    // Per child: pagination context kept for potential Phase-2 tail
    // re-pagination (only relevant for table-bearing children in flex
    // rows). `null` for children that don't have a table or were placed
    // as-is (overflow case).
    final perChildContext = <_ChildContext?>[];
    for (var ci = 0; ci < children.length; ci++) {
      final child = children[ci];
      // For flex-row children, sibling rect-deltas are wrong: all
      // siblings share y-coordinates, so deltas after the first are 0.
      // That used to cascade into a NEGATIVE frameH and an inflated
      // budget, packing the right-side table into a single slice that
      // got "repeated on every page" by the assembly loop. For flex-row
      // children, fall back to each child's own bounding-rect height —
      // its rendered height inside the source layout, including any
      // stretch from `align-items: stretch`. The stretch is empty space,
      // not real chrome, but `frameH` is computed against the inner
      // table below so any stretch shows up there; for flex-row the
      // stretch contributes 0 per-slice overhead because the cloned
      // wrapper re-stretches in the page, so we explicitly zero it.
      final h = isFlexRow
          ? (child as web.HTMLElement)
              .getBoundingClientRect()
              .height
              .toDouble()
          : childHeights[ci];
      final innerTable = _findDescendantTable(child);
      if (innerTable == null) {
        // No table — keep as a single fragment; will be repeated.
        perChildSlices.add([_Sized(child, h)]);
        perChildContext.add(null);
        continue;
      }
      if (innerTable == child) {
        // Child IS the table — slice with full content budget minus the
        // sum of non-table sibling heights (block flow only).
        final budget = contentHeight - siblingOverhead;
        if (budget <= 0) {
          perChildSlices.add([_Sized(child, h)]);
          perChildContext.add(null);
          continue;
        }
        final firstBudgetForTable = _adjustFirstBudget(
          firstBudget,
          siblingOverhead,
        );
        final p = _paginateTable(
          innerTable,
          budget,
          doc,
          firstBudget: firstBudgetForTable,
        );
        perChildSlices.add(p.slices);
        perChildContext.add(_ChildContext(
          child: child,
          table: innerTable,
          rowGroups: p.rowGroups,
          frameH: 0,
        ));
        continue;
      }
      // Child wraps a deeper table. Frame = h - innerTable.h. We use
      // rect-delta `h` (includes child's margins) and innerTable's
      // bounding-rect height (no margin issue inside a table). For flex-
      // row children, force frameH = 0 — `h` is the stretched wrapper
      // height which doesn't reflect real per-slice chrome.
      final tableH =
          (innerTable as web.HTMLElement).getBoundingClientRect().height
              .toDouble();
      final frameH = isFlexRow ? 0.0 : (h - tableH);
      final overhead = frameH + siblingOverhead;
      final budget = contentHeight - overhead;
      if (budget <= 0) {
        // Overhead alone already overflows — emit child as-is.
        perChildSlices.add([_Sized(child, h)]);
        perChildContext.add(null);
        continue;
      }
      // Subtract the same overhead from firstBudget when it's set.
      final firstBudgetForTable = _adjustFirstBudget(firstBudget, overhead);
      final p = _paginateTable(
        innerTable,
        budget,
        doc,
        firstBudget: firstBudgetForTable,
      );
      final childSlices = <_Sized>[
        for (final ts in p.slices)
          _Sized(
            _cloneReplacingTable(child, ts.element as web.HTMLTableElement),
            frameH + ts.height,
          ),
      ];
      perChildSlices.add(childSlices);
      perChildContext.add(_ChildContext(
        child: child,
        table: innerTable,
        rowGroups: p.rowGroups,
        frameH: frameH,
      ));
    }

    // PHASE 2: when this is a flex-row container with multiple
    // table-bearing children of UNEQUAL slice counts, the longer child's
    // "tail" slices were sized for half-width display. After the shorter
    // sibling exhausts (and we drop it from the page, letting the longer
    // one take full row width), those tail slices only fill ~50 % of a
    // page because rows wrap less at full-width = each row is shorter.
    //
    // Fix: temporarily switch the container to `display: block`
    // (full-width children), re-measure the longer child's tail rows at
    // their actual full-width heights, and re-pack into full-width slices.
    // Replace the longer child's `slices[minSlices..]` with these, so:
    //   - Pages 0..minSlices-1: side-by-side (Phase 1, unchanged).
    //   - Pages minSlices..end: full-width slices that pack properly.
    if (isFlexRow) {
      final tableChildIdx = <int>[
        for (var k = 0; k < children.length; k++)
          if (perChildContext[k] != null && perChildSlices[k].length > 1) k,
      ];
      if (tableChildIdx.length >= 2) {
        var minS = perChildSlices[tableChildIdx.first].length;
        var maxS = minS;
        var longerIdx = tableChildIdx.first;
        for (final k in tableChildIdx) {
          final n = perChildSlices[k].length;
          if (n < minS) minS = n;
          if (n > maxS) {
            maxS = n;
            longerIdx = k;
          }
        }
        if (maxS > minS) {
          _replaceTailWithFullWidthSlices(
            container: containerEl,
            ctx: perChildContext[longerIdx]!,
            minSlices: minS,
            contentHeight: contentHeight,
            perChildSlices: perChildSlices,
            longerIdx: longerIdx,
            doc: doc,
          );
        }
      }
    }

    final numPages =
        perChildSlices.fold<int>(0, (m, s) => s.length > m ? s.length : m);
    if (numPages <= 1) {
      // Nothing to split.
      final h = containerEl.offsetHeight.toDouble();
      return [_Sized(container, h)];
    }

    final result = <_Sized>[];
    for (var pageIdx = 0; pageIdx < numPages; pageIdx++) {
      final containerClone = container.cloneNode(false) as web.Element;
      var maxH = 0.0;
      var sumH = 0.0;

      for (var k = 0; k < perChildSlices.length; k++) {
        final slices = perChildSlices[k];
        if (slices.isEmpty) continue;

        _Sized slice;
        if (slices.length == 1) {
          // Single fragment — repeat on every page (must clone, can't
          // attach the same element to multiple parents).
          slice = slices.first;
          containerClone.appendChild(slice.element.cloneNode(true));
        } else if (pageIdx < slices.length) {
          // Page-specific slice — append directly (already unique).
          slice = slices[pageIdx];
          containerClone.appendChild(slice.element);
        } else {
          // This child is exhausted. Don't add a placeholder — that would
          // hold open a blank half-row (with `flex: 1`) and waste the
          // page. Drop the child entirely; the remaining sibling will
          // naturally take full row width.
          continue;
        }
        if (slice.height > maxH) maxH = slice.height;
        sumH += slice.height;
      }

      result.add(_Sized(containerClone, isFlexRow ? maxH : sumH));
    }
    return result;
  }

  // ---------------------------------------------------------- page wrapper

  web.HTMLElement _buildPageWrapper({
    required web.Document doc,
    required int pageNumber,
    required int totalPages,
    required double pageWidthPx,
    required double pageHeightPx,
    required double marginTopPx,
    required double marginBottomPx,
    required double marginLeftPx,
    required double marginRightPx,
    required double headerHeightPx,
    required double footerHeightPx,
    required List<web.Element> contentElements,
  }) {
    final page = doc.createElement('div') as web.HTMLElement;
    page.className = 'qhp-page';
    page.style
      ..position = 'relative'
      ..width = '${pageWidthPx.round()}px'
      ..height = '${pageHeightPx.round()}px'
      ..overflow = 'hidden';

    // Watermark — added as a real <img> element (rather than a CSS
    // background) so the browser computes the auto height from the image's
    // natural aspect ratio. The walker emits it via _emitImage at the
    // element's rendered rect, so the PDF gets the same aspect-correct
    // dimensions.
    //
    // Inserted as the FIRST child so the walker emits it before any
    // header/content/footer — that puts it at the bottom of the PDF
    // z-stack. (PDF.js / readers respect paint order.)
    //
    // The watermark image is expected to already include any opacity
    // baked in (per the consumer's contract); we don't apply alpha.
    if (options.watermarkUrl != null && options.watermarkUrl!.isNotEmpty) {
      // Parse "X% Y%" form for watermarkPosition (the only form we
      // currently support). Falls back to center on anything else.
      var posLeft = '50%';
      var posTop = '50%';
      final m = RegExp(r'^\s*([\d.]+%|\d+px)\s+([\d.]+%|\d+px)\s*$')
          .firstMatch(options.watermarkPosition);
      if (m != null) {
        posLeft = m.group(1)!;
        posTop = m.group(2)!;
      }
      final watermark = doc.createElement('img') as web.HTMLImageElement;
      watermark.src = options.watermarkUrl!;
      watermark.style
        ..position = 'absolute'
        ..left = posLeft
        ..top = posTop
        // translate centers the image on (left, top) so percentage
        // positions read as "image center at this point on the page".
        ..transform = 'translate(-50%, -50%)'
        ..width = options.watermarkSize
        ..height = 'auto'
        ..maxWidth = '100%'
        ..maxHeight = '100%'
        ..pointerEvents = 'none';
      page.appendChild(watermark);
    }

    // Header slot at the top (within marginTop area). Column flex with
    // justify-content:center vertically centers single-child content while
    // letting the child stretch to full width on the cross axis (so any
    // `text-align` / `justify-content` inside the consumer's HTML still
    // works).
    if (options.hasHeader) {
      final header = doc.createElement('div') as web.HTMLElement;
      header.className = 'qhp-page-header';
      header.style
        ..position = 'absolute'
        ..top = '${marginTopPx.round()}px'
        ..left = '${marginLeftPx.round()}px'
        ..right = '${marginRightPx.round()}px'
        ..height = '${headerHeightPx.round()}px'
        ..display = 'flex'
        ..flexDirection = 'column'
        ..justifyContent = 'center';
      header.innerHTML = _substitutePageVars(
        options.headerHtml ?? '',
        pageNumber,
        totalPages,
      ).toJS;
      page.appendChild(header);
    }

    // Footer slot at the bottom (within marginBottom area). Same column
    // flex centering — keeps the page-counter text mid-band (breathing
    // room above it) and preserves the consumer's `text-align` because
    // the child still spans the full cross-axis width.
    if (options.hasFooter) {
      final footer = doc.createElement('div') as web.HTMLElement;
      footer.className = 'qhp-page-footer';
      footer.style
        ..position = 'absolute'
        ..bottom = '${marginBottomPx.round()}px'
        ..left = '${marginLeftPx.round()}px'
        ..right = '${marginRightPx.round()}px'
        ..height = '${footerHeightPx.round()}px'
        ..display = 'flex'
        ..flexDirection = 'column'
        ..justifyContent = 'center';
      footer.innerHTML = _substitutePageVars(
        options.footerHtml ?? '',
        pageNumber,
        totalPages,
      ).toJS;
      page.appendChild(footer);
    }

    // Content slot fills the remaining area.
    final contentTopPx =
        marginTopPx + (options.hasHeader ? headerHeightPx : 0.0);
    final contentBottomPx =
        marginBottomPx + (options.hasFooter ? footerHeightPx : 0.0);
    final contentArea = doc.createElement('div') as web.HTMLElement;
    contentArea.className = 'qhp-page-content';
    contentArea.style
      ..position = 'absolute'
      ..top = '${contentTopPx.round()}px'
      ..left = '${marginLeftPx.round()}px'
      ..right = '${marginRightPx.round()}px'
      ..bottom = '${contentBottomPx.round()}px'
      ..overflow = 'hidden';
    for (final el in contentElements) {
      contentArea.appendChild(el);
    }
    page.appendChild(contentArea);

    return page;
  }

  String _substitutePageVars(String html, int page, int total) {
    if (html.isEmpty) return '';
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    return html
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{pages}}', '$total')
        .replaceAll('{{date}}', date)
        .replaceAll('{{time}}', time)
        .replaceAll('{{datetime}}', '$date $time');
  }

  /// Yield until the iframe's next animation frame, giving the browser a
  /// chance to flush layout.
  Future<void> _waitForLayout(web.Window win) {
    final completer = Completer<void>();
    void cb(JSAny _) {
      if (!completer.isCompleted) completer.complete();
    }
    win.requestAnimationFrame(cb.toJS);
    return completer.future;
  }

  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Custom] $message');
    }
  }
}

/// Element + its known height in CSS px. Used so the page-packer can
/// reason about cloned (off-DOM) slices whose `offsetHeight` is 0.
class _Sized {
  final web.Element element;
  final double height;
  const _Sized(this.element, this.height);
}

/// Result of slicing a `<table>` by rows: the per-page slice elements
/// (each a clone with its own subset of rows) plus the row-index lists
/// each slice covers, kept so callers can later identify "tail" rows
/// for re-pagination at a different (e.g. full-width) budget.
class _TablePagination {
  final List<_Sized> slices;
  final List<List<int>> rowGroups;
  const _TablePagination(this.slices, this.rowGroups);
}

/// Per-child context retained from Phase-1 (half-width) pagination so
/// Phase-2 tail re-pagination can identify the right rows to redo.
class _ChildContext {
  final web.Element child;
  final web.HTMLTableElement table;
  final List<List<int>> rowGroups;
  final double frameH; // height of non-table content inside [child]
  const _ChildContext({
    required this.child,
    required this.table,
    required this.rowGroups,
    required this.frameH,
  });
}


