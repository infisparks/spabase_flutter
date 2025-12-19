import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'supabase_config.dart';
import 'prescription_page.dart';
import 'patient_documents_page.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:ui' show Offset, Color;
import 'ipd_structure.dart'; // Ensure this file exists
import 'pdf_generator.dart'; // Ensure this file exists
import 'discharge_summary_page.dart'; // Ensure this file exists

// --- UNIFIED & HIGHLY COMPRESSED DATA MODELS ---

String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
}

class DrawingLine {
  final List<Offset> points;
  final int colorValue;
  final double strokeWidth;
  final List<double>? pressure;

  DrawingLine({
    required this.points,
    required this.colorValue,
    required this.strokeWidth,
    this.pressure,
  });

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    final pointsList = <Offset>[];
    final pointsData = json['points'];
    final color = (json['colorValue'] as num?)?.toInt() ?? Colors.black.value;

    // Robust casting for double
    final width = (json['strokeWidth'] is num)
        ? (json['strokeWidth'] as num).toDouble()
        : 2.0;

    final pressureData = json['pressure'] as List<dynamic>?;
    final pressures = pressureData?.map((p) => (p as num).toDouble()).toList();

    if (pointsData is List && pointsData.isNotEmpty) {
      if (pointsData[0] is Map) {
        for (var pointJson in pointsData) {
          if (pointJson is Map) {
            pointsList.add(Offset(
              (pointJson['dx'] as num?)?.toDouble() ?? 0.0,
              (pointJson['dy'] as num?)?.toDouble() ?? 0.0,
            ));
          }
        }
      } else if (pointsData[0] is num) {
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
    return DrawingLine(
      points: pointsList,
      colorValue: color,
      strokeWidth: width,
      pressure: pressures,
    );
  }

  Map<String, dynamic> toJson() {
    if (points.isEmpty) {
      return {
        'points': [],
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'pressure': pressure
      };
    }

    final pointsToEncode = points;
    if (pointsToEncode.isEmpty) {
      return {
        'points': [],
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'pressure': pressure
      };
    }

    final compressedPoints = <int>[];
    int lastX = (pointsToEncode.first.dx * 100).round();
    int lastY = (pointsToEncode.first.dy * 100).round();
    compressedPoints.add(lastX);
    compressedPoints.add(lastY);

    for (int i = 1; i < pointsToEncode.length; i++) {
      int currentX = (pointsToEncode[i].dx * 100).round();
      int currentY = (pointsToEncode[i].dy * 100).round();
      compressedPoints.add(currentX - lastX);
      compressedPoints.add(currentY - lastY);
      lastX = currentX;
      lastY = currentY;
    }

    return {
      'points': compressedPoints,
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
      'pressure': pressure,
    };
  }

  DrawingLine copyWith({List<Offset>? points, List<double>? pressure}) {
    return DrawingLine(
      points: points ?? this.points,
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      pressure: pressure ?? this.pressure,
    );
  }
}

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'imageUrl': imageUrl,
    'position': {'dx': position.dx, 'dy': position.dy},
    'width': width,
    'height': height,
  };

  factory DrawingImage.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>? ?? {'dx': 0.0, 'dy': 0.0};
    return DrawingImage(
      id: json['id'] as String? ?? generateUniqueId(),
      imageUrl: json['imageUrl'] as String? ?? '',
      position: Offset(
        (pos['dx'] as num?)?.toDouble() ?? 0.0,
        (pos['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      width: (json['width'] is num) ? (json['width'] as num).toDouble() : 100.0,
      height: (json['height'] is num) ? (json['height'] as num).toDouble() : 100.0,
    );
  }

  DrawingImage copyWith({
    String? id,
    Offset? position,
    double? width,
    double? height,
  }) {
    return DrawingImage(
      id: id ?? this.id,
      imageUrl: imageUrl,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
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
    final positionJson =
        json['position'] as Map<String, dynamic>? ?? {'dx': 0.0, 'dy': 0.0};
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
  final List<DrawingImage> images;
  final String? locationTag;

  DrawingPage({
    required this.id,
    required this.templateImageUrl,
    required this.pageNumber,
    required this.pageName,
    required this.groupName,
    this.lines = const [],
    this.texts = const [],
    this.images = const [],
    this.locationTag,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'templateImageUrl': templateImageUrl,
    'pageNumber': pageNumber,
    'pageName': pageName,
    'groupName': groupName,
    'lines': lines.map((line) => line.toJson()).toList(),
    'texts': texts.map((text) => text.toJson()).toList(),
    'images': images.map((image) => image.toJson()).toList(),
    'locationTag': locationTag,
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
          .toList() ??
          [],
      texts: (json['texts'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((textJson) => DrawingText.fromJson(textJson))
          .toList() ??
          [],
      images: (json['images'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((imageJson) => DrawingImage.fromJson(imageJson))
          .toList() ??
          [],
      locationTag: json['locationTag'] as String?,
    );
  }

  // --- UPDATED COPYWITH TO ALLOW NULL CLEARING ---
  DrawingPage copyWith({
    List<DrawingLine>? lines,
    String? pageName,
    List<DrawingText>? texts,
    String? groupName,
    int? pageNumber,
    List<DrawingImage>? images,
    String? locationTag,
    bool clearLocationTag = false, // ADDED FLAG
  }) {
    return DrawingPage(
      id: id,
      templateImageUrl: templateImageUrl,
      pageNumber: pageNumber ?? this.pageNumber,
      pageName: pageName ?? this.pageName,
      groupName: groupName ?? this.groupName,
      lines: lines ?? this.lines,
      texts: texts ?? this.texts,
      images: images ?? this.images,
      // If clear flag is true, force null. Otherwise fall back to logic.
      locationTag: clearLocationTag ? null : (locationTag ?? this.locationTag),
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
          .toList() ??
          [],
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

  factory SupabaseTemplateImage.fromJson(Map<String, dynamic> json) {
    final bookUrlsRaw = json['book_img_url'];
    List<String> bookUrls = [];
    if (bookUrlsRaw is List) {
      bookUrls = bookUrlsRaw.map((e) => e.toString()).toList();
    } else if (bookUrlsRaw is String &&
        bookUrlsRaw.startsWith('[') &&
        bookUrlsRaw.endsWith(']')) {
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

  // --- STATE VARIABLES ---
  final Set<String> _expandedGroupNames = {};
  final ScrollController _mainScrollController = ScrollController();
  Widget _buildOtGroupContent(DrawingGroup group) {
    // 1. Group pages by "Set" -> Map<SetNumber, List<Page>>
    final Map<String, List<DrawingPage>> otSets = {};
    final List<DrawingPage> loosePages = [];

    for (var page in group.pages) {
      final match = RegExp(r'OT Form \((\d+)\)').firstMatch(page.pageName);
      if (match != null) {
        final setNum = match.group(1)!;
        otSets.putIfAbsent(setNum, () => []).add(page);
      } else {
        if (page.pageName.contains('OT Form')) {
          otSets.putIfAbsent('1', () => []).add(page);
        } else {
          loosePages.add(page);
        }
      }
    }

    // 2. Logic: If only 1 set (and no loose pages), show Flat List
    if (otSets.length <= 1 && loosePages.isEmpty) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // --- FIX 1: ADD THIS CONTROLLER ---
        // This prevents the ListView from trying to restore a scroll offset
        // from a value that might be a boolean (Expansion state).
        controller: ScrollController(keepScrollOffset: false),
        // ----------------------------------
        itemCount: group.pages.length,
        itemBuilder: (context, index) {
          final page = group.pages[index];
          return _SinglePageTile(
            page: page,
            onTap: () => _openPrescriptionPage(group, page),
            onLongPress: () => _showPageOptionsDialog(group, page),
          );
        },
      );
    }

    // 3. Logic: If > 1 Set, show "Folders"
    final List<Widget> children = [];

    final sortedKeys = otSets.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    for (var key in sortedKeys) {
      final pages = otSets[key]!;
      String dateSuffix = '';
      if (pages.isNotEmpty && pages.first.pageName.contains(' - ')) {
        dateSuffix = pages.first.pageName.split(' - ').last;
      }

      children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: ExpansionTile(
                // --- FIX 2: ADD A UNIQUE KEY ---
                // This ensures the Open/Close state (bool) is stored separately
                // from any scroll offsets.
                key: PageStorageKey('ot_set_${group.id}_$key'),
                // -------------------------------
                title: Text(
                    "OT Form Set $key",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1565C0))
                ),
                subtitle: Text(dateSuffix, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                leading: const Icon(Icons.folder_shared, color: Color(0xFF1565C0)),
                children: pages.map((page) => _SinglePageTile(
                  page: page,
                  onTap: () => _openPrescriptionPage(group, page),
                  onLongPress: () => _showPageOptionsDialog(group, page),
                )).toList(),
              ),
            ),
          )
      );
    }

    for (var page in loosePages) {
      children.add(_SinglePageTile(
        page: page,
        onTap: () => _openPrescriptionPage(group, page),
        onLongPress: () => _showPageOptionsDialog(group, page),
      ));
    }

    return Column(children: children);
  }
  // --- TAG LIST ---
  final List<String> _locationTags = [
    'Deluxe Room',
    'NICU',
    'ICU',
    'Maternity Ward',
    'Paediatric Ward',
    'Male General Ward',
    'Female Ward',
    'Twin Sharing Deluxe',
    'Medford Ward',
  ];

  List<SupabaseTemplateImage> _availableTemplates = [];
  String? _patientName;
  String? _roomType;
  String? _patientAgeSex;

  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mediumGreyText = Color(0xFF64748B);
  static const Color lightBackground = Color(0xFFF8FAFC);

  static final Map<String, String> _groupToColumnMap = groupToColumnMap;

  static final List<String> _allDataColumns = [
    'id',
    'ipd_registration_id',
    'patient_uhid',
    'updated_at',
    ...allGroupColumnNames,
    'custom_groups_data',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllDetails({bool isBackgroundRefresh = false}) async {
    if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final patientDetailsResponse = await supabase
          .from('ipd_registration')
          .select(
          'uhid, patient:patient_detail(name, age, gender), bed:bed_management(room_type, bed_number)')
          .eq('ipd_id', widget.ipdId)
          .single();

      final patientData = patientDetailsResponse['patient'];
      _patientName =
      (patientData != null) ? patientData['name'] as String? : 'N/A';

      final age = (patientData != null) ? patientData['age'] as int? : null;
      final gender = (patientData != null) ? patientData['gender'] as String? : null;
      if (age != null && gender != null) {
        _patientAgeSex = '$age / $gender';
      } else if (age != null) {
        _patientAgeSex = '$age / N/A';
      } else {
        _patientAgeSex = 'N/A';
      }

      final bedData = patientDetailsResponse['bed'];
      _roomType = (bedData != null)
          ? '${bedData['room_type'] ?? 'N/A'} - Bed: ${bedData['bed_number'] ?? 'N/A'}'
          : 'N/A';

      final List<Map<String, dynamic>> templateData =
      await supabase.from('template_images').select(
          'id, name, url, 2url, isbook, book_img_url, tag');
      _availableTemplates = templateData
          .map((json) => SupabaseTemplateImage.fromJson(json))
          .toList();

      final response = await supabase
          .from('user_health_details')
          .select(_allDataColumns.join(','))
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      final List<DrawingGroup> loadedGroups = [];

      if (response != null) {
        _healthRecordId = response['id'] as String;

        for (final config in ipdGroupStructure) {
          final groupName = config.groupName;
          final columnName = config.columnName;

          if (!response.containsKey(columnName)) {
            loadedGroups.add(DrawingGroup(
              id: generateUniqueId(),
              groupName: groupName,
              pages: [],
            ));
            continue;
          }

          final List<dynamic> rawPages = response[columnName] ?? [];
          final pages = rawPages
              .whereType<Map<String, dynamic>>()
              .map((json) => DrawingPage.fromJson(json))
              .toList();

          pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

          final pagesWithGroupName = pages
              .map((page) => page.copyWith(groupName: groupName))
              .toList();

          loadedGroups.add(DrawingGroup(
            id: generateUniqueId(),
            groupName: groupName,
            pages: pagesWithGroupName,
          ));
        }

        final List<dynamic> rawCustomGroups =
            response['custom_groups_data'] ?? [];
        loadedGroups.addAll(rawCustomGroups
            .whereType<Map<String, dynamic>>()
            .map((json) => DrawingGroup.fromJson(json))
            .toList());

        setState(() {
          _drawingGroups = loadedGroups;
          _isLoading = false;
        });
      } else {
        await _createAndSaveDefaultGroups();
      }
    } on PostgrestException catch (e) {
      _showErrorSnackbar('Error loading data: ${e.message}');
    } catch (e) {
      _showErrorSnackbar('Failed to load IPD records: ${e.toString()}');
    } finally {
      if (mounted && !isBackgroundRefresh) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createAndSaveDefaultGroups() async {
    final defaultGroups = ipdGroupStructure
        .map((config) => DrawingGroup(
        id: generateUniqueId(), groupName: config.groupName, pages: []))
        .toList();

    setState(() {
      _drawingGroups = defaultGroups;
      _healthRecordId = null;
    });

    await _saveHealthDetails();
  }

  Future<void> _saveHealthDetails({String? changedGroupName}) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });
    try {
      final Map<String, dynamic> dataToSave = {};
      final List<DrawingGroup> customGroups = [];

      for (final group in _drawingGroups) {
        final columnName = _groupToColumnMap[group.groupName];

        if (columnName != null) {
          if (changedGroupName == null || group.groupName == changedGroupName) {
            group.pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
            final List<Map<String, dynamic>> pagesJson =
            group.pages.map((page) => page.toJson()).toList();
            dataToSave[columnName] = pagesJson;
          }
        } else {
          if (changedGroupName == null || group.groupName == changedGroupName) {
            customGroups.add(group);
          }
        }
      }

      if (changedGroupName == null ||
          _groupToColumnMap[changedGroupName] == null) {
        List<DrawingGroup> finalCustomGroups = customGroups;
        if (changedGroupName != null &&
            _groupToColumnMap[changedGroupName] == null &&
            _healthRecordId != null) {
          final existingData = await supabase
              .from('user_health_details')
              .select('custom_groups_data')
              .eq('id', _healthRecordId!)
              .single();
          final List<dynamic> rawExistingCustom =
              existingData['custom_groups_data'] ?? [];
          final List<DrawingGroup> existingCustomGroups = rawExistingCustom
              .whereType<Map<String, dynamic>>()
              .map((json) => DrawingGroup.fromJson(json))
              .where((g) =>
          g.groupName != changedGroupName)
              .toList();
          finalCustomGroups = [...existingCustomGroups, ...customGroups];
        }

        dataToSave['custom_groups_data'] =
            finalCustomGroups.map((group) => group.toJson()).toList();
      }

      dataToSave['ipd_registration_id'] = widget.ipdId;
      dataToSave['patient_uhid'] = widget.uhid;
      dataToSave['updated_at'] = DateTime.now().toIso8601String();
      if (_healthRecordId != null) {
        dataToSave['id'] = _healthRecordId;
      }

      final List<Map<String, dynamic>> response = await supabase
          .from('user_health_details')
          .upsert(dataToSave,
          onConflict: 'ipd_registration_id, patient_uhid')
          .select('id');

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

  Future<void> _downloadFullRecord() async {
    if (_healthRecordId == null) {
      _showErrorSnackbar("Cannot download, health record is not loaded.");
      return;
    }
    final String patientNameForFile = _patientName ?? 'UnknownPatient';
    final String uhidForFile = widget.uhid;
    setState(() => _isSaving = true);

    await PdfGenerator.downloadFullRecordAsPdf(
      context: context,
      supabase: supabase,
      healthRecordId: _healthRecordId,
      patientName: patientNameForFile,
      uhid: uhidForFile,
    );

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  void _createNewGroup() {
    TextEditingController groupNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Create New Group",
              style: TextStyle(
                  color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
          content: TextField(
            controller: groupNameController,
            decoration: InputDecoration(
              hintText: "Enter group name",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: primaryBlue, width: 2),
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  if (_drawingGroups.any((g) =>
                  g.groupName.toLowerCase() == newGroupName.toLowerCase())) {
                    _showErrorSnackbar("A group with this name already exists.");
                    return;
                  }
                  setState(() {
                    _drawingGroups.add(DrawingGroup(
                      id: generateUniqueId(),
                      groupName: newGroupName,
                      pages: [],
                    ));
                  });
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

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
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

    final config = findGroupConfigByName(group.groupName);
    final pageNumberSuffix = (config?.behavior == AddBehavior.singlePageOnly)
        ? ""
        : " $newPageNumber";

    final newPageName = '$pageNamePrefix$pageNumberSuffix - $formattedDate';

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
      _showErrorSnackbar(
          'Paired template for "$pageNamePrefix" is invalid or missing a back page.');
      return;
    }

    final newPageSetNumber = (group.pages.length / 2).ceil() + 1;
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    final config = findGroupConfigByName(group.groupName);
    final pageNumberSuffix = (config?.behavior == AddBehavior.singlePairOnly)
        ? ""
        : " $newPageSetNumber";

    final frontPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url,
        pageNumber: group.pages.length + 1,
        pageName: '$pageNamePrefix$pageNumberSuffix (Front) - $formattedDate',
        groupName: group.groupName);
    final backPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url2!,
        pageNumber: group.pages.length + 2,
        pageName: '$pageNamePrefix$pageNumberSuffix (Back) - $formattedDate',
        groupName: group.groupName);

    _addPagesToGroup(group, [frontPage, backPage]);
  }

  Future<void> _addSinglePageWithCustomName(
      DrawingGroup group, String tag, String pageNamePrefix) async {
    final template = _findTemplateByTag(tag);
    if (template == null) return;

    final newPageNumber = group.pages.length + 1;
    TextEditingController nameController =
    TextEditingController(text: '$pageNamePrefix $newPageNumber');

    final String? customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter Name for ${group.groupName}'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "Sheet Name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Add'),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.of(context).pop(nameController.text.trim());
              } else {
                _showErrorSnackbar("Name cannot be empty.");
              }
            },
          ),
        ],
      ),
    );

    if (customName != null && customName.isNotEmpty) {
      final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());
      final finalPageName = '$customName - $formattedDate';

      if (group.pages.any(
              (p) => p.pageName.toLowerCase() == finalPageName.toLowerCase())) {
        _showErrorSnackbar("A sheet with this name already exists in this group.");
        return;
      }

      final newPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.url,
        pageNumber: newPageNumber,
        pageName: finalPageName,
        groupName: group.groupName,
      );
      _addPagesToGroup(group, [newPage]);
    }
  }

  void _showConsentOptions(DrawingGroup group, String tag) async {
    final consentTemplates = _availableTemplates
        .where((t) => t.tag == tag && t.name != 'OT Form')
        .toList();

    if (consentTemplates.isEmpty) {
      _showErrorSnackbar("No relevant consent forms found.");
      return;
    }

    final selectedTemplate =
    await _showTemplateSelectionDialog(consentTemplates);
    if (selectedTemplate == null || !mounted) return;

    // --- OLD CODE REMOVED FROM HERE (The block that stopped duplicates) ---

    // --- NEW LOGIC: Allow duplicates and append a number/date ---

    // 1. Calculate how many times this specific template appears already
    final existingCount = group.pages
        .where((p) => p.pageName.startsWith(selectedTemplate.name))
        .length;

    // 2. Generate a formatted date
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    // 3. Create a unique name: "Template Name (2) - Date"
    String finalPageName;
    if (existingCount > 0) {
      finalPageName = '${selectedTemplate.name} (${existingCount + 1}) - $formattedDate';
    } else {
      finalPageName = '${selectedTemplate.name} - $formattedDate';
    }

    final newPageNumber = group.pages.length + 1;

    final newPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: selectedTemplate.url,
        pageNumber: newPageNumber,
        pageName: finalPageName, // Use the new dynamic name
        groupName: group.groupName);

    _addPagesToGroup(group, [newPage]);
  }

  void _showGenericListSelection(DrawingGroup group, String tag) async {
    final templates = _availableTemplates.where((t) => t.tag == tag).toList();

    if (templates.isEmpty) {
      _showErrorSnackbar("No templates found for this group (tag: $tag).");
      return;
    }

    final selectedTemplate = await _showTemplateSelectionDialog(templates);
    if (selectedTemplate == null || !mounted) return;

    if (group.pages
        .any((p) => p.pageName.toLowerCase() == selectedTemplate.name.toLowerCase())) {
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

  void _addOtFormPage(DrawingGroup group, String templateName) {
    final template = _findTemplateByName(templateName);
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
          pageNumber: i + 1,
          pageName: 'OT Form - Page ${i + 1}',
          groupName: group.groupName));
    }
    _addPagesToGroup(group, bookPages);
  }

  void _showDischargeOptions(DrawingGroup group, String tag) async {
    final dischargeTemplates =
    _availableTemplates.where((t) => t.tag == tag).toList();
    if (dischargeTemplates.isEmpty) {
      _showErrorSnackbar("No 'Discharge' or 'Dama' templates found.");
      return;
    }

    final selectedTemplate =
    await _showTemplateSelectionDialog(dischargeTemplates);
    if (selectedTemplate == null || !mounted) return;

    final newPageSetNumber =
        (group.pages.length / ((selectedTemplate.url2 ?? '').isNotEmpty ? 2 : 1))
            .ceil() +
            1;
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());

    if ((selectedTemplate.url2 ?? '').isNotEmpty) {
      final front = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url,
          pageNumber: group.pages.length + 1,
          pageName:
          '${selectedTemplate.name} $newPageSetNumber (Front) - $formattedDate',
          groupName: group.groupName);
      final back = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url2!,
          pageNumber: group.pages.length + 2,
          pageName:
          '${selectedTemplate.name} $newPageSetNumber (Back) - $formattedDate',
          groupName: group.groupName);
      _addPagesToGroup(group, [front, back]);
    } else {
      final newPage = DrawingPage(
          id: generateUniqueId(),
          templateImageUrl: selectedTemplate.url,
          pageNumber: group.pages.length + 1,
          pageName:
          '${selectedTemplate.name} $newPageSetNumber - $formattedDate',
          groupName: group.groupName);
      _addPagesToGroup(group, [newPage]);
    }
  }

  void _addPagesToGroup(DrawingGroup group, List<DrawingPage> newPages) {
    if (newPages.isEmpty) return;
    setState(() {
      final updatedPages = List<DrawingPage>.from(group.pages)..addAll(newPages);
      for (int i = 0; i < updatedPages.length; i++) {
        updatedPages[i] = updatedPages[i].copyWith(pageNumber: i + 1);
      }
      final updatedGroup = group.copyWith(pages: updatedPages);
      final groupIndex =
      _drawingGroups.indexWhere((g) => g.groupName == group.groupName);
      if (groupIndex != -1) {
        _drawingGroups[groupIndex] = updatedGroup;
      }
    });
    _saveHealthDetails(changedGroupName: group.groupName);
  }

  void _addNewPageToGroup(DrawingGroup group) {
    final config = findGroupConfigByName(group.groupName);

    if (config == null) {
      _showCustomTemplateDialogForGroup(group);
      return;
    }

    if ((config.behavior == AddBehavior.singlePageOnly ||
        config.behavior == AddBehavior.singlePairOnly ||
        config.behavior == AddBehavior.singleBook) &&
        group.pages.isNotEmpty) {
      _showErrorSnackbar("This group can only contain one item.");
      return;
    }

    switch (config.behavior) {
      case AddBehavior.singlePageOnly:
      case AddBehavior.multiPageSingle:
        _addSinglePage(group, config.templateTag!, config.pageNamePrefix);
        break;
      case AddBehavior.multiPageSingleCustomName:
        _addSinglePageWithCustomName(
            group, config.templateTag!, config.pageNamePrefix);
        break;
      case AddBehavior.singlePairOnly:
      case AddBehavior.multiPagePaired:
        _addPairedPage(group, config.templateTag!, config.pageNamePrefix);
        break;
      case AddBehavior.multiPageFromList:
        if (config.templateTag == 't10') {
          _showConsentOptions(group, config.templateTag!);
        } else if (config.templateTag == 't14') {
          _showDischargeOptions(group, config.templateTag!);
        } else if (config.templateTag == 't19') {
          _showGenericListSelection(group, config.templateTag!);
        } else {
          _showGenericListSelection(group, config.templateTag!);
        }
        break;
      case AddBehavior.singleBook:
        _addOtFormPage(group, config.templateName!);
        break;
      case AddBehavior.multiPageCustom:
        _showCustomTemplateDialogForGroup(group);
        break;
      case AddBehavior.multiBook:
        _addOtFormWithLogic(group, config.templateName!);
        break;

      case AddBehavior.multiPageCustom:
        _showCustomTemplateDialogForGroup(group);
        break;
    }
  }

  Future<void> _addOtFormWithLogic(DrawingGroup group, String templateName) async {
    final template = _findTemplateByName(templateName);
    if (template == null || !template.isbook || template.bookImgUrl.isEmpty) {
      _showErrorSnackbar('The OT Form template is invalid or missing pages.');
      return;
    }

    // 1. Identify existing sets
    // We assume names are like "OT Form (1) - Page 1", "OT Form (2) - Page 1"
    final existingSets = <String>{};
    for (var page in group.pages) {
      final match = RegExp(r'OT Form \((\d+)\)').firstMatch(page.pageName);
      if (match != null) {
        existingSets.add(match.group(1)!);
      } else if (page.pageName.contains('OT Form')) {
        existingSets.add('1'); // Legacy/First set
      }
    }

    final int nextSetNumber = existingSets.length + 1;
    final bool isFirstOt = existingSets.isEmpty;

    // --- POPUP LEVEL 1: General Confirmation ---
    bool confirmAdd = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFirstOt ? 'Add OT Form?' : 'Add Another OT Form?'),
        content: Text(
            'This will add ${template.bookImgUrl.length} pages to the file. '
                '${!isFirstOt ? "\nYou already have ${existingSets.length} OT form(s)." : ""} '
                '\nDo you want to proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    ) ?? false;

    if (!confirmAdd) return;

    // --- POPUP LEVEL 2 & 3: Double Confirmation for 2nd+ OT ---
    if (!isFirstOt) {
      // Confirmation 2.1
      bool confirmMulti = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add 2nd OT Form?'),
          content: const Text('You are about to add a SECOND OT form. Do you want to continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes Add It")),
          ],
        ),
      ) ?? false;

      if (!confirmMulti) return;

      // Confirmation 2.2 (Strict "Are you sure?")
      bool confirmFinal = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text('Please confirm one last time to create a new OT Set.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("I am Sure"),
            ),
          ],
        ),
      ) ?? false;

      if (!confirmFinal) return;
    }

    // --- GENERATE PAGES ---
    final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());
    final List<DrawingPage> bookPages = [];

    for (int i = 0; i < template.bookImgUrl.length; i++) {
      // Name Format: "OT Form (1) - Page 1 - 12 Dec 2024"
      final pageName = 'OT Form ($nextSetNumber) - Page ${i + 1} - $formattedDate';

      bookPages.add(DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: template.bookImgUrl[i],
        pageNumber: group.pages.length + i + 1,
        pageName: pageName,
        groupName: group.groupName,
      ));
    }

    _addPagesToGroup(group, bookPages);
    _showSuccessSnackbar('OT Form ($nextSetNumber) added successfully.');
  }
  // --- NEW MENU LOGIC: Page Options (Date & Tags) ---

  void _showPageOptionsDialog(DrawingGroup group, DrawingPage page) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  page.pageName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: darkText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),

              // Option 1: Change Date
              ListTile(
                leading: const Icon(Icons.calendar_month, color: primaryBlue),
                title: const Text('Change Page Date'),
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  _changePageDate(group, page);
                },
              ),

              // Option 2: Set Location Tag
              ListTile(
                leading: const Icon(Icons.label, color: primaryBlue),
                title: const Text('Set Location Tag'),
                subtitle: Text(page.locationTag ?? 'None'),
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  _showTagSelectionDialog(group, page);
                },
              ),

              // Option 3: Clear Tag (Only if exists)
              if (page.locationTag != null)
                ListTile(
                  leading: const Icon(Icons.label_off, color: Colors.red),
                  title: const Text('Clear Location Tag',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _updatePageTag(group, page, null);
                  },
                ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // Logic to show Date Picker and update Page Name
  void _changePageDate(DrawingGroup group, DrawingPage page) async {
    // 1. Try to parse existing date from page name
    DateTime initialDate = DateTime.now();
    int splitIndex = page.pageName.lastIndexOf(' - ');
    String namePart = page.pageName;

    if (splitIndex != -1) {
      String datePart = page.pageName.substring(splitIndex + 3);
      namePart = page.pageName.substring(0, splitIndex);
      try {
        initialDate = DateFormat('dd MMM yyyy').parse(datePart);
      } catch (e) {
        debugPrint("Could not parse date from page name, using now.");
      }
    }

    // 2. Show Date Picker
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryBlue),
          ),
          child: child!,
        );
      },
    );

    // 3. Update Page Name if date picked
    if (picked != null) {
      final String newFormattedDate = DateFormat('dd MMM yyyy').format(picked);
      final String newPageName = '$namePart - $newFormattedDate';

      setState(() {
        final updatedPages = List<DrawingPage>.from(group.pages);
        final index = updatedPages.indexWhere((p) => p.id == page.id);

        if (index != -1) {
          updatedPages[index] = updatedPages[index].copyWith(pageName: newPageName);

          final updatedGroup = group.copyWith(pages: updatedPages);
          final groupIndex = _drawingGroups.indexWhere((g) => g.groupName == group.groupName);

          if (groupIndex != -1) {
            _drawingGroups[groupIndex] = updatedGroup;
            _saveHealthDetails(changedGroupName: group.groupName);
            _showSuccessSnackbar("Date updated successfully.");
          }
        }
      });
    }
  }

  void _showTagSelectionDialog(DrawingGroup group, DrawingPage page) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select Location Tag'),
          children: [
            // Explicit Clear Option
            SimpleDialogOption(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              onPressed: () {
                _updatePageTag(group, page, null); // Pass null to clear
                Navigator.pop(context);
              },
              child: const Row(
                children: [
                  Icon(Icons.close, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text("None (Clear Tag)", style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            const Divider(),
            ..._locationTags.map((tag) => SimpleDialogOption(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              onPressed: () {
                _updatePageTag(group, page, tag);
                Navigator.pop(context);
              },
              child: Text(tag, style: const TextStyle(fontSize: 16)),
            )),
          ],
        );
      },
    );
  }

  void _updatePageTag(DrawingGroup group, DrawingPage page, String? newTag) {
    setState(() {
      final updatedPages = List<DrawingPage>.from(group.pages);
      final index = updatedPages.indexWhere((p) => p.id == page.id);

      if (index != -1) {
        // Use the new forceClearTag param in copyWith
        updatedPages[index] = updatedPages[index].copyWith(
            locationTag: newTag,
            clearLocationTag: newTag == null // THIS FIXES THE BUG
        );

        final updatedGroup = group.copyWith(pages: updatedPages);
        final groupIndex = _drawingGroups.indexWhere((g) => g.groupName == group.groupName);

        if (groupIndex != -1) {
          _drawingGroups[groupIndex] = updatedGroup;
          _saveHealthDetails(changedGroupName: group.groupName);
        }
      }
    });
  }

  void _showCustomTemplateDialogForGroup(DrawingGroup group) async {
    SupabaseTemplateImage? selectedTemplate = _availableTemplates.firstWhere(
            (t) => t.name != 'OT Form',
        orElse: () => _availableTemplates.first);
    if (selectedTemplate == null || !mounted) return;

    selectedTemplate = await _showTemplateSelectionDialog(
        _availableTemplates.where((t) => t.name != 'OT Form').toList());
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
            TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(context)),
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

  Future<SupabaseTemplateImage?> _showTemplateSelectionDialog(
      List<SupabaseTemplateImage> templatesToShow) async {
    TextEditingController searchController = TextEditingController();
    List<SupabaseTemplateImage> filteredTemplates = List.from(templatesToShow);

    return await showDialog<SupabaseTemplateImage?>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text("Select Template",
                  style: TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Search templates...",
                        prefixIcon: const Icon(Icons.search,
                            color: mediumGreyText, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (query) {
                        setState(() {
                          filteredTemplates = templatesToShow
                              .where((t) =>
                              t.name.toLowerCase().contains(query.toLowerCase()))
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

  void _openPrescriptionPage(DrawingGroup group, DrawingPage page) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          groupId: group.id,
          pageId: page.id,
          groupName: group.groupName,
        ),
      ),
    );

    if (result is List<DrawingPage> && mounted) {
      setState(() {
        final groupIndex =
        _drawingGroups.indexWhere((g) => g.groupName == group.groupName);
        if (groupIndex != -1) {
          result.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
          final updatedGroup =
          _drawingGroups[groupIndex].copyWith(pages: result);
          _drawingGroups[groupIndex] = updatedGroup;
        } else {
          _loadAllDetails(isBackgroundRefresh: true);
        }
      });
    } else if (result != null) {
      // Silent refresh to keep scroll position
      _loadAllDetails(isBackgroundRefresh: true);
    }
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

  void _openDischargeSummaryPage() {
    if (_patientName == null || _patientAgeSex == null) {
      _showErrorSnackbar("Patient details not fully loaded yet.");
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DischargeSummaryPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          patientName: _patientName!,
          ageSex: _patientAgeSex!,
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
    }).where((group) =>
    group.pages.isNotEmpty ||
        group.groupName.toLowerCase().contains(lowerQuery)).toList();

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: const Text("Manage Patient Details",
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 20, color: darkText)),
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.08),
        toolbarHeight: 60,
        centerTitle: false,
      ),
      body: CustomScrollView(
        controller: _mainScrollController, // Attached controller
        slivers: [
          SliverPadding(
            padding:
            EdgeInsets.fromLTRB(horizontalPadding, 16.0, horizontalPadding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Patient Information",
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: darkText)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.person_outline,
                              color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("Name: ${_patientName ?? 'N/A'}",
                              style: const TextStyle(
                                  fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.medical_information_outlined,
                              color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("IPD ID: ${widget.ipdId}",
                              style: const TextStyle(
                                  fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.credit_card_outlined,
                              color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("UHID: ${widget.uhid}",
                              style: const TextStyle(
                                  fontSize: 15, color: mediumGreyText)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.local_hospital_outlined,
                              color: primaryBlue, size: 18),
                          const SizedBox(width: 6),
                          Text("Room: ${_roomType ?? 'N/A'}",
                              style: const TextStyle(
                                  fontSize: 15, color: mediumGreyText)),
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
                          prefixIcon: const Icon(Icons.search,
                              color: mediumGreyText, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                              BorderSide(color: Colors.grey[200]!, width: 1)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                              const BorderSide(color: primaryBlue, width: 2)),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Refresh Data',
                      child: InkWell(
                        onTap: _isSaving ? null : () => _loadAllDetails(isBackgroundRefresh: false),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border:
                            Border.all(color: Colors.grey[200]!, width: 1),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1))
                            ],
                          ),
                          child: _isSaving
                              ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh,
                              color: primaryBlue, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _downloadFullRecord,
                        icon:
                        const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text("Download Full Record"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed:
                        _isSaving || _isLoading ? null : _openDischargeSummaryPage,
                        icon: const Icon(Icons.description, size: 18),
                        label: const Text("Discharge Summary"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _openDocumentsPage,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text("Manage Documents"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _createNewGroup,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text("Create New Group"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ],
                  ),
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
                    Icon(Icons.folder_off_outlined,
                        size: 60, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text("No Groups Available"),
                    const SizedBox(height: 8),
                    const Text(
                        "Click on 'Create New Group' to get started."),
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
                    Text(
                        "Your search for '$_searchQuery' did not match any pages or groups."),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, groupIndex) {
                  final group = displayedGroups[groupIndex];

                  final config = findGroupConfigByName(group.groupName);
                  bool isAddDisabled = false;
                  bool isPairedDisplay = false;

                  if (config != null) {
                    if ((config.behavior == AddBehavior.singlePageOnly ||
                        config.behavior == AddBehavior.singlePairOnly ||
                        config.behavior == AddBehavior.singleBook) &&
                        group.pages.isNotEmpty) {
                      isAddDisabled = true;
                    }
                    if (config.behavior == AddBehavior.multiPagePaired ||
                        config.behavior == AddBehavior.singlePairOnly) {
                      isPairedDisplay = true;
                    }
                  } else {
                    isPairedDisplay = false;
                  }

                  return Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding, vertical: 6.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      color: Colors.white,
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: PageStorageKey(group.groupName), // Key for State preservation
                          initiallyExpanded: _searchQuery.isNotEmpty ||
                              _expandedGroupNames.contains(group.groupName),
                          onExpansionChanged: (bool isExpanded) {
                            setState(() {
                              if (isExpanded) {
                                _expandedGroupNames.add(group.groupName);
                              } else {
                                _expandedGroupNames.remove(group.groupName);
                              }
                            });
                          },
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          title: Text(group.groupName,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: darkText)),
                          trailing: IconButton(
                            icon: Icon(Icons.add_box_rounded,
                                color:
                                isAddDisabled ? Colors.grey : primaryBlue,
                                size: 24),
                            onPressed: isAddDisabled
                                ? null
                                : () => _addNewPageToGroup(group),
                            tooltip: isAddDisabled
                                ? "Only one item allowed in this group"
                                : "Add New Page to ${group.groupName}",
                          ),
                          childrenPadding: const EdgeInsets.only(
                              left: 8.0, right: 8.0, bottom: 8.0, top: 0),
                          children: [
                            const Divider(
                                height: 1,
                                thickness: 1,
                                indent: 8,
                                endIndent: 8,
                                color: lightBackground),

                            // 1. Empty State Logic
                            if (group.pages.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text(
                                      "No pages in this group. Click '+' to add one.",
                                      style: TextStyle(
                                          color: mediumGreyText,
                                          fontStyle: FontStyle.italic)),
                                ),
                              ),

                            // -----------------------------------------------------------
                            // 3.2 CHANGE STARTS HERE: Add the specific check for 'OT'
                            // -----------------------------------------------------------

                            // 2. OT Group Logic (Uses the new Folder function)
                            if (group.groupName == 'OT')
                              _buildOtGroupContent(group)

                            // 3. Paired Display Logic (Clinical Notes, etc.)
                            else if (isPairedDisplay)
                              ..._buildPairedPageRows(group)

                            // 4. Standard List Logic (Everything else)
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                // Fix for scroll controller crash
                                controller: ScrollController(keepScrollOffset: false),
                                itemCount: group.pages.length,
                                itemBuilder: (context, index) {
                                  final page = group.pages[index];
                                  return _SinglePageTile(
                                    page: page,
                                    onTap: () =>
                                        _openPrescriptionPage(group, page),
                                    onLongPress: () => _showPageOptionsDialog(group, page),
                                  );
                                },
                              )
                            // -----------------------------------------------------------
                            // 3.2 CHANGE ENDS HERE
                            // -----------------------------------------------------------
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

  List<Widget> _buildPairedPageRows(DrawingGroup group) {
    List<Widget> rows = [];
    final sortedPages = List<DrawingPage>.from(group.pages)
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    for (int i = 0; i < sortedPages.length; i += 2) {
      final DrawingPage pageFront = sortedPages[i];
      final DrawingPage? pageBack =
      (i + 1 < sortedPages.length) ? sortedPages[i + 1] : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _PairedPageTile(
            pageFront: pageFront,
            pageBack: pageBack,
            onFrontTap: () => _openPrescriptionPage(group, pageFront),
            onBackTap: pageBack != null
                ? () => _openPrescriptionPage(group, pageBack)
                : null,
            onFrontLongPress: () => _showPageOptionsDialog(group, pageFront), // NEW
            onBackLongPress: pageBack != null
                ? () => _showPageOptionsDialog(group, pageBack) // NEW
                : null,
          ),
        ),
      );
    }
    return rows;
  }
}

class _SinglePageTile extends StatelessWidget {
  final DrawingPage page;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SinglePageTile({
    required this.page,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        leading: const Icon(Icons.description_outlined,
            color: _ManageIpdPatientPageState.primaryBlue, size: 22),
        title: Row(
          children: [
            Expanded(
              child: Text(
                page.pageName,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _ManageIpdPatientPageState.darkText,
                    fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (page.locationTag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  page.locationTag!,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ]
          ],
        ),
        subtitle: Text("Page ${page.pageNumber}",
            style: const TextStyle(
                color: _ManageIpdPatientPageState.mediumGreyText, fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: _ManageIpdPatientPageState.mediumGreyText),
        onTap: onTap,
        onLongPress: onLongPress,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: _ManageIpdPatientPageState.primaryBlue.withOpacity(0.3),
                width: 1)),
        tileColor: _ManageIpdPatientPageState.primaryBlue
            .withOpacity(0.03),
      ),
    );
  }
}

class _PairedPageTile extends StatelessWidget {
  final DrawingPage pageFront;
  final DrawingPage? pageBack;
  final VoidCallback onFrontTap;
  final VoidCallback? onBackTap;
  final VoidCallback onFrontLongPress;
  final VoidCallback? onBackLongPress;

  const _PairedPageTile({
    required this.pageFront,
    this.pageBack,
    required this.onFrontTap,
    this.onBackTap,
    required this.onFrontLongPress,
    this.onBackLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildTileCard(
            context,
            page: pageFront,
            onTap: onFrontTap,
            onLongPress: onFrontLongPress,
            isFront: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildTileCard(
            context,
            page: pageBack,
            onTap: onBackTap,
            onLongPress: onBackLongPress,
            isFront: false,
          ),
        ),
      ],
    );
  }

  Widget _buildTileCard(
      BuildContext context, {
        DrawingPage? page,
        VoidCallback? onTap,
        VoidCallback? onLongPress,
        bool isFront = true,
      }) {
    final bool isEmpty = page == null;
    final String defaultText = isFront ? "(Front)" : "(Back)";
    final String baseName = page?.pageName
        .split(' - ')[0]
        .replaceAll(RegExp(r'\s*\((Front|Back)\)$'), '')
        .trim() ??
        defaultText;

    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isEmpty
              ? Colors.grey[300]!
              : _ManageIpdPatientPageState.primaryBlue.withOpacity(0.4),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isEmpty ? null : onTap,
        onLongPress: isEmpty ? null : onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    isEmpty
                        ? Icons.disabled_by_default_outlined
                        : (isFront
                        ? Icons.flip_to_front_outlined
                        : Icons.flip_to_back_outlined),
                    color: isEmpty
                        ? Colors.grey[400]
                        : _ManageIpdPatientPageState.primaryBlue,
                    size: 18,
                  ),
                  Text(
                    page != null
                        ? "Page ${page.pageNumber}"
                        : (isFront ? "Front" : "Back"),
                    style: const TextStyle(
                        color: _ManageIpdPatientPageState.mediumGreyText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                baseName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isEmpty
                      ? _ManageIpdPatientPageState.mediumGreyText
                      : _ManageIpdPatientPageState.darkText,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (page?.locationTag != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    page!.locationTag!,
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              const SizedBox(height: 4),
              Text(
                page != null
                    ? DateFormat('dd MMM yy').format(
                    DateTime.tryParse(page.pageName.split(' - ').last) ??
                        DateTime.now())
                    : " ",
                style: TextStyle(
                  color: _ManageIpdPatientPageState.mediumGreyText
                      .withOpacity(0.8),
                  fontSize: 11,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}