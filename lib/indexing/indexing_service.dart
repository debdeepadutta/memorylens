import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../utils/context_classification_service.dart';
import '../utils/duplicate_detection_service.dart';

enum IndexingState { idle, indexing, pausedBattery, completed, error }

class IndexingProgress {
  final int totalCount;
  final int indexedCount;
  final Duration estimatedTimeLeft;
  final IndexingState state;
  final bool isQuickIndexComplete;

  IndexingProgress({
    required this.totalCount,
    required this.indexedCount,
    required this.estimatedTimeLeft,
    required this.state,
    this.isQuickIndexComplete = false,
  });
}

class IndexingService {
  static final IndexingService _instance = IndexingService._internal();
  factory IndexingService() => _instance;
  IndexingService._internal();

  Isolate? _indexingIsolate;
  SendPort? _isolateSendPort;
  final ReceivePort _receivePort = ReceivePort();

  final _progressController = StreamController<IndexingProgress>.broadcast();
  Stream<IndexingProgress> get progressStream => _progressController.stream;

  bool _isPaused = false;
  bool get isPaused => _isPaused;
  IndexingState _currentState = IndexingState.idle;

  void pause() {
    _isPaused = true;
    _isolateSendPort?.send({'cmd': 'pause'});
    _updateState(IndexingState.idle); // Or a specific paused state if needed
  }

  void resume() {
    _isPaused = false;
    _isolateSendPort?.send({'cmd': 'resume'});
    _updateState(IndexingState.indexing);
  }

  void setThrottle(bool isThrottled) {
    _isolateSendPort?.send({'cmd': 'throttle', 'value': isThrottled});
  }

  void prioritize(String assetId) {
    _isolateSendPort?.send({'cmd': 'prioritize', 'value': assetId});
  }

  void _updateState(IndexingState state) {
    _currentState = state;
    // We emit a new progress mostly from the isolate, but we can fast-update state here if needed.
  }

  Future<void> startIndexing() async {
    if (_currentState == IndexingState.indexing) return;
    _currentState = IndexingState.indexing;

    // Request permissions
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      _progressController.addError("Photo permission denied");
      _currentState = IndexingState.error;
      return;
    }

