import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart'; // Make sure you have this file configured

// --- Top-Level Constants ---
const double canvasWidth = 1000;
const double canvasHeight = 1414;
const String kBaseImageUrl = 'https://apimmedford.infispark.in/';

// --- Unified & Highly Compressed Data Models ---

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
        // OLD UNCOMPRESSED FORMAT: [{'dx': 123.45, 'dy': 678.90}]
        for (var pointJson in pointsData) {
          if (pointJson is Map) {
            pointsList.add(Offset(
              (pointJson['dx'] as num?)?.toDouble() ?? 0.0,
              (pointJson['dy'] as num?)?.toDouble() ?? 0.0,
            ));
          }
        }
      } else if (pointsData[0] is num) {
        // NEW COMPRESSED FORMAT (Delta Encoded Integers): [x1, y1, dx2, dy2, ...]
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

    // 1. Simplify the line first (highest impact). Epsilon = 1.0 is a good balance.
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

class DrawingText {
  final String id;
  final String text;
  final Offset position;
  final int colorValue;
  final double fontSize;

  DrawingText({
    required this.id,
    required this.text,
    required this.position,
    required this.colorValue,
    required this.fontSize,
  });

  DrawingText copyWith({
    String? id,
    String? text,
    Offset? position,
    int? colorValue,
    double? fontSize,
  }) {
    return DrawingText(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  factory DrawingText.fromJson(Map<String, dynamic> json) {
    return DrawingText(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      position: Offset(
        (json['position']?['dx'] as num?)?.toDouble() ?? 0.0,
        (json['position']?['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      colorValue: (json['colorValue'] as int?) ?? Colors.black.value,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'position': {'dx': position.dx, 'dy': position.dy},
      'colorValue': colorValue,
      'fontSize': fontSize,
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
  final List<DrawingText> texts;

  DrawingPage({
    required this.id,
    required this.pageNumber,
    required this.pageName,
    required this.groupName,
    required this.templateImageUrl,
    this.lines = const [],
    this.texts = const [],
  });

  DrawingPage copyWith({
    String? id,
    int? pageNumber,
    String? pageName,
    String? groupName,
    String? templateImageUrl,
    List<DrawingLine>? lines,
    List<DrawingText>? texts,
  }) {
    return DrawingPage(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      pageName: pageName ?? this.pageName,
      groupName: groupName ?? this.groupName,
      templateImageUrl: templateImageUrl ?? this.templateImageUrl,
      lines: lines ?? this.lines,
      texts: texts ?? this.texts,
    );
  }

  factory DrawingPage.fromJson(Map<String, dynamic> json) {
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
      texts: (json['texts'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((textJson) => DrawingText.fromJson(textJson))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pageNumber': pageNumber,
      'pageName': pageName,
      'groupName': groupName,
      'templateImageUrl': templateImageUrl,
      'lines': lines.map((line) => line.toJson()).toList(),
      'texts': texts.map((text) => text.toJson()).toList(),
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

enum DrawingTool { pen, eraser, text }

class _CopiedPageData {
  final List<DrawingLine> lines;
  final List<DrawingText> texts;
  _CopiedPageData({required this.lines, required this.texts});
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

  // --- Data State ---
  List<DrawingPage> _viewablePages = [];
  int _currentPageIndex = 0;
  String? _healthRecordId;
  DrawingGroup? _currentGroup;
  List<DrawingPage> _pagesInCurrentGroup = [];
  _CopiedPageData? _copiedPageData;

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
  double _currentFontSize = 20.0;
  DrawingTool _selectedTool = DrawingTool.pen;

  // --- Text Editing State ---
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  String? _editingTextId;

  // --- View State ---
  final PageController _pageController = PageController();
  final TransformationController _transformationController = TransformationController();
  ui.Image? _currentTemplateUiImage;
  bool _isLoadingPrescription = true;
  bool _isSaving = false;
  bool _isInitialZoomSet = false;
  bool _isStylusInteraction = false;
  final bool _isPenOnlyMode = true;

  // --- Autosave & Realtime State ---
  Timer? _debounceTimer;
  RealtimeChannel? _healthRecordChannel;
  DateTime? _lastSuccessfulSaveTime;
  bool _isDisposed = false;

  // --- Constants ---
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mediumGreyText = Color(0xFF64748B);
  static const Color lightBackground = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadHealthDetailsAndPage();
    _transformationController.addListener(_onTransformUpdated);
    _textFocusNode.addListener(_onTextFocusChange);
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
    _textController.dispose();
    _textFocusNode.removeListener(_onTextFocusChange);
    _textFocusNode.dispose();
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
              backgroundColor: Colors.blue,
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
    _commitTextChanges();
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
          // Changed text:
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

  // --- Pointer and Interaction Handlers ---

  void _handlePointerDown(PointerDownEvent details) {
    _commitTextChanges();
    setState(() => _isStylusInteraction = details.kind == ui.PointerDeviceKind.stylus);
    if (!_isPenOnlyMode || !_isStylusInteraction) return;
    final transformedPosition = _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    if (_selectedTool == DrawingTool.pen) {
      setState(() {
        final currentPage = _viewablePages[_currentPageIndex];
        final newLine = DrawingLine(points: [transformedPosition], colorValue: _currentColor.value, strokeWidth: _strokeWidth);
        _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: [...currentPage.lines, newLine]);
      });
    } else if (_selectedTool == DrawingTool.text) {
      _handleTextTap(transformedPosition);
    }
  }

  void _handlePointerMove(PointerMoveEvent details) {
    if (!_isPenOnlyMode || !_isStylusInteraction) return;
    final transformedPosition = _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

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

  void _handlePointerUp(PointerUpEvent details) {
    if (_isStylusInteraction) {
      _debouncedSave();
      setState(() => _isStylusInteraction = false);
    }
  }

  // --- Text Handling ---

  void _onTransformUpdated() => setState(() {});

  void _onTextFocusChange() {
    if (!_textFocusNode.hasFocus) _commitTextChanges();
  }

  void _commitTextChanges() {
    if (_editingTextId == null) return;
    String oldText = "";
    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];
      final textIndex = currentPage.texts.indexWhere((t) => t.id == _editingTextId);
      if (textIndex != -1) {
        oldText = currentPage.texts[textIndex].text;
        final updatedTexts = List<DrawingText>.from(currentPage.texts);
        if (_textController.text.trim().isEmpty) {
          updatedTexts.removeAt(textIndex);
        } else {
          updatedTexts[textIndex] = updatedTexts[textIndex].copyWith(text: _textController.text);
        }
        _viewablePages[_currentPageIndex] = currentPage.copyWith(texts: updatedTexts);
        if (oldText != _textController.text) {
          _debouncedSave();
        }
      }
      _editingTextId = null;
      _textController.clear();
    });
  }

  void _handleTextTap(Offset canvasPosition) {
    _commitTextChanges();
    final currentPage = _viewablePages[_currentPageIndex];
    DrawingText? tappedText;

    for (final text in currentPage.texts) {
      final textRect = Rect.fromLTWH(text.position.dx, text.position.dy - text.fontSize, text.fontSize * text.text.length * 0.6, text.fontSize * 2);
      if (textRect.contains(canvasPosition)) {
        tappedText = text;
        break;
      }
    }

    setState(() {
      if (tappedText != null) {
        _editingTextId = tappedText.id;
        _textController.text = tappedText.text;
        _currentColor = Color(tappedText.colorValue);
        _currentFontSize = tappedText.fontSize;
        _textFocusNode.requestFocus();
      } else {
        final newText = DrawingText(id: generateUniqueId(), text: "", position: canvasPosition, colorValue: _currentColor.value, fontSize: _currentFontSize);
        _viewablePages[_currentPageIndex] = currentPage.copyWith(texts: [...currentPage.texts, newText]);
        _editingTextId = newText.id;
        _textController.clear();
        _textFocusNode.requestFocus();
      }
    });
  }

  // --- Utility & Action Methods ---

  void _copyPageContent() {
    if (_viewablePages.isEmpty) return;
    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _copiedPageData = _CopiedPageData(
        lines: currentPage.lines.map((line) => line.copyWith()).toList(),
        texts: currentPage.texts.map((text) => text.copyWith()).toList(),
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
      final pastedTextsWithNewIds = _copiedPageData!.texts.map((textToCopy) => textToCopy.copyWith(id: generateUniqueId())).toList();
      _viewablePages[_currentPageIndex] = currentPage.copyWith(
        lines: [...currentPage.lines, ..._copiedPageData!.lines],
        texts: [...currentPage.texts, ...pastedTextsWithNewIds],
      );
    });
    _debouncedSave();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Content pasted!'), backgroundColor: Colors.blue, duration: Duration(seconds: 2)));
  }

  void _undoLastAction() {
    HapticFeedback.lightImpact();
    if (_viewablePages.isEmpty || _viewablePages[_currentPageIndex].lines.isEmpty) return;
    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];
      final newLines = List<DrawingLine>.from(currentPage.lines)..removeLast();
      _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: newLines);
    });
    _debouncedSave();
  }

  void _clearAllDrawings() {
    HapticFeedback.mediumImpact();
    if (_viewablePages.isEmpty) return;
    setState(() {
      _viewablePages[_currentPageIndex] = _viewablePages[_currentPageIndex].copyWith(lines: [], texts: []);
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
      _commitTextChanges();
      if (_pageController.hasClients) _pageController.jumpToPage(index);
      setState(() {
        _currentPageIndex = index;
        _isInitialZoomSet = false;
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
                          _commitTextChanges();
                          setState(() {
                            _viewablePages = newViewablePages;
                            _currentPageIndex = newPageIndex;
                            _isInitialZoomSet = false;
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
    _commitTextChanges();
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
            _buildCopyPasteMenu(),
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
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerUp,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _viewablePages.length,
                    onPageChanged: (index) async {
                      _commitTextChanges();
                      setState(() {
                        _currentPageIndex = index;
                        _isInitialZoomSet = false;
                        _transformationController.value = Matrix4.identity();
                      });
                      await _loadTemplateUiImage(_viewablePages[index].templateImageUrl);
                    },
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        panEnabled: !_isStylusInteraction,
                        scaleEnabled: !_isStylusInteraction,
                        minScale: 0.1,
                        maxScale: 10.0,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        child: CustomPaint(
                          painter: PrescriptionPainter(
                            drawingPage: _viewablePages[index],
                            templateUiImage: _currentTemplateUiImage,
                            editingTextId: _editingTextId,
                          ),
                          child: const SizedBox(width: canvasWidth, height: canvasHeight),
                        ),
                      );
                    },
                  ),
                ),
                if (_editingTextId != null) _buildTextFieldOverlay(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCopyPasteMenu() {
    return PopupMenuButton<String>(
      onSelected: (String value) {
        if (value == 'copy') _copyPageContent();
        else if (value == 'paste') _pastePageContent();
      },
      icon: const Icon(Icons.more_vert, color: primaryBlue),
      tooltip: 'Page Actions',
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'copy', child: ListTile(leading: Icon(Icons.copy_all_rounded), title: Text('Copy Page'))),
        if (_copiedPageData != null)
          const PopupMenuItem<String>(value: 'paste', child: ListTile(leading: Icon(Icons.paste_rounded), title: Text('Paste on Page'))),
      ],
    );
  }

  Widget _buildTextFieldOverlay() {
    if (_editingTextId == null) return const SizedBox.shrink();
    final currentPage = _viewablePages[_currentPageIndex];
    final textToEdit = currentPage.texts.firstWhere((t) => t.id == _editingTextId, orElse: () => DrawingText(id: '', text: '', position: Offset.zero, colorValue: 0, fontSize: 0));
    if (textToEdit.id.isEmpty) return const SizedBox.shrink();

    final matrix = _transformationController.value;
    final canvasOffset = textToEdit.position;
    final screenOffset = MatrixUtils.transformPoint(matrix, canvasOffset);
    final currentScale = matrix.getMaxScaleOnAxis();
    final scaledFontSize = textToEdit.fontSize * currentScale;

    return Positioned(
      left: screenOffset.dx,
      top: screenOffset.dy,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - screenOffset.dx - 20),
        child: IntrinsicWidth(
          child: TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true),
            style: TextStyle(fontSize: scaledFontSize, color: Color(textToEdit.colorValue), decoration: TextDecoration.none, decorationThickness: 0),
            onSubmitted: (_) => _commitTextChanges(),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: [_selectedTool == DrawingTool.pen, _selectedTool == DrawingTool.eraser, _selectedTool == DrawingTool.text],
            onPressed: (index) {
              HapticFeedback.selectionClick();
              setState(() {
                _commitTextChanges();
                if (index == 0) _selectedTool = DrawingTool.pen;
                else if (index == 1) _selectedTool = DrawingTool.eraser;
                else _selectedTool = DrawingTool.text;
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
              Tooltip(message: "Text", child: Icon(Icons.text_fields_rounded, size: 20)),
            ],
          ),
          const SizedBox(width: 16),
          ...[Colors.black, Colors.blue, Colors.red, Colors.green].map((color) => _buildColorOption(color)).toList(),
          const SizedBox(width: 16),
          if (_selectedTool == DrawingTool.text)
            Row(
              children: [
                const Icon(Icons.format_size, size: 20, color: mediumGreyText),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: _currentFontSize,
                    min: 10.0,
                    max: 60.0,
                    divisions: 10,
                    onChanged: (value) => setState(() => _currentFontSize = value),
                    activeColor: primaryBlue,
                  ),
                ),
              ],
            ),
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
  final String? editingTextId;

  PrescriptionPainter({required this.drawingPage, this.templateUiImage, this.editingTextId});

  @override
  void paint(Canvas canvas, Size size) {
    if (templateUiImage != null) {
      paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, size.width, size.height), image: templateUiImage!, fit: BoxFit.contain, alignment: Alignment.center);
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.grey[200]!);
    }

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

    for (var text in drawingPage.texts) {
      if (text.id == editingTextId) continue;
      final textSpan = TextSpan(
        text: text.text,
        style: TextStyle(color: Color(text.colorValue), fontSize: text.fontSize, fontWeight: FontWeight.w500),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout(minWidth: 0, maxWidth: canvasWidth - text.position.dx);
      textPainter.paint(canvas, text.position);
    }
  }

  @override
  bool shouldRepaint(covariant PrescriptionPainter oldDelegate) {
    return oldDelegate.drawingPage != drawingPage || oldDelegate.templateUiImage != templateUiImage || oldDelegate.editingTextId != editingTextId;
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
    return w == 1.0 ? Offset(x, y) : Offset(x / w, y / w);
  }
}