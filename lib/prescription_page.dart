import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math'; // Added for sqrt()
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'app_clipboard.dart'; // Import the new file
import 'supabase_config.dart';
import 'image_manipulation_helpers.dart';
import 'patient_info_header_card.dart';
import 'drawing_models.dart';
import 'pdf_generator.dart';
// --- NEW IMPORT ---
import 'floating_reference_window.dart'; // Import the new reusable file
import 'page_layout_definitions.dart'; // Import the new file
import 'package:medford_app/marco/drawing_macro_model.dart'; // NEW
import 'package:medford_app/marco/autocompletesidebar.dart'; // NEW
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
const String kSupabaseBucketName = 'pages';

// Application Colors
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);
const Color mediumGreyText = Color(0xFF64748B);
const Color lightBackground = Color(0xFFF8FAFC);

enum DrawingTool { pen, eraser, image, lasso }

// class _CopiedPageData {
//   final List<DrawingLine> lines;
//   final List<DrawingImage> images;
//   _CopiedPageData({required this.lines, required this.images});
// }

// --- ADDED: Model for content currently being transformed after paste ---
class _PastedTransformData {
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  final Offset offset;
  final double scale;
  _PastedTransformData({
    required this.lines,
    required this.images,
    this.offset = Offset.zero,
    this.scale = 1.0,
  });

  _PastedTransformData copyWith({
    List<DrawingLine>? lines,
    List<DrawingImage>? images,
    Offset? offset,
    double? scale,
  }) {
    return _PastedTransformData(
      lines: lines ?? this.lines,
      images: images ?? this.images,
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
    );
  }
}
// --- END ADDED MODEL ---


class UploadedImage {
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
  bool _isSidebarOpen = false;
  final SupabaseClient supabase = SupabaseConfig.client;
  final ImagePicker _picker = ImagePicker();

// --- NEW: MACRO LOGIC START ---

  // 1. Logic to Save the selection as a Macro
  // --- NEW MACRO SAVE LOGIC (Uses Clipboard Data) ---
  Future<void> _saveMacroFromClipboard() async {
    final copiedData = AppClipboard().getData();

    if (copiedData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No content in clipboard to save! Copy something first.'))
      );
      return;
    }

    // 1. Calculate Bounds from the CLIPBOARD DATA to normalize it
    // We need to find the top-left corner of the copied content so we can save it starting at (0,0)
    double minX = double.infinity;
    double minY = double.infinity;

    for (var line in copiedData.lines) {
      for (var p in line.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
      }
    }
    for (var img in copiedData.images) {
      if (img.position.dx < minX) minX = img.position.dx;
      if (img.position.dy < minY) minY = img.position.dy;
    }

    // If content was empty (rare), default to 0
    if (minX == double.infinity) minX = 0;
    if (minY == double.infinity) minY = 0;

    final Offset origin = Offset(minX, minY);
    TextEditingController nameController = TextEditingController();

    // 2. Show Name Dialog
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Macro from Clipboard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Save the currently copied content as a reusable macro.'),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Macro Name',
                hintText: 'e.g., Rx Paracetamol',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    // 3. Normalize Data (Shift points to 0,0 based on calculated origin)
    final normalizedLines = copiedData.lines.map((line) {
      return line.copyWith(
        points: line.points.map((p) => p - origin).toList(),
      );
    }).toList();

    final normalizedImages = copiedData.images.map((img) {
      return img.copyWith(position: img.position - origin);
    }).toList();

    // 4. Save to Supabase
    try {
      final newMacro = MedicalMacro(
        id: '', // DB generates this
        name: name,
        lines: normalizedLines,
        images: normalizedImages,
        userId: supabase.auth.currentUser?.id,
      );

      await supabase.from('medical_macros').insert({
        'name': newMacro.name,
        'content': newMacro.toContentJson(),
        'user_id': supabase.auth.currentUser?.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Macro Saved Successfully!'), backgroundColor: Colors.green));

      // Optional: Clear clipboard after saving?
      // AppClipboard().clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving macro: $e'), backgroundColor: Colors.red));
    }
  }

// --- ADD THIS MISSING FUNCTION ---
  // --- UPDATED: FETCH HEAVY DATA ON DROP ---
  Future<void> _onMacroDropped(MedicalMacro lightweightMacro, Offset localOffset) async {
    // 1. Show a quick loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Downloading macro data...'),
            duration: Duration(milliseconds: 800)
        )
    );

    try {
      // 2. Fetch the heavy 'content' column JUST for this macro
      final response = await supabase
          .from('medical_macros')
          .select('content')
          .eq('id', lightweightMacro.id)
          .single();

      if (response == null) throw "Macro data not found";

      // 3. Parse the heavy data manually
      final content = response['content'] as Map<String, dynamic>;

      final fetchedLines = (content['lines'] as List<dynamic>?)
          ?.map((e) => DrawingLine.fromJson(e))
          .toList() ?? [];

      final fetchedImages = (content['images'] as List<dynamic>?)
          ?.map((e) => DrawingImage.fromJson(e))
          .toList() ?? [];

      // 4. Generate new IDs and Paste
      final pastedImages = fetchedImages.map((img) => img.copyWith(id: generateUniqueId())).toList();
      final pastedLines = fetchedLines.map((line) => line.copyWith()).toList();

      setState(() {
        _pastedTransformData = _PastedTransformData(
          lines: pastedLines,
          images: pastedImages,
          offset: _transformToCanvasCoordinates(localOffset),
          scale: 1.0,
        );
        _isTransformingPastedContent = true;
        _selectedTool = DrawingTool.image;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load macro: $e'), backgroundColor: Colors.red)
      );
    }
  }
  // -------------------------------



// --- NEW FUNCTION: Refresh and Update Current Page ---
  Future<void> _refreshAndApplyDetails() async {
    setState(() => _isLoadingPrescription = true);

    try {
      // 1. Fetch latest data
      final ipdResponse = await supabase
          .from('ipd_registration')
          .select('*, patient_detail(*), bed_management(*)')
          .eq('uhid', widget.uhid)
          .eq('ipd_id', widget.ipdId)
          .maybeSingle();

      if (ipdResponse != null) {
        // 2. Update local state
        setState(() {
          _ipdRegistrationDetails = ipdResponse;
          _patientDetails = ipdResponse['patient_detail'] as Map<String, dynamic>? ?? {};
          _bedDetails = ipdResponse['bed_management'] as Map<String, dynamic>? ?? {};
          _patientName = _patientDetails['name'] as String? ?? 'N/A';
        });

        // 3. Get Layout from the new separate file
        final targetLayout = PageLayoutDefinitions.getLayoutForGroup(widget.groupName);

        if (targetLayout != null) {
          // We need to cast it correctly for the helper function
          // If it's the specific Indoor layout, logic is handled inside _applyNewDetailsToPage
          // but for generic mapping, we pass the map.
          _applyNewDetailsToPage(targetLayout);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Details refreshed and layout applied!'),
                backgroundColor: Colors.green));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No auto-fill layout defined for this page type.'),
                backgroundColor: Colors.orange));
          }
        }
      }
    } catch (e) {
      debugPrint("Error refreshing details: $e");
    } finally {
      if (mounted) setState(() => _isLoadingPrescription = false);
    }
  }

  void _applyNewDetailsToPage(Map<String, dynamic> layout) {
    // Normalize the group name for safe comparison
    final String cleanGroupName = widget.groupName.trim().toUpperCase();

    // --- CHECK: Page Logic for Daily Drug Chart ---
    if (cleanGroupName == 'DAILY DRUG CHART' && _currentPageIndex % 2 != 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Header details are only applied to the front page of the Drug Chart.'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    // --- FIX: OT LOGIC (Skip Page 1 / Index 0) ---
    // Using cleanGroupName ensures it catches "OT", "ot", " OT " etc.
    if (cleanGroupName == 'OT' && _currentPageIndex == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Header details are NOT applied to the first page of the OT Form.'),
            backgroundColor: Colors.orange));
      }
      return; // <--- This STOPS the function here for Page 1
    }
    // 1. Prepare Data Strings
    final String name = _patientDetails['name'] ?? '';
    String fullUhid = widget.uhid;
    final String uhid = fullUhid.length > 5 ? fullUhid.substring(fullUhid.length - 5) : fullUhid;
    final String ipd = widget.ipdId.toString();
    final String ageVal = _patientDetails['age']?.toString() ?? '';
    final String sexVal = _patientDetails['gender'] ?? '';
    final String ageSex = "$ageVal / $sexVal";
    final String doa = _ipdRegistrationDetails['admission_date']?.toString() ?? '';
    final String admTime = _ipdRegistrationDetails['admission_time']?.toString() ?? '';
    final String consultant = _ipdRegistrationDetails['under_care_of_doctor'] ?? '';
    String room = _bedDetails['room_type']?.toString() ?? '';
    String bedNo = _bedDetails['bed_number']?.toString() ?? '';
    final String soWoDo = _ipdRegistrationDetails['so_wo_do'] ?? '';
    final String roomWard = "$room / $bedNo";
    final String contact = _patientDetails['number']?.toString() ?? '';
    String address = _patientDetails['address'] ?? '';
    if (address.isEmpty) address = _ipdRegistrationDetails['relative_address'] ?? '';
    final String referredBy = _ipdRegistrationDetails['admission_source'] ?? '';

    // 2. Get Current Texts
    final currentPage = _viewablePages[_currentPageIndex];
    List<DrawingText> currentTexts = List.from(currentPage.texts);

    // 3. Remove OLD auto-filled texts
    for (var entry in layout.entries) {
      final config = entry.value as Map<String, dynamic>;
      final targetPos = Offset(config['x'] as double, config['y'] as double);
      currentTexts.removeWhere((t) =>
      (t.position.dx - targetPos.dx).abs() < 1.0 &&
          (t.position.dy - targetPos.dy).abs() < 1.0);
    }

    // 4. Create NEW texts
    List<DrawingText> newTexts = [];

    void addText(String key, String value) {
      if (value.isEmpty || !layout.containsKey(key)) return;
      final config = layout[key] as Map<String, dynamic>;

      double specificFontSize = config.containsKey('fontSize')
          ? (config['fontSize'] as num).toDouble()
          : 15.0;

      newTexts.add(DrawingText(
        id: generateUniqueId(),
        text: value.toUpperCase(),
        position: Offset(config['x'] as double, config['y'] as double),
        colorValue: Colors.black.value,
        fontSize: specificFontSize,
      ));
    }

    bool separateAgeSex = (layout == PageLayoutDefinitions.indoorFileLayout) ||
        (layout == PageLayoutDefinitions.dailyDrugChartLayout);

    addText('patient_name', name);
    addText('so_wo_do', soWoDo);
    addText('age', separateAgeSex ? ageVal : ageSex);
    addText('sex', sexVal);
    addText('uhid', uhid);
    addText('room_ward', roomWard);
    addText('bed_details', roomWard);
    addText('ipd_no', ipd);
    addText('doa', doa);
    addText('admission_date', doa);
    addText('admission_time', admTime);
    addText('consultant', consultant);
    addText('contact', contact);
    addText('referred_dr', referredBy);

    if (layout == PageLayoutDefinitions.indoorFileLayout && address.isNotEmpty) {
      final config1 = layout['address'] as Map<String, dynamic>;
      final config2 = layout['address_line_2'] as Map<String, dynamic>;
      double width = config1['width'] as double;
      int charsPerLine1 = (width / 12).floor();

      if (address.length <= charsPerLine1) {
        addText('address', address);
      } else {
        int splitIndex = address.lastIndexOf(' ', charsPerLine1);
        if (splitIndex == -1) splitIndex = charsPerLine1;
        addText('address', address.substring(0, splitIndex));

        newTexts.add(DrawingText(
          id: generateUniqueId(),
          text: address.substring(splitIndex).trim().toUpperCase(),
          position: Offset(config2['x'] as double, config2['y'] as double),
          colorValue: Colors.black.value,
          fontSize: 15.0,
        ));
      }
    }

    currentTexts.addAll(newTexts);
    setState(() {
      _viewablePages[_currentPageIndex] = currentPage.copyWith(texts: currentTexts);
    });
    _savePrescriptionData();
  }

  static final Map<String, Map<String, double>> _progressNoteLayout = {
    // ADJUST 'x' AND 'y' TO MATCH YOUR TEMPLATE LINES
    'patient_name': {'x': 194, 'y': 228},
    'uhid':         {'x': 500, 'y': 258},

    'room_ward':    {'x': 200, 'y': 258},
    'ipd_no':       {'x': 682, 'y': 258},
    'age':          {'x': 834, 'y': 228},
    'doa':          {'x': 808, 'y': 258},
    'consultant':   {'x': 155, 'y': 289},
  };



  static final Map<String, Map<String, double>> _indoorFileLayout = {
    // Line 1: Patient Name
    'patient_name':   {'x': 191, 'y': 740, 'width': 400},
    'so_wo_do':       {'x': 194, 'y': 780, 'width': 200},
    // Line 3: Age / Sex / Date / Time
    'age':            {'x': 113, 'y': 823, 'width': 80},
    'sex':            {'x': 215, 'y': 823, 'width': 80},
    'admission_date': {'x': 445, 'y': 823, 'width': 200},
    'admission_time': {'x': 745, 'y': 823, 'width': 100},

    // Line 4: UHID / IPD / Address
    'uhid':           {'x': 156, 'y': 862, 'width': 200},
    'ipd_no':         {'x': 461, 'y': 862, 'width': 180},
    'address':        {'x': 740, 'y': 862, 'width': 300}, // Very small space on form

    // Overflow Address (Placed slightly below if needed, or you can map it to S/o line)
    'address_line_2': {'x': 73,  'y': 903, 'width': 1000},

    // Line 5: Contact No
    'contact':        {'x': 175, 'y': 947, 'width': 400},

    // Line 6: Consultant
    'consultant':     {'x': 233, 'y': 989, 'width': 450},

    // Line 7: Bed / Referred Dr
    'bed_details':    {'x': 214, 'y': 1031, 'width': 300},
    'referred_dr':    {'x': 574, 'y': 1031, 'width': 300},
  };
  Future<CroppedFile?> _cropImage(XFile pickedFile) async {
    return await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      // Compress quality to keep uploads fast
      compressQuality: 80,
      // UI Settings for Android and iOS
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop & Rotate',
          toolbarColor: primaryBlue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Crop & Rotate',
        ),
      ],
    );
  }


  // --- UPDATED FUNCTION TO HANDLE MULTIPLE GROUPS ---
  void _autoFillCommonPages() {
    final layout = PageLayoutDefinitions.getLayoutForGroup(widget.groupName);
    if (layout == null || layout == PageLayoutDefinitions.indoorFileLayout) return;

    if (_viewablePages.isEmpty) return;

    // Prepare Data
    final String name = _patientDetails['name'] ?? '';
    String fullUhid = widget.uhid;
    final String uhid = fullUhid.length > 5 ? fullUhid.substring(fullUhid.length - 5) : fullUhid;
    final String ipd = widget.ipdId.toString();
    final String ageVal = _patientDetails['age']?.toString() ?? '';
    final String sexVal = _patientDetails['gender'] ?? '';
    final String soWoDo = _ipdRegistrationDetails['so_wo_do'] ?? '';
    final String ageSex = "$ageVal / $sexVal";
    final String doa = _ipdRegistrationDetails['admission_date']?.toString() ?? '';
    final String consultant = _ipdRegistrationDetails['under_care_of_doctor'] ?? '';
    String room = _bedDetails['room_type']?.toString() ?? '';
    String bedNo = _bedDetails['bed_number']?.toString() ?? '';
    final String roomWard = "$room / $bedNo";

    // Normalize group name
    final String cleanGroupName = widget.groupName.trim().toUpperCase();

    // Check specific flags
    bool isDailyDrugChart = (cleanGroupName == 'DAILY DRUG CHART');
    bool isOT = (cleanGroupName == 'OT'); // Robust check for OT
    bool separateAgeSex = isDailyDrugChart;

    bool dataChanged = false;
    List<DrawingPage> updatedPages = [..._viewablePages];

    for (int i = 0; i < updatedPages.length; i++) {
      // Logic for Drug Chart
      if (isDailyDrugChart && i % 2 != 0) continue;

      // --- FIX: Logic for OT (Strictly skip index 0) ---
      if (isOT && i == 0) continue;
      // ------------------------------------------------

      if (updatedPages[i].texts.isNotEmpty) continue;

      List<DrawingText> newTexts = [];

      void addText(String key, String value) {
        if (value.isEmpty || !layout.containsKey(key)) return;
        final config = layout[key] as Map<String, dynamic>;

        double specificFontSize = config.containsKey('fontSize')
            ? (config['fontSize'] as num).toDouble()
            : 15.0;

        newTexts.add(DrawingText(
          id: generateUniqueId(),
          text: value.toUpperCase(),
          position: Offset(config['x'] as double, config['y'] as double),
          colorValue: Colors.black.value,
          fontSize: specificFontSize,
        ));
      }

      addText('patient_name', name);
      addText('age', separateAgeSex ? ageVal : ageSex);
      addText('sex', sexVal);
      addText('so_wo_do', soWoDo);
      addText('uhid', uhid);
      addText('room_ward', roomWard);
      addText('ipd_no', ipd);
      addText('doa', doa);
      addText('admission_date', doa);
      addText('consultant', consultant);

      if (newTexts.isNotEmpty) {
        updatedPages[i] = updatedPages[i].copyWith(texts: newTexts);
        dataChanged = true;
      }
    }

    if (dataChanged) {
      setState(() {
        _viewablePages = updatedPages;
      });
      _savePrescriptionData();
    }
  }
    // 4. Save if any page was updated



