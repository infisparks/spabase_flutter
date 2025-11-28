import 'package:flutter/foundation.dart';
import 'drawing_models.dart'; // Make sure this import points to your models

/// Data model for copied content
class CopiedPageData {
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  // If you want to copy text too, add it here:
  // final List<DrawingText> texts;

  CopiedPageData({
    required this.lines,
    required this.images,
    // this.texts = const [],
  });
}

/// Global Singleton Service
class AppClipboard {
  // 1. Singleton Instance
  static final AppClipboard _instance = AppClipboard._internal();
  factory AppClipboard() => _instance;
  AppClipboard._internal();

  // 2. The Data
  CopiedPageData? _data;

  // 3. Notifier to update UI when data changes (Show/Hide Paste button)
  final ValueNotifier<bool> hasDataNotifier = ValueNotifier(false);

  // 4. Methods
  void setData(CopiedPageData data) {
    _data = data;
    hasDataNotifier.value = true;
  }

  CopiedPageData? getData() {
    return _data;
  }

  void clear() {
    _data = null;
    hasDataNotifier.value = false;
  }

  bool get hasData => _data != null;
}