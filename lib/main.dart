import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'onboarding/onboarding_screen.dart';
import 'search/photo_detail_screen.dart';
import 'search/timeline_tab.dart';
import 'indexing/indexing_service.dart';
import 'db/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'utils/semantic_search_service.dart';
import 'search/settings_tab.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/sign_in_screen.dart';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/user_service.dart';
import 'screens/upgrade_screen.dart';
import 'widgets/trial_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;

  runApp(const MemoryLensApp());
}

class MemoryLensApp extends StatelessWidget {
  const MemoryLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memorylens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B8CAE),
          primary: const Color(0xFF6B8CAE),
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 28,
            letterSpacing: -0.5,
          ),
          bodyLarge: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w400,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF6B8CAE).withAlpha(38),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          UserService.initUser(user);
          return FutureBuilder<bool>(
            future: _checkOnboarding(),
            builder: (context, onboardingSnapshot) {
              if (onboardingSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final hasSeenOnboarding = onboardingSnapshot.data ?? false;
              if (!hasSeenOnboarding) {
                return const OnboardingScreen();
              }
              return const AppShell();
            },
          );
        }

        return const SignInScreen();
      },
    );
  }

  Future<bool> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenOnboarding') ?? false;
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const SearchTab(),
    const TimelineTab(),
    const SettingsTab(),
  ];

  StreamSubscription? _progressSub;
  bool _hasShownCompletion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFirstLaunch();
    IndexingService().startIndexing();

    _progressSub = IndexingService().progressStream.listen((progress) {
      if (progress.state == IndexingState.completed && !_hasShownCompletion) {
        _hasShownCompletion = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Loading complete!'),
                ],
              ),
              backgroundColor: const Color(0xFF6B8CAE),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      IndexingService().setThrottle(false);
    } else if (state == AppLifecycleState.resumed) {
      IndexingService().setThrottle(true);
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenSetup = prefs.getBool('hasSeenIndexingSetup') ?? false;

    if (!hasSeenSetup) {
      prefs.setBool('hasSeenIndexingSetup', true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Setting up your search engine in background'),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SignInScreen();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: UserService.getUserStream(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = (snapshot.hasData && snapshot.data!.exists)
            ? snapshot.data!.data()
            : null;
        final isPro = userData?['isPro'] ?? false;
        final trialStartDate = userData?['trialStartDate'] as String?;
        final trialDaysRemaining = UserService.getTrialDaysRemaining(
          trialStartDate,
        );

        // If trial expired and NOT Pro, show UpgradeScreen and block access
        if (trialDaysRemaining <= 0 && !isPro) {
          return const UpgradeScreen();
        }

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (!isPro && trialDaysRemaining > 0)
                  TrialBanner(daysRemaining: trialDaysRemaining),
                Expanded(child: _tabs[_currentIndex]),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search, color: Color(0xFF6B8CAE)),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(
                  Icons.photo_library,
                  color: Color(0xFF6B8CAE),
                ),
                label: 'Timeline',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: Color(0xFF6B8CAE)),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  static const String _recentSearchesKey = 'recent_searches';
  List<String> _recentSearches = [];
  List<String> _documentTags = [];

  List<AssetEntity> _photos = [];
  Map<String, String> _matchHighlights = {};
  Map<String, int> _matchPriorities = {};
  Set<String> _indexedIds = {};
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();
  final IndexingService _indexingService = IndexingService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _currentQuery = '';
  StreamSubscription? _progressSubscription;
  AssetPathEntity? _recentAlbum;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadRecentSearches();
    _loadDocumentTags();
    _searchController.addListener(_onSearchChanged);
    PhotoManager.addChangeCallback(_onGalleryChanged);
    _progressSubscription = _indexingService.progressStream.listen((progress) {
      if (mounted) {
        _refreshIndexedStatus();
        if (progress.indexedCount > _photos.length &&
            !_isFetchingMore &&
            _hasMore &&
            _currentQuery.isEmpty) {
          _fetchMorePhotos();
        }
      }
    });
    _scrollController.addListener(_onScroll);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_currentQuery != _searchController.text) {
        _performSearch(_searchController.text, saveToHistory: false);
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _recentSearches = prefs.getStringList(_recentSearchesKey) ?? [];
      });
    }
  }

  Future<void> _loadDocumentTags() async {
    final tags = await DatabaseHelper.instance.getDistinctContexts();
    if (mounted) {
      setState(() {
        _documentTags = tags;
      });
    }
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList(_recentSearchesKey) ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 20) searches = searches.sublist(0, 20);
    await prefs.setStringList(_recentSearchesKey, searches);
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  Future<void> _deleteRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList(_recentSearchesKey) ?? [];
    searches.remove(query);
    await prefs.setStringList(_recentSearchesKey, searches);
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  Future<void> _loadInitialData() async {
    await _loadIndexedIds();
    await _loadPhotos();
  }

  Future<void> _loadIndexedIds() async {
    final ids = await DatabaseHelper.instance.getIndexedAssetIds();
    if (mounted) {
      setState(() {
        _indexedIds = ids;
      });
    }
  }

  Future<void> _refreshIndexedStatus() async {
    final ids = await DatabaseHelper.instance.getIndexedAssetIds();
    if (mounted && ids.length != _indexedIds.length) {
      setState(() {
        _indexedIds = ids;
        if (_currentQuery.isEmpty) _sortPhotos();
      });
      _loadDocumentTags();
    }
  }

  void _sortPhotos() {
    _photos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
  }

  void _onGalleryChanged(MethodCall call) {
    if (mounted && _currentQuery.isEmpty) {
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_onGalleryChanged);
    _progressSubscription?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_currentQuery.isNotEmpty) return;

    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMore) {
      _fetchMorePhotos();
    }
  }

  Future<void> _loadPhotos() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    if (!state.isAuth && !state.hasAccess) {
      setState(() => _isLoading = false);
      return;
    }

    final FilterOptionGroup filterOption = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: filterOption,
    );

    if (albums.isNotEmpty) {
      _recentAlbum = albums.first;
      final List<AssetEntity> photos = await _recentAlbum!.getAssetListPaged(
        page: 0,
        size: _pageSize,
      );

      setState(() {
        _photos = photos;
        _sortPhotos();
        _isLoading = false;
        _currentPage = 0;
        _hasMore = photos.length == _pageSize;
        _matchHighlights = {};
      });
    } else {
      setState(() {
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _fetchMorePhotos() async {
    if (_isFetchingMore || !_hasMore || _recentAlbum == null) return;
    setState(() => _isFetchingMore = true);

    final int nextPage = _currentPage + 1;
    final List<AssetEntity> newPhotos = await _recentAlbum!.getAssetListPaged(
      page: nextPage,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _currentPage = nextPage;
        _photos.addAll(newPhotos);
        _sortPhotos();
        _hasMore = newPhotos.length == _pageSize;
        _isFetchingMore = false;
      });
    }
  }

  Future<void> _performSearch(String query, {bool saveToHistory = true}) async {
    if (mounted) {
      setState(() {
        _currentQuery = query;
        _isLoading = true;
      });
    }

    if (query.trim().isEmpty) {
      _currentPage = 0;
      await _loadPhotos();
      return;
    }

    if (saveToHistory) {
      await _saveRecentSearch(query.trim());
    }

    final metadata = await DatabaseHelper.instance.getAllPhotosMetadata();
    final results = SemanticSearchService().search(
      query: query,
      photos: metadata,
    );

    if (results.isEmpty) {
      if (mounted) {
        setState(() {
          _photos = [];
          _isLoading = false;
          _hasMore = false;
          _matchHighlights = {};
        });
      }
      return;
    }

    List<AssetEntity> foundAssets = [];
    Map<String, String> highlights = {};
    Map<String, int> priorities = {};

    for (var res in results) {
      final asset = await AssetEntity.fromId(res.assetId);
      if (asset != null) {
        foundAssets.add(asset);
        highlights[res.assetId] = res.highlights;
        priorities[res.assetId] = res.priority;
      }
    }

    if (mounted) {
      setState(() {
        _photos = foundAssets;
        _matchHighlights = highlights;
        _matchPriorities = priorities;
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentQuery.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentQuery.isNotEmpty) {
          _searchController.clear();
          _performSearch('', saveToHistory: false);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: TextField(
              controller: _searchController,
              onSubmitted: (val) => _performSearch(val, saveToHistory: true),
              decoration: InputDecoration(
                hintText: 'Search text, objects, dates...',
                hintStyle: const TextStyle(
                  fontWeight: FontWeight.w300,
                  color: Colors.black54,
                  fontSize: 16,
                ),
                prefixIcon: _currentQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.black54,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('', saveToHistory: false);
                        },
                      )
                    : const Icon(Icons.search, color: Colors.black54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.black54),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('', saveToHistory: false);
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          if (_currentQuery.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 24, 8),
              child: Text(
                _photos.isEmpty
                    ? ""
                    : "${_photos.length} photos found for $_currentQuery",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B8CAE),
                ),
              ),
            ),

          // Suggestions Row (Recent Searches + Document Tags)
          if (_searchController.text.isEmpty &&
              (_recentSearches.isNotEmpty || _documentTags.isNotEmpty))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  ..._recentSearches.map(
                    (query) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InputChip(
                        label: Text(query),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w400,
                          color: Colors.black87,
                        ),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        onPressed: () {
                          _searchController.text = query;
                          _performSearch(query, saveToHistory: true);
                        },
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _deleteRecentSearch(query),
                      ),
                    ),
                  ),

                  if (_recentSearches.isNotEmpty && _documentTags.isNotEmpty)
                    Container(
                      width: 1,
                      height: 24,
                      color: Colors.grey.shade300,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),

                  ..._documentTags.map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        label: Text(tag),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6B8CAE),
                        ),
                        backgroundColor: const Color(0xFF6B8CAE).withAlpha(15),
                        side: const BorderSide(color: Colors.transparent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        onPressed: () {
                          _searchController.text = tag;
                          _performSearch(tag, saveToHistory: true);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6B8CAE)),
                  )
                : _photos.isEmpty
                ? const Center(
                    child: Text(
                      'No matches found.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    children: [
                      if (_photos.isEmpty)
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 100),
                              Icon(
                                Icons.search_off_rounded,
                                size: 80,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No photos found for "$_currentQuery"',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _buildSearchGrid(1), // Priority 1 (Exact)

                        if (_hasPriority(2)) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 32, 24, 12),
                            child: Text(
                              'Similar results',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          _buildSearchGrid(2), // Priority 2 (Related)
                        ],

                        if (_hasPriority(3) && !_hasPriority(2)) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(24, 32, 24, 12),
                            child: Text(
                              'Partial matches',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          _buildSearchGrid(3), // Priority 3 (Partial)
                        ],

                        if (_hasMore && _currentQuery.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF6B8CAE),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  bool _hasPriority(int priority) {
    return _matchPriorities.values.any((p) => p == priority);
  }

  Widget _buildSearchGrid(int priority) {
    // Filter photos by priority if searching, otherwise show all if priority 1 and no search
    final filteredPhotos = _currentQuery.isEmpty
        ? (priority == 1 ? _photos : [])
        : _photos.where((p) => _matchPriorities[p.id] == priority).toList();

    if (filteredPhotos.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: filteredPhotos.length,
      itemBuilder: (context, index) {
        final asset = filteredPhotos[index];
        return PhotoGridItem(
          asset: asset,
          isIndexed: _indexedIds.contains(asset.id),
          allPhotos:
              _photos, // Maintain original list context for detail view swipe
          index: _photos.indexOf(asset),
          highlight: _matchHighlights[asset.id],
        );
      },
    );
  }
}

