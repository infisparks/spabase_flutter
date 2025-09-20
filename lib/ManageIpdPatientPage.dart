// File: ManageIpdPatientPage.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'supabase_config.dart';
import 'prescription_page.dart';
import 'patient_documents_page.dart'; // New Import
import 'dart:math';
import 'dart:ui' show Offset;

// --- Helper Functions for Robust JSON Parsing ---
int _safeParseInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? defaultValue;
  return defaultValue;
}

double _safeParseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? defaultValue;
  return defaultValue;
}

// --- Data Models for Supabase Serialization ---
String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(100000).toString();
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

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    'colorValue': colorValue,
    'strokeWidth': strokeWidth,
  };

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    return DrawingLine(
      points: (json['points'] as List<dynamic>?)
          ?.map((p) => Offset(_safeParseDouble(p['dx']), _safeParseDouble(p['dy'])))
          .toList() ?? [],
      colorValue: _safeParseInt(json['colorValue']),
      strokeWidth: _safeParseDouble(json['strokeWidth']),
    );
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
        _safeParseDouble(positionJson['dx']),
        _safeParseDouble(positionJson['dy']),
      ),
      colorValue: _safeParseInt(json['colorValue']),
      fontSize: _safeParseDouble(json['fontSize'], defaultValue: 16.0),
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
      pageNumber: _safeParseInt(json['pageNumber']),
      pageName: json['pageName'] as String? ?? 'Unnamed Page',
      groupName: json['groupName'] as String? ?? 'Uncategorized',
      lines: (json['lines'] as List<dynamic>?)
          ?.map((lineJson) => DrawingLine.fromJson(lineJson as Map<String, dynamic>))
          .toList() ?? [],
      texts: (json['texts'] as List<dynamic>?)
          ?.map((textJson) => DrawingText.fromJson(textJson as Map<String, dynamic>))
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
          ?.map((pageJson) => DrawingPage.fromJson(pageJson as Map<String, dynamic>))
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
    return SupabaseTemplateImage(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Template',
      url: json['url'] as String? ?? '',
      url2: json['2url'] as String?,
      isbook: json['isbook'] as bool? ?? false,
      bookImgUrl: (json['book_img_url'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
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
      // FIX: Use a more robust join syntax with aliased tables
      final patientDetailsResponse = await supabase
          .from('ipd_registration')
          .select('uhid, patient:patient_detail(name), bed:bed_management(room_type, bed_number)')
          .eq('ipd_id', widget.ipdId)
          .single();

      // FIX: Access the data using the aliases
      final patientData = patientDetailsResponse['patient'];
      _patientName = (patientData != null) ? patientData['name'] as String? : 'N/A';

      final bedData = patientDetailsResponse['bed'];
      if (bedData != null) {
        final roomType = bedData['room_type'] as String?;
        final bedNumber = bedData['bed_number'] as String?;
        _roomType = '${roomType ?? 'N/A'} - Bed: ${bedNumber ?? 'N/A'}';
      } else {
        _roomType = 'N/A';
      }

      // Fetch available templates, including the 'tag'
      final List<Map<String, dynamic>> templateData = await supabase
          .from('template_images')
          .select('id, name, url, 2url, isbook, book_img_url, tag');
      _availableTemplates = templateData.map((json) => SupabaseTemplateImage.fromJson(json)).toList();

      // Fetch existing health records
      final response = await supabase
          .from('user_health_details')
          .select('id, prescription_data, ipd_registration_id')
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      if (response != null) {
        _healthRecordId = response['id'] as String;
        final List<dynamic> rawGroups = response['prescription_data'] ?? [];
        setState(() {
          _drawingGroups = rawGroups.map((json) => DrawingGroup.fromJson(json)).toList();
        });
      } else {
        debugPrint('No existing health records found. Creating default group.');
        final defaultGroup = DrawingGroup(
          id: generateUniqueId(),
          groupName: 'Indoor Patient Progress Digital',
          pages: [],
        );
        setState(() {
          _drawingGroups = [defaultGroup];
          _healthRecordId = null;
        });
        await _saveHealthDetails();
        debugPrint('Default group created and saved.');
      }
    } on PostgrestException catch (e) {
      debugPrint('Supabase Error loading data: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('General Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load IPD records: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveHealthDetails() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });
    try {
      final List<Map<String, dynamic>> groupsJson = _drawingGroups.map((group) => group.toJson()).toList();

      final List<Map<String, dynamic>> response = await supabase
          .from('user_health_details')
          .upsert({
        'ipd_registration_id': widget.ipdId,
        'patient_uhid': widget.uhid,
        'prescription_data': groupsJson,
        if (_healthRecordId != null) 'id': _healthRecordId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'ipd_registration_id, patient_uhid')
          .select('id');

      if (response.isNotEmpty && response[0]['id'] != null) {
        if (mounted) {
          if (_healthRecordId == null) {
            _healthRecordId = response[0]['id'] as String;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Details saved successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception('Failed to save details (no ID returned).');
      }
    } on PostgrestException catch (e) {
      debugPrint('Supabase Error saving details: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Supabase Error: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('Error saving details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _createNewGroup() {
    TextEditingController groupNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Create New Group", style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
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
              style: TextButton.styleFrom(foregroundColor: mediumGreyText),
              child: const Text("Cancel", style: TextStyle(fontSize: 15)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text("Create", style: TextStyle(fontSize: 15)),
              onPressed: () {
                if (groupNameController.text.isNotEmpty) {
                  setState(() {
                    _drawingGroups.add(DrawingGroup(
                      id: generateUniqueId(),
                      groupName: groupNameController.text,
                      pages: [],
                    ));
                  });
                  _saveHealthDetails();
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _addNewPageToGroup(DrawingGroup group) async {
    if (group.groupName == 'Indoor Patient Progress Digital') {
      final t9Template = _availableTemplates.firstWhere(
            (t) => t.tag == 't9',
        orElse: () => SupabaseTemplateImage(
          id: '',
          name: '',
          url: '',
          isbook: false,
          bookImgUrl: [],
        ),
      );

      if (t9Template.id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Required "t9" template not found. Cannot add page.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final formattedDate = DateFormat('dd MMM yyyy').format(DateTime.now());
      final newPageName = 'Page ${group.pages.length + 1} - $formattedDate';

      final newPage = DrawingPage(
        id: generateUniqueId(),
        templateImageUrl: t9Template.url,
        pageNumber: group.pages.length + 1,
        pageName: newPageName,
        groupName: group.groupName,
      );

      setState(() {
        final updatedPages = List<DrawingPage>.from(group.pages)..add(newPage);
        final updatedGroup = group.copyWith(pages: updatedPages);
        final groupIndex = _drawingGroups.indexWhere((g) => g.id == group.id);
        if (groupIndex != -1) {
          _drawingGroups[groupIndex] = updatedGroup;
        }
      });

      await _saveHealthDetails();
      return;
    }

    _showTemplateDialogForGroup(group);
  }

  void _showTemplateDialogForGroup(DrawingGroup group) async {
    final templatesForDialog = _availableTemplates;

    if (templatesForDialog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No templates available. Please add templates to the database.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    SupabaseTemplateImage? selectedTemplate = await _showTemplateSelectionDialog(templatesForDialog);

    if (selectedTemplate == null || !mounted) return;

    TextEditingController pageNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Add New Page", style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pageNameController,
                decoration: InputDecoration(
                  hintText: "Enter page name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: primaryBlue, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: lightBlue,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primaryBlue.withAlpha((255 * 0.3).round())),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image, color: primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Template: ${selectedTemplate.name}",
                        style: const TextStyle(fontSize: 15, color: darkText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(foregroundColor: mediumGreyText),
              child: const Text("Cancel", style: TextStyle(fontSize: 15)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text("Add Page", style: TextStyle(fontSize: 15)),
              onPressed: () {
                if (pageNameController.text.isNotEmpty) {
                  setState(() {
                    final newPage = DrawingPage(
                      id: generateUniqueId(),
                      templateImageUrl: selectedTemplate.url,
                      pageNumber: group.pages.length + 1,
                      pageName: pageNameController.text,
                      groupName: group.groupName,
                    );
                    final updatedPages = List<DrawingPage>.from(group.pages)..add(newPage);
                    final updatedGroup = group.copyWith(pages: updatedPages);
                    final groupIndex = _drawingGroups.indexWhere((g) => g.id == group.id);
                    if (groupIndex != -1) {
                      _drawingGroups[groupIndex] = updatedGroup;
                    }
                  });
                  _saveHealthDetails();
                  Navigator.pop(context);
                }
              },
            ),
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
              title: const Text("Select Template", style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Search templates...",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: primaryBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 15),
                      onChanged: (query) {
                        setState(() {
                          filteredTemplates = templatesToShow
                              .where((template) =>
                              template.name.toLowerCase().contains(query.toLowerCase()))
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
                            title: Text(template.name, style: const TextStyle(fontSize: 15)),
                            onTap: () {
                              Navigator.pop(context, template);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: mediumGreyText),
                  child: const Text("Cancel", style: TextStyle(fontSize: 15)),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          groupId: group.id,
          pageId: page.id,
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
      final filteredPages = group.pages.where((page) =>
      page.pageName.toLowerCase().contains(lowerQuery) ||
          page.groupName.toLowerCase().contains(lowerQuery)).toList();
      return group.copyWith(pages: filteredPages);
    }).where((group) => group.pages.isNotEmpty || group.groupName.toLowerCase().contains(lowerQuery)).toList();

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: const Text(
          "Manage Patient Details",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: darkText),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withAlpha((255 * 0.08).round()),
        toolbarHeight: 60,
        centerTitle: false,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16.0, horizontalPadding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Patient Information",
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: darkText),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.person_outline, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("Name: ${_patientName ?? 'N/A'}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.medical_information_outlined, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("IPD ID: ${widget.ipdId}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.credit_card_outlined, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("UHID: ${widget.uhid}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.local_hospital_outlined, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("Room: ${_roomType ?? 'N/A'}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey[200]!, width: 1)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryBlue, width: 2)),
                          ),
                          style: const TextStyle(fontSize: 15),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
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
                              boxShadow: [BoxShadow(color: Colors.black.withAlpha((255 * 0.05).round()), blurRadius: 3, offset: const Offset(0, 1))],
                            ),
                            child: _isSaving
                                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: primaryBlue))
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
                        label: const Text("Manage Documents", style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          elevation: 3,
                          shadowColor: primaryBlue.withAlpha((255 * 0.2).round()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _createNewGroup,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text("Create New Group", style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          elevation: 3,
                          shadowColor: primaryBlue.withAlpha((255 * 0.2).round()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          if (_drawingGroups.isEmpty && !_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off_outlined, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text("No Groups Available", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                      const SizedBox(height: 8),
                      const Text(
                        "Click on 'Create New Group' to get started.",
                        style: TextStyle(fontSize: 15, color: mediumGreyText),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (displayedGroups.isEmpty && _searchQuery.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text("No Results Found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                      const SizedBox(height: 8),
                      Text(
                        "Your search for '$_searchQuery' did not match any pages or groups.",
                        style: const TextStyle(fontSize: 15, color: mediumGreyText),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
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
                          title: Text(group.groupName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_box_rounded, color: primaryBlue, size: 24),
                            onPressed: () => _addNewPageToGroup(group),
                            tooltip: "Add New Page to ${group.groupName}",
                          ),
                          iconColor: primaryBlue,
                          collapsedIconColor: mediumGreyText,
                          childrenPadding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 8.0),
                          children: [
                            const Divider(height: 1, thickness: 1, color: lightBackground),
                            if (group.pages.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  "No pages in this group. Click '+' to add one.",
                                  style: TextStyle(color: mediumGreyText, fontStyle: FontStyle.italic, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ...group.pages.map((page) {
                              return Column(
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.description_outlined, color: primaryBlue, size: 22),
                                    title: Text(page.pageName, style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 15)),
                                    subtitle: Text("Page ${page.pageNumber}", style: const TextStyle(color: mediumGreyText, fontSize: 13)),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: mediumGreyText),
                                    onTap: () => _openPrescriptionPage(group, page),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    hoverColor: lightBlue.withAlpha((255 * 0.5).round()),
                                  ),
                                  if (page != group.pages.last)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Divider(height: 1, thickness: 0.5, color: lightBackground),
                                    ),
                                ],
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