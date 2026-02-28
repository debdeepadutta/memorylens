import '../db/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

class MemoryStory {
  final String narrative;
  final String mostVisitedLocation;
  final int totalPhotos;
  final String topCategory;
  final List<String>
  top3Categories; // e.g. ["📸 People", "🍕 Food", "📱 Screenshots"]

  MemoryStory({
    required this.narrative,
    required this.mostVisitedLocation,
    required this.totalPhotos,
    required this.topCategory,
    required this.top3Categories,
  });
}

class GlobalStats {
  final int totalPhotos;
  final int totalMonths;
  final String mostActiveMonth;
  final String topCategory;

  GlobalStats({
    required this.totalPhotos,
    required this.totalMonths,
    required this.mostActiveMonth,
    required this.topCategory,
  });
}

class CategoryDef {
  final String name;
  final String icon;
  final List<String> keywords;

  CategoryDef(this.name, this.icon, this.keywords);
}

class MemoryStoryService {
  static final List<CategoryDef> _categoryDefs = [
    CategoryDef('People', '📸', [
      'face',
      'person',
      'people',
      'crowd',
      'man',
      'woman',
      'child',
      'human',
    ]),
    CategoryDef('Food', '🍕', [
      'food',
      'meal',
      'drink',
      'restaurant',
      'cuisine',
      'dish',
      'breakfast',
      'lunch',
      'dinner',
      'cooking',
    ]),
    CategoryDef('Places', '🏛️', [
      'temple',
      'church',
      'mosque',
      'monument',
      'building',
      'architecture',
      'city',
      'urban',
      'landmark',
      'tower',
      'bridge',
    ]),
    CategoryDef('Documents', '📄', [
      'receipt',
      'invoice',
      'bill',
      'certificate',
      'document',
      'form',
      'paper',
      'text',
      'license',
      'passport',
    ]),
    CategoryDef('Screenshots', '📱', []), // Handled by ratio
    CategoryDef('Events', '🎉', [
      'party',
      'celebration',
      'birthday',
      'wedding',
      'festival',
      'concert',
      'audience',
      'stage',
      'ceremony',
    ]),
    CategoryDef('Nature', '🌿', [
      'tree',
      'flower',
      'garden',
      'mountain',
      'river',
      'sky',
      'cloud',
      'forest',
      'nature',
      'landscape',
      'outdoor',
      'ocean',
      'sunset',
    ]),
    CategoryDef('Shopping', '🛍️', [
      'product',
      'price tag',
      'shopping bag',
      'store',
      'market',
      'grocery',
      'fashion',
      'clothing',
      'shoes',
    ]),
    CategoryDef('Travel', '🚗', [
      'car',
      'bus',
      'train',
      'road',
      'airport',
      'vehicle',
      'airplane',
      'flight',
      'highway',
      'street',
      'bicycle',
      'motorcycle',
    ]),
    CategoryDef('Study', '📚', [
      'book',
      'notebook',
      'pen',
      'diagram',
      'handwriting',
      'notes',
      'classroom',
      'school',
      'university',
      'library',
      'blackboard',
      'whiteboard',
    ]),
    CategoryDef('Music', '🎵', [
      'music',
      'instrument',
      'performance',
      'guitar',
      'piano',
      'drums',
      'singer',
      'stage',
      'concert',
    ]),
    CategoryDef('Fitness', '💪', [
      'gym',
      'sport',
      'exercise',
      'workout',
      'running',
      'athlete',
      'football',
      'basketball',
      'soccer',
      'tennis',
      'yoga',
      'stadium',
    ]),
  ];

  static Future<GlobalStats> getGlobalStats() async {
    final db = DatabaseHelper.instance;
    final allMetadata = await db.getAllPhotosMetadata();

    if (allMetadata.isEmpty) {
      return GlobalStats(
        totalPhotos: 0,
        totalMonths: 0,
        mostActiveMonth: "N/A",
        topCategory: "N/A",
      );
    }

    Map<String, int> monthCounts = {};
    Map<String, int> categoryCounts = {};

    for (var photo in allMetadata) {
      final dateStr = photo['creation_date'] as String?;
      if (dateStr != null) {
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          final mKey = DateFormat('MMMM yyyy').format(date);
          monthCounts[mKey] = (monthCounts[mKey] ?? 0) + 1;
        }
      }

      final category = await _detectCategory(photo);
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }

    final mostActive = monthCounts.isEmpty
        ? "N/A"
        : monthCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final topCat = categoryCounts.isEmpty
        ? "Personal"
        : categoryCounts.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

