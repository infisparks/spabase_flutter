import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

// Assuming these are defined in your project or imported elsewhere
import 'drawing_models.dart';
import 'image_manipulation_helpers.dart';
import 'pdf_generator.dart'; // Just for access to ImageCacheManager, etc.
import 'supabase_config.dart';
// --- Constants (Copied from main file) ---
const double canvasWidth = 1000;
const double canvasHeight = 1414;
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);
const Color mediumGreyText = Color(0xFF64748B);

// --- Type Aliases for PiP ---
typedef PipSelectedPageData = (DrawingGroup, DrawingPage);


/// *******************************************************************
/// **The Floating Picture-in-Picture (PiP) window**
///
/// This widget is the draggable and resizable frame that holds
/// the page selector and the read-only canvas.
/// *******************************************************************
class PipReferenceWindow extends StatefulWidget {
  final String patientUhid;
  final List<DrawingGroup> allGroups;
  final PipSelectedPageData? selectedPageData;
  final Size initialSize;
  final String healthRecordId;
  final Map<String, String> groupToColumnMap;
  final VoidCallback onClose;
  final void Function(DrawingGroup, DrawingPage) onPageSelected;
  final ValueChanged<Offset> onPositionChanged;
  final ValueChanged<Offset> onSizeChanged;

  const PipReferenceWindow({
    super.key,
    required this.patientUhid,
    required this.allGroups,
    this.selectedPageData,
    required this.initialSize,
    required this.healthRecordId,
    required this.groupToColumnMap,
    required this.onClose,
    required this.onPageSelected,
    required this.onPositionChanged,
    required this.onSizeChanged,
  });

  @override
  State<PipReferenceWindow> createState() => _PipReferenceWindowState();
}

class _PipReferenceWindowState extends State<PipReferenceWindow> {
  DrawingGroup? _listedGroup;
  bool _isShowingSelector = true;

  @override
  void initState() {
    super.initState();
    // Default to showing the selector if no page is selected initially
    _isShowingSelector = widget.selectedPageData == null;
  }

  @override
  void didUpdateWidget(covariant PipReferenceWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Automatically switch to viewer if a page is newly selected via callback
    if (widget.selectedPageData != null && oldWidget.selectedPageData == null) {
      _isShowingSelector = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12.0,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: widget.initialSize.width,
        height: widget.initialSize.height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryBlue, width: 2),
        ),
        child: Column(
          children: [
            // --- HEADER (for dragging) ---
            GestureDetector(
              onPanUpdate: (details) => widget.onPositionChanged(details.delta),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                height: 48,
                color: primaryBlue.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.drag_indicator, color: mediumGreyText),
                    Expanded(
                      child: Text(
                        _isShowingSelector
                            ? 'Select Reference Page'
                            : (widget.selectedPageData?.$2.pageName ??
                            'Reference'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: darkText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isShowingSelector ? Icons.visibility : Icons.list,
                          size: 20, color: primaryBlue),
                      tooltip:
                      _isShowingSelector ? 'Show Viewer' : 'Show Page List',
                      // Disable button if no page is selected to view
                      onPressed: widget.selectedPageData == null
                          ? null
                          : () =>
                          setState(() => _isShowingSelector = !_isShowingSelector),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: Colors.red[700]),
                      tooltip: 'Close Window',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
            // --- BODY (Selector or Viewer) ---
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isShowingSelector
                    ? _buildPageSelector()
                    : _ReadOnlyCanvas(
                  key: ValueKey(widget.selectedPageData?.$2.id ?? 'empty'),
                  group: widget.selectedPageData!.$1,
                  page: widget.selectedPageData!.$2,
                  healthRecordId: widget.healthRecordId,
                  groupToColumnMap: widget.groupToColumnMap,
                ),
              ),
            ),
            // --- RESIZE HANDLE ---
            GestureDetector(
              onPanUpdate: (details) => widget.onSizeChanged(details.delta),
              child: Container(
                height: 16,
                color: primaryBlue.withOpacity(0.1),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.open_in_full_rounded,
                        size: 14, color: mediumGreyText),
                    SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the Group > Page list selector UI
  Widget _buildPageSelector() {
    if (widget.allGroups.isEmpty) {
      return const Center(child: Text('No groups available.'));
    }

    if (_listedGroup == null) {
      // Show Group List
      return ListView.builder(
        key: const ValueKey('pip-group-list'),
        itemCount: widget.allGroups.length,
        itemBuilder: (context, index) {
          final group = widget.allGroups[index];
          return ListTile(
            leading: const Icon(Icons.folder_open_outlined, color: mediumGreyText),
            title: Text(group.groupName),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => setState(() => _listedGroup = group),
          );
        },
      );
    } else {
      // Show Page List for the selected group
      final pages = _listedGroup!.pages;
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.arrow_back_ios, size: 16),
            title: Text(_listedGroup!.groupName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => setState(() => _listedGroup = null),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              key: ValueKey(_listedGroup!.id),
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final page = pages[index];
                bool isSelected = page.id == widget.selectedPageData?.$2.id;
                return ListTile(
                  leading: Icon(Icons.description_outlined,
                      color: isSelected ? primaryBlue : mediumGreyText),
                  title: Text(page.pageName,
                      style: TextStyle(
                          fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? primaryBlue : darkText)),
                  selected: isSelected,
                  selectedTileColor: primaryBlue.withOpacity(0.1),
                  onTap: () {
                    widget.onPageSelected(_listedGroup!, page);
                    // No need to set state here, parent handles the switch via didUpdateWidget
                  },
                );
              },
            ),
          ),
        ],
      );
    }
  }
}