    _receivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('progress')) {
          final p = message['progress'] as Map<String, dynamic>;
          _progressController.add(
            IndexingProgress(
              totalCount: p['totalCount'],
              indexedCount: p['indexedCount'],
              estimatedTimeLeft: Duration(seconds: p['estimatedSecondsLeft']),
              state: IndexingState.values[p['stateIndex']],
              isQuickIndexComplete: p['isQuickIndexComplete'] ?? false,
            ),
          );
          if (IndexingState.values[p['stateIndex']] ==
              IndexingState.completed) {
            _saveLastIndexedTime();
          }
        } else if (message.containsKey('log')) {
          print("Isolate Log: ${message['log']}");
        }
      }
    });

    // We need the RootIsolateToken to use platform channels in the isolate
    RootIsolateToken rootToken = RootIsolateToken.instance!;

    // Get a temporary directory path before spawning isolate
    Directory tempDir = await getTemporaryDirectory();

    final maxPhotos = -1;

    _indexingIsolate = await Isolate.spawn(_isolateEntryPoint, {
      'sendPort': _receivePort.sendPort,
      'rootToken': rootToken,
      'tempPath': tempDir.path,
      'maxPhotos': maxPhotos,
    });
  }

  Future<void> _saveLastIndexedTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'last_indexed_time',
      DateTime.now().toIso8601String(),
    );
  }

  Future<String?> getLastIndexedTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_indexed_time');
  }

  Future<void> rebuildIndex() async {
    _isolateSendPort?.send({'cmd': 'stop'});
    _indexingIsolate?.kill();
    _indexingIsolate = null;
    _currentState = IndexingState.idle;

    await DatabaseHelper.instance.clearAllData();
    await startIndexing();
  }

  void dispose() {
    _indexingIsolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
    _progressController.close();
  }

  // --- ISOLATE ENTRY POINT ---
  static Future<void> _isolateEntryPoint(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final RootIsolateToken rootToken = args['rootToken'];
    final String tempPath = args['tempPath'];

    // Initialize platform channels for this isolate
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

    // Setup communication from main isolate to this background isolate
    final ReceivePort commandPort = ReceivePort();
    sendPort.send(commandPort.sendPort);

    bool isPaused = false;
    bool isThrottled = true; // Predict foreground actively using app
    final List<String> priorityQueue = [];

    commandPort.listen((message) {
      if (message is Map) {
        if (message['cmd'] == 'pause') isPaused = true;
        if (message['cmd'] == 'resume') isPaused = false;
        if (message['cmd'] == 'throttle') isThrottled = message['value'];
        if (message['cmd'] == 'prioritize') {
          final id = message['value'];
          if (!priorityQueue.contains(id)) priorityQueue.add(id);
        }
      }
    });

    try {
      final dbHelper = DatabaseHelper.instance;
      final battery = Battery();

      // 1. Get already indexed IDs to skip them
      final Set<String> indexedIds = await dbHelper.getIndexedAssetIds();
      final int initialIndexedCount = indexedIds.length;

      // 2. Fetch all paths/albums - ensure newest first
      final FilterOptionGroup filterOption = FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );

      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: RequestType.common, // Images and Videos
        onlyAll: true,
        filterOption: filterOption,
      );

      if (paths.isEmpty) {
        _sendProgress(sendPort, 0, 0, 0, IndexingState.completed, true);
        return;
      }

      final AssetPathEntity allPhotos = paths.first;
      final int totalAssetsCount = await allPhotos.assetCountAsync;

      // Calculate how many are pending
      int totalPending = totalAssetsCount - indexedIds.length;
      if (totalPending <= 0) {
        _sendProgress(
          sendPort,
          totalAssetsCount,
          totalAssetsCount,
          0,
          IndexingState.completed,
          true,
        );
        return;
      }

      int processedCount = indexedIds.length;
      final int batchSize = 50;

      final textRecognizerLatin = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final imageLabeler = ImageLabeler(options: ImageLabelerOptions());
      final barcodeScanner = BarcodeScanner();

      // Moving average for time estimation
      List<int> batchTimesMs = [];
      int avgMsPerItem = 1000; // default guess 1 second

      int pageIndex = 0; // manual tracking for the while loop

      // 3. Process until no unindexed photos OR priority hits exist
      while (processedCount < totalAssetsCount || priorityQueue.isNotEmpty) {
        final int maxPhotos = args['maxPhotos'] ?? -1;
        if (maxPhotos != -1 &&
            processedCount >= maxPhotos &&
            priorityQueue.isEmpty) {
          _sendProgress(
            sendPort,
            totalAssetsCount,
            processedCount,
            0,
            IndexingState.completed,
            true,
          );
          break;
        }

        // Wait if paused
        while (isPaused) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // Check battery
        final batteryLevel = await battery.batteryLevel;
        final batteryState = await battery.batteryState;
        if (batteryLevel < 15) {
          _sendProgress(
            sendPort,
            totalAssetsCount,
            processedCount,
            0,
            IndexingState.pausedBattery,
            processedCount >= 500,
          );
          // Wait until battery is >= 15 or charging
          while (true) {
            await Future.delayed(const Duration(minutes: 1));
            final newLevel = await battery.batteryLevel;
            final state = await battery.batteryState;
            if (newLevel >= 15 || state == BatteryState.charging) {
              break;
            }
          }
        }

        // THROTTLER LOGIC
        if (isThrottled && batteryState != BatteryState.charging) {
          // When actively using foreground app, sleep intentionally to save GPU/CPU UI frames.
          // But if plugging into the wall? Bypass throttle automatically for max speed!
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        final stopwatch = Stopwatch()..start();

        List<AssetEntity> batch = [];

        // 3A: Consume Priority Queue First
        if (priorityQueue.isNotEmpty) {
          final batchIds = priorityQueue.take(batchSize).toList();
          priorityQueue.removeRange(0, batchIds.length);
          for (var id in batchIds) {
            final entity = await AssetEntity.fromId(id);
            if (entity != null) batch.add(entity);
          }
        } else {
          // 3B: Fetch normal pages seamlessly
          batch = await allPhotos.getAssetListPaged(
            page: pageIndex,
            size: batchSize,
          );
          pageIndex++;

          if (batch.isEmpty) {
            // Exit index condition
            break;
          }
        }

        List<Map<String, dynamic>> batchResults = [];

        for (var asset in batch) {
          // Wait if paused
          while (isPaused) {
            await Future.delayed(const Duration(milliseconds: 500));
          }

          if (indexedIds.contains(asset.id)) {
            continue;
          }

          String extractedText = "";
          String imageLabelsStr = "";
          String locationName = "";
          String qrContent = "";
          String? ocrBlocksStr;
          String? pHash;

          try {
            try {
              // Geocoding extraction (Fast, native OS cached)
              final LatLng? preciseLocation = await asset.latlngAsync();
              if (preciseLocation != null) {
                final lat = preciseLocation.latitude;
                final lng = preciseLocation.longitude;

                if (lat != 0.0 && lng != 0.0) {
                  List<Placemark> placemarks = await placemarkFromCoordinates(
                    lat,
                    lng,
                  );

                  if (placemarks.isNotEmpty) {
                    Placemark place = placemarks.first;
                    List<String> locParts = [];
                    if (place.locality != null && place.locality!.isNotEmpty) {
                      locParts.add(place.locality!);
                    } else if (place.administrativeArea != null &&
                        place.administrativeArea!.isNotEmpty) {
                      locParts.add(place.administrativeArea!);
                    }
                    if (place.country != null && place.country!.isNotEmpty) {
                      locParts.add(place.country!);
                    }
                    locationName = locParts.join(', ');
                  }
                }
              }
            } catch (e) {
              sendPort.send({'log': 'Geocoding error for ${asset.id}: $e'});
            }

            final file = await asset.file;
            final Uint8List? thumbData = await asset.thumbnailDataWithSize(
              const ThumbnailSize(500, 500),
            );

            List<ImageLabel> labels = [];
            final futures = <Future<void>>[];
            File? tempThumbFile;

            // Only run OCR on photos/images using FULL RESOLUTION
            if (asset.type == AssetType.image && file != null) {
              final ocrInputImage = InputImage.fromFile(file);
              final res = await textRecognizerLatin.processImage(ocrInputImage);
              extractedText = _cleanOcrText(res.text);

              // Extract blocks for visual selection
              final List<Map<String, dynamic>> blocks = [];
              for (var block in res.blocks) {
                blocks.add({
                  'text': block.text,
                  'rect': {
                    'left': block.boundingBox.left,
                    'top': block.boundingBox.top,
                    'right': block.boundingBox.right,
                    'bottom': block.boundingBox.bottom,
                  },
                });
              }
              ocrBlocksStr = jsonEncode(blocks);
            }

            // Always run Image Labeling and Barcode scanning using THUMBNAIL constraints
            if (thumbData != null) {
              tempThumbFile = File('$tempPath/${asset.id}_thumb.jpg');
              await tempThumbFile.writeAsBytes(thumbData);
              final labelInputImage = InputImage.fromFile(tempThumbFile);

              // 1. Image Labeling
              futures.add(
                imageLabeler.processImage(labelInputImage).then((res) {
                  labels = res;
                }),
              );

              // 2. Barcode Scanning
              futures.add(
                barcodeScanner.processImage(labelInputImage).then((barcodes) {
                  if (barcodes.isNotEmpty) {
                    qrContent = barcodes
                        .map((b) => b.displayValue ?? "")
                        .where((s) => s.isNotEmpty)
                        .join(' | ');
                  }
                }),
              );

              // 3. pHash calculation
              futures.add(
                DuplicateDetectionService()
                    .calculatePHash(asset, thumbData)
                    .then((hash) {
                      pHash = hash;
                    }),
              );
            }

            // Execute all simultaneously
            await Future.wait(futures);

            final List<String> detectedTags = labels
                .map((l) => l.label)
                .toList();

            // Intelligent Document Detection Heuristic
            if (extractedText.length > 50 &&
                !detectedTags.any(
                  (t) =>
                      ['Landscape', 'Portrait', 'Food', 'Nature'].contains(t),
                )) {
              if (!detectedTags.contains('Document')) {
                detectedTags.add('Document');
              }
            }

            imageLabelsStr = detectedTags.join(', ');

            // Contextual Classification
            final context = ContextClassificationService.classify(
              extractedText,
              imageLabelsStr,
              location: locationName,
            );

            if (tempThumbFile != null && await tempThumbFile.exists()) {
              await tempThumbFile.delete();
            }

            batchResults.add({
              'assetId': asset.id,
              'extractedText': extractedText,
              'imageLabels': imageLabelsStr,
              'userLabels':
                  imageLabelsStr, // Initial hidden search metadata matches AI labels
              'context': context,
              'locationName': locationName,
              'qrContent': qrContent,
              'ocrBlocks': ocrBlocksStr,
              'creationDate': asset.createDateTime.toIso8601String(),
              'pHash': pHash,
            });
          } catch (e) {
            sendPort.send({'log': 'Error processing asset ${asset.id}: $e'});
          }

          processedCount++;
          indexedIds.add(asset.id);

          // Clear asset memory reference
        }

        // OPTIMIZATION: Batch insert to DB
        if (batchResults.isNotEmpty) {
          await dbHelper.insertOcrResultsBatch(batchResults);
        }

        stopwatch.stop();

        // Update time estimation
        if (batch.isNotEmpty) {
          int itemsProcessed = batchResults.length;
          if (itemsProcessed > 0 || batchTimesMs.isEmpty) {
            int msPerItem =
                stopwatch.elapsedMilliseconds ~/
                (itemsProcessed > 0 ? itemsProcessed : 1);
            batchTimesMs.add(msPerItem);
            if (batchTimesMs.length > 5) {
              batchTimesMs.removeAt(0); // keep last 5 batches
            }
            avgMsPerItem =
                batchTimesMs.reduce((a, b) => a + b) ~/ batchTimesMs.length;
          }
        }

        int remainingItems = totalAssetsCount - processedCount;
        int estimatedSecondsLeft = (remainingItems * avgMsPerItem) ~/ 1000;

        // Quick index is complete if we've processed 50 more items than we started with,
        // OR if we've processed all items in a small library.
        bool quickIndexDone =
            (processedCount - initialIndexedCount >= 50) ||
            (processedCount >= totalAssetsCount);

        _sendProgress(
          sendPort,
          totalAssetsCount,
          processedCount,
          estimatedSecondsLeft,
          IndexingState.indexing,
          quickIndexDone,
        );

        // Periodically run duplicate detection if we've processed a significant amount
        if (processedCount % 100 == 0) {
          DuplicateDetectionService().findDuplicates();
        }
      }

      textRecognizerLatin.close();
      imageLabeler.close();
      barcodeScanner.close();

      // Trigger duplicate detection
      sendPort.send({
        'log': 'Indexing complete. Starting duplicate detection scan...',
      });
      await DuplicateDetectionService().findDuplicates();
      sendPort.send({'log': 'Duplicate detection complete.'});

      _sendProgress(
        sendPort,
        totalAssetsCount,
        totalAssetsCount,
        0,
        IndexingState.completed,
        true,
      );
    } catch (e) {
      sendPort.send({'log': 'Fatal isolate error: $e'});
      _sendProgress(sendPort, 0, 0, 0, IndexingState.error, false);
    }
  }

  static void _sendProgress(
    SendPort sendPort,
    int totalCount,
    int indexedCount,
    int estimatedSecondsLeft,
    IndexingState state,
    bool isQuickIndexComplete, // new parameter
  ) {
    sendPort.send({
      'progress': {
        'totalCount': totalCount,
        'indexedCount': indexedCount,
        'estimatedSecondsLeft': estimatedSecondsLeft,
        'stateIndex': state.index,
        'isQuickIndexComplete': isQuickIndexComplete,
      },
    });
  }

  static String _cleanOcrText(String rawText) {
    if (rawText.isEmpty) return "";
    final lines = rawText.split('\n');
    final cleanedLines = <String>[];
    for (var line in lines) {
      final trimmed = line.trim();
      // Remove lines with less than 3 characters (removes single noise chars)
      if (trimmed.length >= 3) {
        cleanedLines.add(trimmed);
      }
    }
    return cleanedLines.join('\n');
  }
}