// --- 2. NEW: PASTE THIS ENTIRE FUNCTION ---
  void _autoFillIndoorPatientFile() {
    // Only run for "Indoor Patient File" and only if the page is empty
    if (widget.groupName != 'Indoor Patient File') return;
    if (_viewablePages.isEmpty || _viewablePages[_currentPageIndex].texts.isNotEmpty) return;

    // Prepare Data safely
    final String name = _patientDetails['name'] ?? '';
    final String soWoDo = _ipdRegistrationDetails['so_wo_do'] ?? '';
    final String age = _patientDetails['age']?.toString() ?? '';
    final String sex = _patientDetails['gender'] ?? '';
    final String uhid = widget.uhid;
    final String ipd = widget.ipdId.toString();
    final String mobile = _patientDetails['number']?.toString() ?? '';
    final String consultant = _ipdRegistrationDetails['under_care_of_doctor'] ?? '';

    String address = _patientDetails['address'] ?? '';
    if (address.isEmpty) address = _ipdRegistrationDetails['relative_address'] ?? '';

    String admDate = _ipdRegistrationDetails['admission_date']?.toString() ?? '';
    String admTime = _ipdRegistrationDetails['admission_time']?.toString() ?? '';
    String room = _bedDetails['room_type']?.toString() ?? '';
    String bedNo = _bedDetails['bed_number']?.toString() ?? '';
    // Combine them with a " / " as you requested
    final String bed = "$room / $bedNo";
    final String referredBy = _ipdRegistrationDetails['admission_source'] ?? '';

    List<DrawingText> newTexts = [];

    final layout = PageLayoutDefinitions.indoorFileLayout;

    void addText(String key, String value) {
      if (value.isEmpty || !layout.containsKey(key)) return;
      final config = layout[key] as Map<String, dynamic>;
      newTexts.add(DrawingText(
        id: generateUniqueId(),
        text: value.toUpperCase(),
        position: Offset(config['x'] as double, config['y'] as double),
        colorValue: Colors.black.value,
        fontSize: 15.0,
      ));
    }

    addText('patient_name', name);
    addText('age', age);
    addText('sex', sex);
    addText('admission_date', admDate);
    addText('so_wo_do', soWoDo); // <-- ADD THIS LINE
    addText('admission_time', admTime);
    addText('uhid', uhid);
    addText('ipd_no', ipd);
    addText('contact', mobile);
    addText('consultant', consultant);
    addText('bed_details', bed);
    addText('referred_dr', referredBy);

    // Address logic
    if (address.isNotEmpty) {
      final config1 = _indoorFileLayout['address']!;
      final config2 = _indoorFileLayout['address_line_2']!;
      int charsPerLine1 = (config1['width']! / 12).floor();

      if (address.length <= charsPerLine1) {
        addText('address', address);
      } else {
        int splitIndex = address.lastIndexOf(' ', charsPerLine1);
        if (splitIndex == -1) splitIndex = charsPerLine1;
        addText('address', address.substring(0, splitIndex));

        newTexts.add(DrawingText(
          id: generateUniqueId(),
          text: address.substring(splitIndex).trim(),
          position: Offset(config2['x']!, config2['y']!),
          colorValue: Colors.black.value,
          fontSize: 15.0,
        ));
      }
    }

    if (newTexts.isNotEmpty) {
      setState(() {
        final currentPage = _viewablePages[_currentPageIndex];
        _viewablePages[_currentPageIndex] = currentPage.copyWith(
            texts: [...currentPage.texts, ...newTexts]
        );
      });
      _savePrescriptionData(); // Auto-save
    }
  }
  // --- Data State ---
  List<DrawingPage> _viewablePages = [];
  int _currentPageIndex = 0;
  String? _healthRecordId;
  DrawingGroup? _currentGroup;
  List<DrawingPage> _pagesInCurrentGroup = [];
  // _CopiedPageData? _copiedPageData;
  List<UploadedImage> _userUploadedImages = [];
  List<StampImage> _stamps = [];
  String _patientName = 'Loading Patient Name...';
  Map<String, dynamic> _patientDetails = {};
  Map<String, dynamic> _ipdRegistrationDetails = {};
  Map<String, dynamic> _bedDetails = {};
  List<DrawingGroup>? _allPatientGroups;
  bool _isLoadingAllGroups = false;

  // --- UPDATED: State for PiP (Reference) Window ---
  bool _isPipWindowVisible = false;
  // Use the new type alias
  PipSelectedPageData? _pipSelectedPageData;
  Offset _pipPosition = const Offset(50, 50);
  Size _pipSize = const Size(400, 565); // A4 aspect ratio

  // --- ADDED: State for Post-Paste Transformation ---
  bool _isTransformingPastedContent = false;
  _PastedTransformData? _pastedTransformData;
  Offset? _pasteDragStartLocal; // Local position where drag started relative to the content's origin
  // --- END ADDED STATE ---

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
    'Icu chart': 'icu_chart_data',
    'Transfer Summary': 'transfer_summary_data',
    'Prescription Sheet': 'prescription_sheet_data',
    'Billing Consent': 'billing_consent_data'
  };
  void _nextPage() {
    if (_viewablePages.length <= 1) return;
    final newIndex = (_currentPageIndex + 1) % _viewablePages.length;
    _navigateToPage(newIndex);
  }

  void _previousPage() {
    if (_viewablePages.length <= 1) return;
    final newIndex = (_currentPageIndex - 1 + _viewablePages.length) %
        _viewablePages.length;
    _navigateToPage(newIndex);
  }

  void _clearCopiedContent() {
    HapticFeedback.mediumImpact();
    // REPLACE:
    AppClipboard().clear();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied content cleared.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2)));
  }

  Widget _buildFloatingCopyPasteButton() {
    // REPLACE CHECK:
    if (!AppClipboard().hasData || _isTransformingPastedContent) {
      return const SizedBox.shrink();
    }

    // Determine if content is available (Logic handled by AppClipboard now)
    return Positioned(
      bottom: 20,
      right: 20,
      child: FloatingActionButton.extended(
        onPressed: _pastePageContent,
        icon: const Icon(Icons.paste_rounded, size: 24),
        label: const Text('Paste Content'),
        tooltip: 'Paste Copied Content to this Page',
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 6,
      ),
    );
  }


  String _getBasePagePrefix(String pageName) {
    // 1. Remove date and time suffix (" - dd MMM yyyy" or similar)
    String baseName = pageName.split(' - ')[0].trim();

    // 2. If it's a paired page, use the part before the parenthesis.
    if (baseName.contains('(')) {
      return baseName.split('(')[0].trim();
    }

    // 3. If it's a single page (like Dr Visit), remove the number/set number.
    // Example: "Doctor Visit 1" -> "Doctor Visit"
    // Example: "Prescription 2" -> "Prescription"
    final parts = baseName.split(' ');
    if (parts.isNotEmpty && int.tryParse(parts.last) != null) {
      // Check if the last part looks like a number
      return parts.sublist(0, parts.length - 1).join(' ').trim();
    }

    // 4. Fallback (e.g., OT form, Consent names, or Custom names without numbers)
    return baseName;
  }

  // --- Drawing State ---
  // --- Drawing State ---
  Color _currentColor = Colors.black;
  double _strokeWidth = 2.0;
  DrawingTool _selectedTool = DrawingTool.pen;

  // REMOVED: _isEnhancedHandwriting, _isVelocitySensitive, _lastMoveTimestamp
  // KEPT: Pressure Sensitivity
  bool _isPressureSensitive = false;

  // REMOVED: Velocity constants (_kMinDrawVelocity, etc.)

  List<Offset> _lassoPoints = [];

  // --- Image Manipulation State ---
  String? _selectedImageId;
  Offset? _dragStartCanvasPosition;
  bool _isMovingSelectedImage = false;

  // --- View State ---
  PageController _pageController = PageController();
  final TransformationController _transformationController =
  TransformationController();
  bool _isLoadingPrescription = true;
  bool _isSaving = false;
  bool _isLoadingStamps = false;
  bool _isInitialZoomSet = false;
  bool _isStylusInteraction = false;
  final bool _isPenOnlyMode = true;
  final ValueNotifier<int> _redrawNotifier = ValueNotifier(0);

  // --- Autosave & Realtime State ---
  Timer? _debounceTimer;
  RealtimeChannel? _healthRecordChannel;
  DateTime? _lastSuccessfulSaveTime;
  bool _isDisposed = false;

  get pagePrefix => null;

  @override
  void initState() {
    super.initState();
    _loadHealthDetailsAndPage();
    _fetchUserUploadedImages();
    _fetchStamps();
    _transformationController.addListener(_onTransformUpdated);
    AppClipboard().hasDataNotifier.addListener(_onClipboardChanged);
  }

  @override
  void dispose() {
    _isDisposed = true;
    AppClipboard().hasDataNotifier.removeListener(_onClipboardChanged);
    _debounceTimer?.cancel();
    if (_healthRecordChannel != null) {
      supabase.removeChannel(_healthRecordChannel!);
    }
    _transformationController.removeListener(_onTransformUpdated);
    _transformationController.dispose();
    _pageController.dispose();
    _redrawNotifier.dispose();
    ImageCacheManager.clear();
    super.dispose();
  }
  void _onClipboardChanged() {
    if (mounted) setState(() {});
  }
  String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  // --- Data Loading, Saving, and Realtime ---

