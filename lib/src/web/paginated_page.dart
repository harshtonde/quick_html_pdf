/// One paginated page produced by [CustomPaginator] and consumed by
/// [DomWalker]. The element points at the `<div class="qhp-page">` wrapper
/// that owns the page's header / footer / content / watermark slots.
library;

import 'package:web/web.dart' as web;

class PaginatedPage {
  final web.HTMLElement element;
  final int pageNumber;
  final int totalPages;

  PaginatedPage({
    required this.element,
    required this.pageNumber,
    required this.totalPages,
  });
}
