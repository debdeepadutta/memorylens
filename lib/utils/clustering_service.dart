import 'package:photo_manager/photo_manager.dart';
import '../models/life_cluster.dart';
import '../db/database_helper.dart';

class ClusteringService {
  static Future<List<LifeCluster>> cluster(List<AssetEntity> assets) async {
    if (assets.isEmpty) return [];

    // Sort assets by date descending
    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    List<LifeCluster> clusters = [];
    if (assets.isEmpty) return clusters;

    List<AssetEntity> currentGroup = [assets.first];
    Map<String, dynamic>? firstMeta = await DatabaseHelper.instance
        .getPhotoDetails(assets.first.id);
    String currentContext = firstMeta?['context'] ?? 'Personal';

    for (int i = 1; i < assets.length; i++) {
      final asset = assets[i];
      final meta = await DatabaseHelper.instance.getPhotoDetails(asset.id);
      final context = meta?['context'] ?? 'Personal';

      final prevAsset = currentGroup.last;
      final timeDiff = prevAsset.createDateTime
          .difference(asset.createDateTime)
          .abs();

      // Cluster if:
      // 1. Same context AND within 36 hours
      // 2. OR very close time proximity (within 2 hours) regardless of context
      bool shouldCluster =
          (context == currentContext && timeDiff.inHours < 36) ||
          (timeDiff.inHours < 2);

      if (shouldCluster) {
        currentGroup.add(asset);
      } else {
        clusters.add(await _createCluster(currentGroup, currentContext));
        currentGroup = [asset];
        currentContext = context;
      }
    }

    if (currentGroup.isNotEmpty) {
      clusters.add(await _createCluster(currentGroup, currentContext));
    }

    return clusters;
  }

  static Future<LifeCluster> _createCluster(
    List<AssetEntity> group,
    String context,
  ) async {
    final startTime = group.last.createDateTime; // Group is sorted desc
    final endTime = group.first.createDateTime;

    // Aggregate metadata for smart title
    Set<String> locations = {};
    Set<String> keywords = {};

    for (var asset in group) {
      final meta = await DatabaseHelper.instance.getPhotoDetails(asset.id);
      if (meta != null) {
        if (meta['locationName'] != null && meta['locationName'].isNotEmpty) {
          locations.add(meta['locationName'].split(',').first.trim());
        }
        final text = meta['extractedText']?.toLowerCase() ?? '';
        if (text.contains('exam') || text.contains('test'))
          keywords.add('Exam');
        if (text.contains('invoice') || text.contains('bill'))
          keywords.add('Expenses');
        if (text.contains('resume') || text.contains('hiring'))
          keywords.add('Job Applications');
      }
    }

    String title = _generateSmartTitle(context, locations, keywords, startTime);
    String summary =
        "${group.length} items • ${_formatMonth(startTime)} ${startTime.year}";

    return LifeCluster(
      title: title,
      category: context,
      startTime: startTime,
      endTime: endTime,
      assets: group,
      summary: summary,
    );
  }

  static String _generateSmartTitle(
    String context,
    Set<String> locations,
    Set<String> keywords,
    DateTime date,
  ) {
    if (context == 'Travel' && locations.isNotEmpty) {
      return "Trip to ${locations.first}";
    }
    if (context == 'Finance' || keywords.contains('Expenses')) {
      return "Monthly Expenses: ${_formatMonth(date)}";
    }
    if (context == 'Study' || keywords.contains('Exam')) {
      return "Study Session: ${keywords.contains('Exam') ? 'Exam Prep' : 'Learning'}";
    }
    if (keywords.contains('Job Applications')) {
      return "Career: Job Applications";
    }
    if (context == 'Social') {
      return "Social Gathering";
    }
    if (context == 'Shopping') {
      return "Shopping Activity";
    }

    // Default fallback
    return "${_formatMonth(date)} Highlights";
  }

  static String _formatMonth(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[date.month - 1];
  }
}