// --- 3. UPDATE: REPLACE YOUR EXISTING FUNCTION WITH THIS ONE ---
  Future<void> _loadHealthDetailsAndPage() async {
    if (!mounted) return;
    final String? currentPageIdBeforeRefresh = _viewablePages.isNotEmpty
        ? _viewablePages[_currentPageIndex].id
        : widget.pageId;

    setState(() => _isLoadingPrescription = true);

    try {
      final columnName =
          _groupToColumnMap[widget.groupName] ?? 'custom_groups_data';
      final columnsToSelect = ['id', columnName, 'custom_groups_data']
          .toSet()
          .join(',');

      final response = await supabase
          .from('user_health_details')
          .select(columnsToSelect)
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      if (response != null) {
        _healthRecordId = response['id'] as String?;

        final ipdResponse = await supabase
            .from('ipd_registration')
            .select('*, patient_detail(*), bed_management(*)')
            .eq('uhid', widget.uhid)
            .eq('ipd_id', widget.ipdId)
            .maybeSingle();

        if (ipdResponse != null) {
          _ipdRegistrationDetails = ipdResponse;
          _patientDetails =
              ipdResponse['patient_detail'] as Map<String, dynamic>? ?? {};
          _bedDetails =
              ipdResponse['bed_management'] as Map<String, dynamic>? ?? {};
          setState(() {
            _patientName = _patientDetails['name'] as String? ?? 'Patient Name N/A';
          });
        }

        if (columnName == 'custom_groups_data') {
          final rawCustomGroups = response['custom_groups_data'] ?? [];
          final customGroups = (rawCustomGroups as List?)
              ?.map((json) =>
              DrawingGroup.fromJson(json as Map<String, dynamic>))
              .toList() ??
              [];
          _currentGroup = customGroups.firstWhere((g) => g.id == widget.groupId,
              orElse: () =>
              throw Exception("Custom group '${widget.groupId}' not found."));
          _pagesInCurrentGroup = _currentGroup!.pages;
        } else {
          final rawPages = response[columnName] ?? [];
          _pagesInCurrentGroup = (rawPages as List?)
              ?.map((json) =>
              DrawingPage.fromJson(json as Map<String, dynamic>))
              .toList() ??
              [];
          _currentGroup = DrawingGroup(
              id: widget.groupName,
              groupName: widget.groupName,
              pages: _pagesInCurrentGroup);
        }

        String basePagePrefix = _getBasePagePrefix(_pagesInCurrentGroup.firstWhere(
                (p) => p.id == currentPageIdBeforeRefresh).pageName);

        _viewablePages = _pagesInCurrentGroup
            .where((p) => _getBasePagePrefix(p.pageName) == basePagePrefix)
            .toList();

        int initialIndex =
        _viewablePages.indexWhere((p) => p.id == currentPageIdBeforeRefresh);

        if (initialIndex != -1) {
          _currentPageIndex = initialIndex;
          _pageController.dispose();
          _pageController = PageController(initialPage: _currentPageIndex);
        }

        // --- MOVED: Trigger Auto Fill HERE (After data is loaded) ---
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _autoFillIndoorPatientFile();
            _autoFillCommonPages();
          }
        });
        // ----------------------------------

        _setupRealtimeSubscription();
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPrescription = false);
    }
  }

  void _setupRealtimeSubscription() {
    // ... (implementation unchanged)
    if (_healthRecordId == null || _healthRecordChannel != null) return;
    _healthRecordChannel = supabase
        .channel('public:user_health_details:id=eq.$_healthRecordId')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_health_details',
      filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _healthRecordId!),
      callback: (payload) async {
        if (_isDisposed) return;
        final newRecord = payload.newRecord;
        if (newRecord == null) return;
        final updatedAtString = newRecord['updated_at'] as String?;
        if (updatedAtString == null) return;
        final remoteUpdateTime = DateTime.parse(updatedAtString);

        if (_lastSuccessfulSaveTime != null &&
            remoteUpdateTime.difference(_lastSuccessfulSaveTime!).inSeconds.abs() < 5) {
          debugPrint('Ignoring self-initiated realtime update.');
          return;
        }

        if (mounted) {
          debugPrint("External update detected. Auto-refreshing...");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data was updated by another user. Refreshing...'),
              backgroundColor: primaryBlue,
              duration: Duration(seconds: 3),
            ),
          );
          await _loadHealthDetailsAndPage();
        }
      },
    )
        .subscribe();
  }

  void _debouncedSave() {
    // ... (implementation unchanged)
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      if (!_isSaving) {
        _savePrescriptionData();
      }
    });
  }

  void _syncViewablePagesToMasterList() {
    // ... (implementation unchanged)
    for (var viewablePage in _viewablePages) {
      int pageIndex =
      _pagesInCurrentGroup.indexWhere((p) => p.id == viewablePage.id);
      if (pageIndex != -1) {
        _pagesInCurrentGroup[pageIndex] = viewablePage;
      }
    }
  }
  int _retryAttempts = 0;
  Future<void> _savePrescriptionData({bool isManualSave = false}) async {

    // ... (implementation unchanged)
    _debounceTimer?.cancel();
    if (!mounted) return;
    setState(() => _isSaving = true);
    if (_healthRecordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error: Health Record ID missing. Cannot save.'),
          backgroundColor: Colors.red));
      setState(() => _isSaving = false);
      return;
    }

    // RECURSIVE RETRY LOGIC
    const int maxRetries = 3;
    try {
      _syncViewablePagesToMasterList();
      final columnName = _groupToColumnMap[widget.groupName];
      final Map<String, dynamic> dataToSave = {};

      if (columnName != null) {
        dataToSave[columnName] =
            _pagesInCurrentGroup.map((page) => page.toJson()).toList();
      } else {
        // Custom Group
        // Fetch current custom groups first to avoid overwriting other groups
        final response = await supabase
            .from('user_health_details')
            .select('custom_groups_data')
            .eq('id', _healthRecordId!)
            .single();
        final rawCustomGroups = response['custom_groups_data'] ?? [];
        final List<DrawingGroup> customGroups = (rawCustomGroups as List?)
            ?.map(
                (json) => DrawingGroup.fromJson(json as Map<String, dynamic>))
            .toList() ??
            [];
        // Find the index of the group we are currently editing
        int groupIndex = customGroups.indexWhere((g) => g.id == widget.groupId);
        if (groupIndex != -1) {
          // Update the pages for the current group
          customGroups[groupIndex] =
              customGroups[groupIndex].copyWith(pages: _pagesInCurrentGroup);
        } else {
          // This case should ideally not happen if loaded correctly
          // If it does, maybe add the new group? Or throw error.
          // For now, let's add it (assuming _currentGroup is correctly populated)
          if (_currentGroup != null) {
            customGroups
                .add(_currentGroup!.copyWith(pages: _pagesInCurrentGroup));
          } else {
            throw Exception(
                "Custom group '${widget.groupId}' not found for saving and _currentGroup is null.");
          }
        }
        dataToSave['custom_groups_data'] =
            customGroups.map((group) => group.toJson()).toList();
      }
      dataToSave['updated_at'] = DateTime.now().toIso8601String();

      if (_healthRecordId != null) {
        await supabase
            .from('user_health_details')
            .update(dataToSave)
            .eq('id', _healthRecordId!)
    .timeout(const Duration(seconds: 15));
        _lastSuccessfulSaveTime = DateTime.now();
    _retryAttempts = 0;
        if (mounted && isManualSave) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Saved! Refreshing to synchronize.'),
              backgroundColor: Colors.green));
          // Refresh after manual save to ensure consistency
          await _loadHealthDetailsAndPage();
        }
      } else {
        throw Exception("Health Record ID is missing.");
      }
    } catch (e) {
      debugPrint('Error saving: $e');
      if (_retryAttempts < maxRetries) {
        _retryAttempts++;
        debugPrint('Retrying save... Attempt $_retryAttempts');
        // Wait 2 seconds before retrying
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) await _savePrescriptionData(isManualSave: isManualSave);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Connection failed. Please check internet and try saving manually.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'Retry', onPressed: () => _savePrescriptionData(isManualSave: true)),
          ));
        }
        _retryAttempts = 0;
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- PDF Download Functionality ---
  Future<void> _downloadGroupAsPdf() async {
    // ... (implementation unchanged)
    setState(() => _isSaving = true);
    await PdfGenerator.downloadGroupAsPdf(
      context: context,
      supabase: supabase,
      healthRecordId: _healthRecordId,
      groupName: widget.groupName,
      groupId: widget.groupId,
      groupToColumnMap: _groupToColumnMap,
    );
    if (mounted) setState(() => _isSaving = false);
  }

  // --- Stamp Functionality ---
  Future<void> _fetchStamps() async {
    // ... (implementation unchanged)
    if (!mounted) return;
    setState(() => _isLoadingStamps = true);
    try {
      final response = await supabase.from('stamp_image').select();
      if (response.isNotEmpty) {
        _stamps = (response as List)
            .map((data) => StampImage.fromJson(data as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching stamps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load stamps: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingStamps = false);
    }
  }

  Future<void> _showStampSelectorModal() async {
    // ... (implementation unchanged)
    if (_isLoadingStamps) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Loading stamps...')));
      }
      return;
    }
    if (_stamps.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No stamps found.'), backgroundColor: Colors.orange));
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select a Stamp",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkText)),
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
                  itemCount: _stamps.length,
                  itemBuilder: (context, index) {
                    final stamp = _stamps[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _addImageToCanvas(stamp.stampUrl);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Stamp added!'),
                                  backgroundColor: Colors.green));
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: mediumGreyText.withOpacity(0.5)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            stamp.stampUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                  child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes !=
                                          null
                                          ? loadingProgress
                                          .cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                          : null));
                            },
                            errorBuilder: (context, error, stackTrace) =>
                            const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.red)),
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

  // --- Image Handling & Storage ---
  Future<void> _fetchUserUploadedImages() async {
    // ... (implementation unchanged)
    try {
      final storagePath = 'public/images/${widget.uhid}/';
      final files =
      await supabase.storage.from(kSupabaseBucketName).list(path: storagePath);

      _userUploadedImages = files.map((file) {
        final publicUrl = supabase.storage
            .from(kSupabaseBucketName)
            .getPublicUrl('$storagePath${file.name}');
        return UploadedImage(name: file.name, publicUrl: publicUrl);
      }).toList();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error fetching uploaded images: $e');
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      // 1. Pick the image
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return; // User cancelled picking

      // 2. Crop the image
      final CroppedFile? croppedFile = await _cropImage(pickedFile);
      if (croppedFile == null) return; // User cancelled cropping

      setState(() => _isSaving = true);

      // 3. Prepare upload using the CROPPED file
      final imageBytes = await croppedFile.readAsBytes();
      final fileName = '${generateUniqueId()}.${pickedFile.path.split('.').last}'; // Keep original extension
      final storagePath = 'public/images/${widget.uhid}/$fileName';

      // 4. Upload to Supabase
      await supabase.storage.from(kSupabaseBucketName).uploadBinary(
        storagePath,
        imageBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );

      // 5. Get URL and Add to Canvas
      final publicUrl = supabase.storage
          .from(kSupabaseBucketName)
          .getPublicUrl(storagePath);

      _addImageToCanvas(publicUrl);

      // Refresh the "Uploaded Images" list in the background
      await _fetchUserUploadedImages();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Image cropped and uploaded successfully!'),
            backgroundColor: Colors.green));
      }
    } on StorageException catch (e) {
      debugPrint('Supabase Storage Error: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: ${e.message}'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint('General Image Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  void _addImageToCanvas(String publicUrl) {
    // ... (implementation unchanged)
    const double defaultImageSize = 200.0;
    final newImage = DrawingImage(
      id: generateUniqueId(),
      imageUrl: publicUrl,
      position: Offset(canvasWidth / 2 - defaultImageSize / 2,
          canvasHeight / 2 - defaultImageSize / 2),
      width: defaultImageSize,
      height: defaultImageSize,
    );

    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _viewablePages[_currentPageIndex] =
          currentPage.copyWith(images: [...currentPage.images, newImage]);
      _selectedImageId = newImage.id;
      _isMovingSelectedImage = false;
    });

    _debouncedSave();
  }

  void _updateSelectedImage(
      {Offset? newPosition, double? newWidth, double? newHeight}) {
    // ... (implementation unchanged)
    if (_selectedImageId == null) return;

    final currentPage = _viewablePages[_currentPageIndex];
    final imageIndex =
    currentPage.images.indexWhere((img) => img.id == _selectedImageId);

    if (imageIndex != -1) {
      final oldImage = currentPage.images[imageIndex];
      final updatedImages = List<DrawingImage>.from(currentPage.images);

      updatedImages[imageIndex] = oldImage.copyWith(
        position: newPosition,
        width: newWidth,
        height: newHeight,
      );

      setState(() {
        _viewablePages[_currentPageIndex] =
            currentPage.copyWith(images: updatedImages);
        _redrawNotifier.value = 1 - _redrawNotifier.value;
      });
      _debouncedSave();
    }
  }

  void _resizeSelectedImage(double delta) {
    // ... (implementation unchanged)
    if (_selectedImageId == null) return;
    final currentPage = _viewablePages[_currentPageIndex];
    final image =
    currentPage.images.firstWhere((img) => img.id == _selectedImageId);

    double newWidth = (image.width + delta).clamp(50.0, canvasWidth);
    double newHeight = (image.height + delta).clamp(50.0, canvasHeight);

    _updateSelectedImage(newWidth: newWidth, newHeight: newHeight);
  }

  void _deleteSelectedImage() {
    // ... (implementation unchanged)
    if (_selectedImageId == null) return;
    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _viewablePages[_currentPageIndex] = currentPage.copyWith(
        images: currentPage.images
            .where((img) => img.id != _selectedImageId)
            .toList(),
      );
      _selectedImageId = null;
      _isMovingSelectedImage = false;
    });
    _debouncedSave();
  }

  void _toggleImageMoveMode() {
    // ... (implementation unchanged)
    if (_selectedImageId == null) return;
    setState(() {
      _isMovingSelectedImage = !_isMovingSelectedImage;
      _selectedTool = DrawingTool.image;
      if (!_isMovingSelectedImage) _dragStartCanvasPosition = null;
    });
  }

  Future<void> _showUploadedImagesSelector() async {
    // ... (implementation unchanged)
    await _fetchUserUploadedImages();

    if (_userUploadedImages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No uploaded images found for this patient. Use Camera or Gallery to upload one.'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Uploaded Images",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkText)),
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
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                  Text('Image added from uploaded files!'),
                                  backgroundColor: Colors.green));
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: mediumGreyText.withOpacity(0.5)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            uploadedImage.publicUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                  child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes !=
                                          null
                                          ? loadingProgress
                                          .cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                          : null));
                            },
                            errorBuilder: (context, error, stackTrace) =>
                            const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.red)),
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
    final transformedPosition =
    _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    final currentPage = _viewablePages[_currentPageIndex];
    setState(() =>
    _isStylusInteraction = details.kind == ui.PointerDeviceKind.stylus);

    // Handle Paste Transformation Drag Start
    if (_isTransformingPastedContent) {
      _pasteDragStartLocal = transformedPosition - _pastedTransformData!.offset;
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      setState(() {
        _lassoPoints = [transformedPosition];
      });
      return;
    }

    if (_selectedTool == DrawingTool.image) {
      final selectedImage = IterableX(currentPage.images)
          .firstWhereOrNull((img) => img.id == _selectedImageId);
      bool hitSelectedImage = false;

      if (selectedImage != null) {
        final imageRect = Rect.fromLTWH(
            selectedImage.position.dx,
            selectedImage.position.dy,
            selectedImage.width,
            selectedImage.height)
            .inflate(5);
        if (imageRect.contains(transformedPosition)) {
          hitSelectedImage = true;
        }
      }

      if (hitSelectedImage) {
        if (_isMovingSelectedImage) {
          _dragStartCanvasPosition =
              transformedPosition - selectedImage!.position;
        } else {
          _handleCanvasTap(transformedPosition);
        }
        return;
      } else {
        _handleCanvasTap(transformedPosition);
        return;
      }
    }

    if (_isPenOnlyMode && _isStylusInteraction) {
      if (_selectedTool == DrawingTool.pen) {
        setState(() {
          final newLine = DrawingLine(
            points: [transformedPosition],
            colorValue: _currentColor.value,
            strokeWidth: _strokeWidth,
            // UPDATED: Only check pressure sensitivity
            pressure: _isPressureSensitive ? [details.pressure] : null,
          );
          _viewablePages[_currentPageIndex] =
              currentPage.copyWith(lines: [...currentPage.lines, newLine]);
        });
      }
    }
  }







  void _handlePointerMove(PointerMoveEvent details) {
    final transformedPosition =
    _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    // Handle Paste Transformation Drag Move
    if (_isTransformingPastedContent && _pasteDragStartLocal != null) {
      final newOffset = transformedPosition - _pasteDragStartLocal!;
      setState(() {
        _pastedTransformData = _pastedTransformData!.copyWith(
          offset: newOffset,
        );
        _redrawNotifier.value = 1 - _redrawNotifier.value;
      });
      return;
    }

    if (_selectedTool == DrawingTool.lasso) {
      setState(() {
        _lassoPoints = [..._lassoPoints, transformedPosition];
        _redrawNotifier.value = 1 - _redrawNotifier.value;
      });
      return;
    }

    if (_selectedTool == DrawingTool.image &&
        _isMovingSelectedImage &&
        _selectedImageId != null &&
        _dragStartCanvasPosition != null) {
      final newImagePosition = transformedPosition - _dragStartCanvasPosition!;
      _updateSelectedImage(newPosition: newImagePosition);
      return;
    }

    if (_isPenOnlyMode && _isStylusInteraction) {
      if (_selectedTool == DrawingTool.pen) {
        setState(() {
          final currentPage = _viewablePages[_currentPageIndex];
          if (currentPage.lines.isEmpty) return;
          final lastLine = currentPage.lines.last;
          final newPoints = [...lastLine.points, transformedPosition];

          // UPDATED: Only capture pressure if enabled, remove velocity logic
          List<double>? newPressures = lastLine.pressure;
          if (_isPressureSensitive) {
            newPressures = [...(lastLine.pressure ?? []), details.pressure];
          }

          final updatedLines = List<DrawingLine>.from(currentPage.lines);
          updatedLines.last = lastLine.copyWith(
              points: newPoints, pressure: newPressures);

          _viewablePages[_currentPageIndex] =
              currentPage.copyWith(lines: updatedLines);
        });
      } else if (_selectedTool == DrawingTool.eraser) {
        _eraseLineAtPoint(transformedPosition);
      }
    }
  }
  void _handlePointerUp(PointerUpEvent details) {
    // ... (implementation unchanged)

    // --- ADDED: Handle Paste Transformation Drag End ---
    if (_isTransformingPastedContent && _pasteDragStartLocal != null) {
      _pasteDragStartLocal = null;
      // Do not save here, save happens on finalize
      return;
    }
    // --- END ADDED ---

    if (_selectedTool == DrawingTool.lasso) {
      if (_lassoPoints.length > 2) {
        _copySelectedContent();
      }
      setState(() {
        _lassoPoints = [];
        _redrawNotifier.value = 1 - _redrawNotifier.value; // Clear lasso
      });
      return;
    }

    if (_selectedTool == DrawingTool.image &&
        _selectedImageId != null &&
        _dragStartCanvasPosition != null) {
      _dragStartCanvasPosition = null;
      _debouncedSave();
    }

    if (_isStylusInteraction) {
      _debouncedSave();
      setState(() => _isStylusInteraction = false);
    }
  }

  void _handleCanvasTap(Offset canvasPosition) {
    // ... (implementation unchanged)
    final currentPage = _viewablePages[_currentPageIndex];
    String? newSelectedImageId;

    for (final image in currentPage.images.reversed) {
      final imageRect = Rect.fromLTWH(image.position.dx, image.position.dy,
          image.width, image.height)
          .inflate(5);
      if (imageRect.contains(canvasPosition)) {
        newSelectedImageId = image.id;
        break;
      }
    }

    setState(() {
      if (newSelectedImageId != null) {
        if (_selectedImageId != newSelectedImageId) {
          _isMovingSelectedImage = false;
        }
        _selectedImageId = newSelectedImageId;
      } else {
        _selectedImageId = null;
        _isMovingSelectedImage = false;
      }
      _redrawNotifier.value = 1 - _redrawNotifier.value;
    });
  }




  // --- Utility & Action Methods ---
  void _copySelectedContent() {
    if (_lassoPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Draw a closed shape to copy content.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }

    final path = Path()..moveTo(_lassoPoints.first.dx, _lassoPoints.first.dy);
    for (int i = 1; i < _lassoPoints.length; i++) {
      path.lineTo(_lassoPoints[i].dx, _lassoPoints[i].dy);
    }
    path.close();

    final currentPage = _viewablePages[_currentPageIndex];
    final copiedLines = <DrawingLine>[];
    final copiedImages = <DrawingImage>[];

    // 2. COPY LINES
    const double samplingDistance = 5.0;

    for (var line in currentPage.lines) {
      bool foundIntersection = false;
      final points = line.points;

      if (points.any((p) => path.contains(p))) {
        foundIntersection = true;
      } else {
        for (int i = 0; i < points.length - 1; i++) {
          final p1 = points[i];
          final p2 = points[i + 1];
          final distance = (p2 - p1).distance;

          if (distance > samplingDistance) {
            final int steps = (distance / samplingDistance).ceil();
            for (int j = 1; j < steps; j++) {
              final double t = j / steps;
              final intermediatePoint = Offset.lerp(p1, p2, t)!;
              if (path.contains(intermediatePoint)) {
                foundIntersection = true;
                break;
              }
            }
          }
          if (foundIntersection) break;
        }
      }

      if (foundIntersection) {
        copiedLines.add(line.copyWith());
      }
    }

    // 3. COPY IMAGES
    for (var image in currentPage.images) {
      final imageRect = Rect.fromLTWH(
          image.position.dx, image.position.dy, image.width, image.height);
      final imageCenter = imageRect.center;
      if (path.contains(imageCenter)) {
        copiedImages.add(image.copyWith());
      }
    }

    if (copiedLines.isEmpty && copiedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No content found within the lasso selection.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }

    // REPLACE SAVING LOGIC:
    AppClipboard().setData(CopiedPageData(
      lines: copiedLines,
      images: copiedImages,
    ));

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Copied ${copiedLines.length} drawing(s) and ${copiedImages.length} image(s)!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2)));
  }

  void _onTransformUpdated() => setState(() {});

  void _showPatientDetailsModal() {
    // ... (implementation unchanged)
    if (_isLoadingPrescription) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return PatientInfoModal(
          supabase: supabase,
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          healthRecordId: _healthRecordId,
        );
      },
    );
  }

  void _copyPageContent() {
    if (_viewablePages.isEmpty) return;
    final currentPage = _viewablePages[_currentPageIndex];

    // REPLACE SAVING LOGIC:
    AppClipboard().setData(CopiedPageData(
      lines: currentPage.lines.map((line) => line.copyWith()).toList(),
      images: currentPage.images.map((image) => image.copyWith()).toList(),
    ));

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Full page content copied!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2)));
  }

  void _pastePageContent() {
    // REPLACE GETTING LOGIC:
    final clipboardData = AppClipboard().getData();

    if (clipboardData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nothing to paste.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }
    if (_viewablePages.isEmpty) return;

    // 1. Assign new unique IDs to pasted images
    final pastedImagesWithNewIds = clipboardData.images
        .map((imageToCopy) => imageToCopy.copyWith(id: generateUniqueId()))
        .toList();

    // 2. Set the state to start transforming the pasted content
    setState(() {
      _pastedTransformData = _PastedTransformData(
        lines: clipboardData.lines.map((line) => line.copyWith()).toList(),
        images: pastedImagesWithNewIds,
        offset: Offset.zero,
        scale: 1.0,
      );
      _isTransformingPastedContent = true;
      _selectedTool = DrawingTool.image;
      _selectedImageId = null;
      _isMovingSelectedImage = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Content pasted! Drag to move and press the ✓ button to finalize.'),
        backgroundColor: primaryBlue,
        duration: Duration(seconds: 4)));
  }

  // --- ADDED: Finalize Paste ---
  void _finalizePaste() {
    if (_pastedTransformData == null) return;

    final currentPage = _viewablePages[_currentPageIndex];
    final pastedData = _pastedTransformData!;
    final Offset finalOffset = pastedData.offset;
    final double finalScale = pastedData.scale;

    // 1. Apply final transformation to all lines and images
    final List<DrawingLine> finalLines = pastedData.lines.map((line) {
      final newPoints = line.points.map((p) {
        return (p * finalScale) + finalOffset;
      }).toList();
      // Adjust stroke width by scale if necessary (optional, but good practice)
      final newStrokeWidth = line.strokeWidth * finalScale;
      return line.copyWith(points: newPoints, strokeWidth: newStrokeWidth);
    }).toList();

    final List<DrawingImage> finalImages = pastedData.images.map((image) {
      return image.copyWith(
        position: (image.position * finalScale) + finalOffset,
        width: image.width * finalScale,
        height: image.height * finalScale,
      );
    }).toList();


    setState(() {
      // 2. Merge transformed content into the page
      _viewablePages[_currentPageIndex] = currentPage.copyWith(
        lines: [...currentPage.lines, ...finalLines],
        images: [...currentPage.images, ...finalImages],
      );
      // 3. Clear temporary state
      _pastedTransformData = null;
      _isTransformingPastedContent = false;
      _selectedTool = DrawingTool.pen; // Return to default tool
    });





    _debouncedSave();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pasted content finalized and saved.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2)));
  }

  // --- ADDED: Cancel Paste ---
  void _cancelPaste() {
    // FIX: Changed HapticFeedback.warning() to HapticFeedback.mediumImpact()
    HapticFeedback.mediumImpact();
    setState(() {
      _pastedTransformData = null;
      _isTransformingPastedContent = false;
      _selectedTool = DrawingTool.pen; // Return to default tool
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pasted content canceled.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2)));
  }
  // --- END ADDED PASTE LOGIC ---


  void _undoLastAction() {
    // ... (implementation unchanged)
    HapticFeedback.lightImpact();
    if (_viewablePages.isEmpty ||
        (_viewablePages[_currentPageIndex].lines.isEmpty &&
            _viewablePages[_currentPageIndex].images.isEmpty)) return;

    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];
      final lines = currentPage.lines.toList();
      final images = currentPage.images.toList();

      if (lines.isNotEmpty) {
        lines.removeLast();
      } else if (images.isNotEmpty) {
        images.removeLast();
      }

      _selectedImageId = null;
      _isMovingSelectedImage = false;

      _viewablePages[_currentPageIndex] =
          currentPage.copyWith(lines: lines, images: images);
    });
    _debouncedSave();
  }

  void _clearAllDrawings() {
    // ... (implementation unchanged)
    HapticFeedback.mediumImpact();
    if (_viewablePages.isEmpty) return;
    setState(() {
      _viewablePages[_currentPageIndex] =
          _viewablePages[_currentPageIndex].copyWith(lines: [], images: []);
      _selectedImageId = null;
      _isMovingSelectedImage = false;
    });
    _debouncedSave();
  }

  void _eraseLineAtPoint(Offset point) {
    // ... (implementation unchanged)
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
      setState(() => _viewablePages[_currentPageIndex] =
          currentPage.copyWith(lines: linesToKeep));
    }
  }

  void _zoomByFactor(double factor) {
    // ... (implementation unchanged)
    HapticFeedback.lightImpact();
    final center =
    (context.findRenderObject() as RenderBox).size.center(Offset.zero);
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
    return point.dx >= 0 &&
        point.dx <= canvasWidth &&
        point.dy >= 0 &&
        point.dy <= canvasHeight;
  }

  void _setInitialZoom(Size viewportSize) {
    if (viewportSize.isEmpty) return;
    final scale = (viewportSize.width / canvasWidth)
        .clamp(0.1, viewportSize.height / canvasHeight);
    final dx = (viewportSize.width - canvasWidth * scale) / 2;
    final dy = (viewportSize.height - canvasHeight * scale) / 2;
    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  void _navigateToPage(int index) {
    // ... (implementation unchanged)
    if (index >= 0 && index < _viewablePages.length) {
      if (_pageController.hasClients) _pageController.jumpToPage(index);
      setState(() {
        _currentPageIndex = index;
        _isInitialZoomSet = false;
        _selectedImageId = null;
        _isMovingSelectedImage = false;
      });
    }
  }

  Future<void> _showFolderPageSelector() async {
    // ... (implementation unchanged)
    if (_pagesInCurrentGroup.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pages in '${_currentGroup?.groupName ?? 'Group'}'",
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkText)),
              const SizedBox(height: 10),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _pagesInCurrentGroup.length,
                  itemBuilder: (context, index) {
                    final page = _pagesInCurrentGroup[index];
                    final bool isSelected =
                        page.id == _viewablePages[_currentPageIndex].id;
                    return ListTile(
                      leading: Icon(Icons.description_outlined,
                          color: isSelected ? primaryBlue : mediumGreyText),
                      title: Text(page.pageName,
                          style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? primaryBlue : darkText)),
                      selected: isSelected,
                      selectedTileColor: primaryBlue.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      onTap: () {
                        Navigator.pop(context);
                        final tappedPage = _pagesInCurrentGroup[index];
                        if (tappedPage.id ==
                            _viewablePages[_currentPageIndex].id) return;
                        final tappedPrefix =
                        tappedPage.pageName.split('(')[0].trim();
                        final newViewablePages = _pagesInCurrentGroup
                            .where((p) =>
                        _getBasePagePrefix(p.pageName) == tappedPrefix)
                            .toList();
                        final newPageIndex = newViewablePages
                            .indexWhere((p) => p.id == tappedPage.id);
                        if (newPageIndex != -1) {
                          setState(() {
                            _viewablePages = newViewablePages;
                            _currentPageIndex = newPageIndex;
                            _isInitialZoomSet = false;
                            _selectedImageId = null;
                            _isMovingSelectedImage = false;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_pageController.hasClients) {
                              _pageController.jumpToPage(newPageIndex);
                            }
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

  // --- MODIFIED: For All Groups Modal (using RPC) ---
  Future<void> _fetchAllGroupsAndPages(StateSetter modalSetState) async {
    // Added modalSetState parameter
    if (_healthRecordId == null) return;
    modalSetState(() => _isLoadingAllGroups = true); // Use modalSetState
    try {
      final response = await supabase.rpc(
        'get_group_page_metadata',
        params: {'record_id': _healthRecordId!},
      );

      if (response is List) {
        List<DrawingGroup> allGroups = response
            .map((groupData) =>
            DrawingGroup.fromJson(groupData as Map<String, dynamic>))
            .where((group) => group.pages.isNotEmpty)
            .toList();
        allGroups.sort((a, b) => a.groupName.compareTo(b.groupName));

        // Use modalSetState to update the modal and the main state
        modalSetState(() {
          _allPatientGroups = allGroups;
        });
      } else {
        throw Exception(
            'Unexpected response format from RPC: ${response.runtimeType}');
      }
    } catch (e) {
      debugPrint('Error fetching all groups via RPC: $e');
      if (mounted) {
        // Use modal's context if possible, otherwise use page's context
        BuildContext currentContext =
            context; // Assuming this is the main page context
        try {
          // Attempt to close modal from its own context if error occurs during fetch
          // If modal isn't open, this might throw, hence the try-catch
          if (Navigator.canPop(currentContext)) Navigator.of(currentContext).pop();
        } catch (_) {}

        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
          // Use this.context for ScaffoldMessenger
            content: Text('Failed to load all groups: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      // Use modalSetState to update loading state
      if (mounted) {
        // Check if the main widget is still mounted
        modalSetState(() {
          _isLoadingAllGroups = false;
        });
      }
    }
  }

  // --- NEW: Helper to fetch all groups for the PiP window ---
  Future<void> _loadAllGroupsForPip() async {
    if (_healthRecordId == null) return;
    setState(() => _isLoadingAllGroups = true);
    try {
      final response = await supabase.rpc(
        'get_group_page_metadata',
        params: {'record_id': _healthRecordId!},
      );

      if (response is List) {
        List<DrawingGroup> allGroups = response
            .map((groupData) =>
            DrawingGroup.fromJson(groupData as Map<String, dynamic>))
            .where((group) => group.pages.isNotEmpty)
            .toList();
        allGroups.sort((a, b) => a.groupName.compareTo(b.groupName));
        setState(() {
          _allPatientGroups = allGroups;
        });
      } else {
        throw Exception(
            'Unexpected response format from RPC: ${response.runtimeType}');
      }
    } catch (e) {
      debugPrint('Error fetching all groups via RPC: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to load all groups: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAllGroups = false);
      }
    }
  }

  // --- NEW: Toggle the PiP (Reference) Window ---
  Future<void> _togglePipWindow() async {
    if (_isPipWindowVisible) {
      setState(() => _isPipWindowVisible = false);
      return;
    }

    // Load groups if not already loaded
    if (_allPatientGroups == null && !_isLoadingAllGroups) {
      await _loadAllGroupsForPip();
    }

    // Check again in case fetch failed or is in progress
    if (_allPatientGroups != null) {
      setState(() {
        _isPipWindowVisible = true;
        _pipSelectedPageData = null; // Start with no page selected
      });
    } else if (!_isLoadingAllGroups) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load patient groups for reference window.'),
          backgroundColor: Colors.red));
    }
  }


  void _navigateToNewPage(DrawingGroup group, DrawingPage page) {
    // ... (implementation unchanged)
    if (page.id == _viewablePages[_currentPageIndex].id) {
      if (Navigator.canPop(context))
        Navigator.of(context).pop(); // Just close the modal
      return;
    }
    if (Navigator.canPop(context)) Navigator.of(context).pop();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PrescriptionPage(
          ipdId: widget.ipdId,
          uhid: widget.uhid,
          groupId: group.id,
          pageId: page.id,
          groupName: group.groupName,
        ),
      ),
    );
  }


  Future<void> _showAllGroupsAndPagesModal() async {
    DrawingGroup? selectedGroup;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            // --- *** FIX: Call fetch inside builder if needed *** ---
            // Call fetch only if data is not loaded and not currently loading
            if (_allPatientGroups == null && !_isLoadingAllGroups) {
              // Use WidgetsBinding to schedule fetch after build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Pass modalSetState to the fetch function
                _fetchAllGroupsAndPages(modalSetState);
              });
            }
            // --- *** END FIX *** ---

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.only(top: 16.0),
              child: Column(
                children: [
                  // Modal Title Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        if (selectedGroup != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios,
                                color: darkText, size: 20),
                            onPressed: () =>
                                modalSetState(() => selectedGroup = null),
                          )
                        else
                          const SizedBox(width: 48), // Placeholder
                        Expanded(
                          child: Text(
                            selectedGroup == null
                                ? 'All Groups'
                                : selectedGroup!.groupName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: darkText),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: mediumGreyText),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Modal Content
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildModalContent(
                        context,
                        selectedGroup,
                            (DrawingGroup group) {
                          // onGroupTap
                          modalSetState(() => selectedGroup = group);
                        },
                            (DrawingPage page) {
                          // onPageTap
                          if (selectedGroup != null) {
                            _navigateToNewPage(selectedGroup!, page);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Helper widget to build the content inside the modal
  Widget _buildModalContent(
      BuildContext context,
      DrawingGroup? selectedGroup,
      ValueChanged<DrawingGroup> onGroupTap,
      ValueChanged<DrawingPage> onPageTap,
      ) {
    // ... (implementation mostly unchanged, added checks for _allPatientGroups)
    if (_isLoadingAllGroups) {
      return const Center(child: CircularProgressIndicator());
    }

    // Use a local variable to avoid issues if _allPatientGroups becomes null during build
    final List<DrawingGroup>? currentGroups = _allPatientGroups;

    if (currentGroups == null) {
      // Show loading or retry depending on state (isLoading handles loading)
      // This state might occur if fetch failed before
      return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load groups.'),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  // Re-trigger fetch, but need modalSetState.
                  // This button might need to be part of the StatefulBuilder state management.
                  // For simplicity, let's assume reopening the modal triggers the fetch again.
                  if (Navigator.canPop(context)) Navigator.pop(context);
                  _showAllGroupsAndPagesModal(); // Re-open to retry
                },
                child: const Text('Retry'),
              )
            ],
          ));
    }
    if (currentGroups.isEmpty) {
      return const Center(child: Text('No groups found for this patient.'));
    }


    // Show Page List
    if (selectedGroup != null) {
      // Find the selected group in the latest fetched list
      final groupToShow = IterableX(currentGroups)
          .firstWhereOrNull((g) => g.id == selectedGroup.id);
      if (groupToShow == null || groupToShow.pages.isEmpty) {
        return const Center(child: Text('No pages found in this group.'));
      }
      final pages = groupToShow.pages;

      return ListView.builder(
        key: ValueKey(groupToShow.id), // For AnimatedSwitcher
        itemCount: pages.length,
        itemBuilder: (context, index) {
          final page = pages[index];
          final bool isSelected =
              page.id == widget.pageId && groupToShow.id == widget.groupId;
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onTap: () => onPageTap(page),
          );
        },
      );
    }
    // Show Group List
    else {
      return ListView.builder(
        key: const ValueKey('group-list'), // For AnimatedSwitcher
        itemCount: currentGroups.length,
        itemBuilder: (context, index) {
          final group = currentGroups[index];
          final bool isCurrentGroup = group.id == widget.groupId;
          return ListTile(
            leading: Icon(Icons.folder_open_outlined,
                color: isCurrentGroup ? primaryBlue : mediumGreyText),
            title: Text(group.groupName,
                style: TextStyle(
                    fontWeight:
                    isCurrentGroup ? FontWeight.bold : FontWeight.normal,
                    color: isCurrentGroup ? primaryBlue : darkText)),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 16, color: mediumGreyText),
            selected: isCurrentGroup,
            selectedTileColor: primaryBlue.withOpacity(0.1),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onTap: () => onGroupTap(group),
          );
        },
      );
    }
  }


  // --- ADDED: Floating Toolbar for Pasted Content Transformation ---
  Widget _buildPastedContentToolbar() {
    if (!_isTransformingPastedContent || _pastedTransformData == null) {
      return const SizedBox.shrink();
    }

    // Place the toolbar in the center bottom of the screen
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Cancel Paste',
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _cancelPaste,
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Adjust Pasted Content (Drag to Move)',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: darkText)),
                const SizedBox(width: 16),
                Tooltip(
                  message: 'Finalize Paste',
                  child: IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: _finalizePaste,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // --- END ADDED TOOLBAR ---

  Future<bool> _handleBackButton() async {
    // If paste is pending, confirm cancellation before navigating back
    if (_isTransformingPastedContent) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Pasted Content?'),
          content: const Text('You are currently adjusting pasted content. Discard changes and go back?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // Stay
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                _cancelPaste(); // Discard and change state
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(_pagesInCurrentGroup); // Go back
              },
              child: const Text('Yes, Discard'),
            ),
          ],
        ),
      );
      return false; // Prevent immediate pop if dialog is shown
    }

    _syncViewablePagesToMasterList();
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop(_pagesInCurrentGroup);
    }
    return false;
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrescription) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Error handling for empty pages
    if (_viewablePages.isEmpty &&
        _currentGroup != null &&
        _currentGroup!.pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBackButton),
            title: Text(_currentGroup!.groupName),
            actions: [
              IconButton(
                icon: const Icon(Icons.collections_bookmark_outlined,
                    color: primaryBlue),
                tooltip: 'All Groups',
                onPressed: _showAllGroupsAndPagesModal,
              ),
              const SizedBox(width: 8),
            ]),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                    "No viewable pages found in '${_currentGroup!.groupName}'. Check if the page ID '${widget.pageId}' exists or if pages are correctly named.",
                    textAlign: TextAlign.center))),
      );
    }
    if (_viewablePages.isEmpty) {
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBackButton),
            title: const Text("Error")),
        body: const Center(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Page data could not be loaded or found.",
                    textAlign: TextAlign.center))),
      );
    }

    final currentPageData = _viewablePages[_currentPageIndex];
    // Disable pan/scale if transforming pasted content
    final bool panScaleEnabled = !_isStylusInteraction &&
        !_isMovingSelectedImage &&
        _selectedTool != DrawingTool.lasso &&
        !_isTransformingPastedContent;

    return WillPopScope(
      onWillPop: _handleBackButton,
      child: Scaffold(
        backgroundColor: lightBackground,
        // REMOVED: endDrawer is no longer used here.

        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBackButton,
              tooltip: 'Back'),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_patientName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("${currentPageData.pageName} (${currentPageData.groupName})",
                  style: const TextStyle(fontSize: 12, color: mediumGreyText)),
            ],
          ),
          backgroundColor: Colors.white,
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: primaryBlue),
              tooltip: 'Patient Details',
              onPressed: _showPatientDetailsModal,
            ),
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.orange),
              tooltip: 'Refresh',
              onPressed: _isLoadingPrescription ? null : _refreshAndApplyDetails,
            ),

            // --- 2. UPDATED SIDEBAR TOGGLE ---
            IconButton(
              // Highlight blue if open
              icon: Icon(Icons.widgets_outlined,
                  color: _isSidebarOpen ? primaryBlue : mediumGreyText),
              tooltip: 'Smart Macros',
              onPressed: () {
                setState(() {
                  _isSidebarOpen = !_isSidebarOpen;
                });
              },
            ),
            // --------------------------------

            IconButton(
              icon: Icon(Icons.picture_in_picture_alt_outlined,
                  color: _isPipWindowVisible ? Colors.red : primaryBlue),
              tooltip: 'Open Reference Window',
              onPressed: _togglePipWindow,
            ),
            IconButton(
                icon: const Icon(Icons.collections_bookmark_outlined,
                    color: primaryBlue),
                tooltip: 'All Groups',
                onPressed: _showAllGroupsAndPagesModal),
            IconButton(
                icon: const Icon(Icons.list_alt, color: primaryBlue),
                tooltip: 'Select Page in this Group',
                onPressed: _showFolderPageSelector),
            if (_viewablePages.length > 1) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: primaryBlue, size: 20),
                tooltip: 'Previous Page',
                onPressed: _previousPage,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4.0, right: 4.0),
                child: Center(
                  child: ActionChip(
                    onPressed: _showFolderPageSelector,
                    label: Text(
                      "${_currentPageIndex + 1}/${_viewablePages.length}",
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primaryBlue),
                    ),
                    backgroundColor: primaryBlue.withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios,
                    color: primaryBlue, size: 20),
                tooltip: 'Next Page',
                onPressed: _nextPage,
              ),
            ],
            _buildPageActionsMenu(),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded,
                  color: primaryBlue),
              tooltip: 'Download Group as PDF',
              onPressed: _isSaving ? null : _downloadGroupAsPdf,
            ),
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: primaryBlue))
                  : const Icon(Icons.save_alt_rounded, color: primaryBlue),
              tooltip: "Save and Refresh",
              onPressed:
              _isSaving ? null : () => _savePrescriptionData(isManualSave: true),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: Row(children: [
                Expanded(child: _buildDrawingToolbar()),
                _buildPanToolbar()
              ]),
            ),
          ),
        ),

        body: DragTarget<MedicalMacro>(
          onAcceptWithDetails: (details) {
            final RenderBox renderBox = context.findRenderObject() as RenderBox;
            final localOffset = renderBox.globalToLocal(details.offset);
            _onMacroDropped(details.data, localOffset);

            // Optional: Close sidebar automatically after drop
            // setState(() => _isSidebarOpen = false);
          },
          builder: (context, candidateData, rejectedData) {
            return LayoutBuilder(
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
                        onPageChanged: (index) {
                          setState(() {
                            _currentPageIndex = index;
                            _isInitialZoomSet = false;
                            _transformationController.value = Matrix4.identity();
                            _selectedImageId = null;
                            _isMovingSelectedImage = false;
                            _lassoPoints = [];
                          });
                        },
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          return _PrescriptionCanvasPage(
                            drawingPage: _viewablePages[index],
                            selectedImageId: _selectedImageId,
                            redrawNotifier: _redrawNotifier,
                            lassoPoints:
                            index == _currentPageIndex ? _lassoPoints : [],
                            transformationController: _transformationController,
                            panScaleEnabled: panScaleEnabled,
                            isPressureSensitive: _isPressureSensitive,
                            pastedTransformData: index == _currentPageIndex ? _pastedTransformData : null,
                            onTap: (details) {
                              if (!_isTransformingPastedContent && _selectedTool == DrawingTool.image &&
                                  !_isStylusInteraction &&
                                  !_isMovingSelectedImage) {
                                _handleCanvasTap(_transformToCanvasCoordinates(
                                    details.localPosition));
                              }
                            },
                          );
                        },
                      ),
                    ),
                    if (_selectedImageId != null) _buildImageOverlayControls(),
                    _buildFloatingCopyPasteButton(),
                    _buildPastedContentToolbar(),

                    if (_isPipWindowVisible)
                      Positioned(
                        left: _pipPosition.dx,
                        top: _pipPosition.dy,
                        child: PipReferenceWindow(
                          key: const ValueKey('pip_window'),
                          patientUhid: widget.uhid,
                          allGroups: _allPatientGroups ?? [],
                          selectedPageData: _pipSelectedPageData,
                          initialSize: _pipSize,
                          healthRecordId: _healthRecordId!,
                          groupToColumnMap: _groupToColumnMap,
                          onClose: () {
                            setState(() => _isPipWindowVisible = false);
                          },
                          onPageSelected: (group, page) {
                            setState(() => _pipSelectedPageData = (group, page));
                          },
                          onPositionChanged: (delta) {
                            setState(() {
                              final newX = (_pipPosition.dx + delta.dx).clamp(
                                  0.0, constraints.maxWidth - _pipSize.width);
                              final newY = (_pipPosition.dy + delta.dy).clamp(
                                  0.0, constraints.maxHeight - _pipSize.height);
                              _pipPosition = Offset(newX, newY);
                            });
                          },
                          onSizeChanged: (delta) {
                            setState(() {
                              final newWidth = (_pipSize.width + delta.dx).clamp(
                                  300.0, constraints.maxWidth - _pipPosition.dx);
                              final newHeight =
                                  (newWidth / canvasWidth) * canvasHeight;

                              if (newHeight >
                                  constraints.maxHeight - _pipPosition.dy) {
                                _pipSize = Size(
                                    ((constraints.maxHeight - _pipPosition.dy) /
                                        canvasHeight) *
                                        canvasWidth,
                                    constraints.maxHeight - _pipPosition.dy);
                              } else {
                                _pipSize = Size(newWidth, newHeight);
                              }
                            });
                          },
                        ),
                      ),

                    // --- 3. NEW SIDEBAR PLACEMENT (Inside Stack) ---
                    if (_isSidebarOpen)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 300, // Fixed width for sidebar
                        child: Material(
                          elevation: 16, // Add shadow
                          child: AutoCompleteSidebar(
                            onMacroDropped: (macro, offset) {
                              // This callback is secondary if dragging works,
                              // but useful for logic like closing the sidebar.
                            },
                          ),
                        ),
                      ),
                    // -----------------------------------------------
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // --- Other Build methods (_buildImageOverlayControls, _buildPageActionsMenu, etc.) ---
  // ... (These methods remain unchanged from the previous version) ...
  Widget _buildImageOverlayControls() {
    // ... (implementation unchanged)
    if (_selectedImageId == null) return const SizedBox.shrink();

    final currentPage = _viewablePages[_currentPageIndex];
    final selectedImage = IterableX(currentPage.images)
        .firstWhereOrNull((img) => img.id == _selectedImageId);

    if (selectedImage == null) return const SizedBox.shrink();

    return ImageOverlayControls(
      imagePosition: selectedImage.position,
      imageWidth: selectedImage.width,
      imageHeight: selectedImage.height,
      transformMatrix: _transformationController.value,
      isMovingSelectedImage: _isMovingSelectedImage,
      onResize: _resizeSelectedImage,
      onDelete: _deleteSelectedImage,
      onToggleMoveMode: _toggleImageMoveMode,
    );
  }

  Widget _buildPageActionsMenu() {
    return PopupMenuButton<String>(
      onSelected: (String value) {
        if (value == 'copy_full')
          _copyPageContent();
        else if (value == 'paste')
          _pastePageContent();
        else if (value == 'clear_copy')
          _clearCopiedContent();
        else if (value == 'camera')
          _pickAndUploadImage(ImageSource.camera);
        else if (value == 'gallery')
          _pickAndUploadImage(ImageSource.gallery);
        else if (value == 'uploaded')
          _showUploadedImagesSelector();
        else if (value == 'stamp') _showStampSelectorModal();
      },
      icon: const Icon(Icons.more_vert, color: primaryBlue),
      tooltip: 'Page Actions',
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
            value: 'copy_full',
            child: ListTile(
                leading: Icon(Icons.copy_all_rounded),
                title: Text('Copy Full Page'))),
        // REPLACE CHECKS:
        if (AppClipboard().hasData)
          const PopupMenuItem<String>(
              value: 'paste',
              child: ListTile(
                  leading: Icon(Icons.paste_rounded),
                  title: Text('Paste on Page'))),
        if (AppClipboard().hasData)
          const PopupMenuItem<String>(
              value: 'clear_copy',
              child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: Text('Clear Copied Content',
                      style: TextStyle(color: Colors.red)))),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
            value: 'camera',
            child: ListTile(
                leading: Icon(Icons.camera_alt_rounded),
                title: Text('Insert from Camera'))),
        const PopupMenuItem<String>(
            value: 'gallery',
            child: ListTile(
                leading: Icon(Icons.photo_library_rounded),
                title: Text('Insert from Gallery'))),
        const PopupMenuItem<String>(
            value: 'uploaded',
            child: ListTile(
                leading: Icon(Icons.cloud_upload_rounded),
                title: Text('Pick from Uploaded'))),
        const PopupMenuItem<String>(
            value: 'stamp',
            child: ListTile(
                leading: Icon(Icons.star_rounded), title: Text('Insert Stamp'))),
      ],
    );
  }




  Widget _buildDrawingToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ToggleButtons(
            onPressed: _isTransformingPastedContent ? null : (index) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedImageId = null;
                _isMovingSelectedImage = false;
                _lassoPoints = [];
                if (index == 0)
                  _selectedTool = DrawingTool.pen;
                else if (index == 1)
                  _selectedTool = DrawingTool.eraser;
                else if (index == 2)
                  _selectedTool = DrawingTool.image;
                else
                  _selectedTool = DrawingTool.lasso;
              });
            },
            isSelected: [
              _selectedTool == DrawingTool.pen,
              _selectedTool == DrawingTool.eraser,
              _selectedTool == DrawingTool.image,
              _selectedTool == DrawingTool.lasso,
            ],
            borderRadius: BorderRadius.circular(8),
            selectedBorderColor: primaryBlue,
            fillColor: primaryBlue,
            color: mediumGreyText,
            selectedColor: Colors.white,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            children: const [
              Tooltip(message: "Pen", child: Icon(Icons.edit, size: 20)),
              Tooltip(
                  message: "Eraser",
                  child: Icon(Icons.cleaning_services, size: 20)),
              Tooltip(
                  message: "Image Select/Move",
                  child: Icon(Icons.photo_library_outlined, size: 20)),
              Tooltip(
                  message: "Lasso Copy Selection",
                  child: Icon(Icons.select_all, size: 20)),
            ],
          ),
          const SizedBox(width: 8),

          if (_selectedTool == DrawingTool.pen) ...[
            // KEPT: Pressure Sensitivity Toggle Only
            IconButton(
              icon: Icon(
                Icons.opacity,
                color: _isPressureSensitive ? primaryBlue : mediumGreyText,
                size: 22,
              ),
              tooltip: _isPressureSensitive
                  ? 'Pressure Sensitivity (ON)'
                  : 'Pressure Sensitivity (OFF)',
              onPressed: _isTransformingPastedContent ? null : () {
                setState(() {
                  _isPressureSensitive = !_isPressureSensitive;
                  _redrawNotifier.value = 1 - _redrawNotifier.value;
                });
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_isPressureSensitive
                      ? 'Pressure Sensitive Mode Activated'
                      : 'Pressure Sensitive Mode Deactivated'),
                  backgroundColor: primaryBlue,
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
          ],

          const SizedBox(width: 8),

          if (_selectedTool != DrawingTool.image &&
              _selectedTool != DrawingTool.lasso)
            ...[
              Colors.black,
              Colors.blue,
              primaryBlue,
              Colors.red,
              Colors.green
            ].map((color) => _buildColorOption(color)).toList(),
          if (_selectedTool == DrawingTool.pen ||
              _selectedTool == DrawingTool.eraser)
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
                    onChanged: _isTransformingPastedContent ? null : (value) => setState(() => _strokeWidth = value),
                    activeColor: primaryBlue,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 24),
          IconButton(
              icon:
              const Icon(Icons.undo_rounded, color: primaryBlue, size: 22),
              onPressed: _isTransformingPastedContent ? null : _undoLastAction,
              tooltip: "Undo"),
        ],
      ),
    );
  }

  Widget _buildPanToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // --- NEW: Save Macro Button (Visible only if Clipboard has data) ---
        ValueListenableBuilder<bool>(
          valueListenable: AppClipboard().hasDataNotifier,
          builder: (context, hasData, child) {
            if (!hasData) return const SizedBox.shrink(); // Hide if empty

            return Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: IconButton(
                icon: const Icon(Icons.save_as, color: Colors.green),
                tooltip: "Save Clipboard as Macro",
                onPressed: _saveMacroFromClipboard,
              ),
            );
          },
        ),
        // ------------------------------------------------------------------

        IconButton(
            onPressed: _zoomIn,
            icon: const Icon(Icons.zoom_in),
            tooltip: "Zoom In"),
        IconButton(
            onPressed: _zoomOut,
            icon: const Icon(Icons.zoom_out),
            tooltip: "Zoom Out"),
        IconButton(
            onPressed: _resetZoom,
            icon: const Icon(Icons.zoom_out_map),
            tooltip: "Reset Zoom"),
      ],
    );
  }

  Widget _buildColorOption(Color color) {
    // ... (implementation unchanged)
    bool isSelected = _currentColor == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: GestureDetector(
        onTap: _isTransformingPastedContent ? null : () => setState(() => _currentColor = color),
        child: Tooltip(
          message: color.toString(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: primaryBlue, width: 2.5)
                  : Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        ),
      ),
    );
  }
}

