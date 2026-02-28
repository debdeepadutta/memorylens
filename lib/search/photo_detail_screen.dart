import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'full_screen_image_view.dart';
import '../db/database_helper.dart';
import '../indexing/indexing_service.dart';
import '../utils/ocr_formatting_service.dart';

class PhotoDetailScreen extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const PhotoDetailScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  late int _currentIndex;
  AssetEntity get _currentAsset => widget.assets[_currentIndex];

  String? _extractedText;
  String? _locationName;
  String? _imageLabels;
  String? _userLabels;
  String? _qrContent;
  DateTime? _createDateTime;
  int? _width;
  int? _height;
  int? _fileSize;
  bool _isLoading = true;
  bool _isRefiring = false;

  String? _detectedOtp;
  List<String> _detectedPhones = [];
  List<String> _detectedUrls = [];
  List<String> _detectedEmails = [];

  bool _showMetadata = false;
  final TextEditingController _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);

    IndexingService().prioritize(_currentAsset.id);

    final details = await DatabaseHelper.instance.getPhotoDetails(
      _currentAsset.id,
    );
    final file = await _currentAsset.file;
    int? fileSize;
    if (file != null) {
      fileSize = await file.length();
    }

    if (mounted) {
      setState(() {
        _extractedText = details?['extractedText'];
        _imageLabels = details?['imageLabels'];
        _userLabels = details?['userLabels'];
        _locationName = details?['locationName'];
        _qrContent = details?['qrContent'];
        _createDateTime = _currentAsset.createDateTime;
        _width = _currentAsset.width;
        _height = _currentAsset.height;
        _fileSize = fileSize;
        _isLoading = false;
        _processExtractedText();
      });
    }
  }

  void _processExtractedText() {
    if (_extractedText == null || _extractedText!.isEmpty) {
      _detectedOtp = null;
      _detectedPhones = [];
      _detectedUrls = [];
      _detectedEmails = [];
      return;
    }

    final text = _extractedText!;

    // 1. OTP Detection
    final otpRegex = RegExp(
      r'(?:otp|code|verification|verify|pin|is|#)\D*(\b\d{4,6}\b)',
      caseSensitive: false,
    );
    final otpMatch = otpRegex.firstMatch(text);
    _detectedOtp = otpMatch?.group(1);

    // 2. Phone Detection
    final phoneRegex = RegExp(
      r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}',
    );
    _detectedPhones = phoneRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();

    // 3. URL Detection
    // Improved regex to catch protocol-less URLs like meet.google.com
    final urlRegex = RegExp(
      r'\b((?:https?:\/\/|www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*))',
      caseSensitive: false,
    );

    // GMeet specific pattern for cases where protocol/domain might be missed by OCR
    final meetCodeRegex = RegExp(r'\b[a-z]{3}-[a-z]{4}-[a-z]{3}\b');

    List<String> urls = urlRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((u) => u.contains('.') || u.startsWith('http'))
        .toList();

    // Add GMeet links if codes found but full URLs missed
    final meetMatches = meetCodeRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
    for (var code in meetMatches) {
      final fullLink = 'meet.google.com/$code';
      if (!urls.any((u) => u.contains(code))) {
        urls.add(fullLink);
      }
    }

    _detectedUrls = urls.toSet().toList();

    // 4. Email Detection
    final emailRegex = RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
      caseSensitive: false,
    );
    _detectedEmails = emailRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList();
  }

  void _nextPhoto() {
    if (_currentIndex < widget.assets.length - 1) {
      setState(() {
        _currentIndex++;
        _loadDetails();
      });
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadDetails();
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showToast("Copied!", Colors.green.shade600);
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_extractedText != null && _extractedText!.isNotEmpty)
            TextButton(
              onPressed: () => _copyToClipboard(_extractedText!),
              child: const Text(
                "Copy All",
                style: TextStyle(
                  color: Color(0xFF6B8CAE),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // 1. Photo Section
                _buildPhotoSection(),

                // 2. Metadata Section
                _buildMetadataSection(),

                // 3. OCR Text Section
                if (!_isLoading) _buildOcrSection(),

                // 4. Detected Elements Section
                if (!_isLoading) _buildDetectedActionsSection(),

                _buildRefireSection(),
                const SizedBox(height: 40),
              ],
            ),
          ),
          // 4. Navigation Bar
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return FutureBuilder<File?>(
      future: _currentAsset.file,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      FullScreenImageView(asset: _currentAsset),
                ),
              );
            },
            child: Hero(
              tag: _currentAsset.id,
              child: Stack(
                children: [
                  Image.file(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                  _buildLocationPill(),
                ],
              ),
            ),
          );
        }
        return AspectRatio(
          aspectRatio: _currentAsset.width / _currentAsset.height,
          child: Container(color: Colors.grey.shade100),
        );
      },
    );
  }

  Widget _buildLocationPill() {
    if (_locationName == null || _locationName!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("📍 ", style: TextStyle(fontSize: 14)),
            Text(
              _locationName!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection() {
    final dateStr = _createDateTime != null
        ? "${_createDateTime!.day}/${_createDateTime!.month}/${_createDateTime!.year}"
        : "";
    final resStr = (_width != null && _height != null)
        ? "${_width}x$_height"
        : "";
    final sizeStr = _fileSize != null ? _formatSize(_fileSize!) : "";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dateStr,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          _metaDivider(),
          Text(
            resStr,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          _metaDivider(),
          Text(
            sizeStr,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _metaDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text("|", style: TextStyle(color: Colors.grey.shade300)),
    );
  }

  Widget _buildOcrSection() {
    if (_extractedText == null || _extractedText!.isEmpty) {
      return const SizedBox.shrink();
    }

    final elements = OcrFormattingService.parse(_extractedText!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  "EXTRACTED TEXT",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF6B8CAE),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(_extractedText!),
                icon: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_all, size: 16, color: Color(0xFF6B8CAE)),
                    SizedBox(width: 4),
                    Text(
                      "Copy All",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6B8CAE),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SelectionArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elements.map((e) => _buildDocElement(e)).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocElement(OcrElement element) {
    switch (element.type) {
      case OcrElementType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            element.text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.3,
            ),
          ),
        );
      case OcrElementType.listItem:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Text(
                  element.listNumber != null ? "${element.listNumber}." : "•",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B8CAE),
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  _buildFormattedTextSpan(element.text),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        );
      case OcrElementType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(
            _buildFormattedTextSpan(element.text),
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        );
      case OcrElementType.table:
        return _buildDocTable(element.tableData!);
      case OcrElementType.divider:
        return _buildDivider();
    }
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
    );
  }

  Widget _buildDocTable(List<List<String>> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
            dataRowColor: WidgetStateProperty.all(Colors.white),
            columnSpacing: 24,
            horizontalMargin: 16,
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dividerThickness: 1,
            border: TableBorder(
              horizontalInside: BorderSide(color: Colors.grey.withOpacity(0.1)),
              verticalInside: BorderSide(color: Colors.grey.withOpacity(0.1)),
            ),
            columns: data[0].map((header) {
              return DataColumn(
                label: Text(
                  header,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              );
            }).toList(),
            rows: data.skip(1).map((row) {
              return DataRow(
                cells: row.map((cell) {
                  return DataCell(
                    Text(
                      cell,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  TextSpan _buildFormattedTextSpan(String text) {
    final phoneRegex = RegExp(
      r'(\+?\d{1,3}[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}',
    );
    final emailRegex = RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    );
    final urlRegex = RegExp(r'https?:\/\/\S+|www\.\S+');

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    void addNormal(String t) {
      if (t.isNotEmpty) {
        spans.add(
          TextSpan(
            text: t,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
        );
      }
    }

    final allMatches = <_MatchWrapper>[];
    for (var m in phoneRegex.allMatches(text)) {
      allMatches.add(_MatchWrapper(m, 'phone'));
    }
    for (var m in emailRegex.allMatches(text)) {
      allMatches.add(_MatchWrapper(m, 'email'));
    }
    for (var m in urlRegex.allMatches(text)) {
      allMatches.add(_MatchWrapper(m, 'url'));
    }

    allMatches.sort((a, b) => a.match.start.compareTo(b.match.start));

    for (var wrapper in allMatches) {
      if (wrapper.match.start < lastMatchEnd) continue;
      addNormal(text.substring(lastMatchEnd, wrapper.match.start));

      final mText = text.substring(wrapper.match.start, wrapper.match.end);
      spans.add(
        TextSpan(
          text: mText,
          style: const TextStyle(
            color: Color(0xFF6B8CAE),
            backgroundColor: Color(0x106B8CAE),
            fontWeight: FontWeight.bold,
            fontSize: 16,
            height: 1.6,
          ),
        ),
      );
      lastMatchEnd = wrapper.match.end;
    }
    addNormal(text.substring(lastMatchEnd));

    return TextSpan(children: spans);
  }

  Widget _buildDetectedActionsSection() {
    final hasAnyDetection =
        _detectedOtp != null ||
        _detectedPhones.isNotEmpty ||
        _detectedUrls.isNotEmpty ||
        _detectedEmails.isNotEmpty ||
        (_qrContent != null && _qrContent!.isNotEmpty);

    if (!hasAnyDetection) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              "DETECTED ACTIONS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Color(0xFF6B8CAE),
              ),
            ),
          ),
          if (_detectedOtp != null)
            _buildActionCard(
              title: "Verification Code",
              value: _detectedOtp!,
              icon: Icons.security,
              iconColor: Colors.orange,
              actions: [
                _actionButton(
                  "Copy OTP",
                  Icons.copy,
                  () => _copyToClipboard(_detectedOtp!),
                  isPrimary: true,
                ),
              ],
            ),
          ..._detectedUrls.map(
            (url) => _buildActionCard(
              title: "Link",
              value: url,
              icon: Icons.link,
              iconColor: Colors.blue,
              actions: [
                _actionButton(
                  "Open",
                  Icons.open_in_new,
                  () => _launchUrlWithScheme(url),
                  isPrimary: true,
                ),
                _actionButton("Copy", Icons.copy, () => _copyToClipboard(url)),
              ],
            ),
          ),
          ..._detectedPhones.map(
            (phone) => _buildActionCard(
              title: "Phone Number",
              value: phone,
              icon: Icons.phone,
              iconColor: Colors.green,
              actions: [
                _actionButton(
                  "Call",
                  Icons.phone,
                  () => launchUrl(Uri.parse('tel:$phone')),
                  isPrimary: true,
                ),
                _actionButton(
                  "Copy",
                  Icons.copy,
                  () => _copyToClipboard(phone),
                ),
              ],
            ),
          ),
          ..._detectedEmails.map(
            (email) => _buildActionCard(
              title: "Email",
              value: email,
              icon: Icons.email,
              iconColor: Colors.redAccent,
              actions: [
                _actionButton(
                  "Email",
                  Icons.email,
                  () => launchUrl(Uri.parse('mailto:$email')),
                  isPrimary: true,
                ),
                _actionButton(
                  "Copy",
                  Icons.copy,
                  () => _copyToClipboard(email),
                ),
              ],
            ),
          ),
          if (_qrContent != null && _qrContent!.isNotEmpty)
            _buildActionCard(
              title: "QR Code",
              value: _qrContent!,
              icon: Icons.qr_code,
              iconColor: Colors.purple,
              actions: [
                if (_qrContent!.startsWith('http'))
                  _actionButton(
                    "Open",
                    Icons.open_in_new,
                    () => _launchUrlWithScheme(_qrContent!),
                    isPrimary: true,
                  ),
                _actionButton(
                  "Copy All",
                  Icons.copy,
                  () => _copyToClipboard(_qrContent!),
                ),
              ],
            ),
          _buildHiddenMetadataSection(),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required List<Widget> actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: a,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: _currentIndex > 0 ? _prevPhoto : null,
            icon: const Icon(Icons.arrow_back_ios, size: 14),
            label: const Text("Previous"),
            style: TextButton.styleFrom(
              foregroundColor: _currentIndex > 0 ? Colors.black87 : Colors.grey,
            ),
          ),
          Text(
            "${_currentIndex + 1} / ${widget.assets.length}",
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton.icon(
            onPressed: _currentIndex < widget.assets.length - 1
                ? _nextPhoto
                : null,
            icon: const Text("Next"),
            label: const Icon(Icons.arrow_forward_ios, size: 14),
            style: TextButton.styleFrom(
              foregroundColor: _currentIndex < widget.assets.length - 1
                  ? Colors.black87
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.blue.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPrimary ? Colors.blue.shade200 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isPrimary ? Colors.blue.shade700 : Colors.grey.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.blue.shade700 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefireSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          if (_isRefiring)
            const Column(
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6B8CAE),
                ),
                SizedBox(height: 12),
                Text(
                  "Enhanced Analysis in progress...",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _refireOcr,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text("Retry OCR (High Accuracy)"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.blue.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refireOcr() async {
    setState(() => _isRefiring = true);

    try {
      final file = await _currentAsset.originFile;
      if (file == null) {
        setState(() => _isRefiring = false);
        return;
      }

      final inputImage = InputImage.fromFile(file);
      final textRecognizer = TextRecognizer();
      final result = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final cleanedText = _cleanOcrText(result.text);

      // Extract blocks for visual selection
      final List<Map<String, dynamic>> blocks = [];
      for (var block in result.blocks) {
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
      final ocrBlocksJson = jsonEncode(blocks);

      await DatabaseHelper.instance.insertOcrResult(
        _currentAsset.id,
        cleanedText,
        _imageLabels ?? '',
        _locationName ?? '',
        _qrContent,
        ocrBlocksJson,
      );

      if (mounted) {
        setState(() {
          _extractedText = cleanedText;
          _isRefiring = false;
          _processExtractedText();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isRefiring = false);
    }
  }

  Future<void> _launchUrlWithScheme(String url) async {
    String formattedUrl = url.trim();
    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }
    try {
      final Uri uri = Uri.parse(formattedUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Could not launch $formattedUrl: $e");
    }
  }

  String _cleanOcrText(String rawText) {
    if (rawText.isEmpty) return "";
    final lines = rawText.split('\n');
    final cleanedLines = <String>[];
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        cleanedLines.add(line);
      }
    }
    return cleanedLines.join('\n');
  }

  Widget _buildHiddenMetadataSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showMetadata = !_showMetadata),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showMetadata ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "SEARCH KEYWORDS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Color(0xFF6B8CAE),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showMetadata) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_userLabels ?? "")
                  .split(',')
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .map(
                    (tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _removeLabel(tag),
                      deleteIconColor: Colors.grey,
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: InputDecoration(
                      hintText: "Add custom tag...",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) => _addLabel(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addLabel,
                  icon: const Icon(Icons.add_circle, color: Color(0xFF6B8CAE)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _addLabel() {
    final newLabel = _labelController.text.trim();
    if (newLabel.isEmpty) return;

    List<String> tags = (_userLabels ?? "")
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (!tags.contains(newLabel)) {
      tags.add(newLabel);
      final updated = tags.join(', ');
      DatabaseHelper.instance.updateUserLabels(_currentAsset.id, updated);
      setState(() {
        _userLabels = updated;
        _labelController.clear();
      });
    }
  }

  void _removeLabel(String label) {
    List<String> tags = (_userLabels ?? "")
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    tags.remove(label);
    final updated = tags.join(', ');
    DatabaseHelper.instance.updateUserLabels(_currentAsset.id, updated);
    setState(() {
      _userLabels = updated;
    });
  }
}

class _MatchWrapper {
  final RegExpMatch match;
  final String type;
  _MatchWrapper(this.match, this.type);
}
