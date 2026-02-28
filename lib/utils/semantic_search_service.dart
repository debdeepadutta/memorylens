import 'package:intl/intl.dart';

enum MatchReason {
  ocr('Found in text'),
  label('Found in image labels'),
  location('Found in location'),
  date('Matched date');

  final String explanation;
  const MatchReason(this.explanation);
}

class SearchResult {
  final String assetId;
  final double score;
  final Set<MatchReason> reasons;
  final String highlights;
  final int priority; // 1: Exact, 2: Related, 3: Partial

  SearchResult({
    required this.assetId,
    required this.score,
    required this.reasons,
    required this.highlights,
    required this.priority,
  });
}

class SemanticSearchService {
  static final SemanticSearchService _instance =
      SemanticSearchService._internal();
  factory SemanticSearchService() => _instance;
  SemanticSearchService._internal();

  // Keyword scoring weights
  static const double weightOcr = 1.0;
  static const double weightLabels = 2.0; // Higher weight for object detection
  static const double weightLocation = 1.0;
  static const double weightDate = 1.0;

  final Map<String, List<String>> _relatedTerms = {
    'teddy': ['teddy bear', 'stuffed animal', 'plush'],
    'food': ['meal', 'restaurant', 'eat', 'dish', 'cuisine', 'snack'],
    'temple': ['church', 'mosque', 'monument', 'worship', 'religious'],
    'beach': ['ocean', 'sea', 'sand', 'waves', 'shore', 'coast'],
    'birthday': ['cake', 'celebrate', 'party', 'candles', 'gifts'],
    'travel': ['trip', 'journey', 'vacation', 'tourist', 'sightseeing'],
    'receipt': ['bill', 'invoice', 'payment', 'purchase', 'order'],
    'dog': ['puppy', 'pet', 'animal', 'canine'],
    'cat': ['kitten', 'pet', 'animal', 'feline'],
    'car': ['vehicle', 'drive', 'road', 'transport', 'automobile'],
  };

  List<SearchResult> search({
    required String query,
    required List<Map<String, dynamic>> photos,
    DateTime? now,
  }) {
    if (query.trim().isEmpty) return [];

    final currentNow = now ?? DateTime.now();
    final lowerQuery = query.toLowerCase().trim();

    final dateRange = _parseDateRange(lowerQuery, currentNow);
    final keywords = _extractKeywords(lowerQuery);

    // Level 1: Exact matches
    List<SearchResult> allResults = _performSearch(
      photos: photos,
      keywords: keywords,
      dateRange: dateRange,
      priority: 1,
    );

    // If NO results found in Level 1, try Level 2: Related matches
    if (allResults.isEmpty && keywords.isNotEmpty) {
      List<String> relatedKeywords = [];
      for (var kw in keywords) {
        if (_relatedTerms.containsKey(kw)) {
          relatedKeywords.addAll(_relatedTerms[kw]!);
        }
      }

      if (relatedKeywords.isNotEmpty) {
        allResults = _performSearch(
          photos: photos,
          keywords: relatedKeywords,
          dateRange: dateRange,
          priority: 2,
        );
      }
    }

    // If STILL NO results found, try Level 3: Partial matches
    if (allResults.isEmpty && keywords.isNotEmpty) {
      allResults = _performSearch(
        photos: photos,
        keywords: keywords,
        dateRange: dateRange,
        priority: 3,
        isPartial: true,
      );
    }

    return allResults;
  }

