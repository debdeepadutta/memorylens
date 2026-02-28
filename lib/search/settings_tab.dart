import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../indexing/indexing_service.dart';
import 'storage_cleanup_screen.dart';
import '../auth/auth_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  int _dbSize = 0;
  int _duplicateCount = 0;
  int _indexedCount = 0;
  int _totalDeviceAssets = 0;
  String? _lastIndexed;
  PermissionStatus _photoPermission = PermissionStatus.denied;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    final dbSize = await DatabaseHelper.instance.getDatabaseSize();
    final lastIndexedIso = await IndexingService().getLastIndexedTime();
    final photoPermissionStatus = await Permission.photos.status;
    final indexedCount = await DatabaseHelper.instance.getTotalPhotosCount();

    // Get total assets from device
    int totalAssets = 0;
    try {
      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (paths.isNotEmpty) {
        totalAssets = await paths.first.assetCountAsync;
      }
    } catch (e) {
      print("Error fetching total assets: $e");
    }

    final duplicateGroups = await DatabaseHelper.instance.getDuplicateGroups();
    final duplicateCount = duplicateGroups.length;

    if (mounted) {
      setState(() {
        _dbSize = dbSize;
        _duplicateCount = duplicateCount;
        _indexedCount = indexedCount;
        _totalDeviceAssets = totalAssets;
        _lastIndexed = lastIndexedIso;
        _photoPermission = photoPermissionStatus;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }

  String _formatLastIndexed(String? iso) {
    if (iso == null) return "Never";
    final date = DateTime.parse(iso);
    return DateFormat('MMM d, h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _buildSectionHeader('Storage & Maintenance'),
          _buildSettingTile(
            icon: Icons.cleaning_services_rounded,
            title: 'Storage Cleanup',
            subtitle: 'Find and remove duplicate photos',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StorageCleanupScreen(),
                ),
              ).then((_) => _refreshStats());
            },
          ),

          const SizedBox(height: 12),
          StreamBuilder<IndexingProgress>(
            stream: IndexingService().progressStream,
            builder: (context, snapshot) {
              final progress = snapshot.data;

              // Use live stream data if available, otherwise fallback to database snapshot
              int currentIndexed = progress?.indexedCount ?? _indexedCount;
              int totalToIndex = (progress?.totalCount ?? 0) > 0
                  ? progress!.totalCount
                  : _totalDeviceAssets;

              String status = 'Idle';
              if (progress != null) {
                if (progress.state == IndexingState.indexing) {
                  status = 'Indexing...';
                } else if (progress.state == IndexingState.completed) {
                  status = 'Complete';
                }
              } else if (_indexedCount > 0 &&
                  _indexedCount >= _totalDeviceAssets &&
                  _totalDeviceAssets > 0) {
                status = 'Complete';
              }

              return _buildExpandableSection(
                title: 'Indexing',
                icon: Icons.search_rounded,
                children: [
                  _buildInfoTile(
                    icon: Icons.auto_graph_rounded,
                    title: 'Search Engine Status',
                    subtitle: status,
                    trailingText: '$currentIndexed / $totalToIndex',
                  ),
                  _buildInfoTile(
                    icon: Icons.history_rounded,
                    title: 'Last Indexed',
                    trailingText: _formatLastIndexed(_lastIndexed),
                  ),
                  _buildActionTile(
                    icon: Icons.search_rounded,
                    title: 'Scan for New Photos',
                    onTap: () async {
                      IndexingService().startIndexing();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Scanning for new photos...'),
                        ),
                      );
                    },
                  ),
                  _buildActionTile(
                    icon: Icons.refresh_rounded,
                    title: 'Rebuild Index',
                    subtitle: 'Delete and re-scan everything',
                    onTap: () => _confirmAction(
                      title: 'Rebuild Index?',
                      message:
                          'This will delete the current index and start over. It may take some time.',
                      actionLabel: 'Rebuild',
                      onConfirm: () async {
                        await IndexingService().rebuildIndex();
                        _refreshStats();
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),
          _buildExpandableSection(
            title: 'Storage',
            icon: Icons.storage_rounded,
            children: [
              _buildInfoTile(
                icon: Icons.storage_rounded,
                title: 'Index Size',
                trailingText: _formatSize(_dbSize),
              ),
              _buildInfoTile(
                icon: Icons.cleaning_services_rounded,
                title: 'Potential Duplicates',
                trailingText: '$_duplicateCount found',
              ),
              _buildActionTile(
                icon: Icons.auto_fix_high,
                title: 'Storage Cleanup',
                subtitle: 'Review and remove duplicates',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StorageCleanupScreen(),
                    ),
                  ).then((_) => _refreshStats());
                },
              ),
              _buildActionTile(
                icon: Icons.delete_forever_rounded,
                title: 'Clear Index',
                subtitle: 'Delete all searchable data',
                textColor: Colors.redAccent,
                onTap: () => _confirmAction(
                  title: 'Clear Index?',
                  message:
                      'This will delete all indexed text and categories. You will need to re-index to use search.',
                  actionLabel: 'Clear',
                  onConfirm: () async {
                    await DatabaseHelper.instance.clearAllData();
                    _refreshStats();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildExpandableSection(
            title: 'Privacy',
            icon: Icons.privacy_tip_outlined,
            children: [
              _buildStatusIndicator('Offline Mode Active', true),
              _buildStatusIndicator('No Network Calls Made', true),
              _buildStatusIndicator('No Account Required', true),
              _buildSettingTile(
                icon: Icons.camera_enhance_rounded,
                title: 'Photo Access',
                subtitle: _photoPermission.isGranted
                    ? 'Granted'
                    : 'Limited/Denied',
                trailing: TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Manage'),
                ),
                onTap: () {},
              ),
              _buildActionTile(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: 'Sign out of your account',
                textColor: Colors.redAccent,
                onTap: () => _confirmAction(
                  title: 'Sign Out?',
                  message: 'Are you sure you want to sign out?',
                  actionLabel: 'Sign Out',
                  isDestructive: true,
                  onConfirm: () async {
                    await AuthService.signOut();
                    if (mounted) {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/', (route) => false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Signed out successfully.'),
                        ),
                      );
                    }
                  },
                ),
              ),
              _buildActionTile(
                icon: Icons.warning_amber_rounded,
                title: 'Clear All Data',
                subtitle: 'Reset everything to factory settings',
                textColor: Colors.red,
                onTap: () => _confirmAction(
                  title: 'Clear All Data?',
                  message:
                      'This will delete the index, cache, and all app settings. This cannot be undone.',
                  actionLabel: 'Reset Everything',
                  onConfirm: () async {
                    await DatabaseHelper.instance.clearAllData();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (mounted) {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/', (route) => false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('App reset successfully.'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildExpandableSection(
            title: 'About',
            icon: Icons.info_outline_rounded,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B8CAE).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_rounded,
                        size: 48,
                        color: Color(0xFF6B8CAE),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MemoryLens',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Version 1.0.0',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Built with Flutter',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Divider(height: 32),
                    const Text(
                      'How It Works',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'MemoryLens uses on-device AI to read text in your photos and understand what is in them. Everything runs on your phone. Nothing is sent to any server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'All processing happens on your device. No data is ever uploaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF6B8CAE).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF6B8CAE), size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing:
          trailing ??
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required String trailingText,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.grey.shade700, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          : null,
      trailing: Text(
        trailingText,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (textColor ?? const Color(0xFF6B8CAE)).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: textColor ?? const Color(0xFF6B8CAE),
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12))
          : null,
      onTap: onTap,
    );
  }

  Widget _buildExpandableSection({
    required String title,
    String? subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            : null,
        leading: Icon(icon, color: const Color(0xFF6B8CAE)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.topLeft,
        children: children,
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: Colors.green.withAlpha(100),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onConfirm,
    bool isDestructive = true,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? Colors.redAccent
                  : const Color(0xFF6B8CAE),
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onConfirm();
    }
  }
}