class PhotoGridItem extends StatefulWidget {
  final AssetEntity asset;
  final bool isIndexed;
  final List<AssetEntity> allPhotos;
  final int index;
  final String? highlight;

  const PhotoGridItem({
    super.key,
    required this.asset,
    required this.allPhotos,
    required this.index,
    this.isIndexed = true,
    this.highlight,
  });

  @override
  State<PhotoGridItem> createState() => _PhotoGridItemState();
}

class _PhotoGridItemState extends State<PhotoGridItem> {
  Uint8List? _tinyData;
  Uint8List? _mediumData;
  bool _isLoadingTiny = true;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _loadProgressiveThumbnails();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _loadProgressiveThumbnails() async {
    final tiny = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(100, 100),
    );
    if (_cancelled || !mounted) return;
    setState(() {
      _tinyData = tiny;
      _isLoadingTiny = false;
    });

    final medium = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(300, 300),
    );
    if (_cancelled || !mounted) return;
    setState(() {
      _mediumData = medium;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!widget.isIndexed) IndexingService().prioritize(widget.asset.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PhotoDetailScreen(
              initialIndex: widget.index,
              assets: widget.allPhotos,
            ),
          ),
        );
      },
      child: Container(
        color: Colors.grey.shade200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isLoadingTiny)
              Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white),
              )
            else if (_tinyData != null)
              Image.memory(
                _tinyData!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
              ),
            if (_mediumData != null)
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: Image.memory(
                  _mediumData!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
              ),

            if (!widget.isIndexed)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withAlpha(80),
                  child: const Center(
                    child: Icon(
                      Icons.hourglass_empty_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),

            if (widget.highlight != null)
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.highlight!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// SettingsTab has been moved to search/settings_tab.dart