// --- WIDGET TO MANAGE CANVAS AND TEMPLATE IMAGE (Unchanged, except for removing PiP widgets) ---
class _PrescriptionCanvasPage extends StatefulWidget {
  final DrawingPage drawingPage;
  final String? selectedImageId;
  final ValueNotifier<int> redrawNotifier;
  final List<Offset> lassoPoints;
  final TransformationController transformationController;
  final bool panScaleEnabled;
  final ValueChanged<TapUpDetails> onTap;
  // REMOVED: isEnhancedHandwriting, isVelocitySensitive
  final bool isPressureSensitive;
  final _PastedTransformData? pastedTransformData;

  const _PrescriptionCanvasPage({
    required this.drawingPage,
    this.selectedImageId,
    required this.redrawNotifier,
    required this.lassoPoints,
    required this.transformationController,
    required this.panScaleEnabled,
    required this.onTap,
    // REMOVED arguments
    required this.isPressureSensitive,
    this.pastedTransformData,
  });

  @override
  State<_PrescriptionCanvasPage> createState() => _PrescriptionCanvasPageState();
}

class _PrescriptionCanvasPageState extends State<_PrescriptionCanvasPage>
    with AutomaticKeepAliveClientMixin {
  ui.Image? _templateUiImage;
  // **OPTIMIZATION: Map to hold all loaded ui.Images for DrawingImages**
  final Map<String, ui.Image> _loadedDrawingImages = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAllImages();
  }

  @override
  void didUpdateWidget(_PrescriptionCanvasPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawingPage != widget.drawingPage ||
        oldWidget.pastedTransformData != widget.pastedTransformData // Check for pasted data change
    ) {
      _loadAllImages();
    }
  }

  String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  Future<void> _loadAllImages() async {
    // 1. Load Template (Priority)
    final String fullTemplateUrl = _getFullImageUrl(widget.drawingPage.templateImageUrl);
    ui.Image? templateImage;

    // validation: Check if URL exists before trying
    if (fullTemplateUrl.isNotEmpty) {
      try {
        // OPTIMIZATION: Decode image to specific width (e.g., tablet screen width) to save RAM
        // You would need a custom image provider or logic here, but standard cache is okay for now
        // provided you don't load 50 at once.
        templateImage = await ImageCacheManager.loadImage(fullTemplateUrl);
      } catch (e) {
        debugPrint('Error loading template: $e');
      }
    }

    // 2. Load Drawing Images with CONCURRENCY LIMIT
    final allImages = [...widget.drawingPage.images];
    if (widget.pastedTransformData != null) {
      allImages.addAll(widget.pastedTransformData!.images);
    }

    final newLoadedDrawingImages = <String, ui.Image>{};

    // BATCH LOADING: Load 3 images at a time, not all 30 at once.
    int chunkSize = 3;
    for (var i = 0; i < allImages.length; i += chunkSize) {
      final end = (i + chunkSize < allImages.length) ? i + chunkSize : allImages.length;
      final chunk = allImages.sublist(i, end);

      await Future.wait(chunk.map((drawingImage) async {
        try {
          // Validation: skip empty URLs
          if (drawingImage.imageUrl.isEmpty) return;

          // Check cache first
          final cachedImage = ImageCacheManager.getCachedImage(drawingImage.imageUrl);
          if (cachedImage != null) {
            newLoadedDrawingImages[drawingImage.id] = cachedImage;
            return;
          }

          final loadedImage = await ImageCacheManager.loadImage(drawingImage.imageUrl);
          if (loadedImage != null) {
            newLoadedDrawingImages[drawingImage.id] = loadedImage;
          }
        } catch (e) {
          debugPrint('Error loading image ${drawingImage.id}: $e');
        }
      }));

      // Small delay to let UI thread breathe on low-end devices
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      setState(() {
        _templateUiImage = templateImage;
        _loadedDrawingImages
          ..clear()
          ..addAll(newLoadedDrawingImages);
      });
    }
  }



  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Show a loading indicator if the template isn't loaded yet
    if (widget.drawingPage.templateImageUrl.isNotEmpty &&
        _templateUiImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return InteractiveViewer(
      transformationController: widget.transformationController,
      panEnabled: widget.panScaleEnabled,
      scaleEnabled: widget.panScaleEnabled,
      minScale: 0.1,
      maxScale: 10.0,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: GestureDetector(
        onTapUp: widget.onTap,
        // --- ADD THIS LISTENER WRAPPER ---
        child: Listener(
          onPointerDown: (details) {
            // This prints the exact X and Y to your "Run" console when you tap
            print("COORDINATES: x: ${details.localPosition.dx.round()}, y: ${details.localPosition.dy.round()}");
          },
          child: CustomPaint(
            painter: PrescriptionPainter(
              drawingPage: widget.drawingPage,
              templateUiImage: _templateUiImage,
              loadedDrawingImages: _loadedDrawingImages,
              selectedImageId: widget.selectedImageId,
              redrawNotifier: widget.redrawNotifier,
              lassoPoints: widget.lassoPoints,

              isPressureSensitive: widget.isPressureSensitive,

              pastedTransformData: widget.pastedTransformData,
            ),
            child: const SizedBox(width: canvasWidth, height: canvasHeight),
          ),
        ),
        // ---------------------------------
      ),
    );
  }
}






