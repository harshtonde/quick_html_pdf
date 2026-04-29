/// Font registration + cascade resolution for the vector PDF pipeline.
///
/// **Vector mode requires consumers to register at least one font** via
/// `PdfOptions.fonts`. Registration:
///
/// 1. Fetches each TTF (via `dart:html.HttpRequest` / `web.window.fetch`).
/// 2. Base64-encodes it.
/// 3. Calls `JsPDF.addFileToVFS` + `JsPDF.addFont` to register the family.
///
/// Resolution: walks a CSS `font-family` declaration (comma-separated list)
/// from left to right. First family with a registered match wins. The match
/// considers weight + style. If nothing matches, falls back to the first
/// registered font (Regular weight if available); never falls back to a
/// jsPDF built-in (those lack non-Latin-1 glyphs).
///
/// If no fonts are registered at all, [register] throws — the calling
/// strategy uses that to surface a clear "register at least one font" error
/// to the caller.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../exceptions.dart';
import '../options.dart';
import 'js_interop.dart';

/// A font that's been registered with jsPDF and can be selected by
/// `pdf.setFont(family, style)`.
class ResolvedFont {
  /// jsPDF font name (the value `JsPDF.setFont` expects).
  final String family;

  /// jsPDF style token: `'normal'`, `'bold'`, `'italic'`, `'bolditalic'`.
  final String style;

  /// CSS family name used at registration time (case-preserved).
  final String cssFamily;

  /// CSS weight as registered (`'normal'`, `'bold'`, or numeric).
  final String cssWeight;

  /// CSS style as registered (`'normal'`, `'italic'`, `'oblique'`).
  final String cssStyle;

  const ResolvedFont({
    required this.family,
    required this.style,
    required this.cssFamily,
    required this.cssWeight,
    required this.cssStyle,
  });
}

class FontRegistry {
  final List<PdfFont> _declared;
  final bool debug;

  /// All resolved fonts after [register] runs. Maps lowercase family → list of
  /// resolved variants (different weights/styles).
  final Map<String, List<ResolvedFont>> _byFamily = {};

  /// Index by (family-lowercase + style) for direct lookup during resolution.
  final Map<String, ResolvedFont> _byKey = {};

  bool _registered = false;

  FontRegistry({required List<PdfFont> declared, this.debug = false})
      : _declared = declared;

  /// Whether [register] has been called and at least one font is available.
  bool get isReady => _registered && _byKey.isNotEmpty;

  /// Whether the consumer registered any fonts at all.
  bool get hasDeclaredFonts => _declared.isNotEmpty;

  /// Fetch + register every declared font with [pdf]. Idempotent: subsequent
  /// calls with the same [pdf] are no-ops if registration already succeeded.
  ///
  /// Throws [PdfGenerationException] (`code: 'no-fonts-registered'`) when
  /// the consumer didn't pass any fonts.
  Future<void> register(JsPDF pdf) async {
    if (_registered) return;
    if (_declared.isEmpty) {
      throw const PdfGenerationException(
        'Vector PDF mode requires at least one font registered via '
        'PdfOptions.fonts. Without a registered font, jsPDF would fall back '
        'to its WinAnsi-only built-ins (which produce wrong glyphs for any '
        'non-Latin-1 character — e.g. "₹" → "¹"). Register a TTF that covers '
        'your content. See README "Custom Fonts".',
        phase: PdfGenerationPhase.vectorEmission,
        code: 'no-fonts-registered',
      );
    }

    for (final font in _declared) {
      try {
        await _registerOne(pdf, font);
      } catch (e) {
        if (debug) _log('Failed to register ${font.family} (${font.src}): $e');
        // Continue with the others; the resolver will fall back.
      }
    }

    if (_byKey.isEmpty) {
      throw PdfGenerationException(
        'No fonts registered successfully (declared: '
        '${_declared.map((f) => "${f.family} <- ${f.src}").join(", ")}). '
        'Check that the font URLs are reachable and CORS-allowed.',
        phase: PdfGenerationPhase.fontLoading,
        code: 'no-fonts-loaded',
      );
    }
    _registered = true;
  }

  Future<void> _registerOne(JsPDF pdf, PdfFont font) async {
    final fontBytes = await _resolveBytes(font);
    final base64Str = base64Encode(fontBytes);
    final jsPdfStyle = _toJsPdfStyle(weight: font.weight, style: font.style);
    final familySafe = font.family.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final filename = '$familySafe-$jsPdfStyle.ttf';

    pdf.addFileToVFS(filename, base64Str);
    pdf.addFont(filename, font.family, jsPdfStyle);

    final resolved = ResolvedFont(
      family: font.family,
      style: jsPdfStyle,
      cssFamily: font.family,
      cssWeight: font.weight,
      cssStyle: font.style,
    );
    final familyLc = font.family.toLowerCase();
    _byFamily.putIfAbsent(familyLc, () => []).add(resolved);
    _byKey['$familyLc|$jsPdfStyle'] = resolved;

    if (debug) {
      _log('Registered $filename → setFont("${font.family}", "$jsPdfStyle")'
          ' [${font.bytes != null ? "bytes" : "url"}]');
    }
  }

