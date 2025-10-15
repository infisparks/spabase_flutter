import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'supabase_config.dart'; // Make sure you have this file configured

// Extension for list safety
extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

// --- Top-Level Constants ---
const double canvasWidth = 1000;
const double canvasHeight = 1414;
const String kBaseImageUrl = 'https://apimmedford.infispark.in/';
const String kSupabaseBucketName = 'pages'; // Assuming the bucket name for uploads
const double kImageHandleSize = 40.0; // Size of the move/resize handle
const double kImageResizeStep = 20.0; // Amount to resize image by

// Application Colors (MOVED TO TOP-LEVEL TO FIX ERROR)
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);
const Color mediumGreyText = Color(0xFF64748B);
const Color lightBackground = Color(0xFFF8FAFC);


// --- Utility Classes & Functions ---

String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(100000).toString();
}

/// A more robust implementation of the Ramer-Douglas-Peucker algorithm.
List<Offset> simplify(List<Offset> points, double epsilon) {
  if (points.length < 3) {
    return points;
  }

  double findPerpendicularDistance(Offset point, Offset lineStart, Offset lineEnd) {
    double dx = lineEnd.dx - lineStart.dx;
    double dy = lineEnd.dy - lineStart.dy;
    if (dx == 0 && dy == 0) return (point - lineStart).distance;
    double t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / (dx * dx + dy * dy);
    t = max(0, min(1, t));
    double closestX = lineStart.dx + t * dx;
    double closestY = lineStart.dy + t * dy;
    return sqrt(pow(point.dx - closestX, 2) + pow(point.dy - closestY, 2));
  }

  double dMax = 0;
  int index = 0;
  for (int i = 1; i < points.length - 1; i++) {
    double d = findPerpendicularDistance(points[i], points.first, points.last);
    if (d > dMax) {
      index = i;
      dMax = d;
    }
  }

  if (dMax > epsilon) {
    var recResults1 = simplify(points.sublist(0, index + 1), epsilon);
    var recResults2 = simplify(points.sublist(index, points.length), epsilon);
    return recResults1.sublist(0, recResults1.length - 1) + recResults2;
  } else {
    return [points.first, points.last];
  }
}

class Matrix4Utils {
  static Offset transformPoint(Matrix4 matrix, Offset offset) {
    final storage = matrix.storage;
    final dx = offset.dx;
    final dy = offset.dy;
    final x = storage[0] * dx + storage[4] * dy + storage[12];
    final y = storage[1] * dx + storage[5] * dy + storage[13];
    final w = storage[3] * dx + storage[7] * dy + storage[15];
    return w == 1.0 ? Offset(x / w, y / w) : Offset(x / w, y / w);
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
}

// --- Unified & Highly Compressed Data Models ---

class DrawingLine {
  final List<Offset> points;
  final int colorValue;
  final double strokeWidth;

  DrawingLine({
    required this.points,
    required this.colorValue,
    required this.strokeWidth,
  });

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    final pointsList = <Offset>[];
    final pointsData = json['points'];
    final color = (json['colorValue'] as num?)?.toInt() ?? Colors.black.value;
    final width = (json['strokeWidth'] as num?)?.toDouble() ?? 2.0;

    if (pointsData is List && pointsData.isNotEmpty) {
      if (pointsData[0] is Map) {
        // OLD UNCOMPRESSED FORMAT
        for (var pointJson in pointsData) {
          if (pointJson is Map) {
            pointsList.add(Offset(
              (pointJson['dx'] as num?)?.toDouble() ?? 0.0,
              (pointJson['dy'] as num?)?.toDouble() ?? 0.0,
            ));
          }
        }
      } else if (pointsData[0] is num) {
        // NEW COMPRESSED FORMAT (Delta Encoded Integers)
        if (pointsData.length >= 2) {
          double lastX = (pointsData[0] as num).toDouble() / 100.0;
          double lastY = (pointsData[1] as num).toDouble() / 100.0;
          pointsList.add(Offset(lastX, lastY));

          for (int i = 2; i < pointsData.length; i += 2) {
            if (i + 1 < pointsData.length) {
              lastX += (pointsData[i] as num).toDouble() / 100.0;
              lastY += (pointsData[i + 1] as num).toDouble() / 100.0;
              pointsList.add(Offset(lastX, lastY));
            }
          }
        }
      }
    }

    return DrawingLine(points: pointsList, colorValue: color, strokeWidth: width);
  }

  Map<String, dynamic> toJson() {
    if (points.isEmpty) {
      return {'points': [], 'colorValue': colorValue, 'strokeWidth': strokeWidth};
    }

    // 1. Simplify the line first (highest impact). Epsilon = 0.2
    final simplifiedPoints = simplify(points, 0.2);
    if (simplifiedPoints.isEmpty) {
      return {'points': [], 'colorValue': colorValue, 'strokeWidth': strokeWidth};
    }

    final compressedPoints = <int>[];

    // 2. Add the first point as absolute coordinates (multiplied by 100).
    int lastX = (simplifiedPoints.first.dx * 100).round();
    int lastY = (simplifiedPoints.first.dy * 100).round();
    compressedPoints.add(lastX);
    compressedPoints.add(lastY);

    // 3. Add subsequent points as delta (differences).
    for (int i = 1; i < simplifiedPoints.length; i++) {
      int currentX = (simplifiedPoints[i].dx * 100).round();
      int currentY = (simplifiedPoints[i].dy * 100).round();
      compressedPoints.add(currentX - lastX); // Add delta X
      compressedPoints.add(currentY - lastY); // Add delta Y
      lastX = currentX;
      lastY = currentY;
    }

    return {
      'points': compressedPoints,
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
    };
  }

