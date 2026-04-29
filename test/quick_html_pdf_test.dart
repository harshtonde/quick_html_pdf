import 'package:flutter_test/flutter_test.dart';
import 'package:quick_html_pdf/quick_html_pdf.dart';

void main() {
  group('TemplateEngine', () {
    test('renders simple placeholders', () {
      final result = TemplateEngine.render('Hello {{name}}!', {
        'name': 'World',
      });
      expect(result, 'Hello World!');
    });

    test('renders nested placeholders', () {
      final result = TemplateEngine.render(
        '{{user.name}} from {{user.company.name}}',
        {
          'user': {
            'name': 'Alice',
            'company': {'name': 'Acme Corp'},
          },
        },
      );
      expect(result, 'Alice from Acme Corp');
    });

    test('escapes HTML in regular placeholders', () {
      final result = TemplateEngine.render('<p>{{text}}</p>', {
        'text': '<script>alert("xss")</script>',
      });
      expect(result, '<p>&lt;script&gt;alert("xss")&lt;/script&gt;</p>');
    });

    test('does not escape HTML in raw placeholders', () {
      final result = TemplateEngine.render('<div>{{{html}}}</div>', {
        'html': '<strong>Bold</strong>',
      });
      expect(result, '<div><strong>Bold</strong></div>');
    });

    test('renders each loops', () {
      final result = TemplateEngine.render(
        '{{#each items}}<li>{{this.name}}</li>{{/each}}',
        {
          'items': [
            {'name': 'Apple'},
            {'name': 'Banana'},
          ],
        },
      );
      expect(result, '<li>Apple</li><li>Banana</li>');
    });

    test('provides @index in loops', () {
      final result = TemplateEngine.render(
        '{{#each items}}{{@index}}: {{this}}; {{/each}}',
        {
          'items': ['a', 'b', 'c'],
        },
      );
      expect(result, '0: a; 1: b; 2: c; ');
    });

    test('provides @index1 (1-based) in loops', () {
      final result = TemplateEngine.render(
        '{{#each items}}{{@index1}}. {{this.name}} {{/each}}',
        {
          'items': [
            {'name': 'First'},
            {'name': 'Second'},
          ],
        },
      );
      expect(result, '1. First 2. Second ');
    });

    test('returns empty string for missing keys', () {
      final result = TemplateEngine.render(
        'Hello {{name}}!',
        <String, dynamic>{},
      );
      expect(result, 'Hello !');
    });

    test('throws on unclosed each block', () {
      expect(
        () => TemplateEngine.render('{{#each items}}<li>{{this}}</li>', {
          'items': ['a'],
        }),
        throwsA(isA<TemplateException>()),
      );
    });
  });

  group('PdfOptions', () {
    test('has correct default values (v3: print mode is the default)', () {
      const options = PdfOptions();
      expect(options.pageFormat, PdfPageFormat.a4);
      expect(options.orientation, PdfOrientation.portrait);
      expect(options.output, PdfOutput.print);
      expect(options.filename, 'document.pdf');
      expect(options.debug, false);
      expect(options.fonts, isEmpty);
    });

    test('exposes three output modes', () {
      expect(PdfOutput.values, hasLength(3));
      expect(PdfOutput.values, contains(PdfOutput.print));
      expect(PdfOutput.values, contains(PdfOutput.download));
      expect(PdfOutput.values, contains(PdfOutput.bytes));
    });

    test('calculates effective dimensions for portrait', () {
      const options = PdfOptions(
        pageFormat: PdfPageFormat.a4,
        orientation: PdfOrientation.portrait,
      );
      expect(options.effectiveWidthMm, 210);
      expect(options.effectiveHeightMm, 297);
    });

    test('calculates effective dimensions for landscape', () {
      const options = PdfOptions(
        pageFormat: PdfPageFormat.a4,
        orientation: PdfOrientation.landscape,
      );
      expect(options.effectiveWidthMm, 297);
      expect(options.effectiveHeightMm, 210);
    });

    test('copyWith creates modified copy', () {
      const original = PdfOptions(filename: 'original.pdf');
      final copy = original.copyWith(filename: 'copy.pdf');

      expect(original.filename, 'original.pdf');
      expect(copy.filename, 'copy.pdf');
      expect(copy.pageFormat, original.pageFormat);
    });

    test('copyWith preserves fonts', () {
      const fontA = PdfFont(family: 'A', src: 'a.ttf');
      const fontB = PdfFont(family: 'B', src: 'b.ttf');
      const original = PdfOptions(fonts: [fontA]);
      final copy = original.copyWith(fonts: [fontA, fontB]);
      expect(copy.fonts.map((f) => f.family), ['A', 'B']);
    });
  });

  group('PdfFont', () {
    test('defaults weight/style to normal', () {
      const f = PdfFont(family: 'Test', src: '/test.ttf');
      expect(f.family, 'Test');
      expect(f.src, '/test.ttf');
      expect(f.weight, 'normal');
      expect(f.style, 'normal');
    });
  });

  group('PdfMargins', () {
    test('default margins', () {
      const margins = PdfMargins();
      expect(margins.topMm, 20);
      expect(margins.rightMm, 15);
      expect(margins.bottomMm, 20);
      expect(margins.leftMm, 15);
    });

    test('uniform margins', () {
      const margins = PdfMargins.all(10);
      expect(margins.topMm, 10);
      expect(margins.rightMm, 10);
      expect(margins.bottomMm, 10);
      expect(margins.leftMm, 10);
    });

    test('symmetric margins', () {
      const margins = PdfMargins.symmetric(vertical: 25, horizontal: 20);
      expect(margins.topMm, 25);
      expect(margins.bottomMm, 25);
      expect(margins.leftMm, 20);
      expect(margins.rightMm, 20);
    });

    test('toCss generates correct string', () {
      const margins = PdfMargins(
        topMm: 10,
        rightMm: 15,
        bottomMm: 20,
        leftMm: 25,
      );
      expect(margins.toCss(), '10.0mm 15.0mm 20.0mm 25.0mm');
    });
  });

  group('HtmlComposer', () {
    test('composes complete HTML document', () {
      const options = PdfOptions();
      final html = HtmlComposer.compose('<p>Test</p>', options);

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<html'));
      expect(html, contains('@page'));
      expect(html, contains('<p>Test</p>'));
      expect(html, contains('class="pdf-content"'));
    });

    test('does not inject Paged.js script or running elements', () {
      // v3 uses CustomPaginator; the composer must not emit Paged.js
      // artifacts (script tag, PagedConfig shim, running-element wrappers,
      // @top-center / @bottom-center margin boxes). Header/footer chrome
      // is built per-page by CustomPaginator.
      const options = PdfOptions(
        headerHtml: '<div>Header</div>',
        footerHtml: '<div>Footer</div>',
      );
      final html = HtmlComposer.compose('<p>Body</p>', options);

      expect(html, isNot(contains('PagedConfig')));
      expect(html, isNot(contains('qhp:pagedjs-done')));
      expect(html, isNot(contains('qhp-running-header')));
      expect(html, isNot(contains('qhp-running-footer')));
      expect(html, isNot(contains('@top-center')));
      expect(html, isNot(contains('@bottom-center')));
    });
  });

  group('PdfGenerationException', () {
    test('includes phase information', () {
      const exception = PdfGenerationException(
        'Test error',
        phase: PdfGenerationPhase.vectorEmission,
        code: 'sample-code',
      );

      expect(exception.message, 'Test error');
      expect(exception.phase, PdfGenerationPhase.vectorEmission);
      expect(exception.code, 'sample-code');
      expect(exception.toString(), contains('vectorEmission'));
      expect(exception.toString(), contains('sample-code'));
    });
  });
}
