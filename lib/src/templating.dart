/// Fast template engine for QuickHtmlPdf.
///
/// Supports:
/// - `{{key}}` - HTML-escaped interpolation
/// - `{{nested.path}}` - Dot notation for nested objects
/// - `{{{rawHtml}}}` - Unescaped HTML insertion
/// - `{{#each items}}...{{/each}}` - Loop blocks
/// - `{{this.field}}` - Access current item in loop
/// - `{{@index}}` - Current loop index (0-based)
/// - `{{@index1}}` - Current loop index (1-based)
library;

import 'dart:convert';

import 'exceptions.dart';

/// HTML escape codec for safe interpolation.
const HtmlEscape _htmlEscape = HtmlEscape(HtmlEscapeMode.element);

/// Template engine that processes HTML templates with dynamic data.
class TemplateEngine {
  // Regex patterns for template syntax
  static final RegExp _rawPattern = RegExp(r'\{\{\{(\s*[\w.]+\s*)\}\}\}');
  static final RegExp _escapedPattern = RegExp(r'\{\{(\s*[\w.@]+\s*)\}\}');
  static final RegExp _eachBlockPattern = RegExp(
    r'\{\{#each\s+([\w.]+)\s*\}\}([\s\S]*?)\{\{/each\}\}',
    multiLine: true,
  );

  /// Render a template with the given data.
  ///
  /// Throws [TemplateException] if the template syntax is invalid
  /// or required data keys are missing.
  static String render(String template, Map<String, dynamic> data) {
    try {
      // Process in order: loops first, then raw, then escaped
      var result = _processEachBlocks(template, data);
      result = _processRawInterpolations(result, data);
      result = _processEscapedInterpolations(result, data);

      // Check for any remaining unprocessed template tags
      _validateNoRemainingTags(result);

      return result;
    } catch (e) {
      if (e is TemplateException) rethrow;
      throw TemplateException('Template rendering failed', e.toString());
    }
  }

  /// Process {{#each items}}...{{/each}} blocks.
  static String _processEachBlocks(String template, Map<String, dynamic> data) {
    return template.replaceAllMapped(_eachBlockPattern, (match) {
      final keyPath = match.group(1)!.trim();
      final blockContent = match.group(2)!;

      final items = _resolveValue(keyPath, data);

      if (items == null) {
        throw TemplateException(
          'Each block key not found: $keyPath',
          'Available keys: ${data.keys.join(', ')}',
        );
      }

      if (items is! List) {
        throw TemplateException(
          'Each block requires a List, got ${items.runtimeType}',
          'Key: $keyPath',
        );
      }

      final buffer = StringBuffer();

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        var itemContent = blockContent;

        // Create context for this iteration
        final itemData = <String, dynamic>{
          ...data,
          '@index': i,
          '@index1': i + 1,
          '@first': i == 0,
          '@last': i == items.length - 1,
        };

        // Handle {{this}} and {{this.field}} patterns
        if (item is Map<String, dynamic>) {
          // Replace {{this.field}} with the field value
          itemContent = itemContent.replaceAllMapped(
            RegExp(r'\{\{\{?\s*this\.([\w.]+)\s*\}?\}\}'),
            (m) {
              final isRaw = m.group(0)!.startsWith('{{{');
              final fieldPath = m.group(1)!.trim();
              final value = _resolveValue(fieldPath, item);
              final strValue = value?.toString() ?? '';
              return isRaw ? strValue : _htmlEscape.convert(strValue);
            },
          );

          // Replace {{this}} with the entire item (as JSON for maps)
          itemContent = itemContent.replaceAllMapped(
            RegExp(r'\{\{(\{?)\s*this\s*(\}?)\}\}'),
            (m) {
              final isRaw = m.group(1) == '{' && m.group(2) == '}';
              final strValue = item.toString();
              return isRaw ? strValue : _htmlEscape.convert(strValue);
            },
          );
        } else {
          // For non-map items, {{this}} represents the value directly
          itemContent = itemContent.replaceAllMapped(
            RegExp(r'\{\{(\{?)\s*this\s*(\}?)\}\}'),
            (m) {
              final isRaw = m.group(1) == '{' && m.group(2) == '}';
              final strValue = item?.toString() ?? '';
              return isRaw ? strValue : _htmlEscape.convert(strValue);
            },
          );
        }

        // Process nested each blocks recursively with item context
        if (item is Map<String, dynamic>) {
          itemContent = _processEachBlocks(itemContent, {...itemData, ...item});
        } else {
          itemContent = _processEachBlocks(itemContent, itemData);
        }

        // Process @index and other special variables
        itemContent = _processEscapedInterpolations(itemContent, itemData);

        // Process raw interpolations within the item context
        if (item is Map<String, dynamic>) {
          itemContent = _processRawInterpolations(itemContent, {
            ...data,
            ...item,
          });
          itemContent = _processEscapedInterpolations(itemContent, {
            ...data,
            ...item,
          });
        }

        buffer.write(itemContent);
      }

      return buffer.toString();
    });
  }

  /// Process {{{rawHtml}}} interpolations (unescaped).
  static String _processRawInterpolations(
    String template,
    Map<String, dynamic> data,
  ) {
    return template.replaceAllMapped(_rawPattern, (match) {
      final keyPath = match.group(1)!.trim();
      final value = _resolveValue(keyPath, data);

      if (value == null) {
        // Return empty string for missing optional values in raw mode
        return '';
      }

      return value.toString();
    });
  }

  /// Process {{key}} interpolations (HTML-escaped).
  static String _processEscapedInterpolations(
    String template,
    Map<String, dynamic> data,
  ) {
    return template.replaceAllMapped(_escapedPattern, (match) {
      final keyPath = match.group(1)!.trim();

      // Skip special loop variables if not in loop context
      if (keyPath.startsWith('@')) {
        final value = data[keyPath];
        if (value != null) {
          return _htmlEscape.convert(value.toString());
        }
        return match.group(0)!; // Keep as-is if not in loop context
      }

      final value = _resolveValue(keyPath, data);

      if (value == null) {
        // Return empty string for missing values
        return '';
      }

      return _htmlEscape.convert(value.toString());
    });
  }

  /// Resolve a dot-notation path to a value in the data map.
  static dynamic _resolveValue(String keyPath, Map<String, dynamic> data) {
    final parts = keyPath.split('.');
    dynamic current = data;

    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(part)) {
          return null;
        }
        current = current[part];
      } else if (current is Map) {
        if (!current.containsKey(part)) {
          return null;
        }
        current = current[part];
      } else {
        return null;
      }
    }

    return current;
  }

  /// Validate that no template tags remain unprocessed.
  static void _validateNoRemainingTags(String result) {
    // Check for unclosed each blocks
    if (result.contains('{{#each')) {
      final match = RegExp(r'\{\{#each\s+(\w+)').firstMatch(result);
      throw TemplateException(
        'Unclosed each block',
        match != null ? 'Block for "${match.group(1)}" is not closed' : null,
      );
    }

    if (result.contains('{{/each}}')) {
      throw TemplateException(
        'Unexpected closing tag',
        'Found {{/each}} without matching {{#each}}',
      );
    }
  }
}