  DrawingLine copyWith({
    List<Offset>? points,
    int? colorValue,
    double? strokeWidth,
  }) {
    return DrawingLine(
      points: points ?? this.points,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

// NOTE: DrawingText class removed as per request.

class DrawingImage {
  final String id;
  final String imageUrl;
  final Offset position;
  final double width;
  final double height;

  DrawingImage({
    required this.id,
    required this.imageUrl,
    required this.position,
    required this.width,
    required this.height,
  });

  DrawingImage copyWith({
    String? id,
    String? imageUrl,
    Offset? position,
    double? width,
    double? height,
  }) {
    // Maintain aspect ratio if only one dimension is provided, but we are not doing that here.
    return DrawingImage(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  factory DrawingImage.fromJson(Map<String, dynamic> json) {
    return DrawingImage(
      id: (json['id'] as String?) ?? generateUniqueId(),
      imageUrl: (json['imageUrl'] as String?) ?? '',
      position: Offset(
        (json['position']?['dx'] as num?)?.toDouble() ?? 0.0,
        (json['position']?['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      width: (json['width'] as num?)?.toDouble() ?? 200.0,
      height: (json['height'] as num?)?.toDouble() ?? 200.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'position': {'dx': position.dx, 'dy': position.dy},
      'width': width,
      'height': height,
    };
  }
}

class DrawingPage {
  final String id;
  final int pageNumber;
  final String pageName;
  final String groupName;
  final String templateImageUrl;
  final List<DrawingLine> lines;
  // final List<DrawingText> texts; // Removed
  final List<DrawingImage> images;

  DrawingPage({
    required this.id,
    required this.pageNumber,
    required this.pageName,
    required this.groupName,
    required this.templateImageUrl,
    this.lines = const [],
    // this.texts = const [], // Removed
    this.images = const [],
  });

  DrawingPage copyWith({
    String? id,
    int? pageNumber,
    String? pageName,
    String? groupName,
    String? templateImageUrl,
    List<DrawingLine>? lines,
    // List<DrawingText>? texts, // Removed
    List<DrawingImage>? images,
  }) {
    return DrawingPage(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      pageName: pageName ?? this.pageName,
      groupName: groupName ?? this.groupName,
      templateImageUrl: templateImageUrl ?? this.templateImageUrl,
      lines: lines ?? this.lines,
      // texts: texts ?? this.texts, // Removed
      images: images ?? this.images,
    );
  }

  factory DrawingPage.fromJson(Map<String, dynamic> json) {
    // NOTE: Decoding of 'texts' is removed.
    return DrawingPage(
      id: (json['id'] as String?) ?? '',
      pageNumber: (json['pageNumber'] as int?) ?? 0,
      pageName: json['pageName'] as String? ?? 'Unnamed Page',
      groupName: json['groupName'] as String? ?? 'Unnamed Group',
      templateImageUrl: (json['templateImageUrl'] as String?) ?? '',
      lines: (json['lines'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((lineJson) => DrawingLine.fromJson(lineJson))
          .toList() ??
          [],
      // texts: (json['texts'] as List<dynamic>?) // Removed text parsing
      //     ?.whereType<Map<String, dynamic>>()
      //     .map((textJson) => DrawingText.fromJson(textJson))
      //     .toList() ??
      //     [],
      images: (json['images'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((imageJson) => DrawingImage.fromJson(imageJson))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    // NOTE: Encoding of 'texts' is removed.
    return {
      'id': id,
      'pageNumber': pageNumber,
      'pageName': pageName,
      'groupName': groupName,
      'templateImageUrl': templateImageUrl,
      'lines': lines.map((line) => line.toJson()).toList(),
      // 'texts': texts.map((text) => text.toJson()).toList(), // Removed text encoding
      'images': images.map((image) => image.toJson()).toList(),
    };
  }
}

class DrawingGroup {
  final String id;
  final String groupName; // Standardized to groupName
  final List<DrawingPage> pages;

  DrawingGroup({
    required this.id,
    required this.groupName,
    this.pages = const [],
  });

  DrawingGroup copyWith({
    String? id,
    String? groupName,
    List<DrawingPage>? pages,
  }) {
    return DrawingGroup(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      pages: pages ?? this.pages,
    );
  }

  factory DrawingGroup.fromJson(Map<String, dynamic> json) {
    return DrawingGroup(
      id: (json['id'] as String?) ?? '',
      groupName: json['groupName'] as String? ?? json['name'] as String? ?? 'Unnamed Group',
      pages: (json['pages'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((pageJson) => DrawingPage.fromJson(pageJson))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupName': groupName,
      'pages': pages.map((page) => page.toJson()).toList(),
    };
  }
}

// --- End of Data Models ---

enum DrawingTool { pen, eraser, image } // Removed text tool

class _CopiedPageData {
  final List<DrawingLine> lines;
  // final List<DrawingText> texts; // Removed
  final List<DrawingImage> images;
  _CopiedPageData({required this.lines, required this.images}); // Removed texts
}

class UploadedImage { // Model for Supabase Storage files
  final String name;
  final String publicUrl;

  UploadedImage({required this.name, required this.publicUrl});
}


class PrescriptionPage extends StatefulWidget {
  final int ipdId;
  final String uhid;
  final String groupId;
  final String pageId;
  final String groupName;

  const PrescriptionPage({
    super.key,
    required this.ipdId,
    required this.uhid,
    required this.groupId,
    required this.pageId,
    required this.groupName,
  });

  @override
  State<PrescriptionPage> createState() => _PrescriptionPageState();
}

class _PrescriptionPageState extends State<PrescriptionPage> {
  final SupabaseClient supabase = SupabaseConfig.client;
  final ImagePicker _picker = ImagePicker();

  // --- Data State ---
  List<DrawingPage> _viewablePages = [];
  int _currentPageIndex = 0;
  String? _healthRecordId;
  DrawingGroup? _currentGroup;
  List<DrawingPage> _pagesInCurrentGroup = [];
  _CopiedPageData? _copiedPageData;
  List<UploadedImage> _userUploadedImages = [];

  static const Map<String, String> _groupToColumnMap = {
    'Indoor Patient Progress Digital': 'indoor_patient_progress_digital_data',
    'Daily Drug Chart': 'daily_drug_chart_data',
    'Dr Visit Form': 'dr_visit_form_data',
    'Patient Charges Form': 'patient_charges_form_data',
    'Glucose Monitoring Sheet': 'glucose_monitoring_sheet_data',
    'Pt Admission Assessment (Nursing)': 'pt_admission_assessment_nursing_data',
    'Clinical Notes': 'clinical_notes_data',
    'Investigation Sheet': 'investigation_sheet_data',
    'Progress Notes': 'progress_notes_data',
    'Consent': 'consent_data',
    'OT': 'ot_data',
    'Nursing Notes': 'nursing_notes_data',
    'TPR / Intake / Output': 'tpr_intake_output_data',
    'Discharge / Dama': 'discharge_dama_data',
    'Casualty Note': 'casualty_note_data',
    'Indoor Patient File': 'indoor_patient_file_data',
  };

  // --- Drawing State ---
  Color _currentColor = Colors.black;
  double _strokeWidth = 2.0;
  // double _currentFontSize = 20.0; // Removed
  DrawingTool _selectedTool = DrawingTool.pen;

  // --- Image Manipulation State ---
  String? _selectedImageId;
  Offset? _dragStartCanvasPosition; // Starting canvas position for image movement
  bool _isMovingSelectedImage = false; // Flag to enable image movement

  // --- Text Editing State ---
  // final TextEditingController _textController = TextEditingController(); // Removed
  // final FocusNode _textFocusNode = FocusNode(); // Removed
  // String? _editingTextId; // Removed

  // --- View State ---
  final PageController _pageController = PageController();
  final TransformationController _transformationController = TransformationController();
  ui.Image? _currentTemplateUiImage;
  bool _isLoadingPrescription = true;
  bool _isSaving = false;
  bool _isInitialZoomSet = false;
  bool _isStylusInteraction = false;
  final bool _isPenOnlyMode = true; // Kept this true to enforce stylus drawing
  final ValueNotifier<int> _redrawNotifier = ValueNotifier(0);

  // --- Autosave & Realtime State ---
  Timer? _debounceTimer;
  RealtimeChannel? _healthRecordChannel;
  DateTime? _lastSuccessfulSaveTime;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadHealthDetailsAndPage();
    _fetchUserUploadedImages();
    _transformationController.addListener(_onTransformUpdated);
    // _textFocusNode.addListener(_onTextFocusChange); // Removed
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    if (_healthRecordChannel != null) {
      supabase.removeChannel(_healthRecordChannel!);
    }
    _transformationController.removeListener(_onTransformUpdated);
    _transformationController.dispose();
    _pageController.dispose();
    // _textController.dispose(); // Removed
    // _textFocusNode.removeListener(_onTextFocusChange); // Removed
    // _textFocusNode.dispose(); // Removed
    _redrawNotifier.dispose();
    ImageCacheManager.clear();
    super.dispose();
  }

  String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  // --- Data Loading, Saving, and Realtime ---

  Future<void> _loadTemplateUiImage(String relativePath) async {
    final String fullUrl = _getFullImageUrl(relativePath);
    if (fullUrl.isEmpty) {
      if (mounted) setState(() => _currentTemplateUiImage = null);
      return;
    }
    try {
      final stream = NetworkImage(fullUrl).resolve(ImageConfiguration.empty);
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
      if (mounted) setState(() => _currentTemplateUiImage = loadedImage);
    } catch (e) {
      debugPrint('Error loading image from $fullUrl: $e');
      if (mounted) setState(() => _currentTemplateUiImage = null);
    }
  }

  Future<void> _loadHealthDetailsAndPage() async {
    if (!mounted) return;
    final String? currentPageIdBeforeRefresh = _viewablePages.isNotEmpty ? _viewablePages[_currentPageIndex].id : widget.pageId; // 1. Preserve ID
    setState(() => _isLoadingPrescription = true);
    try {
      final columnName = _groupToColumnMap[widget.groupName] ?? 'custom_groups_data';
      final columnsToSelect = ['id', columnName, 'custom_groups_data'].join(',');
      final response = await supabase
          .from('user_health_details')
          .select(columnsToSelect)
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      if (response != null) {
        _healthRecordId = response['id'] as String?;
        if (columnName == 'custom_groups_data') {
          final rawCustomGroups = response['custom_groups_data'] ?? [];
          final customGroups = (rawCustomGroups as List?)?.map((json) => DrawingGroup.fromJson(json as Map<String, dynamic>)).toList() ?? [];
          _currentGroup = customGroups.firstWhere((g) => g.id == widget.groupId, orElse: () => throw Exception("Custom group not found."));
          _pagesInCurrentGroup = _currentGroup!.pages;
        } else {
          final rawPages = response[columnName] ?? [];
          _pagesInCurrentGroup = (rawPages as List?)?.map((json) => DrawingPage.fromJson(json as Map<String, dynamic>)).toList() ?? [];
          _currentGroup = DrawingGroup(id: widget.groupId, groupName: widget.groupName, pages: _pagesInCurrentGroup);
        }

        // Find the page we are starting on or last saved
        DrawingPage startPage = _pagesInCurrentGroup.firstWhere((p) => p.id == currentPageIdBeforeRefresh, orElse: () => throw Exception("Start page not found in new data."));
        String pagePrefix = startPage.pageName.split('(')[0].trim();
        _viewablePages = _pagesInCurrentGroup.where((p) => p.pageName.split('(')[0].trim() == pagePrefix).toList();

        // 2. Restore Index: Use the preserved ID to find the new index
        int initialIndex = _viewablePages.indexWhere((p) => p.id == currentPageIdBeforeRefresh);

        if (initialIndex != -1) {
          _currentPageIndex = initialIndex;
          // 3. Inform PageController
          if (_pageController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _pageController.jumpToPage(_currentPageIndex);
            });
          }
          await _loadTemplateUiImage(_viewablePages[_currentPageIndex].templateImageUrl);
        } else {
          throw Exception("Starting page could not be located after refresh.");
        }
        _setupRealtimeSubscription();
      } else {
        throw Exception("No health record found.");
      }
    } catch (e) {
      debugPrint('Error loading health details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load details: ${e.toString()}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoadingPrescription = false);
    }
  }

  void _setupRealtimeSubscription() {
    if (_healthRecordId == null || _healthRecordChannel != null) return;
    _healthRecordChannel = supabase
        .channel('public:user_health_details:id=eq.$_healthRecordId')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_health_details',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: _healthRecordId!),
      callback: (payload) async { // Make callback async
        if (_isDisposed) return;
        final newRecord = payload.newRecord;
        if (newRecord == null) return;
        final updatedAtString = newRecord['updated_at'] as String?;
        if (updatedAtString == null) return;
        final remoteUpdateTime = DateTime.parse(updatedAtString);

        if (_lastSuccessfulSaveTime != null && remoteUpdateTime.difference(_lastSuccessfulSaveTime!).inSeconds.abs() < 5) {
          debugPrint('Ignoring self-initiated realtime update.');
          return;
        }

        // --- AUTO-REFRESH LOGIC ---
        if (mounted) {
          debugPrint("External update detected. Auto-refreshing...");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data was updated by another user. Refreshing...'),
              backgroundColor: primaryBlue,
              duration: Duration(seconds: 3),
            ),
          );
          await _loadHealthDetailsAndPage(); // Auto-refresh the page
        }
      },
    )
        .subscribe();
  }

  void _debouncedSave() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      if (!_isSaving) {
        _savePrescriptionData();
      }
    });
  }

  void _syncViewablePagesToMasterList() {
    for (var viewablePage in _viewablePages) {
      int pageIndex = _pagesInCurrentGroup.indexWhere((p) => p.id == viewablePage.id);
      if (pageIndex != -1) {
        _pagesInCurrentGroup[pageIndex] = viewablePage;
      }
    }
  }

  Future<void> _savePrescriptionData({bool isManualSave = false}) async {
    _debounceTimer?.cancel();
    // _commitTextChanges(); // Removed
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      _syncViewablePagesToMasterList();
      final columnName = _groupToColumnMap[widget.groupName];
      final Map<String, dynamic> dataToSave = {};

      if (columnName != null) {
        dataToSave[columnName] = _pagesInCurrentGroup.map((page) => page.toJson()).toList();
      } else {
        final response = await supabase.from('user_health_details').select('custom_groups_data').eq('id', _healthRecordId!).single();
        final rawCustomGroups = response['custom_groups_data'] ?? [];
        final List<DrawingGroup> customGroups = (rawCustomGroups as List?)?.map((json) => DrawingGroup.fromJson(json as Map<String, dynamic>)).toList() ?? [];
        int groupIndex = customGroups.indexWhere((g) => g.id == widget.groupId);
        if (groupIndex != -1) {
          customGroups[groupIndex] = customGroups[groupIndex].copyWith(pages: _pagesInCurrentGroup);
        } else {
          throw Exception("Custom group not found for saving.");
        }
        dataToSave['custom_groups_data'] = customGroups.map((group) => group.toJson()).toList();
      }
      dataToSave['updated_at'] = DateTime.now().toIso8601String();

      if (_healthRecordId != null) {
        await supabase.from('user_health_details').update(dataToSave).eq('id', _healthRecordId!);
        _lastSuccessfulSaveTime = DateTime.now();

        if (mounted && isManualSave) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved! Refreshing to synchronize.'), backgroundColor: Colors.green));
          await _loadHealthDetailsAndPage();
        }
      } else {
        throw Exception("Health Record ID is missing.");
      }
    } catch (e) {
      debugPrint('Error saving: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Image Handling & Storage ---

  Future<void> _fetchUserUploadedImages() async {
    try {
      // The path should be specific to the user, e.g., 'public/images/UHID/'
      final storagePath = 'public/images/${widget.uhid}/';
      final files = await supabase.storage.from(kSupabaseBucketName).list(path: storagePath);

      _userUploadedImages = files.map((file) {
        final publicUrl = supabase.storage.from(kSupabaseBucketName).getPublicUrl('$storagePath${file.name}');
        return UploadedImage(name: file.name, publicUrl: publicUrl);
      }).toList();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error fetching uploaded images: $e');
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    // _commitTextChanges(); // Removed
    final XFile? pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() => _isSaving = true);
      try {
        final imageFile = await pickedFile.readAsBytes();
        final fileName = '${generateUniqueId()}.${pickedFile.path.split('.').last}';
        final storagePath = 'public/images/${widget.uhid}/$fileName';

        // 1. Upload to Supabase Storage
        await supabase.storage.from(kSupabaseBucketName).uploadBinary(
          storagePath,
          imageFile,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

        // 2. Get the public URL
        final publicUrl = supabase.storage.from(kSupabaseBucketName).getPublicUrl(storagePath);

        // 3. Add to DrawingPage data
        _addImageToCanvas(publicUrl);

        // 4. Refresh uploaded images list
        await _fetchUserUploadedImages();

        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image uploaded and added!'), backgroundColor: Colors.green));

      } on StorageException catch (e) {
        debugPrint('Supabase Storage Error: ${e.message}');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: ${e.message}'), backgroundColor: Colors.red));
      } catch (e) {
        debugPrint('General Image Error: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image handling failed: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  void _addImageToCanvas(String publicUrl) {
    const double defaultImageSize = 200.0;
    final newImage = DrawingImage(
      id: generateUniqueId(),
      imageUrl: publicUrl,
      // Center the image on the canvas
      position: Offset(canvasWidth / 2 - defaultImageSize / 2, canvasHeight / 2 - defaultImageSize / 2),
      width: defaultImageSize,
      height: defaultImageSize,
    );

    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _viewablePages[_currentPageIndex] = currentPage.copyWith(images: [...currentPage.images, newImage]);
      _selectedImageId = newImage.id; // Auto-select the new image
      _isMovingSelectedImage = false;
    });

    _debouncedSave();
  }

  void _updateSelectedImage({Offset? newPosition, double? newWidth, double? newHeight}) {
    if (_selectedImageId == null) return;

    final currentPage = _viewablePages[_currentPageIndex];
    final imageIndex = currentPage.images.indexWhere((img) => img.id == _selectedImageId);

    if (imageIndex != -1) {
      final oldImage = currentPage.images[imageIndex];
      final updatedImages = List<DrawingImage>.from(currentPage.images);

      updatedImages[imageIndex] = oldImage.copyWith(
        position: newPosition,
        width: newWidth,
        height: newHeight,
      );

      setState(() {
        _viewablePages[_currentPageIndex] = currentPage.copyWith(images: updatedImages);
        _redrawNotifier.value = 1 - _redrawNotifier.value; // Force repaint
      });
      _debouncedSave();
    }
  }

  void _resizeSelectedImage(double delta) {
    if (_selectedImageId == null) return;
    final currentPage = _viewablePages[_currentPageIndex];
    final image = currentPage.images.firstWhere((img) => img.id == _selectedImageId);

    // Simplistic resizing: change width and height by delta, minimum size of 50
    double newWidth = max(50.0, image.width + delta);
    double newHeight = max(50.0, image.height + delta); // Keep 1:1 ratio for simplicity

    _updateSelectedImage(newWidth: newWidth, newHeight: newHeight);
  }

  Future<void> _showUploadedImagesSelector() async {
    await _fetchUserUploadedImages(); // Ensure we have the latest list

    if (_userUploadedImages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No uploaded images found for this patient. Use Camera or Gallery to upload one.'), backgroundColor: Colors.orange));
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Uploaded Images", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
              const SizedBox(height: 10),
              const Divider(),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _userUploadedImages.length,
                  itemBuilder: (context, index) {
                    final uploadedImage = _userUploadedImages[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _addImageToCanvas(uploadedImage.publicUrl);
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image added from uploaded files!'), backgroundColor: Colors.green));
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: mediumGreyText.withOpacity(0.5)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            uploadedImage.publicUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null));
                            },
                            errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.red)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Pointer and Interaction Handlers ---

  void _handlePointerDown(PointerDownEvent details) {
    // _commitTextChanges(); // Removed
    final transformedPosition = _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    final currentPage = _viewablePages[_currentPageIndex];
    setState(() => _isStylusInteraction = details.kind == ui.PointerDeviceKind.stylus);


    if (_selectedTool == DrawingTool.image) {
      // 1. Check if the tap hits the currently selected image's move handle/body
      final selectedImage = currentPage.images.firstWhereOrNull((img) => img.id == _selectedImageId);
      bool hitSelectedImage = false;

      if (selectedImage != null) {
        final imageRect = Rect.fromLTWH(selectedImage.position.dx, selectedImage.position.dy, selectedImage.width, selectedImage.height).inflate(5);
        if (imageRect.contains(transformedPosition)) {
          hitSelectedImage = true;
        }
      }

      if (hitSelectedImage) {
        // Only start drag if `_isMovingSelectedImage` is true, otherwise treat it as selection
        if (_isMovingSelectedImage) {
          _dragStartCanvasPosition = transformedPosition - selectedImage!.position;
        } else {
          // If not in move mode, just a tap selects it and *might* enter move mode later if user presses move button
          _handleCanvasTap(transformedPosition);
        }
        return;
      } else {
        // If it didn't hit the selected one, try to select a new image, which also handles deselection
        _handleCanvasTap(transformedPosition);
        return;
      }
    }


    // Logic for Drawing/Erasing (Pen/Eraser)
    // Only proceed if tool is pen/eraser AND it's a stylus interaction (Pen Only Mode)
    if (_isPenOnlyMode && _isStylusInteraction) {
      if (_selectedTool == DrawingTool.pen) {
        setState(() {
          final newLine = DrawingLine(points: [transformedPosition], colorValue: _currentColor.value, strokeWidth: _strokeWidth);
          _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: [...currentPage.lines, newLine]);
        });
      }
      // Eraser logic is handled in _handlePointerMove, but setting _isStylusInteraction to true here is crucial
    }
  }

  void _handlePointerMove(PointerMoveEvent details) {
    final transformedPosition = _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    // Image Movement Logic (works with finger or stylus if tool is image and move mode is active)
    if (_selectedTool == DrawingTool.image && _isMovingSelectedImage && _selectedImageId != null && _dragStartCanvasPosition != null) {
      // Logic for dragging/moving an image
      final newImagePosition = transformedPosition - _dragStartCanvasPosition!;
      _updateSelectedImage(newPosition: newImagePosition);
      return;
    }

    // Drawing/Erasing Logic (only with stylus in Pen Only Mode)
    if (_isPenOnlyMode && _isStylusInteraction) {
      if (_selectedTool == DrawingTool.pen) {
        setState(() {
          final currentPage = _viewablePages[_currentPageIndex];
          if (currentPage.lines.isEmpty) return;
          final lastLine = currentPage.lines.last;
          final newPoints = [...lastLine.points, transformedPosition];
          final updatedLines = List<DrawingLine>.from(currentPage.lines);
          updatedLines.last = lastLine.copyWith(points: newPoints);
          _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: updatedLines);
        });
      } else if (_selectedTool == DrawingTool.eraser) {
        _eraseLineAtPoint(transformedPosition);
      }
    }
  }

  void _handlePointerUp(PointerUpEvent details) {
    if (_selectedTool == DrawingTool.image && _selectedImageId != null && _dragStartCanvasPosition != null) {
      _dragStartCanvasPosition = null;
      _debouncedSave(); // Save after image movement
      // Note: _isMovingSelectedImage is NOT reset here, it is controlled by the lock icon.
    }

    if (_isStylusInteraction) {
      _debouncedSave();
      setState(() => _isStylusInteraction = false);
    }
  }

  void _handleCanvasTap(Offset canvasPosition) { // Taps when DrawingTool.image is active
    final currentPage = _viewablePages[_currentPageIndex];
    String? newSelectedImageId;

    // Check top-most image first
    for (final image in currentPage.images.reversed) {
      final imageRect = Rect.fromLTWH(image.position.dx, image.position.dy, image.width, image.height).inflate(5); // Slight tolerance
      if (imageRect.contains(canvasPosition)) {
        newSelectedImageId = image.id;
        break;
      }
    }

    setState(() {
      if (newSelectedImageId != null) {
        // If a new image is tapped, select it, but DON'T auto-enter move mode
        // if the old image was already selected, a tap simply confirms the selection.
        if (_selectedImageId != newSelectedImageId) {
          _isMovingSelectedImage = false; // Reset move mode for new selection
        }
        _selectedImageId = newSelectedImageId;

      } else {
        // If they tapped outside an image, deselect it and exit move mode
        _selectedImageId = null;
        _isMovingSelectedImage = false;
      }
      _redrawNotifier.value = 1 - _redrawNotifier.value; // Force redraw to show/hide selection border
    });
  }

  // --- Utility & Action Methods ---

  void _onTransformUpdated() => setState(() {});

  // Text handling methods removed (e.g., _onTextFocusChange, _commitTextChanges, _handleTextTap)

  void _copyPageContent() {
    if (_viewablePages.isEmpty) return;
    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _copiedPageData = _CopiedPageData(
        lines: currentPage.lines.map((line) => line.copyWith()).toList(),
        // texts: currentPage.texts.map((text) => text.copyWith()).toList(), // Removed
        images: currentPage.images.map((image) => image.copyWith()).toList(),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page content copied!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
  }

  void _pastePageContent() {
    if (_copiedPageData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to paste.'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
      return;
    }
    if (_viewablePages.isEmpty) return;
    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];
      // final pastedTextsWithNewIds = _copiedPageData!.texts.map((textToCopy) => textToCopy.copyWith(id: generateUniqueId())).toList(); // Removed
      final pastedImagesWithNewIds = _copiedPageData!.images.map((imageToCopy) => imageToCopy.copyWith(id: generateUniqueId())).toList();

      _viewablePages[_currentPageIndex] = currentPage.copyWith(
        lines: [...currentPage.lines, ..._copiedPageData!.lines],
        // texts: [...currentPage.texts, ...pastedTextsWithNewIds], // Removed
        images: [...currentPage.images, ...pastedImagesWithNewIds],
      );
    });
    _debouncedSave();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Content pasted!'), backgroundColor: primaryBlue, duration: Duration(seconds: 2)));
  }

  void _undoLastAction() {
    HapticFeedback.lightImpact();
    if (_viewablePages.isEmpty || (_viewablePages[_currentPageIndex].lines.isEmpty && _viewablePages[_currentPageIndex].images.isEmpty)) return; // Removed texts check

    // Simple undo: remove the last added element (line or image)
    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];

      final lines = currentPage.lines.toList();
      final images = currentPage.images.toList();

      // Prioritize removing drawing lines as they are the most frequent operation
      if (lines.isNotEmpty) {
        lines.removeLast();
      } else if (images.isNotEmpty) {
        images.removeLast();
      }

      _selectedImageId = null; // Deselect anything when undoing
      _isMovingSelectedImage = false;

      _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: lines, images: images); // Removed texts
    });
    _debouncedSave();
  }

  void _clearAllDrawings() {
    HapticFeedback.mediumImpact();
    if (_viewablePages.isEmpty) return;
    setState(() {
      _viewablePages[_currentPageIndex] = _viewablePages[_currentPageIndex].copyWith(lines: [], images: []); // Removed texts
      _selectedImageId = null; // Deselect
      _isMovingSelectedImage = false;
    });
    _debouncedSave();
  }

  void _eraseLineAtPoint(Offset point) {
    if (_viewablePages.isEmpty) return;
    final currentPage = _viewablePages[_currentPageIndex];
    final linesToKeep = <DrawingLine>[];
    bool changed = false;
    for (final line in currentPage.lines) {
      bool remove = false;
      for (final p in line.points) {
        if ((p - point).distance < _strokeWidth * 2) {
          remove = true;
          changed = true;
          break;
        }
      }
      if (!remove) linesToKeep.add(line);
    }
    if (changed) {
      setState(() => _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: linesToKeep));
    }
  }