// --- CUSTOM PAINTER CLASS (Modified to draw temporary pasted content) ---
// --- CUSTOM PAINTER CLASS (Updated for Smooth Curves) ---
class PrescriptionPainter extends CustomPainter {
  final DrawingPage drawingPage;
  final ui.Image? templateUiImage;
  final Map<String, ui.Image> loadedDrawingImages;
  final String? selectedImageId;
  final ValueNotifier<int> redrawNotifier;
  final List<Offset> lassoPoints;
  final bool isPressureSensitive;
  final _PastedTransformData? pastedTransformData;

  PrescriptionPainter({
    required this.drawingPage,
    this.templateUiImage,
    required this.redrawNotifier,
    this.selectedImageId,
    required this.lassoPoints,
    required this.isPressureSensitive,
    required this.loadedDrawingImages,
    this.pastedTransformData,
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
        canvas.drawRect(
            destRect, Paint()..color = Colors.grey.withOpacity(0.5));
      }

      if (image.id == selectedImageId) {
        final borderPaint = Paint()
          ..color = primaryBlue
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke;
        canvas.drawRect(destRect.inflate(2.0), borderPaint);
      }
    }

    // 3. Draw Lines (Handwriting)
    for (var line in drawingPage.lines) {
      if (line.points.isEmpty) continue;

      // Check if pressure data exists and mode is on
      bool usePressure = isPressureSensitive &&
          line.pressure != null &&
          line.pressure!.length == line.points.length;

      if (usePressure) {
        // PRESSURE SENSITIVE DRAWING (Raw lines for accuracy with pressure)
        final double minWidth = line.strokeWidth * 0.4;
        final double maxWidth = line.strokeWidth * 2.0;
        final points = line.points;
        final pressures = line.pressure!;
        final tempPaint = Paint()
          ..color = Color(line.colorValue)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        for (int i = 0; i < points.length - 1; i++) {
          final p1 = points[i];
          final p2 = points[i + 1];
          final avgPressure =
          ((pressures[i] + pressures[i + 1]) / 2).clamp(0.0, 1.0);
          final newWidth = ui.lerpDouble(minWidth, maxWidth, avgPressure)!;

          if (newWidth > 0.1) {
            tempPaint.strokeWidth = newWidth;
            canvas.drawLine(p1, p2, tempPaint);
          }
        }
      } else {
        // DEFAULT DRAWING (With Bezier Smoothing)
        final paint = Paint()
          ..color = Color(line.colorValue)
          ..strokeWidth = line.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

        final path = Path();
        if (line.points.length > 1) {
          path.moveTo(line.points[0].dx, line.points[0].dy);

          // --- SMOOTHING LOGIC ---
          // We draw a quadratic curve from the previous point to the
          // midpoint of the current segment. This rounds off the corners
          // created by the raw touch points.
          for (int i = 0; i < line.points.length - 1; i++) {
            final p0 = line.points[i];
            final p1 = line.points[i + 1];

            // Calculate the midpoint between this point and the next
            final midPoint = Offset(
              (p0.dx + p1.dx) / 2,
              (p0.dy + p1.dy) / 2,
            );

            // Use the current point (p0) as the control point to pull the curve
            // towards it, ending at the midpoint.
            if (i == 0) {
              // For the very first segment, just draw a line to the first midpoint
              // to start the curve smoothly.
              path.lineTo(midPoint.dx, midPoint.dy);
            } else {
              path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
            }
          }
          // Connect to the very last point
          path.lineTo(line.points.last.dx, line.points.last.dy);
        } else if (line.points.length == 1) {
          // Draw a dot for a single point tap
          canvas.drawPoints(ui.PointMode.points, [line.points.first], paint);
        }

        canvas.drawPath(path, paint);
      }
    }

