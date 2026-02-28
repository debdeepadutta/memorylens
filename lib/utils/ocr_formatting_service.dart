enum OcrElementType { heading, paragraph, listItem, table, divider }

class OcrElement {
  final String text;
  final OcrElementType type;
  final int? listNumber;
  final List<List<String>>? tableData;

  OcrElement({
    required this.text,
    required this.type,
    this.listNumber,
    this.tableData,
  });
}

class OcrFormattingService {
  /// Transforms raw OCR text into a structured list of document elements.
  static List<OcrElement> parse(String rawText) {
    if (rawText.isEmpty) return [];

    final lines = rawText.split('\n');
    final List<OcrElement> elements = [];

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        // Handle potential divider if multiple empty lines
        int emptyCount = 1;
        while (i + 1 < lines.length && lines[i + 1].trim().isEmpty) {
          emptyCount++;
          i++;
        }
        if (emptyCount >= 3) {
          elements.add(OcrElement(text: "", type: OcrElementType.divider));
        }
        i++;
        continue;
      }

      // 1. Try Table Detection
      final tableBlock = _tryParseTable(lines, i);
      if (tableBlock != null) {
        elements.add(tableBlock.element);
        i = tableBlock.nextIndex;
        continue;
      }

      // 3. Try List Detection
      final listItem = _parseListItem(line);
      if (listItem != null) {
        elements.add(listItem);
        i++;
        continue;
      }

      // 4. Try Heading Detection
      if (_isHeading(line)) {
        elements.add(OcrElement(text: trimmed, type: OcrElementType.heading));
        i++;
        continue;
      }

      // 5. Fallback to Paragraph
      // If it's a single line that's not anything else, treat as paragraph
      // We could try to join adjacent paragraph lines if they aren't separated by empty lines
      List<String> paragraphLines = [line];
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_isHeading(lines[i]) &&
          _parseListItem(lines[i]) == null &&
          _tryParseTable(lines, i) == null) {
        paragraphLines.add(lines[i]);
        i++;
      }

      elements.add(
        OcrElement(
          text: paragraphLines.join('\n'),
          type: OcrElementType.paragraph,
        ),
      );
    }

    return elements;
  }

  static bool _isHeading(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.length > 60) return false;

    // Mostly uppercase
    final letters = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) return false;
    final upperCaseCount = letters
        .split('')
        .where((c) => c == c.toUpperCase())
        .length;
    if (upperCaseCount / letters.length > 0.8) return true;

    // Common heading patterns
    if (RegExp(
      r'^(Section|Chapter|Part|Total|Summary|Date|Invoice|Receipt|Header|Title)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  static OcrElement? _parseListItem(String line) {
    final trimmed = line.trim();
    // Numbered list: "1. ", "1) "
    final numberedPattern = RegExp(r'^(\d+)[\.\)]\s+(.*)$');
    final numberedMatch = numberedPattern.firstMatch(trimmed);
    if (numberedMatch != null) {
      return OcrElement(
        text: numberedMatch.group(2)!,
        type: OcrElementType.listItem,
        listNumber: int.parse(numberedMatch.group(1)!),
      );
    }

    // Bullet points: "- ", "* ", "• "
    final bulletPattern = RegExp(r'^[-\*\•]\s+(.*)$');
    final bulletMatch = bulletPattern.firstMatch(trimmed);
    if (bulletMatch != null) {
      return OcrElement(
        text: bulletMatch.group(1)!,
        type: OcrElementType.listItem,
      );
    }

    return null;
  }

  static _ParseResult? _tryParseTable(List<String> lines, int startIndex) {
    // Improved table detection:
    // Look for lines that have multiple "columns" separated by 2+ spaces or tabs

    List<List<String>> tableData = [];
    int i = startIndex;

    List<String>? tryParseRow(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return null;

      // Split by 2+ spaces or tabs
      final columns = trimmed
          .split(RegExp(r'\s{2,}|\t+'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (columns.length >= 2) return columns;
      return null;
    }

    while (i < lines.length) {
      final row = tryParseRow(lines[i]);
      if (row != null) {
        tableData.add(row);
        i++;
      } else {
        break;
      }
    }

    if (tableData.length >= 2) {
      return _ParseResult(
        OcrElement(
          text: "Table",
          type: OcrElementType.table,
          tableData: tableData,
        ),
        i,
      );
    }

    return null;
  }
}

class _ParseResult {
  final OcrElement element;
  final int nextIndex;
  _ParseResult(this.element, this.nextIndex);
}