  void _zoomByFactor(double factor) {
    HapticFeedback.lightImpact();
    // This is safe to call from a button outside the InteractiveViewer's direct control
    final center = (context.findRenderObject() as RenderBox).size.center(Offset.zero);
    final newMatrix = _transformationController.value.clone()
      ..translate(center.dx, center.dy)
      ..scale(factor)
      ..translate(-center.dx, -center.dy);
    _transformationController.value = newMatrix;
  }

  void _zoomIn() => _zoomByFactor(1.2);
  void _zoomOut() => _zoomByFactor(1 / 1.2);
  void _resetZoom() {
    final size = context.size;
    if (size != null) _setInitialZoom(size);
  }

  Offset _transformToCanvasCoordinates(Offset localPosition) {
    final inverseMatrix = Matrix4.inverted(_transformationController.value);
    return Matrix4Utils.transformPoint(inverseMatrix, localPosition);
  }

  bool _isPointOnCanvas(Offset point) {
    return point.dx >= 0 && point.dx <= canvasWidth && point.dy >= 0 && point.dy <= canvasHeight;
  }

  void _setInitialZoom(Size viewportSize) {
    if (viewportSize.isEmpty) return;
    final scale = min(viewportSize.width / canvasWidth, viewportSize.height / canvasHeight);
    final dx = (viewportSize.width - canvasWidth * scale) / 2;
    final dy = (viewportSize.height - canvasHeight * scale) / 2;
    _transformationController.value = Matrix4.identity()..translate(dx, dy)..scale(scale);
  }