    // 4. Draw Texts
    for (var textItem in drawingPage.texts) {
      final textSpan = TextSpan(
        text: textItem.text,
        style: TextStyle(
          color: Color(textItem.colorValue),
          fontSize: textItem.fontSize,
          fontWeight: FontWeight.bold,
          fontFamily: 'Arial',
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, textItem.position);
    }

    // 5. Draw Paste / Lasso Overlay
    if (pastedTransformData != null) {
      canvas.save();
      canvas.translate(
          pastedTransformData!.offset.dx, pastedTransformData!.offset.dy);
      final double scale = pastedTransformData!.scale;

      // Draw Pasted Lines (Apply the same smoothing logic if desired, or keep simple)
      for (var line in pastedTransformData!.lines) {
        final paint = Paint()
          ..color = Color(line.colorValue).withOpacity(0.8)
          ..strokeWidth = line.strokeWidth * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

        final path = Path();
        if (line.points.isNotEmpty) {
          path.moveTo(line.points[0].dx * scale, line.points[0].dy * scale);
          for (int i = 0; i < line.points.length - 1; i++) {
            final p0 = line.points[i];
            final p1 = line.points[i+1];
            final midX = ((p0.dx + p1.dx) / 2) * scale;
            final midY = ((p0.dy + p1.dy) / 2) * scale;
            final cX = p0.dx * scale;
            final cY = p0.dy * scale;

            if (i == 0) {
              path.lineTo(midX, midY);
            } else {
              path.quadraticBezierTo(cX, cY, midX, midY);
            }
          }
          path.lineTo(line.points.last.dx * scale, line.points.last.dy * scale);
        }
        canvas.drawPath(path, paint);
      }

      // Draw Pasted Images
      for (var image in pastedTransformData!.images) {
        final cachedImage = loadedDrawingImages[image.id];
        final destRect = Rect.fromLTWH(
          image.position.dx * scale,
          image.position.dy * scale,
          image.width * scale,
          image.height * scale,
        );
        if (cachedImage != null) {
          paintImage(
              canvas: canvas,
              rect: destRect,
              image: cachedImage,
              fit: BoxFit.contain,
              alignment: Alignment.topLeft);
        } else {
          canvas.drawRect(
              destRect, Paint()..color = Colors.blueGrey.withOpacity(0.3));
        }
      }
      canvas.restore();
    }

    if (lassoPoints.length > 1 && pastedTransformData == null) {
      final lassoPaint = Paint()
        ..color = primaryBlue
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final lassoPath = Path()
        ..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (int i = 1; i < lassoPoints.length; i++) {
        lassoPath.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
      }
      canvas.drawPath(lassoPath, lassoPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PrescriptionPainter oldDelegate) {
    return oldDelegate.drawingPage != drawingPage ||
        oldDelegate.templateUiImage != templateUiImage ||
        oldDelegate.selectedImageId != selectedImageId ||
        oldDelegate.lassoPoints.length != lassoPoints.length ||
        oldDelegate.isPressureSensitive != isPressureSensitive ||
        oldDelegate.loadedDrawingImages.length !=
            loadedDrawingImages.length ||
        oldDelegate.pastedTransformData != pastedTransformData;
  }
}

// --- HELPER CLASS FOR STROKE SIMPLIFICATION (Unchanged) ---
// This is used by the 'isEnhancedHandwriting' feature
class RdpSimplifier {
  double _getPerpendicularDistance(Offset p, Offset p1, Offset p2) {
    double dx = p2.dx - p1.dx;
    double dy = p2.dy - p1.dy;

    if (dx == 0 && dy == 0) {
      dx = p.dx - p1.dx;
      dy = p.dy - p1.dy;
      return sqrt(dx * dx + dy * dy);
    }

    double num = ((p.dx - p1.dx) * dx + (p.dy - p1.dy) * dy).abs();
    double den = dx * dx + dy * dy;
    double u = num / den;

    double ix, iy;
    if (u > 1) {
      ix = p2.dx;
      iy = p2.dy;
    } else if (u < 0) {
      ix = p1.dx;
      iy = p1.dy;
    } else {
      ix = p1.dx + u * dx;
      iy = p1.dy + u * dy;
    }

    dx = p.dx - ix;
    dy = p.dy - iy;
    return sqrt(dx * dx + dy * dy);
  }

  void _simplify(List<Offset> points, double tolerance, List<Offset> out,
      int start, int end) {
    if (start + 1 >= end) {
      return;
    }

    double maxDistance = 0.0;
    int index = 0;

    for (int i = start + 1; i < end; i++) {
      double distance =
      _getPerpendicularDistance(points[i], points[start], points[end]);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (maxDistance > tolerance) {
      _simplify(points, tolerance, out, start, index);
      out.add(points[index]);
      _simplify(points, tolerance, out, index, end);
    }
  }

  List<Offset> simplify(List<Offset> points, double tolerance) {
    if (points.length < 3) {
      return points;
    }

    final List<Offset> simplifiedPoints = [];
    simplifiedPoints.add(points.first);
    _simplify(points, tolerance, simplifiedPoints, 0, points.length - 1);
    simplifiedPoints.add(points.last);

    return simplifiedPoints;
  }
}