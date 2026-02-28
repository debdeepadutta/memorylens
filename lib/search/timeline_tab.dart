import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../db/database_helper.dart';
import '../utils/memory_story_service.dart';
import 'memory_book_screen.dart';
import 'package:intl/intl.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:math' as math;
import 'dart:typed_data';

class TimelineTab extends StatefulWidget {
  const TimelineTab({super.key});

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  List<Map<String, dynamic>> _allMetadata = [];
  List<MonthGroup> _filteredMonths = [];
  GlobalStats? _stats;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, Color> _colorCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final db = DatabaseHelper.instance;
    _allMetadata = await db.getAllPhotosMetadata();
    _stats = await MemoryStoryService.getGlobalStats();

    _filterMonths('');
  }

  void _onSearchChanged() {
    _filterMonths(_searchController.text);
  }

  void _filterMonths(String query) {
    final lowerQuery = query.toLowerCase();

    Map<String, List<Map<String, dynamic>>> groups = {};
    for (var meta in _allMetadata) {
      final dateStr = meta['creation_date'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final mKey = DateFormat('yyyy-MM').format(date);
      final mDisplay = DateFormat('MMMM yyyy').format(date).toLowerCase();

      bool matches =
          query.isEmpty ||
          mDisplay.contains(lowerQuery) ||
          (meta['extracted_text'] ?? '').toLowerCase().contains(lowerQuery) ||
          (meta['image_labels'] ?? '').toLowerCase().contains(lowerQuery) ||
          (meta['context_category'] ?? '').toLowerCase().contains(lowerQuery);

      if (matches) {
        groups.putIfAbsent(mKey, () => []).add(meta);
      }
    }

    List<MonthGroup> sortedGroups = groups.entries.map((e) {
      final date = DateFormat('yyyy-MM').parse(e.key);
      return MonthGroup(date: date, photos: e.value);
    }).toList();

    sortedGroups.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _filteredMonths = sortedGroups;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAFAFA),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6B8CAE)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 80)),

              if (_stats != null && _searchController.text.isEmpty)
                SliverToBoxAdapter(child: _buildSummaryStrip()),

              if (_filteredMonths.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No memories match your search.',
                      style: TextStyle(color: Colors.black38, fontSize: 16),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final group = _filteredMonths[index];
                      return _buildMonthCard(group, index);
                    }, childCount: _filteredMonths.length),
                  ),
                ),
            ],
          ),

          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: _buildFloatingSearch(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${_stats!.totalPhotos} memories across ${_stats!.totalMonths} ${_stats!.totalMonths == 1 ? 'month' : 'months'}",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatChip(
                  Icons.calendar_today,
                  _stats!.mostActiveMonth,
                  "Most Active",
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.stars,
                  _stats!.topCategory,
                  "Top Category",
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.photo_library,
                  "${_stats!.totalPhotos} photos",
                  "Total",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B8CAE)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSearch() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: "Search your journal...",
          hintStyle: const TextStyle(color: Colors.black26, fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: Colors.black26),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  Future<Color> _getCardColor(
    List<Map<String, dynamic>> photos,
    String mKey,
  ) async {
    if (_colorCache.containsKey(mKey)) return _colorCache[mKey]!;
    if (photos.isEmpty) return const Color(0xFF6B8CAE);
    final asset = await AssetEntity.fromId(photos.first['asset_id']);
    if (asset == null) return const Color(0xFF6B8CAE);
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(100, 100),
    );
    if (data == null) return const Color(0xFF6B8CAE);
    final palette = await PaletteGenerator.fromImageProvider(MemoryImage(data));
    final color =
        palette.dominantColor?.color.withAlpha(255) ?? const Color(0xFF6B8CAE);
    _colorCache[mKey] = color;
    return color;
  }

  Widget _buildMonthCard(MonthGroup group, int index) {
    final mKey = DateFormat('yyyy-MM').format(group.date);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _getCardColor(group.photos, mKey),
        MemoryStoryService.generateStory(
          group.date.year,
          group.date.month,
          providedPhotos: group.photos,
        ),
      ]),
      builder: (context, snapshot) {
        final baseColor = snapshot.hasData
            ? (snapshot.data![0] as Color)
            : const Color(0xFF6B8CAE);
        final story = snapshot.hasData
            ? (snapshot.data![1] as MemoryStory)
            : null;

        return GestureDetector(
          onTap: () async {
            // Show loading overlay
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );

            try {
              List<AssetEntity> assets = [];
              for (var meta in group.photos) {
                final asset = await AssetEntity.fromId(meta['asset_id']);
                if (asset != null) assets.add(asset);
              }

              if (mounted) {
                Navigator.pop(context); // Remove loading overlay
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MemoryBookScreen(
                      initialYear: group.date.year,
                      initialMonth: group.date.month,
                      allAssets: assets,
                      availableMonths: _filteredMonths
                          .map((m) => m.date)
                          .toList(),
                    ),
                  ),
                );
              }
            } catch (e) {
              if (mounted) Navigator.pop(context);
              debugPrint("Error loading assets: $e");
            }
          },
          child: Container(
            height: 280,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [baseColor, baseColor.withAlpha(200)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 24,
                  left: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(group.date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        "${group.photos.length} photos",
                        style: TextStyle(
                          color: Colors.white.withAlpha(180),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  top: 60,
                  right: 20,
                  left: 80,
                  bottom: 80,
                  child: _buildCollage(group.photos, group.date),
                ),

                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (story != null) ...[
                        Text(
                          story.narrative,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: _buildTop3Categories(story.top3Categories),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.auto_stories,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTop3Categories(List<String> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories
            .map(
              (cat) => Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  cat,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCollage(List<Map<String, dynamic>> photos, DateTime date) {
    final displayPhotos = photos.take(5).toList();

    return Stack(
      children: List.generate(displayPhotos.length, (i) {
        final random = math.Random(date.month + date.year + i);
        final rotation = (random.nextDouble() * 0.4) - 0.2;
        final top = 20.0 + (random.nextDouble() * 60);
        final left = (i * 45.0) + (random.nextDouble() * 20);

        return Positioned(
          top: top,
          left: left,
          child: Transform.rotate(
            angle: rotation,
            child: _buildPolaroidThumbnail(displayPhotos[i]['asset_id']),
          ),
        );
      }),
    );
  }

  Widget _buildPolaroidThumbnail(String assetId) {
    return Container(
      width: 70,
      height: 90,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<AssetEntity?>(
              future: AssetEntity.fromId(assetId),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return FutureBuilder<Uint8List?>(
                    future: snapshot.data!.thumbnailDataWithSize(
                      const ThumbnailSize(100, 100),
                    ),
                    builder: (context, thumb) {
                      if (thumb.hasData)
                        return Image.memory(
                          thumb.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        );
                      return Container(color: Colors.grey.shade100);
                    },
                  );
                }
                return Container(color: Colors.grey.shade100);
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class MonthGroup {
  final DateTime date;
  final List<Map<String, dynamic>> photos;
  MonthGroup({required this.date, required this.photos});
}