/// *******************************************************************
/// **The Read-Only Canvas for the PiP window**
///
/// This widget fetches the full page data and renders it.
/// *******************************************************************
class _ReadOnlyCanvas extends StatefulWidget {
  final DrawingGroup group;
  final DrawingPage page; // This is the metadata-only page
  final String healthRecordId;
  final Map<String, String> groupToColumnMap;

  const _ReadOnlyCanvas({
    super.key,
    required this.group,
    required this.page,
    required this.healthRecordId,
    required this.groupToColumnMap,
  });

  @override
  State<_ReadOnlyCanvas> createState() => _ReadOnlyCanvasState();
}

class _ReadOnlyCanvasState extends State<_ReadOnlyCanvas> {
  final TransformationController _pipTransformController =
  TransformationController();
  final SupabaseClient supabase = SupabaseConfig.client;

  DrawingPage? _fullPageData; // The fully loaded page
  ui.Image? _templateUiImage;
  final Map<String, ui.Image> _loadedDrawingImages = {};
  bool _isLoading = false;
  String _loadingStatus = '';

  @override
  void initState() {
    super.initState();
    _fetchFullPageData();
  }

  @override
  void didUpdateWidget(covariant _ReadOnlyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      _fetchFullPageData();
    }
  }

  @override
  void dispose() {
    _pipTransformController.dispose();
    super.dispose();
  }

  String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    const String kBaseImageUrl = 'https://apimmedford.infispark.in/';
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  // Step 2: Fetches the full JSON for the page
  Future<void> _fetchFullPageData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadingStatus = 'Fetching page data...';
        _fullPageData = null;
        _templateUiImage = null;
        _loadedDrawingImages.clear();
        _pipTransformController.value = Matrix4.identity(); // Reset zoom
      });
    }

    try {
      Map<String, dynamic>? pageJson;
      final columnName = widget.groupToColumnMap[widget.group.groupName];

      if (columnName != null) {
        // Default Group
        final response = await supabase
            .from('user_health_details')
            .select(columnName)
            .eq('id', widget.healthRecordId)
            .single();
        final List<dynamic> pagesList = response[columnName] ?? [];
        pageJson = pagesList.firstWhere(
              (p) => p['id'] == widget.page.id,
          orElse: () => null,
        );
      } else {
        // Custom Group
        final response = await supabase
            .from('user_health_details')
            .select('custom_groups_data')
            .eq('id', widget.healthRecordId)
            .single();
        final List<dynamic> groupsList = response['custom_groups_data'] ?? [];
        final groupJson = groupsList.firstWhere(
              (g) => g['id'] == widget.group.id,
          orElse: () => null,
        );
        if (groupJson != null) {
          final List<dynamic> pagesList = groupJson['pages'] ?? [];
          pageJson = pagesList.firstWhere(
                (p) => p['id'] == widget.page.id,
            orElse: () => null,
          );
        }
      }

      if (pageJson != null) {
        final fullPage = DrawingPage.fromJson(pageJson);
        if (mounted) {
          setState(() {
            _fullPageData = fullPage;
            _loadingStatus = 'Loading images...';
          });
        }
        await _loadAllImagesForPage(fullPage); // Step 3
      } else {
        throw Exception("Page data not found in database.");
      }
    } catch (e) {
      debugPrint("Error fetching full PiP page data: $e");
      if (mounted) {
        setState(() {
          _loadingStatus = 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Step 3: Loads ui.Images for the fully loaded page
  Future<void> _loadAllImagesForPage(DrawingPage page) async {
    // 1. Load Template Image
    final String fullTemplateUrl = _getFullImageUrl(page.templateImageUrl);
    ui.Image? templateImage;
    if (fullTemplateUrl.isNotEmpty) {
      try {
        templateImage = await ImageCacheManager.loadImage(fullTemplateUrl);
      } catch (e) {
        debugPrint('PiP Error loading template image: $e');
        templateImage = null;
      }
    }

    // 2. Load all Drawing Images
    final newLoadedDrawingImages = <String, ui.Image>{};
    final futures = <Future<void>>[];

    for (var drawingImage in page.images) {
      futures.add(() async {
        try {
          // Assuming ImageCacheManager exists and is accessible
          final loadedImage =
          await ImageCacheManager.loadImage(drawingImage.imageUrl);
          if (loadedImage != null) {
            newLoadedDrawingImages[drawingImage.id] = loadedImage;
          }
        } catch (e) {
          debugPrint('PiP Error loading drawing image ${drawingImage.id}: $e');
        }
      }());
    }
    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _templateUiImage = templateImage;
        _loadedDrawingImages
          ..clear()
          ..addAll(newLoadedDrawingImages);
        _loadingStatus = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _fullPageData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(_loadingStatus, style: const TextStyle(color: mediumGreyText)),
          ],
        ),
      );
    }

    // InteractiveViewer allows the content to be dragged/zoomed
    return Container(
      color: Colors.grey[300],
      child: InteractiveViewer(
        transformationController: _pipTransformController,
        minScale: 0.2,
        maxScale: 5.0,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(50),
        child: FittedBox(
          fit: BoxFit.contain,
          child: CustomPaint(
            painter: _PipCanvasPainter( // Use a distinct painter for clarity
              drawingPage: _fullPageData!,
              templateUiImage: _templateUiImage,
              loadedDrawingImages: _loadedDrawingImages,
              redrawNotifier: ValueNotifier(0),
            ),
            child: const SizedBox(width: canvasWidth, height: canvasHeight),
          ),
        ),
      ),
    );
  }
}

