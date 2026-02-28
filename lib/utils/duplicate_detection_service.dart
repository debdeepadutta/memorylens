import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import '../db/database_helper.dart';

class DuplicateDetectionService {
  static final DuplicateDetectionService _instance =
      DuplicateDetectionService._internal();
  factory DuplicateDetectionService() => _instance;
  DuplicateDetectionService._internal();

  /// Calculates a perceptual hash (pHash) for an image.
  /// This version accepts Uint8List to avoid re-reading files from disk.
  Future<String?> calculatePHash(
    AssetEntity asset, [
    Uint8List? imageData,
  ]) async {
    try {
      Uint8List? bytes = imageData;
      if (bytes == null) {
        final File? file = await asset.file;
        if (file == null) return null;
        bytes = await file.readAsBytes();
      }

      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Resize & 2. Grayscale
      final img.Image resized = img.copyResize(
        image,
        width: 32,
        height: 32,
        interpolation: img.Interpolation.linear,
      );
      final img.Image gray = img.grayscale(resized);

      // Convert to 2D list for DCT
      List<List<double>> matrix = List.generate(
        32,
        (y) => List.generate(32, (x) {
          final pixel = gray.getPixel(x, y);
          return pixel.luminance.toDouble();
        }),
      );

      // 3. DCT
      final List<List<double>> dctMatrix = _applyDCT(matrix);

      // 4. Keep 8x8 top-left
      List<double> reduced = [];
      double sum = 0;
      for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
          // Skip the first (DC) component for average calculation
          if (i == 0 && j == 0) continue;
          reduced.add(dctMatrix[i][j]);
          sum += dctMatrix[i][j];
        }
      }

      // 5. Average & Threshold
      double avg = sum / reduced.length;
      String hash = "";
      for (var val in reduced) {
        hash += (val >= avg ? "1" : "0");
      }

      return hash;
    } catch (e) {
      print("Error calculating pHash: $e");
      return null;
    }
  }

  /// Optimized 2D DCT implementation using separability (O(N^3))
  List<List<double>> _applyDCT(List<List<double>> matrix) {
    int size = matrix.length;
    List<List<double>> rows = List.generate(
      size,
      (i) => List.generate(size, (j) => 0.0),
    );
    List<List<double>> result = List.generate(
      size,
      (i) => List.generate(size, (j) => 0.0),
    );

    // Apply 1D DCT to rows
    for (int i = 0; i < size; i++) {
      for (int u = 0; u < size; u++) {
        double sum = 0;
        for (int j = 0; j < size; j++) {
          sum +=
              matrix[i][j] * math.cos((2 * j + 1) * u * math.pi / (2 * size));
        }
        double alpha = (u == 0) ? 1 / math.sqrt(size) : math.sqrt(2 / size);
        rows[i][u] = alpha * sum;
      }
    }

    // Apply 1D DCT to columns of the row-transformed matrix
    for (int j = 0; j < size; j++) {
      for (int v = 0; v < size; v++) {
        double sum = 0;
        for (int i = 0; i < size; i++) {
          sum += rows[i][j] * math.cos((2 * i + 1) * v * math.pi / (2 * size));
        }
        double alpha = (v == 0) ? 1 / math.sqrt(size) : math.sqrt(2 / size);
        result[v][j] = alpha * sum;
      }
    }

    return result;
  }

  /// Computes Hamming distance between two binary hashes
  int _hammingDistance(String h1, String h2) {
    if (h1.length != h2.length) return h1.length;
    int distance = 0;
    for (int i = 0; i < h1.length; i++) {
      if (h1[i] != h2[i]) distance++;
    }
    return distance;
  }

  /// Finds and groups duplicates from all indexed photos
  Future<void> findDuplicates() async {
    final photos = await DatabaseHelper.instance.getAllPhotosMetadata();

    // Filter photos with hashes
    final List<Map<String, dynamic>> withHashes = photos
        .where((p) => p['p_hash'] != null && (p['p_hash'] as String).isNotEmpty)
        .toList();

    if (withHashes.isEmpty) return;

    List<List<String>> groups = [];
    Set<String> processed = {};

    for (int i = 0; i < withHashes.length; i++) {
      final String id1 = withHashes[i]['asset_id'];
      if (processed.contains(id1)) continue;

      final String hash1 = withHashes[i]['p_hash'];
      List<String> currentGroup = [id1];
      processed.add(id1);

      for (int j = i + 1; j < withHashes.length; j++) {
        final String id2 = withHashes[j]['asset_id'];
        if (processed.contains(id2)) continue;

        final String hash2 = withHashes[j]['p_hash'];
        int distance = _hammingDistance(hash1, hash2);

        // 90% similarity for 64-bit hash means distance <= 6 (floor(0.1 * 64))
        // Actually 63 bits (excluding DC), so floor(0.1 * 63) = 6
        if (distance <= 6) {
          currentGroup.add(id2);
          processed.add(id2);
        }
      }

      if (currentGroup.length > 1) {
        groups.add(currentGroup);
      }
    }

    // Save to database
    List<Map<String, dynamic>> dbGroups = [];
    for (int i = 0; i < groups.length; i++) {
      dbGroups.add({
        'groupId': 'group_${DateTime.now().millisecondsSinceEpoch}_$i',
        'assetIds': groups[i],
      });
    }

    await DatabaseHelper.instance.saveDuplicateGroups(dbGroups);
  }
}