  void _navigateToPage(int index) async {
    if (index >= 0 && index < _viewablePages.length) {
      // _commitTextChanges(); // Removed
      if (_pageController.hasClients) _pageController.jumpToPage(index);
      setState(() {
        _currentPageIndex = index;
        _isInitialZoomSet = false;
        _selectedImageId = null; // Deselect image on page change
        _isMovingSelectedImage = false;
      });
      await _loadTemplateUiImage(_viewablePages[index].templateImageUrl);
    }
  }

  Future<void> _showFolderPageSelector() async {
    if (_pagesInCurrentGroup.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pages in '${_currentGroup?.groupName ?? 'Group'}'", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
              const SizedBox(height: 10),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _pagesInCurrentGroup.length,
                  itemBuilder: (context, index) {
                    final page = _pagesInCurrentGroup[index];
                    final bool isSelected = page.id == _viewablePages[_currentPageIndex].id;
                    return ListTile(
                      leading: Icon(Icons.description_outlined, color: isSelected ? primaryBlue : mediumGreyText),
                      title: Text(page.pageName, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? primaryBlue : darkText)),
                      selected: isSelected,
                      selectedTileColor: primaryBlue.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      onTap: () {
                        Navigator.pop(context);
                        final tappedPage = _pagesInCurrentGroup[index];
                        if (tappedPage.id == _viewablePages[_currentPageIndex].id) return;
                        final tappedPrefix = tappedPage.pageName.split('(')[0].trim();
                        final newViewablePages = _pagesInCurrentGroup.where((p) => p.pageName.split('(')[0].trim() == tappedPrefix).toList();
                        final newPageIndex = newViewablePages.indexWhere((p) => p.id == tappedPage.id);
                        if (newPageIndex != -1) {
                          // _commitTextChanges(); // Removed
                          setState(() {
                            _viewablePages = newViewablePages;
                            _currentPageIndex = newPageIndex;
                            _isInitialZoomSet = false;
                            _selectedImageId = null; // Deselect image on page change
                            _isMovingSelectedImage = false;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_pageController.hasClients) _pageController.jumpToPage(newPageIndex);
                            _loadTemplateUiImage(newViewablePages[newPageIndex].templateImageUrl);
                          });
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _handleBackButton() async {
    // _commitTextChanges(); // Removed
    _syncViewablePagesToMasterList();
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop(_pagesInCurrentGroup);
    }
    return false;
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrescription) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_viewablePages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Error")),
        body: const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Page data could not be loaded.", textAlign: TextAlign.center))),
      );
    }

    final currentPageData = _viewablePages[_currentPageIndex];

    // Determine if InteractiveViewer should be pan-enabled.
    // It should be disabled when the user is actively drawing (stylus interaction)
    // or when the user is actively moving a selected image.
    final bool panScaleEnabled = !_isStylusInteraction && !_isMovingSelectedImage;


    return WillPopScope(
      onWillPop: _handleBackButton,
      child: Scaffold(
        backgroundColor: lightBackground,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handleBackButton, tooltip: 'Back'),
          title: Text("${currentPageData.pageName} (${currentPageData.groupName})"),
          backgroundColor: Colors.white,
          elevation: 2,
          actions: [
            IconButton(icon: const Icon(Icons.list_alt, color: primaryBlue), tooltip: 'Select Page', onPressed: _showFolderPageSelector),
            if (_viewablePages.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  onPressed: () => _navigateToPage((_currentPageIndex + 1) % _viewablePages.length),
                  avatar: const Icon(Icons.arrow_forward_ios, size: 14, color: primaryBlue),
                  label: Text("${_currentPageIndex + 1}/${_viewablePages.length}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryBlue)),
                  backgroundColor: primaryBlue.withOpacity(0.15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            _buildPageActionsMenu(),
            IconButton(
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: primaryBlue))
                  : const Icon(Icons.save_alt_rounded, color: primaryBlue),
              tooltip: "Save and Refresh",
              onPressed: _isSaving ? null : () => _savePrescriptionData(isManualSave: true),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Row(children: [Expanded(child: _buildDrawingToolbar()), _buildPanToolbar()]),
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!_isInitialZoomSet) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _setInitialZoom(constraints.biggest);
                  _isInitialZoomSet = true;
                }
              });
            }
            return Stack(
              children: [
                Listener(
                  // Listener only for high-precision input (stylus) and image manipulation
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _viewablePages.length,
                    onPageChanged: (index) async {
                      // _commitTextChanges(); // Removed
                      setState(() {
                        _currentPageIndex = index;
                        _isInitialZoomSet = false;
                        _transformationController.value = Matrix4.identity();
                        _selectedImageId = null;
                        _isMovingSelectedImage = false;
                      });
                      await _loadTemplateUiImage(_viewablePages[index].templateImageUrl);
                    },
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        // Enable pan/scale only if NOT drawing/erasing AND NOT actively moving an image
                        panEnabled: panScaleEnabled,
                        scaleEnabled: panScaleEnabled,
                        minScale: 0.1,
                        maxScale: 10.0,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        child: GestureDetector( // Add GestureDetector for image selection (non-stylus taps)
                          onTapUp: (details) {
                            // If tool is image and not actively moving and not a stylus interaction (which is handled by Listener)
                            if (_selectedTool == DrawingTool.image && !_isStylusInteraction && !_isMovingSelectedImage) {
                              _handleCanvasTap(_transformToCanvasCoordinates(details.localPosition));
                            }
                          },
                          child: CustomPaint(
                            painter: PrescriptionPainter(
                              drawingPage: _viewablePages[index],
                              templateUiImage: _currentTemplateUiImage,
                              // editingTextId: _editingTextId, // Removed
                              selectedImageId: _selectedImageId,
                              redrawNotifier: _redrawNotifier,
                            ),
                            child: const SizedBox(width: canvasWidth, height: canvasHeight),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // if (_editingTextId != null) _buildTextFieldOverlay(), // Removed text overlay
                if (_selectedImageId != null) _buildImageOverlayControls(), // Image manipulation controls
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageOverlayControls() {
    if (_selectedImageId == null) return const SizedBox.shrink();

    final currentPage = _viewablePages[_currentPageIndex];
    final selectedImage = currentPage.images.firstWhere((img) => img.id == _selectedImageId);

    final matrix = _transformationController.value;
    final screenOffset = Matrix4Utils.transformPoint(matrix, selectedImage.position);
    final currentScale = matrix.getMaxScaleOnAxis();

    final scaledWidth = selectedImage.width * currentScale;
    final scaledHeight = selectedImage.height * currentScale;

    // The handles are placed around the image in screen coordinates.
    // We use a small offset from the image boundary.

    // 1. Resize Controls (Top Right corner)
    final resizeControls = Positioned(
      left: screenOffset.dx + scaledWidth,
      top: screenOffset.dy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageControlIcon(Icons.add, () => _resizeSelectedImage(kImageResizeStep), tooltip: 'Increase Size'),
          const SizedBox(height: 4),
          _buildImageControlIcon(Icons.remove, () => _resizeSelectedImage(-kImageResizeStep), tooltip: 'Decrease Size'),
        ],
      ),
    );

    // 2. Move Control (Top Left corner)
    final moveControl = Positioned(
      left: screenOffset.dx - kImageHandleSize,
      top: screenOffset.dy - kImageHandleSize,
      child: _buildImageControlIcon(
        _isMovingSelectedImage ? Icons.lock_open_rounded : Icons.open_with,
            () => setState(() {
          _isMovingSelectedImage = !_isMovingSelectedImage;
          _selectedTool = DrawingTool.image; // Ensure tool is set to image
          if (!_isMovingSelectedImage) _dragStartCanvasPosition = null; // Reset drag state
        }),
        tooltip: _isMovingSelectedImage ? 'Exit Move Mode (Pan/Zoom Enabled)' : 'Enter Move Mode (Pan/Zoom Disabled)',
        color: _isMovingSelectedImage ? Colors.red : primaryBlue,
      ),
    );

    // 3. Delete Control (Bottom Left corner)
    final deleteControl = Positioned(
      left: screenOffset.dx - kImageHandleSize,
      top: screenOffset.dy + scaledHeight,
      child: _buildImageControlIcon(Icons.delete_forever, () {
        setState(() {
          _viewablePages[_currentPageIndex] = currentPage.copyWith(
            images: currentPage.images.where((img) => img.id != _selectedImageId).toList(),
          );
          _selectedImageId = null;
          _isMovingSelectedImage = false;
        });
        _debouncedSave();
      }, tooltip: 'Delete Image', color: Colors.red),
    );

    return Stack(
      children: [
        resizeControls,
        moveControl,
        deleteControl,
      ],
    );
  }

  Widget _buildImageControlIcon(IconData icon, VoidCallback onPressed, {String tooltip = '', Color color = primaryBlue}) {
    // Uses Transform.scale to compensate for global zoom effect on the small fixed-size buttons
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
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
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(2, 2))],
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

  Widget _buildPageActionsMenu() {
    return PopupMenuButton<String>(
      onSelected: (String value) {
        if (value == 'copy') _copyPageContent();
        else if (value == 'paste') _pastePageContent();
        else if (value == 'camera') _pickAndUploadImage(ImageSource.camera);
        else if (value == 'gallery') _pickAndUploadImage(ImageSource.gallery);
        else if (value == 'uploaded') _showUploadedImagesSelector();
      },
      icon: const Icon(Icons.more_vert, color: primaryBlue),
      tooltip: 'Page Actions',
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'copy', child: ListTile(leading: Icon(Icons.copy_all_rounded), title: Text('Copy Page'))),
        if (_copiedPageData != null)
          const PopupMenuItem<String>(value: 'paste', child: ListTile(leading: Icon(Icons.paste_rounded), title: Text('Paste on Page'))),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt_rounded), title: Text('Insert from Camera'))),
        const PopupMenuItem<String>(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library_rounded), title: Text('Insert from Gallery'))),
        const PopupMenuItem<String>(value: 'uploaded', child: ListTile(leading: Icon(Icons.cloud_upload_rounded), title: Text('Pick from Uploaded'))),
      ],
    );
  }

  // Widget _buildTextFieldOverlay() { ... } // Removed

  Widget _buildDrawingToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: [_selectedTool == DrawingTool.pen, _selectedTool == DrawingTool.eraser, _selectedTool == DrawingTool.image], // Removed text
            onPressed: (index) {
              HapticFeedback.selectionClick();
              setState(() {
                // _commitTextChanges(); // Removed
                _selectedImageId = null; // Deselect on tool change
                _isMovingSelectedImage = false; // Exit move mode on tool change
                if (index == 0) _selectedTool = DrawingTool.pen;
                else if (index == 1) _selectedTool = DrawingTool.eraser;
                else _selectedTool = DrawingTool.image; // Now index 2 is image
              });
            },
            borderRadius: BorderRadius.circular(8),
            selectedBorderColor: primaryBlue,
            fillColor: primaryBlue,
            color: mediumGreyText,
            selectedColor: Colors.white,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            children: const [
              Tooltip(message: "Pen", child: Icon(Icons.edit, size: 20)),
              Tooltip(message: "Eraser", child: Icon(Icons.cleaning_services, size: 20)),
              // Tooltip(message: "Text", child: Icon(Icons.text_fields_rounded, size: 20)), // Removed text tool
              Tooltip(message: "Image Select/Move", child: Icon(Icons.photo_library_outlined, size: 20)),
            ],
          ),
          const SizedBox(width: 16),
          if (_selectedTool != DrawingTool.image)
            ...[Colors.black, Colors.blue, Colors.red, Colors.green].map((color) => _buildColorOption(color)).toList(),

          if (_selectedTool == DrawingTool.pen || _selectedTool == DrawingTool.eraser)
            Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.line_weight, size: 20, color: mediumGreyText),
                SizedBox(
                  width: 100,
                  child: Slider(
                    value: _strokeWidth,
                    min: 1.0,
                    max: 10.0,
                    divisions: 9,
                    onChanged: (value) => setState(() => _strokeWidth = value),
                    activeColor: primaryBlue,
                  ),
                ),
              ],
            ),

          // Text size slider removed
          // if (_selectedTool == DrawingTool.text)
          //   Row(
          //     children: [
          //       const Icon(Icons.format_size, size: 20, color: mediumGreyText),
          //       SizedBox(
          //         width: 120,
          //         child: Slider(
          //           value: _currentFontSize,
          //           min: 10.0,
          //           max: 60.0,
          //           divisions: 10,
          //           onChanged: (value) => setState(() => _currentFontSize = value),
          //           activeColor: primaryBlue,
          //         ),
          //       ),
          //     ],
          //   ),
          const SizedBox(width: 24),
          IconButton(icon: const Icon(Icons.undo_rounded, color: primaryBlue, size: 22), onPressed: _undoLastAction, tooltip: "Undo"),
          IconButton(icon: const Icon(Icons.delete_sweep_rounded, color: primaryBlue, size: 22), onPressed: _clearAllDrawings, tooltip: "Clear All"),
        ],
      ),
    );
  }

  Widget _buildPanToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(onPressed: _zoomIn, icon: const Icon(Icons.zoom_in), tooltip: "Zoom In"),
        IconButton(onPressed: _zoomOut, icon: const Icon(Icons.zoom_out), tooltip: "Zoom Out"),
        IconButton(onPressed: _resetZoom, icon: const Icon(Icons.zoom_out_map), tooltip: "Reset Zoom"),
      ],
    );
  }

  Widget _buildColorOption(Color color) {
    bool isSelected = _currentColor == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: GestureDetector(
        onTap: () => setState(() => _currentColor = color),
        child: Tooltip(
          message: color.toString(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected ? Border.all(color: primaryBlue, width: 2.5) : Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
          ),
        ),
      ),
    );
  }
}

