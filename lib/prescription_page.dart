import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math'; // Added for sqrt()

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'supabase_config.dart';
import 'image_manipulation_helpers.dart';
import 'patient_info_header_card.dart';
import 'drawing_models.dart';
import 'pdf_generator.dart';

// Assuming ImageCacheManager and Matrix4Utils are defined in 'image_manipulation_helpers.dart'
// Assuming PatientInfoModal is defined in 'patient_info_header_card.dart'
// Assuming PdfGenerator is defined in 'pdf_generator.dart'
// Assuming DrawingLine, DrawingImage, DrawingPage, DrawingGroup, StampImage, generateUniqueId, and ImageOverlayControls are defined/used across the other files.
// IMPORTANT: Make sure your DrawingGroup.fromJson and DrawingPage.fromJson handle potentially missing 'lines' and 'images' gracefully (e.g., default to empty lists).

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

// ADDED: DrawingTool.lasso
enum DrawingTool { pen, eraser, image, lasso }

class _CopiedPageData {
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  _CopiedPageData({required this.lines, required this.images});
}

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
  List<StampImage> _stamps = [];
  String _patientName = 'Loading Patient Name...';
  Map<String, dynamic> _patientDetails = {};
  Map<String, dynamic> _ipdRegistrationDetails = {};
  Map<String, dynamic> _bedDetails = {};
  List<DrawingGroup>? _allPatientGroups;
  bool _isLoadingAllGroups = false;

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
    'Prescription Sheet':'prescription_sheet_data'
  };

  // --- Drawing State ---
  Color _currentColor = Colors.black;
  double _strokeWidth = 2.0;
  DrawingTool _selectedTool = DrawingTool.pen;
  bool _isEnhancedHandwriting = false;
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

  @override
  void initState() {
    super.initState();
    _loadHealthDetailsAndPage();
    _fetchUserUploadedImages();
    _fetchStamps();
    _transformationController.addListener(_onTransformUpdated);
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

  Future<void> _loadHealthDetailsAndPage() async {
    // ... (implementation unchanged)
    if (!mounted) return;
    final String? currentPageIdBeforeRefresh =
    _viewablePages.isNotEmpty ? _viewablePages[_currentPageIndex].id : widget.pageId;
    setState(() => _isLoadingPrescription = true);
    try {
      final columnName =
          _groupToColumnMap[widget.groupName] ?? 'custom_groups_data';
      // Only select the specific column needed + custom_groups + id
      final columnsToSelect = ['id', columnName, 'custom_groups_data'].toSet().join(','); // Use Set to avoid duplicates if columnName is custom_groups_data

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
          _patientDetails = ipdResponse['patient_detail'] as Map<String, dynamic>? ?? {};
          _bedDetails = ipdResponse['bed_management'] as Map<String, dynamic>? ?? {};
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
              orElse: () => throw Exception("Custom group '${widget.groupId}' not found."));
          _pagesInCurrentGroup = _currentGroup!.pages;
        } else {
          final rawPages = response[columnName] ?? [];
          _pagesInCurrentGroup = (rawPages as List?)
              ?.map((json) =>
              DrawingPage.fromJson(json as Map<String, dynamic>))
              .toList() ??
              [];
          // For standard groups, the ID and groupName are the same from the map key
          _currentGroup = DrawingGroup(
              id: widget.groupName,
              groupName: widget.groupName,
              pages: _pagesInCurrentGroup);
        }

        // Find the starting page within the loaded group
        DrawingPage startPage;
        try {
          startPage = _pagesInCurrentGroup.firstWhere(
                  (p) => p.id == currentPageIdBeforeRefresh);
        } catch (e) {
          throw Exception("Start page '$currentPageIdBeforeRefresh' not found in group '${_currentGroup?.groupName}'. Available pages: ${_pagesInCurrentGroup.map((p)=> p.id).join(', ')}");
        }


        // Determine which pages belong to the same 'template type' (part before '(')
        String pagePrefix = startPage.pageName.split('(')[0].trim();
        _viewablePages = _pagesInCurrentGroup
            .where((p) => p.pageName.split('(')[0].trim() == pagePrefix)
            .toList();

        int initialIndex =
        _viewablePages.indexWhere((p) => p.id == currentPageIdBeforeRefresh);

        if (initialIndex != -1) {
          _currentPageIndex = initialIndex;
          _pageController.dispose();
          _pageController = PageController(initialPage: _currentPageIndex);
        } else {
          throw Exception("Starting page '$currentPageIdBeforeRefresh' could not be located in the filtered viewable pages for prefix '$pagePrefix'.");
        }
        _setupRealtimeSubscription();
      } else {
        throw Exception("No health record found for IPD ${widget.ipdId} and UHID ${widget.uhid}.");
      }
    } catch (e) {
      debugPrint('Error loading health details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to load details: ${e.toString()}', maxLines: 3),
            backgroundColor: Colors.red));
      }
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

  Future<void> _savePrescriptionData({bool isManualSave = false}) async {
    // ... (implementation unchanged)
    _debounceTimer?.cancel();
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      _syncViewablePagesToMasterList();
      final columnName = _groupToColumnMap[widget.groupName];
      final Map<String, dynamic> dataToSave = {};

      if (columnName != null) {
        dataToSave[columnName] =
            _pagesInCurrentGroup.map((page) => page.toJson()).toList();
      } else { // Custom Group
        // Fetch current custom groups first to avoid overwriting other groups
        final response = await supabase
            .from('user_health_details')
            .select('custom_groups_data')
            .eq('id', _healthRecordId!)
            .single();
        final rawCustomGroups = response['custom_groups_data'] ?? [];
        final List<DrawingGroup> customGroups = (rawCustomGroups as List?)
            ?.map((json) => DrawingGroup.fromJson(json as Map<String, dynamic>))
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
            customGroups.add(_currentGroup!.copyWith(pages: _pagesInCurrentGroup));
          } else {
            throw Exception("Custom group '${widget.groupId}' not found for saving and _currentGroup is null.");
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
            .eq('id', _healthRecordId!);
        _lastSuccessfulSaveTime = DateTime.now();

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Loading stamps...')));
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
                          border:
                          Border.all(color: mediumGreyText.withOpacity(0.5)),
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
                                          ? loadingProgress.cumulativeBytesLoaded /
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
    // ... (implementation unchanged)
    final XFile? pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() => _isSaving = true);
      try {
        final imageFile = await pickedFile.readAsBytes();
        final fileName =
            '${generateUniqueId()}.${pickedFile.path.split('.').last}';
        final storagePath = 'public/images/${widget.uhid}/$fileName';

        await supabase.storage.from(kSupabaseBucketName).uploadBinary(
          storagePath,
          imageFile,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );

        final publicUrl =
        supabase.storage.from(kSupabaseBucketName).getPublicUrl(storagePath);

        _addImageToCanvas(publicUrl);
        await _fetchUserUploadedImages();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Image uploaded and added!'),
              backgroundColor: Colors.green));
        }
      } on StorageException catch (e) {
        debugPrint('Supabase Storage Error: ${e.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Image upload failed: ${e.message}'),
              backgroundColor: Colors.red));
        }
      } catch (e) {
        debugPrint('General Image Error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Image handling failed: $e'),
              backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
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
                          border:
                          Border.all(color: mediumGreyText.withOpacity(0.5)),
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
                                          ? loadingProgress.cumulativeBytesLoaded /
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
    // ... (implementation unchanged)
    final transformedPosition =
    _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    final currentPage = _viewablePages[_currentPageIndex];
    setState(
            () => _isStylusInteraction = details.kind == ui.PointerDeviceKind.stylus);

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
        final imageRect = Rect.fromLTWH(selectedImage.position.dx,
            selectedImage.position.dy, selectedImage.width, selectedImage.height)
            .inflate(5);
        if (imageRect.contains(transformedPosition)) {
          hitSelectedImage = true;
        }
      }

      if (hitSelectedImage) {
        if (_isMovingSelectedImage) {
          _dragStartCanvasPosition = transformedPosition - selectedImage!.position;
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
              strokeWidth: _strokeWidth);
          _viewablePages[_currentPageIndex] =
              currentPage.copyWith(lines: [...currentPage.lines, newLine]);
        });
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent details) {
    // ... (implementation unchanged)
    final transformedPosition =
    _transformToCanvasCoordinates(details.localPosition);
    if (!_isPointOnCanvas(transformedPosition)) return;

    if (_selectedTool == DrawingTool.lasso) {
      setState(() {
        _lassoPoints = [..._lassoPoints, transformedPosition];
        _redrawNotifier.value = 1 - _redrawNotifier.value; // Force redraw of lasso
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
          final updatedLines = List<DrawingLine>.from(currentPage.lines);
          updatedLines.last = lastLine.copyWith(points: newPoints);
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
    // ... (implementation unchanged)
    if (_lassoPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Draw a closed shape to copy content.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }

    final path = Path()..moveTo(_lassoPoints.first.dx, _lassoPoints.first.dy);
    for (int i = 1; i < _lassoPoints.length; i++) {
      path.lineTo(_lassoPoints[i].dx, _lassoPoints.last.dy);
    }
    path.close();

    final currentPage = _viewablePages[_currentPageIndex];
    final copiedLines = <DrawingLine>[];
    final copiedImages = <DrawingImage>[];

    // 1. Copy Lines
    for (var line in currentPage.lines) {
      if (line.points.any((p) => path.contains(p))) {
        copiedLines.add(line.copyWith()); // Copy the entire line if any point is inside
      }
    }

    // 2. Copy Images
    for (var image in currentPage.images) {
      final imageRect = Rect.fromLTWH(
          image.position.dx, image.position.dy, image.width, image.height);
      // Check if the center of the image is inside the lasso path
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

    setState(() {
      _copiedPageData = _CopiedPageData(
        lines: copiedLines,
        images: copiedImages,
      );
    });

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
    // ... (implementation unchanged)
    if (_viewablePages.isEmpty) return;
    final currentPage = _viewablePages[_currentPageIndex];
    setState(() {
      _copiedPageData = _CopiedPageData(
        lines: currentPage.lines.map((line) => line.copyWith()).toList(),
        images: currentPage.images.map((image) => image.copyWith()).toList(),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Full page content copied!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2)));
  }

  void _pastePageContent() {
    // ... (implementation unchanged)
    if (_copiedPageData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nothing to paste.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2)));
      return;
    }
    if (_viewablePages.isEmpty) return;
    setState(() {
      final currentPage = _viewablePages[_currentPageIndex];
      // Assign new unique IDs to pasted images to avoid ID conflicts
      final pastedImagesWithNewIds = _copiedPageData!.images
          .map((imageToCopy) => imageToCopy.copyWith(id: generateUniqueId()))
          .toList();

      _viewablePages[_currentPageIndex] = currentPage.copyWith(
        lines: [...currentPage.lines, ..._copiedPageData!.lines],
        images: [...currentPage.images, ...pastedImagesWithNewIds],
      );
    });
    _debouncedSave();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Content pasted!'),
        backgroundColor: primaryBlue,
        duration: Duration(seconds: 2)));
  }

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
      setState(() =>
      _viewablePages[_currentPageIndex] = currentPage.copyWith(lines: linesToKeep));
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
                              fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? primaryBlue : darkText)),
                      selected: isSelected,
                      selectedTileColor: primaryBlue.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      onTap: () {
                        Navigator.pop(context);
                        final tappedPage = _pagesInCurrentGroup[index];
                        if (tappedPage.id == _viewablePages[_currentPageIndex].id)
                          return;
                        final tappedPrefix =
                        tappedPage.pageName.split('(')[0].trim();
                        final newViewablePages = _pagesInCurrentGroup
                            .where((p) =>
                        p.pageName.split('(')[0].trim() == tappedPrefix)
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
  Future<void> _fetchAllGroupsAndPages(StateSetter modalSetState) async { // Added modalSetState parameter
    if (_healthRecordId == null) return;
    modalSetState(() => _isLoadingAllGroups = true); // Use modalSetState
    try {
      final response = await supabase.rpc(
        'get_group_page_metadata',
        params: {'record_id': _healthRecordId!},
      );

      if (response is List) {
        List<DrawingGroup> allGroups = response
            .map((groupData) => DrawingGroup.fromJson(groupData as Map<String, dynamic>))
            .where((group) => group.pages.isNotEmpty)
            .toList();
        allGroups.sort((a, b) => a.groupName.compareTo(b.groupName));

        // Use modalSetState to update the modal and the main state
        modalSetState(() {
          _allPatientGroups = allGroups;
        });

      } else {
        throw Exception('Unexpected response format from RPC: ${response.runtimeType}');
      }

    } catch (e) {
      debugPrint('Error fetching all groups via RPC: $e');
      if (mounted) {
        // Use modal's context if possible, otherwise use page's context
        BuildContext currentContext = context; // Assuming this is the main page context
        try {
          // Attempt to close modal from its own context if error occurs during fetch
          // If modal isn't open, this might throw, hence the try-catch
          if (Navigator.canPop(currentContext)) Navigator.of(currentContext).pop();
        } catch (_) {}

        ScaffoldMessenger.of(this.context).showSnackBar(SnackBar( // Use this.context for ScaffoldMessenger
            content: Text('Failed to load all groups: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      // Use modalSetState to update loading state
      if (mounted) { // Check if the main widget is still mounted
        modalSetState(() {
          _isLoadingAllGroups = false;
        });
      }
    }
  }


  void _navigateToNewPage(DrawingGroup group, DrawingPage page) {
    // ... (implementation unchanged)
    if (page.id == _viewablePages[_currentPageIndex].id) {
      if (Navigator.canPop(context)) Navigator.of(context).pop(); // Just close the modal
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
                            icon: const Icon(Icons.arrow_back_ios, color: darkText, size: 20),
                            onPressed: () => modalSetState(() => selectedGroup = null),
                          )
                        else
                          const SizedBox(width: 48), // Placeholder
                        Expanded(
                          child: Text(
                            selectedGroup == null ? 'All Groups' : selectedGroup!.groupName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText),
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
                            (DrawingGroup group) { // onGroupTap
                          modalSetState(() => selectedGroup = group);
                        },
                            (DrawingPage page) { // onPageTap
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
          )
      );
    }
    if (currentGroups.isEmpty) {
      return const Center(child: Text('No groups found for this patient.'));
    }


    // Show Page List
    if (selectedGroup != null) {
      // Find the selected group in the latest fetched list
      final groupToShow = IterableX(currentGroups).firstWhereOrNull((g) => g.id == selectedGroup.id);
      if (groupToShow == null || groupToShow.pages.isEmpty) {
        return const Center(child: Text('No pages found in this group.'));
      }
      final pages = groupToShow.pages;

      return ListView.builder(
        key: ValueKey(groupToShow.id), // For AnimatedSwitcher
        itemCount: pages.length,
        itemBuilder: (context, index) {
          final page = pages[index];
          final bool isSelected = page.id == widget.pageId && groupToShow.id == widget.groupId;
          return ListTile(
            leading: Icon(Icons.description_outlined, color: isSelected ? primaryBlue : mediumGreyText),
            title: Text(page.pageName,
                style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? primaryBlue : darkText)),
            selected: isSelected,
            selectedTileColor: primaryBlue.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            leading: Icon(Icons.folder_open_outlined, color: isCurrentGroup ? primaryBlue : mediumGreyText),
            title: Text(group.groupName,
                style: TextStyle(
                    fontWeight: isCurrentGroup ? FontWeight.bold : FontWeight.normal,
                    color: isCurrentGroup ? primaryBlue : darkText)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: mediumGreyText),
            selected: isCurrentGroup,
            selectedTileColor: primaryBlue.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onTap: () => onGroupTap(group),
          );
        },
      );
    }
  }


  // --- END ADDITION ---

  Future<bool> _handleBackButton() async {
    _syncViewablePagesToMasterList();
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop(_pagesInCurrentGroup);
    }
    return false;
  }


  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    // ... (implementation unchanged)
    if (_isLoadingPrescription) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_viewablePages.isEmpty && _currentGroup != null && _currentGroup!.pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handleBackButton),
            title: Text(_currentGroup!.groupName),
            actions: [
              IconButton(
                icon: const Icon(Icons.collections_bookmark_outlined, color: primaryBlue),
                tooltip: 'All Groups',
                onPressed: _showAllGroupsAndPagesModal,
              ),
              const SizedBox(width: 8),
            ]
        ),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("No viewable pages found in '${_currentGroup!.groupName}'. Check if the page ID '${widget.pageId}' exists or if pages are correctly named.",
                    textAlign: TextAlign.center))),
      );
    }
    if (_viewablePages.isEmpty) {
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handleBackButton),
            title: const Text("Error")
        ),
        body: const Center(
            child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Page data could not be loaded or found.",
                    textAlign: TextAlign.center))),
      );
    }


    final currentPageData = _viewablePages[_currentPageIndex];
    final bool panScaleEnabled = !_isStylusInteraction &&
        !_isMovingSelectedImage &&
        _selectedTool != DrawingTool.lasso;

    return WillPopScope(
      onWillPop: _handleBackButton,
      child: Scaffold(
        backgroundColor: lightBackground,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBackButton,
              tooltip: 'Back'),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_patientName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text("${currentPageData.pageName} (${currentPageData.groupName})", style: const TextStyle(fontSize: 12, color: mediumGreyText)),
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
                icon: const Icon(Icons.collections_bookmark_outlined, color: primaryBlue),
                tooltip: 'All Groups',
                onPressed: _showAllGroupsAndPagesModal),
            IconButton(
                icon: const Icon(Icons.list_alt, color: primaryBlue),
                tooltip: 'Select Page in this Group',
                onPressed: _showFolderPageSelector),
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
              icon: const Icon(Icons.picture_as_pdf_rounded, color: primaryBlue),
              tooltip: 'Download Group as PDF',
              onPressed: _isSaving ? null : _downloadGroupAsPdf,
            ),
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
              child: Row(children: [
                Expanded(child: _buildDrawingToolbar()),
                _buildPanToolbar()
              ]),
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
                        lassoPoints: index == _currentPageIndex ? _lassoPoints : [],
                        transformationController: _transformationController,
                        panScaleEnabled: panScaleEnabled,
                        isEnhancedHandwriting: _isEnhancedHandwriting,
                        onTap: (details) {
                          if (_selectedTool == DrawingTool.image && !_isStylusInteraction && !_isMovingSelectedImage) {
                            _handleCanvasTap(_transformToCanvasCoordinates(details.localPosition));
                          }
                        },
                      );
                    },
                  ),
                ),
                if (_selectedImageId != null) _buildImageOverlayControls(),
              ],
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
    // ... (implementation unchanged)
    return PopupMenuButton<String>(
      onSelected: (String value) {
        if (value == 'copy_full') _copyPageContent();
        else if (value == 'paste') _pastePageContent();
        else if (value == 'camera') _pickAndUploadImage(ImageSource.camera);
        else if (value == 'gallery') _pickAndUploadImage(ImageSource.gallery);
        else if (value == 'uploaded') _showUploadedImagesSelector();
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
        if (_copiedPageData != null)
          const PopupMenuItem<String>(
              value: 'paste',
              child: ListTile(
                  leading: Icon(Icons.paste_rounded),
                  title: Text('Paste on Page'))),
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
    // ... (implementation unchanged)
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ToggleButtons(
            isSelected: [
              _selectedTool == DrawingTool.pen,
              _selectedTool == DrawingTool.eraser,
              _selectedTool == DrawingTool.image,
              _selectedTool == DrawingTool.lasso,
            ],
            onPressed: (index) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedImageId = null;
                _isMovingSelectedImage = false;
                _lassoPoints = [];
                if (index == 0) _selectedTool = DrawingTool.pen;
                else if (index == 1) _selectedTool = DrawingTool.eraser;
                else if (index == 2) _selectedTool = DrawingTool.image;
                else _selectedTool = DrawingTool.lasso;
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

          if (_selectedTool == DrawingTool.pen)
            IconButton(
              icon: Icon(
                _isEnhancedHandwriting ? Icons.auto_awesome : Icons.timeline,
                color: _isEnhancedHandwriting ? primaryBlue : mediumGreyText,
                size: 22,
              ),
              tooltip: _isEnhancedHandwriting
                  ? 'Good Handwriting Mode (ON)'
                  : 'Normal Handwriting Mode (ON)',
              onPressed: () {
                setState(() {
                  _isEnhancedHandwriting = !_isEnhancedHandwriting;
                  _redrawNotifier.value = 1 - _redrawNotifier.value;
                });
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_isEnhancedHandwriting
                      ? 'Good Handwriting Mode Activated'
                      : 'Normal Handwriting Mode Activated'),
                  backgroundColor: primaryBlue,
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
          const SizedBox(width: 8),

          if (_selectedTool != DrawingTool.image && _selectedTool != DrawingTool.lasso)
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
                    onChanged: (value) => setState(() => _strokeWidth = value),
                    activeColor: primaryBlue,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 24),
          IconButton(
              icon: const Icon(Icons.undo_rounded, color: primaryBlue, size: 22),
              onPressed: _undoLastAction,
              tooltip: "Undo"),
          IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: primaryBlue, size: 22),
              onPressed: _clearAllDrawings,
              tooltip: "Clear All"),
        ],
      ),
    );
  }

  Widget _buildPanToolbar() {
    // ... (implementation unchanged)
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
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
        onTap: () => setState(() => _currentColor = color),
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

// --- WIDGET TO MANAGE CANVAS AND TEMPLATE IMAGE ---
class _PrescriptionCanvasPage extends StatefulWidget {
  // ... (implementation unchanged) ...
  final DrawingPage drawingPage;
  final String? selectedImageId;
  final ValueNotifier<int> redrawNotifier;
  final List<Offset> lassoPoints;
  final TransformationController transformationController;
  final bool panScaleEnabled;
  final ValueChanged<TapUpDetails> onTap;
  final bool isEnhancedHandwriting;

  const _PrescriptionCanvasPage({
    required this.drawingPage,
    this.selectedImageId,
    required this.redrawNotifier,
    required this.lassoPoints,
    required this.transformationController,
    required this.panScaleEnabled,
    required this.onTap,
    required this.isEnhancedHandwriting,
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
    if (oldWidget.drawingPage != widget.drawingPage) {
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
    // 1. Load Template Image
    final String fullTemplateUrl = _getFullImageUrl(widget.drawingPage.templateImageUrl);
    ui.Image? templateImage;
    if (fullTemplateUrl.isNotEmpty) {
      try {
        templateImage = await ImageCacheManager.loadImage(fullTemplateUrl);
      } catch (e) {
        debugPrint('Error loading template image: $e');
        templateImage = null;
      }
    }

    // 2. Load all Drawing Images concurrently
    final newLoadedDrawingImages = <String, ui.Image>{};
    final futures = <Future<void>>[];

    for (var drawingImage in widget.drawingPage.images) {
      // Use compute if image loading is CPU intensive, but here network/cache is the bottle neck, so just concurrent loading is fine.
      futures.add(() async {
        final cachedImage = ImageCacheManager.getCachedImage(drawingImage.imageUrl);
        if (cachedImage != null) {
          newLoadedDrawingImages[drawingImage.id] = cachedImage;
          return;
        }

        try {
          final loadedImage = await ImageCacheManager.loadImage(drawingImage.imageUrl);
          if (loadedImage != null) {
            newLoadedDrawingImages[drawingImage.id] = loadedImage;
          }
        } catch (e) {
          debugPrint('Error loading drawing image ${drawingImage.id}: $e');
        }
      }());
    }

    // Wait for all drawing images to load
    await Future.wait(futures);

    // 3. Update State
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
    if (widget.drawingPage.templateImageUrl.isNotEmpty && _templateUiImage == null) {
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
        child: CustomPaint(
          painter: PrescriptionPainter(
            drawingPage: widget.drawingPage,
            templateUiImage: _templateUiImage,
            // **OPTIMIZATION: Pass the pre-loaded image map**
            loadedDrawingImages: _loadedDrawingImages,
            selectedImageId: widget.selectedImageId,
            redrawNotifier: widget.redrawNotifier,
            lassoPoints: widget.lassoPoints,
            isEnhancedHandwriting: widget.isEnhancedHandwriting,
          ),
          child: const SizedBox(width: canvasWidth, height: canvasHeight),
        ),
      ),
    );
  }
}

// --- CUSTOM PAINTER CLASS ---
class PrescriptionPainter extends CustomPainter {
  final DrawingPage drawingPage;
  final ui.Image? templateUiImage;
  // **OPTIMIZATION: Accept pre-loaded image map**
  final Map<String, ui.Image> loadedDrawingImages;
  final String? selectedImageId;
  final ValueNotifier<int> redrawNotifier;
  final List<Offset> lassoPoints;
  final bool isEnhancedHandwriting;

  final RdpSimplifier _simplifier = RdpSimplifier();
  final double _simplificationTolerance = 0.75;


  PrescriptionPainter(
      {required this.drawingPage,
        this.templateUiImage,
        required this.redrawNotifier,
        this.selectedImageId,
        required this.lassoPoints,
        required this.isEnhancedHandwriting,
        // **OPTIMIZATION: Initialize with the loaded map**
        required this.loadedDrawingImages
      })
      : super(repaint: redrawNotifier);

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
      // Draw a white background if there's no template image
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.white);
      // Fallback to the original grey loading indicator style
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.grey[200]!);
    }

    // 2. Draw Images
    for (var image in drawingPage.images) {
      // **OPTIMIZATION: Get pre-loaded image directly from the map**
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
        // Draw placeholder if image is still loading (should be rare now)
        canvas.drawRect(destRect, Paint()..color = Colors.grey.withOpacity(0.5));
        final textPainter = TextPainter(
          text: const TextSpan(
              text: 'Loading...',
              style: TextStyle(color: Colors.black, fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, image.position.translate(5, 5));
      }

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
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;


      if (isEnhancedHandwriting && line.points.length > 1) {
        final List<Offset> pointsToDraw =
        _simplifier.simplify(line.points, _simplificationTolerance);

        if (pointsToDraw.length > 1) {
          final path = Path()..moveTo(pointsToDraw.first.dx, pointsToDraw.first.dy);

          if (pointsToDraw.length < 3) {
            path.lineTo(pointsToDraw.last.dx, pointsToDraw.last.dy);
          } else {
            var p1 = pointsToDraw[0];
            var p2 = pointsToDraw[1];
            for (int i = 1; i < pointsToDraw.length - 1; i++) {
              final midPoint = Offset(
                (p1.dx + p2.dx) / 2,
                (p1.dy + p2.dy) / 2,
              );
              path.quadraticBezierTo(p1.dx, p1.dy, midPoint.dx, midPoint.dy);
              p1 = pointsToDraw[i];
              p2 = pointsToDraw[i + 1];
            }
            path.lineTo(p2.dx, p2.dy);
          }
          canvas.drawPath(path, paint);
        }
      } else if (!isEnhancedHandwriting && line.points.length > 1) {
        final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);
        for (int i = 1; i < line.points.length; i++) {
          path.lineTo(line.points[i].dx, line.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 4. Draw Lasso Line
    if (lassoPoints.length > 1) {
      final lassoPaint = Paint()
        ..color = primaryBlue
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final lassoPath = Path()..moveTo(lassoPoints.first.dx, lassoPoints.first.dy);
      for (int i = 1; i < lassoPoints.length; i++) {
        lassoPath.lineTo(lassoPoints[i].dx, lassoPoints[i].dy);
      }
      canvas.drawPath(lassoPath, lassoPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PrescriptionPainter oldDelegate) {
    // **OPTIMIZATION: Add loadedDrawingImages to repaint check**
    return oldDelegate.drawingPage != drawingPage ||
        oldDelegate.templateUiImage != templateUiImage ||
        oldDelegate.selectedImageId != selectedImageId ||
        oldDelegate.lassoPoints.length != lassoPoints.length ||
        oldDelegate.isEnhancedHandwriting != isEnhancedHandwriting ||
        oldDelegate.loadedDrawingImages.length != loadedDrawingImages.length;
  }
}

// --- HELPER CLASS FOR STROKE SIMPLIFICATION (Unchanged) ---
class RdpSimplifier {
  double _getPerpendicularDistance(
      Offset p, Offset p1, Offset p2) {
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

  void _simplify(List<Offset> points, double tolerance,
      List<Offset> out, int start, int end) {
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