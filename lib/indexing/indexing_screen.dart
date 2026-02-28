import 'package:flutter/material.dart';
import 'indexing_service.dart';
import '../main.dart'; // For navigating to AppShell

class IndexingScreen extends StatefulWidget {
  const IndexingScreen({super.key});

  @override
  State<IndexingScreen> createState() => _IndexingScreenState();
}

class _IndexingScreenState extends State<IndexingScreen> {
  final IndexingService _indexingService = IndexingService();

  @override
  void initState() {
    super.initState();
    // Start indexing processing automatically when the screen opens
    _indexingService.startIndexing();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${twoDigitMinutes}m remaining";
    } else if (duration.inMinutes > 0) {
      return "${twoDigitMinutes}m ${twoDigitSeconds}s remaining";
    } else {
      return "${twoDigitSeconds}s remaining";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: StreamBuilder<IndexingProgress>(
            stream: _indexingService.progressStream,
            builder: (context, snapshot) {
              final progress = snapshot.data;

              if (progress?.state == IndexingState.error) {
                return _buildErrorState(context);
              }

              if (progress?.state == IndexingState.completed ||
                  (progress != null && progress.isQuickIndexComplete)) {
                return _buildCompletedState(context);
              }

              // Loading or processing state
              return _buildProcessingState(context, progress);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingState(
    BuildContext context,
    IndexingProgress? progress,
  ) {
    final bool hasData = progress != null;
    final int total = hasData ? progress.totalCount : 0;
    final int indexed = hasData ? progress.indexedCount : 0;
    final double percent = total > 0 ? (indexed / total) : 0;

    // Default duration if null
    final Duration timeLeft = hasData
        ? progress.estimatedTimeLeft
        : const Duration(seconds: 0);

    final bool isPaused =
        progress?.state == IndexingState.pausedBattery ||
        (hasData &&
            _indexingService
                .isPaused); // Accessing private for quick check, or relying on stream state

    final bool isBatteryPaused = progress?.state == IndexingState.pausedBattery;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 48),
        Text(
          'Building Your Search Index',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const Spacer(),

        // Circular Progress Indicator Stack
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: hasData ? percent : null,
                strokeWidth: 8,
                backgroundColor: Colors.grey.shade100,
                color: const Color(0xFF6B8CAE),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(percent * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        // Detailed text
        Text(
          hasData
              ? 'Processing $indexed / $total photos'
              : 'Analyzing library...',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),

        Text(
          hasData && !isPaused
              ? _formatDuration(timeLeft)
              : (isBatteryPaused
                    ? 'Paused due to low battery'
                    : (isPaused ? 'Paused' : 'Estimating time...')),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isBatteryPaused ? Colors.redAccent : Colors.black54,
          ),
        ),

        const Spacer(),

        // Pause/Resume Button
        if (hasData)
          OutlinedButton.icon(
            onPressed: () {
              if (isPaused) {
                _indexingService.resume();
              } else {
                _indexingService.pause();
                setState(() {}); // Ensure UI updates immediately
              }
            },
            icon: Icon(
              isPaused ? Icons.play_arrow : Icons.pause,
              color: const Color(0xFF6B8CAE),
            ),
            label: Text(
              isPaused ? 'Resume' : 'Pause',
              style: const TextStyle(color: Color(0xFF6B8CAE)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF6B8CAE)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),

        const SizedBox(height: 24),

        // Bottom Message
        Text(
          'You can leave the app.\nIndexing continues in the background.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.black45, height: 1.5),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCompletedState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        const Icon(
          Icons.check_circle_outline,
          size: 100,
          color: Color(0xFF6B8CAE),
        ),
        const SizedBox(height: 32),
        Text(
          'Quick index complete',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        Text(
          'You can now search your recent photos. The rest of your library is indexing silently in the background.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AppShell()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6B8CAE),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Start Searching',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 100, color: Colors.redAccent),
        const SizedBox(height: 32),
        Text(
          'Something went wrong',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        Text(
          'There was a problem preparing your search index. Please ensure permissions are granted and try again.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}