/// *******************************************************************
/// **Dedicated Painter for the Read-Only PiP Canvas**
///
/// This is a simplified version of PrescriptionPainter without
/// interaction logic (lasso, selection border, pressure, smoothing).
/// *******************************************************************
class _PipCanvasPainter extends CustomPainter {
  final DrawingPage drawingPage;
  final ui.Image? templateUiImage;
  final Map<String, ui.Image> loadedDrawingImages;
  final ValueNotifier<int> redrawNotifier;

  _PipCanvasPainter({
    required this.drawingPage,
    this.templateUiImage,
    required this.loadedDrawingImages,
    required this.redrawNotifier,
  }) : super(repaint: redrawNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Template/Background
    if (templateUiImage != null) {
      paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(0, 0, size.width, size.height),
          image: templateUiImage!,
          fit: BoxFit.contain,
          alignment: Alignment.center);
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.white);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.grey[200]!);
    }

    // 2. Draw Images
    for (var image in drawingPage.images) {
      final cachedImage = loadedDrawingImages[image.id];
      final destRect = Rect.fromLTWH(
          image.position.dx, image.position.dy, image.width, image.height);

      if (cachedImage != null) {
        paintImage(
            canvas: canvas,
            rect: destRect,
            image: cachedImage,
            fit: BoxFit.contain,
            alignment: Alignment.topLeft);
      } else {
        // Simple placeholder for loading/error
        canvas.drawRect(destRect, Paint()..color = Colors.grey.withOpacity(0.5));
      }
    }

    // 3. Draw Lines/Drawings (standard line drawing, no pressure/smoothing)
    for (var line in drawingPage.lines) {
      if (line.points.length <= 1) continue;

      final paint = Paint()
        ..color = Color(line.colorValue)
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);
      for (int i = 1; i < line.points.length; i++) {
        path.lineTo(line.points[i].dx, line.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipCanvasPainter oldDelegate) {
    return oldDelegate.drawingPage != drawingPage ||
        oldDelegate.templateUiImage != templateUiImage ||
        oldDelegate.loadedDrawingImages.length != loadedDrawingImages.length;
  }
}