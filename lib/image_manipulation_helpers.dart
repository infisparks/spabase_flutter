import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:async';

// Constants used in image manipulation
const double kImageHandleSize = 40.0;
const double kImageResizeStep = 20.0;

// Application Colors (Required for the overlay controls)
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);

// --- Utility Classes & Functions ---

class Matrix4Utils {
  /// Transforms a local Offset (e.g., in canvas coordinates) by a Matrix4.
  static Offset transformPoint(Matrix4 matrix, Offset offset) {
    final storage = matrix.storage;
    final dx = offset.dx;
    final dy = offset.dy;
    // Perform matrix multiplication for a 3D vector (x, y, 1, 1)
    final x = storage[0] * dx + storage[4] * dy + storage[12];
    final y = storage[1] * dx + storage[5] * dy + storage[13];
    final w = storage[3] * dx + storage[7] * dy + storage[15]; // Perspective component
    return w == 1.0 ? Offset(x, y) : Offset(x / w, y / w);
  }
}

class ImageCacheManager {
  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image?> loadImage(String url) async {
    if (_cache.containsKey(url)) {
      return _cache[url];
    }
    try {
      final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (error, stackTrace) {
        completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      final loadedImage = await completer.future;
      _cache[url] = loadedImage;
      return loadedImage;
    } catch (e) {
      debugPrint('Error loading cached image from $url: $e');
      return null;
    }
  }

  static void clear() => _cache.clear(); // Utility to clear cache

  static ui.Image? getCachedImage(String url) =>
      _cache[url]; // Utility to get cached image
}

// --- Image Overlay Widget ---

typedef UpdateImageCallback = void Function(
    {Offset? newPosition, double? newWidth, double? newHeight});
typedef ResizeImageCallback = void Function(double delta);
typedef DeleteImageCallback = void Function();
typedef ToggleMoveModeCallback = void Function();

/// Builds the circular control icon used for moving, resizing, and deleting.
Widget buildImageControlIcon(
    IconData icon,
    VoidCallback onPressed,
    Matrix4 transformMatrix, {
      String tooltip = '',
      Color color = primaryBlue,
    }) {
  // Uses Transform.scale to compensate for global zoom effect on the small fixed-size buttons
  final currentScale = transformMatrix.getMaxScaleOnAxis();
  final inverseScale = 1 / currentScale;

  return Transform.scale(
    scale: inverseScale,
    child: Tooltip(
      message: tooltip,
      child: Container(
        width: kImageHandleSize,
        height: kImageHandleSize,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(2, 2))
          ],
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: color, size: 20),
          onPressed: onPressed,
        ),
      ),
    ),
  );
}

/// Overlay controls for the currently selected image, displayed in screen coordinates.
class ImageOverlayControls extends StatelessWidget {
  final Offset imagePosition;
  final double imageWidth;
  final double imageHeight;
  final Matrix4 transformMatrix;
  final bool isMovingSelectedImage;
  final ResizeImageCallback onResize;
  final DeleteImageCallback onDelete;
  final ToggleMoveModeCallback onToggleMoveMode;

  const ImageOverlayControls({
    super.key,
    required this.imagePosition,
    required this.imageWidth,
    required this.imageHeight,
    required this.transformMatrix,
    required this.isMovingSelectedImage,
    required this.onResize,
    required this.onDelete,
    required this.onToggleMoveMode,
  });

  @override
  Widget build(BuildContext context) {
    final screenOffset = Matrix4Utils.transformPoint(transformMatrix, imagePosition);
    final currentScale = transformMatrix.getMaxScaleOnAxis();

    final scaledWidth = imageWidth * currentScale;
    final scaledHeight = imageHeight * currentScale;

    // 1. Resize Controls (Top Right corner)
    final resizeControls = Positioned(
      left: screenOffset.dx + scaledWidth,
      top: screenOffset.dy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildImageControlIcon(Icons.add, () => onResize(kImageResizeStep),
              transformMatrix,
              tooltip: 'Increase Size'),
          const SizedBox(height: 4),
          buildImageControlIcon(Icons.remove, () => onResize(-kImageResizeStep),
              transformMatrix,
              tooltip: 'Decrease Size'),
        ],
      ),
    );

    // 2. Move Control (Top Left corner)
    final moveControl = Positioned(
      left: screenOffset.dx - kImageHandleSize,
      top: screenOffset.dy - kImageHandleSize,
      child: buildImageControlIcon(
        isMovingSelectedImage ? Icons.lock_open_rounded : Icons.open_with,
        onToggleMoveMode,
        transformMatrix,
        tooltip: isMovingSelectedImage
            ? 'Exit Move Mode (Pan/Zoom Enabled)'
            : 'Enter Move Mode (Pan/Zoom Disabled)',
        color: isMovingSelectedImage ? Colors.red : primaryBlue,
      ),
    );

    // 3. Delete Control (Bottom Left corner)
    final deleteControl = Positioned(
      left: screenOffset.dx - kImageHandleSize,
      top: screenOffset.dy + scaledHeight,
      child: buildImageControlIcon(
          Icons.delete_forever, onDelete, transformMatrix,
          tooltip: 'Delete Image', color: Colors.red),
    );

    return Stack(
      children: [
        resizeControls,
        moveControl,
        deleteControl,
      ],
    );
  }
}