    // Find icon for top category
    String topCatWithIcon = topCat;
    for (var def in _categoryDefs) {
      if (def.name == topCat) {
        topCatWithIcon = "${def.icon} $topCat";
        break;
      }
    }

    return GlobalStats(
      totalPhotos: allMetadata.length,
      totalMonths: monthCounts.length,
      mostActiveMonth: mostActive,
      topCategory: topCatWithIcon,
    );
  }

  static Future<String> _detectCategory(Map<String, dynamic> photo) async {
    // 1. Check screenshots by ratio
    final assetId = photo['asset_id'] as String;
    final asset = await AssetEntity.fromId(assetId);
    if (asset != null) {
      final ratio = asset.width / asset.height;
      // Typical phone ratios: 9/20=0.45 or 20/9=2.22
      if ((ratio > 0.4 && ratio < 0.5) || (ratio > 2.1 && ratio < 2.4)) {
        return 'Screenshots';
      }
    }

    final text = (photo['extracted_text'] as String? ?? '').toLowerCase();
    final labels = (photo['image_labels'] as String? ?? '').toLowerCase();

    // 2. Keyword matching
    for (var def in _categoryDefs) {
      if (def.name == 'Screenshots') continue;
      for (var kw in def.keywords) {
        if (labels.contains(kw) || text.contains(kw)) {
          return def.name;
        }
      }
    }

    return 'Personal';
  }

  static Future<MemoryStory> generateStory(
    int year,
    int month, {
    List<Map<String, dynamic>>? providedPhotos,
  }) async {
    final List<Map<String, dynamic>> monthPhotos;

    if (providedPhotos != null) {
      monthPhotos = providedPhotos;
    } else {
      final db = DatabaseHelper.instance;
      final allMetadata = await db.getAllPhotosMetadata();
      monthPhotos = allMetadata.where((photo) {
        final dateStr = photo['creation_date'] as String?;
        if (dateStr == null) return false;
        final date = DateTime.tryParse(dateStr);
        return date != null && date.year == year && date.month == month;
      }).toList();
    }

    if (monthPhotos.isEmpty) {
      return MemoryStory(
        narrative: "A quiet time for memories.",
        mostVisitedLocation: "N/A",
        totalPhotos: 0,
        topCategory: "None",
        top3Categories: [],
      );
    }

    Map<String, int> counts = {};
    for (var photo in monthPhotos) {
      final cat = await _detectCategory(photo);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    // Sort categories by count
    final sortedCats = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top3 = sortedCats.take(3).map((e) {
      final def = _categoryDefs.firstWhere(
        (d) => d.name == e.key,
        orElse: () => CategoryDef(e.key, '📸', []),
      );
      return "${def.icon} ${e.key}";
    }).toList();

    final topCat = sortedCats.isNotEmpty ? sortedCats.first.key : 'Personal';
    final topCount = sortedCats.isNotEmpty ? sortedCats.first.value : 0;

    final monthName = DateFormat('MMMM yyyy').format(DateTime(year, month));

    // Build Dynamic Narrative
    String narrative = "";
    if (topCat == 'Screenshots') {
      narrative =
          "$monthName was a busy digital month — you saved $topCount screenshots and ${(counts['Documents'] ?? 0)} important documents.";
    } else if (topCat == 'People') {
      narrative =
          "$monthName was full of people and memories — you captured $topCount people moments and attended ${(counts['Events'] ?? 0)} events.";
    } else if (topCat == 'Food') {
      narrative =
          "$monthName was a foodie month — you photographed $topCount meals and visited ${(counts['Places'] ?? 0)} restaurants.";
    } else if (topCat == 'Nature') {
      narrative =
          "$monthName was an outdoor month — you captured $topCount nature scenes and visited ${(counts['Places'] ?? 0)} places.";
    } else if (topCat == 'Travel') {
      narrative =
          "$monthName saw you on the move — you captured $topCount travel moments across roads and vehicles.";
    } else if (topCat == 'Study') {
      narrative =
          "$monthName was focused on learning — you saved $topCount pages of notes, books, and diagrams.";
    } else {
      // Default dynamic story using top categories
      List<String> fragments = [];
      for (var entry in sortedCats.take(3)) {
        if (entry.value > 0) {
          fragments.add("${entry.value} ${entry.key.toLowerCase()} moments");
        }
      }
      narrative =
          "In $monthName you captured ${fragments.join(fragments.length > 2 ? ', ' : ' and ')}.";
    }

    return MemoryStory(
      narrative: narrative,
      mostVisitedLocation:
          "N/A", // We can add location logic back if needed, but narrative is priority
      totalPhotos: monthPhotos.length,
      topCategory: topCat,
      top3Categories: top3,
    );
  }
}
