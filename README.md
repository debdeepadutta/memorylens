# 🔍 MemoryLens

### Privacy-first Offline AI Photo Search for Android

> Search your photos by meaning. Everything runs on your device. Nothing is ever uploaded.

[![Download APK](https://img.shields.io/badge/Download-APK%20v1.0.0-brightgreen?style=for-the-badge&logo=android)](https://github.com/Debdeepa-cs/memorylens/releases/latest)
[![Flutter](https://img.shields.io/badge/Built%20with-Flutter-blue?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

---

## 📱 What is MemoryLens?

MemoryLens is an intelligent photo search app that understands what is **in** your photos — not just their filenames or dates.

Type **"coffee receipt"** and find that Starbucks bill from last month.  
Type **"temple"** and find all your temple visit photos.  
Type **"OTP"** and instantly copy that verification code.

All of this happens **100% on your device**. No cloud. No account. No privacy risk.

---

## ✨ Features

### 🔍 Semantic Search
- Search photos by meaning and content
- Understands natural language queries
- Results appear in under 1 second

### 📄 OCR Text Extraction
- Reads text from any photo
- Detects and copies phone numbers, links, OTPs
- QR code scanning and decoding
- Code block detection with syntax highlighting

### 🗓️ Timeline Memory Book
- Beautiful memory book style timeline
- Photos grouped by month with AI generated story
- Auto detected categories — Food, Places, Documents, People

### 🗑️ Duplicate Detection
- Finds similar and duplicate photos
- Side by side comparison
- One tap cleanup to free storage

### 🔒 100% Private
- Everything processed on your device
- No internet required
- No data collected or uploaded

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter and Dart |
| OCR | Google MLKit Text Recognition V2 |
| Image Labeling | Google MLKit Image Labeling |
| QR Detection | Google MLKit Barcode Scanning |
| Local Database | SQLite via sqflite |
| Authentication | Firebase Auth |
| Photo Access | photo_manager |
| Background Processing | Dart Isolates |

---

## 📲 Installation

### Direct APK Download
1. Download the latest APK from [Releases](https://github.com/debdeepadutta/memorylens/releases/latest)
2. Enable "Install from unknown sources" on your Android phone
3. Open the downloaded APK and install
4. Grant photo permissions when asked
5. Start searching your memories!

**Requirements:** Android 6.0 or higher — 150MB free storage

---

## 🚀 Build From Source

```bash
# Clone the repository
git clone https://github.com/Debdeepa-cs/memorylens.git

# Navigate to project
cd memorylens

# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release
```

---

## 🗺️ Roadmap

- [x] Phase 1 — App shell and navigation
- [x] Phase 2 — Onboarding flow
- [x] Phase 3 — Photo library access
- [x] Phase 4 — OCR and image indexing
- [x] Phase 5 — Semantic search engine
- [x] Phase 6 — Timeline memory book
- [x] Phase 7 — Duplicate detection
- [x] Phase 8 — Settings screen
- [x] Phase 9 — Firebase authentication
- [x] Phase 10 — Payment integration

---

## 👩‍💻 Developer

**Debdeepa Dutta**  
Kolkata, West Bengal, India

---

## 📄 License

This project is licensed under the MIT License.

---

*Built with Flutter — All AI processing happens on device*
