import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'supabase_config.dart';
import 'prescription_page.dart';
import 'patient_documents_page.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' show Offset, Color;

// --- UNIFIED & HIGHLY COMPRESSED DATA MODELS ---

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

    final simplifiedPoints = simplify(points, 1.0);
    if (simplifiedPoints.isEmpty) {
      return {'points': [], 'colorValue': colorValue, 'strokeWidth': strokeWidth};
    }

    final compressedPoints = <int>[];
    int lastX = (simplifiedPoints.first.dx * 100).round();
    int lastY = (simplifiedPoints.first.dy * 100).round();
    compressedPoints.add(lastX);
    compressedPoints.add(lastY);

    for (int i = 1; i < simplifiedPoints.length; i++) {
      int currentX = (simplifiedPoints[i].dx * 100).round();
      int currentY = (simplifiedPoints[i].dy * 100).round();
      compressedPoints.add(currentX - lastX);
      compressedPoints.add(currentY - lastY);
      lastX = currentX;
      lastY = currentY;
    }

    return {
      'points': compressedPoints,
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
    };
  }

  DrawingLine copyWith({List<Offset>? points}) {
    return DrawingLine(
      points: points ?? this.points,
      colorValue: colorValue,
      strokeWidth: strokeWidth,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'position': {'dx': position.dx, 'dy': position.dy},
    'colorValue': colorValue,
    'fontSize': fontSize,
  };

  factory DrawingText.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>? ?? {'dx': 0.0, 'dy': 0.0};
    return DrawingText(
      id: json['id'] as String? ?? generateUniqueId(),
      text: json['text'] as String? ?? '',
      position: Offset(
        (positionJson['dx'] as num?)?.toDouble() ?? 0.0,
        (positionJson['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? Colors.black.value,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
    );
  }

  DrawingText copyWith({
    String? text,
    Offset? position,
    int? colorValue,
    double? fontSize,
  }) {
    return DrawingText(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

class DrawingPage {
  final String id;
  final String templateImageUrl;
  final int pageNumber;
  final String pageName;
  final String groupName;
  final List<DrawingLine> lines;
  final List<DrawingText> texts;

  DrawingPage({
    required this.id,
    required this.templateImageUrl,
    required this.pageNumber,
    required this.pageName,
    required this.groupName,
    this.lines = const [],
    this.texts = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateImageUrl': templateImageUrl,
    'pageNumber': pageNumber,
    'pageName': pageName,
    'groupName': groupName,
    'lines': lines.map((line) => line.toJson()).toList(),
    'texts': texts.map((text) => text.toJson()).toList(),
  };

  factory DrawingPage.fromJson(Map<String, dynamic> json) {
    return DrawingPage(
      id: json['id'] as String? ?? generateUniqueId(),
      templateImageUrl: json['templateImageUrl'] as String? ?? '',
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
      pageName: json['pageName'] as String? ?? 'Unnamed Page',
      groupName: json['groupName'] as String? ?? 'Uncategorized',
      lines: (json['lines'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((lineJson) => DrawingLine.fromJson(lineJson))
          .toList() ?? [],
      texts: (json['texts'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((textJson) => DrawingText.fromJson(textJson))
          .toList() ?? [],
    );
  }

  DrawingPage copyWith({List<DrawingLine>? lines, String? pageName, List<DrawingText>? texts}) {
    return DrawingPage(
      id: id,
      templateImageUrl: templateImageUrl,
      pageNumber: pageNumber,
      pageName: pageName ?? this.pageName,
      groupName: groupName,
      lines: lines ?? this.lines,
      texts: texts ?? this.texts,
    );
  }
}

class DrawingGroup {
  final String id;
  final String groupName;
  final List<DrawingPage> pages;

  DrawingGroup({
    required this.id,
    required this.groupName,
    this.pages = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupName': groupName,
    'pages': pages.map((page) => page.toJson()).toList(),
  };

  factory DrawingGroup.fromJson(Map<String, dynamic> json) {
    return DrawingGroup(
      id: json['id'] as String? ?? generateUniqueId(),
      groupName: json['groupName'] as String? ?? 'indoor patients progress',
      pages: (json['pages'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((pageJson) => DrawingPage.fromJson(pageJson))
          .toList() ?? [],
    );
  }

  DrawingGroup copyWith({String? groupName, List<DrawingPage>? pages}) {
    return DrawingGroup(
      id: id,
      groupName: groupName ?? this.groupName,
      pages: pages ?? this.pages,
    );
  }
}

// --- End of Data Models ---

class SupabaseTemplateImage {
  final String id;
  final String name;
  final String url;
  final String? url2;
  final bool isbook;
  final List<String> bookImgUrl;
  final String? tag;

  SupabaseTemplateImage({
    required this.id,
    required this.name,
    required this.url,
    this.url2,
    required this.isbook,
    required this.bookImgUrl,
    this.tag,
  });

  // UPDATED: Handles book_img_url being a JSON string or a list
  factory SupabaseTemplateImage.fromJson(Map<String, dynamic> json) {
    final bookUrlsRaw = json['book_img_url'];
    List<String> bookUrls = [];
    if (bookUrlsRaw is List) {
      bookUrls = bookUrlsRaw.map((e) => e.toString()).toList();
    } else if (bookUrlsRaw is String && bookUrlsRaw.startsWith('[') && bookUrlsRaw.endsWith(']')) {
      try {
        final decoded = jsonDecode(bookUrlsRaw) as List<dynamic>;
        bookUrls = decoded.map((e) => e.toString()).toList();
      } catch (e) {
        debugPrint('Could not parse book_img_url string: $e');
      }
    }

    return SupabaseTemplateImage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Template',
      url: json['url'] as String? ?? '',
      url2: json['2url'] as String?,
      isbook: json['isbook'] as bool? ?? false,
      bookImgUrl: bookUrls,
      tag: json['tag'] as String?,
    );
  }
}

// --- The ManageIpdPatientPage Widget ---

class ManageIpdPatientPage extends StatefulWidget {
  final int ipdId;
  final String uhid;

  const ManageIpdPatientPage({
    super.key,
    required this.ipdId,
    required this.uhid,
  });

  @override
  State<ManageIpdPatientPage> createState() => _ManageIpdPatientPageState();
}

class _ManageIpdPatientPageState extends State<ManageIpdPatientPage> {
  final SupabaseClient supabase = SupabaseConfig.client;
  List<DrawingGroup> _drawingGroups = [];
  String? _healthRecordId;
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';
  List<SupabaseTemplateImage> _availableTemplates = [];
  String? _patientName;
  String? _roomType;

  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mediumGreyText = Color(0xFF64748B);
  static const Color lightBackground = Color(0xFFF8FAFC);


  // 1. MAP GROUP NAME TO DATABASE COLUMN NAME
  static const Map<String, String> _groupToColumnMap = {
    'Indoor Patient File': 'indoor_patient_file_data',
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

  };

  // 2. LIST OF ALL COLUMNS TO SELECT FROM THE DB (FIXED CONST ERROR)
  static final List<String> _allDataColumns = [
    'id',
    'ipd_registration_id',
    'patient_uhid',
    'updated_at',
    ..._groupToColumnMap.values, // .values is not const, so the list cannot be const
    'custom_groups_data',
  ];


  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final patientDetailsResponse = await supabase
          .from('ipd_registration')
          .select('uhid, patient:patient_detail(name), bed:bed_management(room_type, bed_number)')
          .eq('ipd_id', widget.ipdId)
          .single();

      final patientData = patientDetailsResponse['patient'];
      _patientName = (patientData != null) ? patientData['name'] as String? : 'N/A';

      final bedData = patientDetailsResponse['bed'];
      _roomType = (bedData != null)
          ? '${bedData['room_type'] ?? 'N/A'} - Bed: ${bedData['bed_number'] ?? 'N/A'}'
          : 'N/A';

      final List<Map<String, dynamic>> templateData =
      await supabase.from('template_images').select('id, name, url, 2url, isbook, book_img_url, tag');
      _availableTemplates = templateData.map((json) => SupabaseTemplateImage.fromJson(json)).toList();

      // --- START: NEW LOADING LOGIC ---
      final response = await supabase
          .from('user_health_details')
          .select(_allDataColumns.join(','))
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      final List<DrawingGroup> loadedGroups = [];

      if (response != null) {
        _healthRecordId = response['id'] as String;

        // 1. Load Default Groups from their specific columns
        for (final entry in _groupToColumnMap.entries) {
          final groupName = entry.key;
          final columnName = entry.value;

          final List<dynamic> rawPages = response[columnName] ?? [];
          final pages = rawPages
              .whereType<Map<String, dynamic>>()
              .map((json) => DrawingPage.fromJson(json))
              .toList();

          // Pages loaded from individual columns don't contain the groupName property,
          // so we map it back in the DrawingPage constructor if necessary, but
          // here we ensure the DrawingGroup is correctly formed.
          final pagesWithGroupName = pages.map((page) => page.copyWith(pageName: page.pageName, lines: page.lines)).toList();


          loadedGroups.add(DrawingGroup(
            id: generateUniqueId(),
            groupName: groupName,
            pages: pagesWithGroupName,
          ));
        }

        // 2. Load Custom Groups
        final List<dynamic> rawCustomGroups = response['custom_groups_data'] ?? [];
        loadedGroups.addAll(
            rawCustomGroups.whereType<Map<String, dynamic>>().map((json) => DrawingGroup.fromJson(json)).toList());

        setState(() {
          _drawingGroups = loadedGroups;
        });

      } else {
        debugPrint('No existing health records found. Creating default groups.');
        await _createAndSaveDefaultGroups();
        debugPrint('Default groups created and saved.');
      }
      // --- END: NEW LOADING LOGIC ---
    } on PostgrestException catch (e) {
      _showErrorSnackbar('Error loading data: ${e.message}');
    } catch (e) {
      _showErrorSnackbar('Failed to load IPD records: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createAndSaveDefaultGroups() async {
    final groupNames = _groupToColumnMap.keys.toList();

    final defaultGroups =
    groupNames.map((name) => DrawingGroup(id: generateUniqueId(), groupName: name, pages: [])).toList();

    setState(() {
      _drawingGroups = defaultGroups;
      _healthRecordId = null;
    });

    // Save ALL details since this is the initial creation
    await _saveHealthDetails();
  }


  // --- START: UPDATED SAVING LOGIC ---
  Future<void> _saveHealthDetails({String? changedGroupName}) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });
    try {
      final Map<String, dynamic> dataToSave = {};
      final List<DrawingGroup> customGroups = [];

      // 1. Separate Default and Custom Groups & prepare data map
      for (final group in _drawingGroups) {
        final columnName = _groupToColumnMap[group.groupName];

        if (columnName != null) {
          // Default group: Prepare pages for its dedicated column
          // Only prepare the data if it's the changed group or if we are doing a full save (initial creation)
          if (changedGroupName == null || group.groupName == changedGroupName) {
            // Store only the pages array, NOT the full DrawingGroup object
            final List<Map<String, dynamic>> pagesJson = group.pages.map((page) => page.toJson()).toList();
            dataToSave[columnName] = pagesJson;
          }
        } else {
          // Custom group: Collect to save in the 'custom_groups_data' column
          customGroups.add(group);
        }
      }

      // 2. Prepare Custom Groups for saving
      // Save custom groups if a custom group was changed or if doing a full save
      if (changedGroupName == null || (_groupToColumnMap[changedGroupName] == null && changedGroupName != null)) {
        dataToSave['custom_groups_data'] = customGroups.map((group) => group.toJson()).toList();
      } else if (changedGroupName == null) {
        // Full save, including custom groups
        dataToSave['custom_groups_data'] = customGroups.map((group) => group.toJson()).toList();
      }

      // 3. Add mandatory metadata
      dataToSave['ipd_registration_id'] = widget.ipdId;
      dataToSave['patient_uhid'] = widget.uhid;
      dataToSave['updated_at'] = DateTime.now().toIso8601String();
      if (_healthRecordId != null) {
        dataToSave['id'] = _healthRecordId;
      }

      // 4. Perform Upsert
      final List<Map<String, dynamic>> response = await supabase
          .from('user_health_details')
          .upsert(dataToSave, onConflict: 'ipd_registration_id, patient_uhid').select('id');

      if (response.isNotEmpty && response[0]['id'] != null) {
        if (mounted && _healthRecordId == null) {
          _healthRecordId = response[0]['id'] as String;
        }
      } else {
        throw Exception('Failed to save details (no ID returned).');
      }
    } on PostgrestException catch (e) {
      _showErrorSnackbar('Supabase Error: ${e.message}');
    } catch (e) {
      _showErrorSnackbar('Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  // --- END: UPDATED SAVING LOGIC ---


  void _createNewGroup() {
    TextEditingController groupNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Create New Group",
              style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
          content: TextField(
            controller: groupNameController,
            decoration: InputDecoration(
              hintText: "Enter group name",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: primaryBlue, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 15),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("Create"),
              onPressed: () {
                if (groupNameController.text.isNotEmpty) {
                  final newGroupName = groupNameController.text;
                  setState(() {
                    _drawingGroups.add(DrawingGroup(
                      id: generateUniqueId(),
                      groupName: newGroupName,
                      pages: [],
                    ));
                  });
                  // Save all data since a new custom group was added
                  _saveHealthDetails(changedGroupName: newGroupName);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // --- NEW: Page Addition Logic ---

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  SupabaseTemplateImage? _findTemplateByTag(String tag) {
    try {
      return _availableTemplates.firstWhere((t) => t.tag == tag);
    } catch (e) {
      _showErrorSnackbar('Required template with tag "$tag" not found.');
      return null;
    }
  }

  SupabaseTemplateImage? _findTemplateByName(String name) {
    try {
      return _availableTemplates.firstWhere((t) => t.name == name);
    } catch (e) {
      _showErrorSnackbar('Required template with name "$name" not found.');
      return null;
    }
  }

  void _addSinglePage(DrawingGroup group, String tag, String pageNamePrefix) {
    final template = _findTemplateByTag(tag);
    if (template == null) return;

    final newPageNumber = group.pages.length + 1;
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());
    final newPageName = '$pageNamePrefix $newPageNumber - $formattedDate';

    final newPage = DrawingPage(
      id: generateUniqueId(),
      templateImageUrl: template.url,
      pageNumber: newPageNumber,
      pageName: newPageName,
      groupName: group.groupName,
    );
    _addPagesToGroup(group, [newPage]);
  }

  void _addPairedPage(DrawingGroup group, String tag, String pageNamePrefix) {
    final template = _findTemplateByTag(tag);
    if (template == null || (template.url2 ?? '').isEmpty) {
      _showErrorSnackbar('Paired template for "$pageNamePrefix" is invalid or missing a back page.');
      return;
    }

    final newPageSetNumber = (group.pages.length / 2).ceil() + 1;
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    final frontPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url,
        pageNumber: group.pages.length + 1,
        pageName: '$pageNamePrefix $newPageSetNumber (Front) - $formattedDate',
        groupName: group.groupName);
    final backPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url2!,
        pageNumber: group.pages.length + 2,
        pageName: '$pageNamePrefix $newPageSetNumber (Back) - $formattedDate',
        groupName: group.groupName);

    _addPagesToGroup(group, [frontPage, backPage]);
  }

  void _showConsentOptions(DrawingGroup group) async {
    final consentTemplates = _availableTemplates.where((t) => t.tag == 't10' && t.name != 'OT Form').toList();

    if (consentTemplates.isEmpty) {
      _showErrorSnackbar("No relevant consent forms found.");
      return;
    }

    final selectedTemplate = await _showTemplateSelectionDialog(consentTemplates);
    if (selectedTemplate == null || !mounted) return;

    // Prevent adding non-book consent forms more than once by name
    if (group.pages.any((p) => p.pageName == selectedTemplate.name)) {
      _showErrorSnackbar("'${selectedTemplate.name}' has already been added.");
      return;
    }

    final newPageNumber = group.pages.length + 1;
    final newPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: selectedTemplate.url,
        pageNumber: newPageNumber,
        pageName: selectedTemplate.name,
        groupName: group.groupName);
    _addPagesToGroup(group, [newPage]);
  }

  void _addOtFormPage(DrawingGroup group) {
    final template = _findTemplateByName('OT Form');
    if (template == null) return;

    if (group.pages.isNotEmpty) {
      _showErrorSnackbar("'${group.groupName}' already contains the OT Form.");
      return;
    }

    if (!template.isbook || template.bookImgUrl.isEmpty) {
      _showErrorSnackbar('The OT Form template is invalid or missing pages.');
      return;
    }

    final bookPages = <DrawingPage>[];
    for (int i = 0; i < template.bookImgUrl.length; i++) {
      bookPages.add(DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: template.bookImgUrl[i],
          pageNumber: i + 1, // Reset page number for this single instance group
          pageName: 'OT Form - Page ${i + 1}',
          groupName: group.groupName));
    }
    _addPagesToGroup(group, bookPages);
  }

  void _showDischargeOptions(DrawingGroup group) async {
    final dischargeTemplates = _availableTemplates.where((t) => t.tag == 't14').toList();
    if (dischargeTemplates.isEmpty) {
      _showErrorSnackbar("No 'Discharge' or 'Dama' templates found.");
      return;
    }

    final selectedTemplate = await _showTemplateSelectionDialog(dischargeTemplates);
    if (selectedTemplate == null || !mounted) return;

    final newPageSetNumber = (group.pages.length / ((selectedTemplate.url2 ?? '').isNotEmpty ? 2 : 1)).ceil() + 1;
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    if ((selectedTemplate.url2 ?? '').isNotEmpty) {
      final front = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url,
          pageNumber: group.pages.length + 1,
          pageName: '${selectedTemplate.name} $newPageSetNumber (Front) - $formattedDate',
          groupName: group.groupName);
      final back = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url2!,
          pageNumber: group.pages.length + 2,
          pageName: '${selectedTemplate.name} $newPageSetNumber (Back) - $formattedDate',
          groupName: group.groupName);
      _addPagesToGroup(group, [front, back]);
    } else {
      final newPage = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url,
          pageNumber: group.pages.length + 1,
          pageName: '${selectedTemplate.name} $newPageSetNumber - $formattedDate',
          groupName: group.groupName);
      _addPagesToGroup(group, [newPage]);
    }
  }

  // UPDATED to call save with the specific group name
  void _addPagesToGroup(DrawingGroup group, List<DrawingPage> newPages) {
    if (newPages.isEmpty) return;
    setState(() {
      final updatedPages = List<DrawingPage>.from(group.pages)..addAll(newPages);
      final updatedGroup = group.copyWith(pages: updatedPages);
      final groupIndex = _drawingGroups.indexWhere((g) => g.id == group.id);
      if (groupIndex != -1) {
        _drawingGroups[groupIndex] = updatedGroup;
      }
    });
    // Pass the name of the group that was changed
    _saveHealthDetails(changedGroupName: group.groupName);
  }

  void _addNewPageToGroup(DrawingGroup group) {
    switch (group.groupName) {
      case 'Indoor Patient Progress Digital':
      case 'Progress Notes':
        _addSinglePage(group, 't9', "Progress Note");
        break;
      case 'Daily Drug Chart':
        _addPairedPage(group, 't2', "Daily Drug Chart");
        break;
      case 'Dr Visit Form':
        _addSinglePage(group, 't3', "Doctor Visit");
        break;
      case 'Patient Charges Form':
        _addSinglePage(group, 't4', "Patient Charges");
        break;
      case 'Glucose Monitoring Sheet':
        _addSinglePage(group, 't5', "Glucose Monitoring");
        break;
      case 'Pt Admission Assessment (Nursing)':
        _addPairedPage(group, 't6', "Admission Assessment");
        break;
      case 'Clinical Notes':
        _addPairedPage(group, 't7', "Clinical Note");
        break;
      case 'Investigation Sheet':
        _addPairedPage(group, 't8', "Investigation");
        break;
      case 'Nursing Notes':
        _addSinglePage(group, 't11', "Nursing Note");
        break;
      case 'TPR / Intake / Output':
        _addSinglePage(group, 't12', "TPR/Intake/Output");
        break;
      case 'Casualty Note':
        _addPairedPage(group, 't15', "Casualty Note");
        break;
      case 'Indoor Patient File':
        _addSinglePage(group, 't1', "Patient File");
        break;
      case 'Consent':
        _showConsentOptions(group);
        break;
      case 'OT': // Dedicated OT group
        _addOtFormPage(group);
        break;
      case 'Discharge / Dama':
        _showDischargeOptions(group);
        break;
      default:
        _showCustomTemplateDialogForGroup(group);
    }
  }

  void _showCustomTemplateDialogForGroup(DrawingGroup group) async {
    SupabaseTemplateImage? selectedTemplate = _availableTemplates.firstWhere((t) => t.name != 'OT Form', orElse: () => _availableTemplates.first);
    if (selectedTemplate == null || !mounted) return;

    selectedTemplate = await _showTemplateSelectionDialog(_availableTemplates.where((t) => t.name != 'OT Form').toList());
    if (selectedTemplate == null || !mounted) return;

    TextEditingController pageNameController =
    TextEditingController(text: '${selectedTemplate.name} ${group.pages.length + 1}');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Add New Page"),
          content: TextField(
            controller: pageNameController,
            decoration: const InputDecoration(hintText: "Enter page name"),
          ),
          actions: <Widget>[
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(context)),
            ElevatedButton(
                child: const Text("Add Page"),
                onPressed: () {
                  if (pageNameController.text.isNotEmpty) {
                    final newPage = DrawingPage(
                        id: generateUniqueId(),
                        templateImageUrl: selectedTemplate!.url,
                        pageNumber: group.pages.length + 1,
                        pageName: pageNameController.text,
                        groupName: group.groupName);
                    _addPagesToGroup(group, [newPage]);
                    Navigator.pop(context);
                  }
                }),
          ],
        );
      },
    );
  }

  Future<SupabaseTemplateImage?> _showTemplateSelectionDialog(List<SupabaseTemplateImage> templatesToShow) async {
    TextEditingController searchController = TextEditingController();
    List<SupabaseTemplateImage> filteredTemplates = List.from(templatesToShow);

    return await showDialog<SupabaseTemplateImage?>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text("Select Template",
                  style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Search templates...",
                        prefixIcon: const Icon(Icons.search, color: mediumGreyText, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (query) {
                        setState(() {
                          filteredTemplates = templatesToShow
                              .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredTemplates.length,
                        itemBuilder: (context, index) {
                          final template = filteredTemplates[index];
                          return ListTile(
                            title: Text(template.name),
                            onTap: () => Navigator.pop(context, template),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // FIXED: Added required 'groupName' parameter
  void _openPrescriptionPage(DrawingGroup group, DrawingPage page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          groupId: group.id,
          pageId: page.id,
          groupName: group.groupName, // Pass the group name
        ),
      ),
    );
    _loadAllDetails();
  }

  void _openDocumentsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientDocumentsPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          patientName: _patientName ?? 'N/A',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double horizontalPadding = screenWidth > 600 ? 24.0 : 16.0;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: lightBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryBlue),
              SizedBox(height: 20),
              Text(
                "Loading patient details...",
                style: TextStyle(fontSize: 16, color: mediumGreyText),
              ),
            ],
          ),
        ),
      );
    }

    final lowerQuery = _searchQuery.toLowerCase();
    final List<DrawingGroup> displayedGroups = _searchQuery.isEmpty
        ? _drawingGroups
        : _drawingGroups.map((group) {
      final filteredPages = group.pages
          .where((page) =>
      page.pageName.toLowerCase().contains(lowerQuery) ||
          page.groupName.toLowerCase().contains(lowerQuery))
          .toList();
      return group.copyWith(pages: filteredPages);
    }).where((group) => group.pages.isNotEmpty || group.groupName.toLowerCase().contains(lowerQuery)).toList();

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: const Text("Manage Patient Details",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: darkText)),
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.08),
        toolbarHeight: 60,
        centerTitle: false,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16.0, horizontalPadding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Patient Information",
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: darkText)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.person_outline, color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("Name: ${_patientName ?? 'N/A'}",
                              style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.medical_information_outlined, color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("IPD ID: ${widget.ipdId}",
                              style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.credit_card_outlined, color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("UHID: ${widget.uhid}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.local_hospital_outlined, color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("Room: ${_roomType ?? 'N/A'}",
                              style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: "Search pages by name or group",
                          prefixIcon: const Icon(Icons.search, color: mediumGreyText, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[200]!, width: 1)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: primaryBlue, width: 2)),
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Refresh Data',
                      child: InkWell(
                        onTap: _isSaving ? null : _loadAllDetails,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[200]!, width: 1),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 1))
                            ],
                          ),
                          child: _isSaving
                              ? const SizedBox(
                              height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh, color: primaryBlue, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openDocumentsPage,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text("Manage Documents"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _createNewGroup,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text("Create New Group"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ]),
            ),
          ),
          if (_drawingGroups.isEmpty && !_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_off_outlined, size: 60, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text("No Groups Available"),
                    const SizedBox(height: 8),
                    const Text("Click on 'Create New Group' to get started."),
                  ],
                ),
              ),
            )
          else if (displayedGroups.isEmpty && _searchQuery.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 60, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text("No Results Found"),
                    const SizedBox(height: 8),
                    Text("Your search for '$_searchQuery' did not match any pages or groups."),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, groupIndex) {
                  final group = displayedGroups[groupIndex];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6.0),
                    child: Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Colors.white,
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          initiallyExpanded: _searchQuery.isNotEmpty,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(group.groupName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_box_rounded, color: primaryBlue, size: 24),
                            onPressed: () => _addNewPageToGroup(group),
                            tooltip: "Add New Page to ${group.groupName}",
                          ),
                          childrenPadding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 8.0),
                          children: [
                            const Divider(height: 1, thickness: 1, color: lightBackground),
                            if (group.pages.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text("No pages in this group. Click '+' to add one.",
                                    style: TextStyle(color: mediumGreyText, fontStyle: FontStyle.italic)),
                              ),
                            ...group.pages.map((page) {
                              return ListTile(
                                leading: const Icon(Icons.description_outlined, color: primaryBlue, size: 22),
                                title: Text(page.pageName,
                                    style:
                                    const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 15)),
                                subtitle: Text("Page ${page.pageNumber}",
                                    style: const TextStyle(color: mediumGreyText, fontSize: 13)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: mediumGreyText),
                                onTap: () => _openPrescriptionPage(group, page),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: displayedGroups.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}