  Future<Uint8List> _resolveBytes(PdfFont font) async {
    if (font.bytes != null) return font.bytes!;
    final src = font.src;
    if (src == null) {
      throw const PdfGenerationException(
        'PdfFont has neither bytes nor src',
        phase: PdfGenerationPhase.fontLoading,
        code: 'pdffont-empty',
      );
    }
    final response = await web.window.fetch(src.toJS).toDart;
    if (!response.ok) {
      throw StateError(
        'HTTP ${response.status} fetching font: $src',
      );
    }
    final ab = await response.arrayBuffer().toDart;
    return ab.toDart.asUint8List();
  }

  /// Resolve a CSS `font-family` declaration to a registered font.
  ///
  /// [cssFontFamily] is the comma-separated list (e.g.
  /// `'Arial, Helvetica, sans-serif'`). [weight] is the CSS weight number
  /// (`400` is normal, `700` is bold). [style] is `'normal'` / `'italic'` /
  /// `'oblique'`.
  ///
  /// Returns the best match. If no family in the list is registered, returns
  /// the first registered font's matching weight/style (so we never fall back
  /// to jsPDF built-ins).
  ResolvedFont resolve({
    required String cssFontFamily,
    required int weight,
    required String style,
  }) {
    final targetStyle = _toJsPdfStyle(
      weight: weight >= 600 ? 'bold' : 'normal',
      style: style,
    );

    final families = _splitFamilyList(cssFontFamily);
    for (final fam in families) {
      final famLc = fam.toLowerCase();
      // Exact (family + style) match.
      final exact = _byKey['$famLc|$targetStyle'];
      if (exact != null) return exact;
      // Family registered but not in this style — fall back to family's
      // 'normal' if available, else any variant.
      final normal = _byKey['$famLc|normal'];
      if (normal != null) return normal;
      final any = _byFamily[famLc];
      if (any != null && any.isNotEmpty) return any.first;
    }

    // No declared family matched. Use the first registered font's
    // matching style if available, else the first font registered.
    if (_byKey.isNotEmpty) {
      // Prefer requested style of the first registered family.
      final firstFamilyLc = _byFamily.keys.first;
      final styleMatch = _byKey['$firstFamilyLc|$targetStyle'];
      if (styleMatch != null) return styleMatch;
      return _byKey.values.first;
    }

    // Should be unreachable — register() throws when nothing succeeded.
    throw const PdfGenerationException(
      'FontRegistry has no fonts to resolve against',
      phase: PdfGenerationPhase.vectorEmission,
      code: 'no-fonts-registered',
    );
  }

  /// Whether [text] contains any codepoint not covered by [font]'s registered
  /// TTF. Used by the DOM walker to fail loudly when a registered font
  /// doesn't cover the rendered content.
  ///
  /// (We don't actually inspect the TTF's glyph table here — that would
  /// require parsing the font. Instead, the walker reports this only as a
  /// debug warning when text contains chars outside U+0000–U+00FF AND the
  /// only registered font is a built-in. Actual missing-glyph detection
  /// happens at render time when jsPDF substitutes.)
  ///
  /// This stub exists to keep the API stable; future versions can parse cmap
  /// tables for proper coverage checking.
  bool isLikelyMissingCoverage(String text, ResolvedFont font) {
    // Conservative heuristic: registered Unicode-aware fonts are assumed to
    // cover anything the consumer asked for. Real coverage check is future
    // work.
    return false;
  }

  /// Split a CSS `font-family` declaration into individual family names,
  /// stripping quotes and whitespace. `'Arial, "Helvetica Neue", sans-serif'`
  /// becomes `['Arial', 'Helvetica Neue', 'sans-serif']`.
  static List<String> _splitFamilyList(String css) {
    return css
        .split(',')
        .map((s) => s.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Convert CSS weight/style to jsPDF's combined style token.
  static String _toJsPdfStyle({
    required String weight,
    required String style,
  }) {
    final isBold = weight == 'bold' ||
        weight == '600' ||
        weight == '700' ||
        weight == '800' ||
        weight == '900' ||
        (int.tryParse(weight) != null && int.parse(weight) >= 600);
    final isItalic = style == 'italic' || style == 'oblique';
    if (isBold && isItalic) return 'bolditalic';
    if (isBold) return 'bold';
    if (isItalic) return 'italic';
    return 'normal';
  }

  void _log(String message) {
    if (debug) {
      // ignore: avoid_print
      print('[QuickHtmlPdf:Fonts] $message');
    }
  }
}