class PrescriptionPainter extends CustomPainter {
  final DrawingPage drawingPage;
  final ui.Image? templateUiImage;
  // final String? editingTextId; // Removed
  final String? selectedImageId;
  final ValueNotifier<int> redrawNotifier;

  PrescriptionPainter({required this.drawingPage, this.templateUiImage, required this.redrawNotifier, this.selectedImageId}) : super(repaint: redrawNotifier); // Removed editingTextId

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Template/Background
    if (templateUiImage != null) {
      paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, size.width, size.height), image: templateUiImage!, fit: BoxFit.contain, alignment: Alignment.center);
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.grey[200]!);
    }

    // 2. Draw Images
    for (var image in drawingPage.images) {
      ImageCacheManager.loadImage(image.imageUrl).then((ui.Image? loadedImage) {
        if (loadedImage != null) {
          // Trigger repaint if image was loaded async
          if (redrawNotifier.value == 0) redrawNotifier.value = 1; else redrawNotifier.value = 0;
        }
      });

      final cachedImage = ImageCacheManager._cache[image.imageUrl];
      final destRect = Rect.fromLTWH(image.position.dx, image.position.dy, image.width, image.height);

      if (cachedImage != null) {
        paintImage(
            canvas: canvas,
            rect: destRect,
            image: cachedImage,
            fit: BoxFit.contain,
            alignment: Alignment.topLeft
        );
      } else {
        // Draw a placeholder while loading
        canvas.drawRect(destRect, Paint()..color = Colors.grey.withOpacity(0.5));
        final textPainter = TextPainter(
          text: const TextSpan(text: 'Loading...', style: TextStyle(color: Colors.black, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, image.position.translate(5, 5));
      }

      // Draw selection border if selected
      if (image.id == selectedImageId) {
        final borderPaint = Paint()
          ..color = primaryBlue
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke;
        canvas.drawRect(destRect.inflate(2.0), borderPaint);
      }
    }

    // 3. Draw Lines/Drawings
    for (var line in drawingPage.lines) {
      final paint = Paint()
        ..color = Color(line.colorValue)
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (line.points.length > 1) {
        final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);
        for (int i = 1; i < line.points.length; i++) {
          path.lineTo(line.points[i].dx, line.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 4. Draw Texts - REMOVED
    // for (var text in drawingPage.texts) {
    //   if (text.id == editingTextId) continue;
    //   final textSpan = TextSpan(
    //     text: text.text,
    //     style: TextStyle(color: Color(text.colorValue), fontSize: text.fontSize, fontWeight: FontWeight.w500),
    //   );
    //   final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout(minWidth: 0, maxWidth: canvasWidth - text.position.dx);
    //   textPainter.paint(canvas, text.position);
    // }
  }

  @override
  bool shouldRepaint(covariant PrescriptionPainter oldDelegate) {
    // Removed editingTextId from comparison
    return oldDelegate.drawingPage != drawingPage || oldDelegate.templateUiImage != templateUiImage || oldDelegate.selectedImageId != selectedImageId;
  }
}