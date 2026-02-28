import 'package:photo_manager/photo_manager.dart';

class LifeCluster {
  final String title;
  final String category;
  final DateTime startTime;
  final DateTime endTime;
  final List<AssetEntity> assets;
  final String summary;

  LifeCluster({
    required this.title,
    required this.category,
    required this.startTime,
    required this.endTime,
    required this.assets,
    required this.summary,
  });
}
