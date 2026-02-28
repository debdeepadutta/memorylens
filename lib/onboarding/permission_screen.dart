import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../indexing/indexing_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isDenied = false;

  Future<void> _requestPermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();

    if (state.isAuth || state.hasAccess) {
      await _completeOnboarding();
    } else {
      setState(() {
        _isDenied = true;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const IndexingScreen()),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Auto-request permission when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              if (_isDenied) ...[
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 32),
                Text(
                  'Photo access is required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  'MemoryLens needs access to your photos to search them locally. You can update this in your device settings.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                ),
              ] else ...[
                const CircularProgressIndicator(color: Color(0xFF6B8CAE)),
                const SizedBox(height: 32),
                Text(
                  'Requesting Permission...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ],
              const Spacer(),
              if (_isDenied)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () async {
                      await PhotoManager.openSetting();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6B8CAE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Open Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 56), // spacer for equal layout
              const SizedBox(height: 16),
              if (_isDenied)
                TextButton(
                  onPressed: _requestPermission,
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      color: Color(0xFF6B8CAE),
                      fontWeight: FontWeight.w500,
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