  List<SearchResult> _performSearch({
    required List<Map<String, dynamic>> photos,
    required List<String> keywords,
    _DateRange? dateRange,
    required int priority,
    Set<String>? excludeIds,
    bool isPartial = false,
  }) {
    List<SearchResult> results = [];

    for (var photo in photos) {
      final assetId = photo['asset_id'] as String;
      if (excludeIds != null && excludeIds.contains(assetId)) continue;

      double score = 0.0;
      Set<MatchReason> reasons = {};

      final ocrText = (photo['extracted_text'] as String? ?? '').toLowerCase();
      final labels = (photo['image_labels'] as String? ?? '').toLowerCase();
      final location = (photo['location_name'] as String? ?? '').toLowerCase();
      final dateStr = photo['creation_date'] as String?;

      DateTime? photoDate;
      if (dateStr != null) {
        photoDate = DateTime.tryParse(dateStr);
      }

      bool dateMatch = true;
      if (dateRange != null) {
        if (photoDate != null) {
          dateMatch =
              photoDate.isAfter(dateRange.start) &&
              photoDate.isBefore(dateRange.end);
          if (dateMatch) {
            score += weightDate;
            reasons.add(MatchReason.date);
          } else {
            continue;
          }
        } else {
          continue;
        }
      }

      if (keywords.isNotEmpty) {
        bool keywordMatched = false;

        for (var kw in keywords) {
          bool matchOcr = isPartial
              ? ocrText.contains(kw)
              : _isExactMatch(ocrText, kw);
          bool matchLabels = isPartial
              ? labels.contains(kw)
              : _isExactMatch(labels, kw);
          bool matchLocation = isPartial
              ? location.contains(kw)
              : _isExactMatch(location, kw);

          if (matchOcr) {
            double currentOcrWeight = weightOcr;
            // Length penalty: if it's a long text document and the keyword is just buried in noise
            if (ocrText.length > 200 && !isPartial) {
              currentOcrWeight *= 0.5;
            }
            score += currentOcrWeight;
            reasons.add(MatchReason.ocr);
            keywordMatched = true;
          }
          if (matchLabels) {
            score += weightLabels;
            reasons.add(MatchReason.label);
            keywordMatched = true;
          }
          if (matchLocation) {
            score += weightLocation;
            reasons.add(MatchReason.location);
            keywordMatched = true;
          }
        }

        if (!keywordMatched) continue;
      } else if (dateRange == null) {
        continue;
      }

      // Minimum relevance threshold for Exact matches to filter noise
      if (priority == 1 && score < 1.0) continue;

      if (score > 0 || dateRange != null) {
        results.add(
          SearchResult(
            assetId: assetId,
            score: score,
            reasons: reasons,
            highlights: reasons.map((r) => r.explanation).join(' • '),
            priority: priority,
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  bool _isExactMatch(String text, String kw) {
    if (text.isEmpty) return false;
    // Simple word boundary check
    final regex = RegExp('\\b${RegExp.escape(kw)}\\b');
    return regex.hasMatch(text);
  }

  List<String> _extractKeywords(String query) {
    String clean = query
        .replaceAll('photos from', '')
        .replaceAll('photos in', '')
        .replaceAll('photos of', '')
        .replaceAll('images of', '')
        .replaceAll('pics of', '')
        .replaceAll('show me', '')
        .replaceAll('find', '');

    const dateTokens = [
      'yesterday',
      'today',
      'last week',
      'last month',
      'last year',
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
      'jan',
      'feb',
      'mar',
      'apr',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];

    for (var token in dateTokens) {
      clean = clean.replaceAll(token, '');
    }

    return clean.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  }

  _DateRange? _parseDateRange(String query, DateTime now) {
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(query);
    if (yearMatch != null) {
      int year = int.parse(yearMatch.group(1)!);
      return _DateRange(DateTime(year, 1, 1), DateTime(year, 12, 31, 23, 59));
    }

    if (query.contains('yesterday')) {
      final yesterday = now.subtract(const Duration(days: 1));
      return _DateRange(
        DateTime(yesterday.year, yesterday.month, yesterday.day),
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59),
      );
    }

    if (query.contains('last week')) {
      final start = now.subtract(Duration(days: now.weekday + 6));
      final end = start.add(const Duration(days: 6, hours: 23, minutes: 59));
      return _DateRange(start, end);
    }

    if (query.contains('last month')) {
      int month = now.month - 1;
      int year = now.year;
      if (month <= 0) {
        month = 12;
        year--;
      }
      final start = DateTime(year, month, 1);
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final end = DateTime(year, month, daysInMonth, 23, 59);
      return _DateRange(start, end);
    }

    final months = {
      'january': 1,
      'jan': 1,
      'february': 2,
      'feb': 2,
      'march': 3,
      'mar': 3,
      'april': 4,
      'apr': 4,
      'may': 5,
      'june': 6,
      'jun': 6,
      'july': 7,
      'jul': 7,
      'august': 8,
      'aug': 8,
      'september': 9,
      'sep': 9,
      'october': 10,
      'oct': 10,
      'november': 11,
      'nov': 11,
      'december': 12,
      'dec': 12,
    };

    for (var entry in months.entries) {
      if (query.contains(entry.key)) {
        int year = now.year;
        final yearM = RegExp(r'\b(20\d{2})\b').firstMatch(query);
        if (yearM != null) year = int.parse(yearM.group(1)!);

        final start = DateTime(year, entry.value, 1);
        final nextMonth = entry.value == 12 ? 1 : entry.value + 1;
        final nextYear = entry.value == 12 ? year + 1 : year;
        final end = DateTime(nextYear, nextMonth, 0, 23, 59);
        return _DateRange(start, end);
      }
    }

    return null;
  }
}

class _DateRange {
  final DateTime start;
  final DateTime end;
  _DateRange(this.start, this.end);
}
