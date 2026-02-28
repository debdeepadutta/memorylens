import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../db/database_helper.dart';
import 'dart:typed_data';

class StorageCleanupScreen extends StatefulWidget {
  const StorageCleanupScreen({super.key});

  @override
  State<StorageCleanupScreen> createState() => _StorageCleanupScreenState();
}

class _StorageCleanupScreenState extends State<StorageCleanupScreen> {
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  int _freedBytes = 0;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final groups = await DatabaseHelper.instance.getDuplicateGroups();
    if (mounted) {
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleKeepBestAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep Best Quality for All?'),
        content: Text(
          'This will automatically keep the highest resolution photo in all ${_groups.length} groups and delete the duplicates. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Deletion'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      int bytesSaved = 0;

      for (var group in _groups) {
        final assetIds = group['assetIds'] as List<String>;
        List<AssetEntity> assets = [];
        for (var id in assetIds) {
          final a = await AssetEntity.fromId(id);
          if (a != null) assets.add(a);
        }

        if (assets.length > 1) {
          assets.sort(
            (a, b) => (b.width * b.height).compareTo(a.width * a.height),
          );
          final toDelete = assets.skip(1).toList();

          for (var a in toDelete) {
            final file = await a.file;
            if (file != null) bytesSaved += await file.length();
          }

          final deleteIds = toDelete.map((a) => a.id).toList();
          await PhotoManager.editor.deleteWithIds(deleteIds);

          for (var id in deleteIds) {
            await DatabaseHelper.instance.deleteAssetMetadata(id);
          }
        }
      }

      setState(() {
        _freedBytes = bytesSaved;
        _isLoading = false;
        _showSuccess = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSuccess) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Storage Cleanup',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
          ? _buildEmptyView()
          : Column(
              children: [
                _buildSummaryHeader(),
                _buildBulkActions(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      return DuplicateGroupCard(
                        group: _groups[index],
                        onResolved: () {
                          setState(() {
                            _groups.removeAt(index);
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_groups.length} duplicate groups found',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review photos and keep only the best versions.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _handleKeepBestAll,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Keep Best for All'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.green.shade600),
                foregroundColor: Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green.shade200,
          ),
          const SizedBox(height: 16),
          const Text(
            'No duplicates found!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Your library is clean and organized.'),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    final mb = (_freedBytes / (1024 * 1024)).toStringAsFixed(1);
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎉 Well Done!',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'You freed $mb MB of space',
                style: const TextStyle(fontSize: 20, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  backgroundColor: const Color(0xFF6B8CAE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text('Return to App'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DuplicateGroupCard extends StatefulWidget {
  final Map<String, dynamic> group;
  final VoidCallback onResolved;

  const DuplicateGroupCard({
    super.key,
    required this.group,
    required this.onResolved,
  });

  @override
  State<DuplicateGroupCard> createState() => _DuplicateGroupCardState();
}

class _DuplicateGroupCardState extends State<DuplicateGroupCard> {
  List<AssetEntity> _assets = [];
  Map<String, int> _fileSizes = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final ids = widget.group['assetIds'] as List<String>;
    List<AssetEntity> assets = [];
    Map<String, int> sizes = {};

    for (var id in ids) {
      final a = await AssetEntity.fromId(id);
      if (a != null) {
        assets.add(a);
        final file = await a.file;
        if (file != null) {
          sizes[id] = await file.length();
        }
      }
    }

    if (mounted) {
      setState(() {
        _assets = assets;
        _fileSizes = sizes;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleKeepBest() async {
    if (_assets.length < 2) return;

    _assets.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final toDelete = _assets.skip(1).map((a) => a.id).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Delete ${toDelete.length} duplicates? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PhotoManager.editor.deleteWithIds(toDelete);
      for (var id in toDelete) {
        await DatabaseHelper.instance.deleteAssetMetadata(id);
      }
      widget.onResolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );

    // Find the one with highest resolution
    _assets.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final bestId = _assets.isNotEmpty ? _assets.first.id : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _assets.length,
                itemBuilder: (context, index) {
                  final asset = _assets[index];
                  final isBest = asset.id == bestId;
                  final sizeMb = ((_fileSizes[asset.id] ?? 0) / (1024 * 1024))
                      .toStringAsFixed(1);

                  return Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade100,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        _buildThumbnail(asset),
                        if (isBest)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BEST',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            color: Colors.black54,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${asset.width}x${asset.height}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  '$sizeMb MB',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onResolved,
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _handleKeepBest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade50,
                    foregroundColor: Colors.green.shade700,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Keep Best'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(AssetEntity asset) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
          );
        }
        return const Center(child: Icon(Icons.photo, color: Colors.grey));
      },
    );
  }
}
