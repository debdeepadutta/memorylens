import 'package:flutter_test/flutter_test.dart';
import 'package:memorylens/utils/ocr_formatting_service.dart';

void main() {
  group('OcrFormattingService Tests', () {
    test('Preserves 100% of text', () {
      const text = "Line 1\nLine 2\n\nLine 3";
      final elements = OcrFormattingService.parse(text);

      String combined = elements.map((e) => e.text).join('\n');
      expect(combined.isNotEmpty, true);

      final originalChars = text.replaceAll(RegExp(r'\s'), '');
      final reconstructedChars = elements
          .map((e) => e.text)
          .join('')
          .replaceAll(RegExp(r'\s'), '');

      expect(reconstructedChars, originalChars);
    });

    test('Detects Headings', () {
      const text = "SUMMARY\nThis is a body line.";
      final elements = OcrFormattingService.parse(text);

      expect(elements[0].type, OcrElementType.heading);
      expect(elements[0].text, "SUMMARY");
    });

    test('Detects Lists', () {
      const text = "1. Item one\n• Item two\n- Item three";
      final elements = OcrFormattingService.parse(text);

      expect(elements[0].type, OcrElementType.listItem);
      expect(elements[0].listNumber, 1);
      expect(elements[1].type, OcrElementType.listItem);
      expect(elements[2].type, OcrElementType.listItem);
    });

    test('Detects Tables', () {
      const text =
          "Name    Age    City\nJohn    25     New York\nJane    30     London";
      final elements = OcrFormattingService.parse(text);

      expect(elements[0].type, OcrElementType.table);
      expect(elements[0].tableData!.length, 3);
      expect(elements[0].tableData![0][0], "Name");
    });

    test('Detects Dividers', () {
      const text = "Start\n\n\n\nEnd";
      final elements = OcrFormattingService.parse(text);

      expect(elements.any((e) => e.type == OcrElementType.divider), true);
    });
  });
}
