import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../utils/memory_story_service.dart';
import 'photo_detail_screen.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class MemoryBookScreen extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final List<AssetEntity> allAssets;
  final List<DateTime> availableMonths;

  const MemoryBookScreen({
    super.key,
    required this.initialYear,
    required this.initialMonth,
    required this.allAssets,
    required this.availableMonths,
  });

  @override
  State<MemoryBookScreen> createState() => _MemoryBookScreenState();
}

class _MemoryBookScreenState extends State<MemoryBookScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.availableMonths.indexWhere(
      (m) => m.year == widget.initialYear && m.month == widget.initialMonth,
    );
    if (_currentIndex == -1) _currentIndex = 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          DateFormat('MMMM yyyy').format(widget.availableMonths[_currentIndex]),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.availableMonths.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, pageIndex) {
          final monthDate = widget.availableMonths[pageIndex];
          final monthAssets = widget.allAssets
              .where(
                (a) =>
                    a.createDateTime.year == monthDate.year &&
                    a.createDateTime.month == monthDate.month,
              )
              .toList();

          return MasonryMonthView(
            year: monthDate.year,
            month: monthDate.month,
            assets: monthAssets,
            allAssets: widget.allAssets,
          );
        },
      ),
    );
  }
}

class MasonryMonthView extends StatefulWidget {
  final int year;
  final int month;
  final List<AssetEntity> assets;
  final List<AssetEntity> allAssets;

  const MasonryMonthView({
    super.key,
    required this.year,
    required this.month,
    required this.assets,
    required this.allAssets,
  });

  @override
  State<MasonryMonthView> createState() => _MasonryMonthViewState();
}

class _MasonryMonthViewState extends State<MasonryMonthView>
    with AutomaticKeepAliveClientMixin {
  late Future<MemoryStory> _storyFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _storyFuture = MemoryStoryService.generateStory(widget.year, widget.month);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: FutureBuilder<MemoryStory>(
            future: _storyFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return _buildModernStoryHeader(snapshot.data!);
              }
              return const SizedBox(height: 100);
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            itemBuilder: (context, index) {
              final asset = widget.assets[index];
              return _buildMasonryPhoto(asset, index);
            },
            childCount: widget.assets.length,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildModernStoryHeader(MemoryStory story) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            story.narrative,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSimpleStat(
                Icons.photo_library,
                "${story.totalPhotos} items",
              ),
              _buildSimpleStat(Icons.stars, story.topCategory),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF6B8CAE)),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildMasonryPhoto(AssetEntity asset, int index) {
    // Determine dynamic height based on orientation or ID
    final bool isPortrait = asset.width < asset.height;
    final double aspectRatio = isPortrait ? 0.7 : 1.2;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhotoDetailScreen(
              initialIndex: widget.allAssets.indexOf(asset),
              assets: widget.allAssets,
            ),
          ),
        );
      },
      child: Hero(
        tag: 'photo_${asset.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: FutureBuilder<Uint8List?>(
                  future: asset.thumbnailDataWithSize(
                    const ThumbnailSize(300, 300),
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
                    }
                    return Container(color: Colors.grey.shade100);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  DateFormat('d MMM').format(asset.createDateTime),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoryCard extends StatelessWidget {
  final MemoryStory story;
  const StoryCard({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    // Keep it for backward compatibility if needed, but not used in MasonryMonthView
    return const SizedBox.shrink();
  }
}
