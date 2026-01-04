import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:collection/collection.dart';

// --- PDF GENERATION IMPORTS ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

// --- AI & MIC IMPORTS ---
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert'; // For jsonDecode

// Assuming these helpers/configs exist in your Flutter project
import 'supabase_config.dart';
import 'floating_reference_window.dart'; // Contains PipReferenceWindow
import 'ipd_structure.dart'; // Import for groupToColumnMap
import 'drawing_models.dart'; // Assumed source for DrawingGroup, DrawingPage

// --- Utility Functions ---

String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
}

// --- Type Definitions ---
class ClinicalNotesData {
  // Kept class definition for backward compatibility reading,
  // but logic to fetch FROM this is removed as requested.
  final String mainComplaintsDuration;
  final String pastHistory;
  final String familySocialHistory;
  final String generalPhysicalExamination;
  final String systemicExaminationCardiovascular;
  final String respiratory;
  final String perAbdomen;
  final String neurology;
  final String skeletal;
  final String otherFindings;
  final String summary;
  final String provisionalDiagnosis1;
  final String provisionalDiagnosis2;
  final String provisionalDiagnosis3;
  final String otherNotes;

  ClinicalNotesData.fromJson(Map<String, dynamic> json)
      : mainComplaintsDuration = json['mainComplaintsDuration'] ?? '',
        pastHistory = json['pastHistory'] ?? '',
        familySocialHistory = json['familySocialHistory'] ?? '',
        generalPhysicalExamination = json['generalPhysicalExamination'] ?? '',
        systemicExaminationCardiovascular = json['systemicExaminationCardiovascular'] ?? '',
        respiratory = json['respiratory'] ?? '',
        perAbdomen = json['perAbdomen'] ?? '',
        neurology = json['neurology'] ?? '',
        skeletal = json['skeletal'] ?? '',
        otherFindings = json['otherFindings'] ?? '',
        summary = json['summary'] ?? '',
        provisionalDiagnosis1 = json['provisionalDiagnosis1'] ?? '',
        provisionalDiagnosis2 = json['provisionalDiagnosis2'] ?? '',
        provisionalDiagnosis3 = json['provisionalDiagnosis3'] ?? '',
        otherNotes = json['otherNotes'] ?? '';
}

class DischargeSummaryData {
  String typeOfDischarge;
  String patientName;
  String ageSex;
  String uhidIpdNumber;
  String consultantInCharge;
  String detailedAddress;
  String detailedAddress2;
  String admissionDateAndTime;
  String dischargeDateAndTime;
  String finalDiagnosis;
  String finalDiagnosis2;
  String procedure;
  String procedure2;
  String provisionalDiagnosis;
  String historyOfPresentIllness;
  String generalPhysicalExamination;
  String systemicExamination;
  String investigations;
  String treatmentGiven;
  String hospitalCourse;
  String surgeryProcedureDetails;
  String conditionAtDischarge;
  String dischargeMedications;
  String followUp;
  String dischargeInstruction;
  String reportImmediatelyIf;
  String summaryPreparedBy;
  String summaryVerifiedBy;
  String summaryExplainedBy;
  String summaryExplainedTo;
  String emergencyContact;
  String date;
  String time;

  DischargeSummaryData({
    required this.typeOfDischarge,
    required this.patientName,
    required this.ageSex,
    required this.uhidIpdNumber,
    required this.consultantInCharge,
    required this.detailedAddress,
    required this.detailedAddress2,
    required this.admissionDateAndTime,
    required this.dischargeDateAndTime,
    required this.finalDiagnosis,
    required this.finalDiagnosis2,
    required this.procedure,
    required this.procedure2,
    required this.provisionalDiagnosis,
    required this.historyOfPresentIllness,
    required this.generalPhysicalExamination,
    required this.systemicExamination,
    required this.investigations,
    required this.treatmentGiven,
    required this.hospitalCourse,
    required this.surgeryProcedureDetails,
    required this.conditionAtDischarge,
    required this.dischargeMedications,
    required this.followUp,
    required this.dischargeInstruction,
    required this.reportImmediatelyIf,
    required this.summaryPreparedBy,
    required this.summaryVerifiedBy,
    required this.summaryExplainedBy,
    required this.summaryExplainedTo,
    required this.emergencyContact,
    required this.date,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'typeOfDischarge': typeOfDischarge,
    'patientName': patientName,
    'ageSex': ageSex,
    'uhidIpdNumber': uhidIpdNumber,
    'consultantInCharge': consultantInCharge,
    'detailedAddress': detailedAddress,
    'detailedAddress2': detailedAddress2,
    'admissionDateAndTime': admissionDateAndTime,
    'dischargeDateAndTime': dischargeDateAndTime,
    'finalDiagnosis': finalDiagnosis,
    'finalDiagnosis2': finalDiagnosis2,
    'procedure': procedure,
    'procedure2': procedure2,
    'provisionalDiagnosis': provisionalDiagnosis,
    'historyOfPresentIllness': historyOfPresentIllness,
    'generalPhysicalExamination': generalPhysicalExamination,
    'systemicExamination': systemicExamination,
    'investigations': investigations,
    'treatmentGiven': treatmentGiven,
    'hospitalCourse': hospitalCourse,
    'surgeryProcedureDetails': surgeryProcedureDetails,
    'conditionAtDischarge': conditionAtDischarge,
    'dischargeMedications': dischargeMedications,
    'followUp': followUp,
    'dischargeInstruction': dischargeInstruction,
    'reportImmediatelyIf': reportImmediatelyIf,
    'summaryPreparedBy': summaryPreparedBy,
    'summaryVerifiedBy': summaryVerifiedBy,
    'summaryExplainedBy': summaryExplainedBy,
    'summaryExplainedTo': summaryExplainedTo,
    'emergencyContact': emergencyContact,
    'date': date,
    'time': time,
  };

  factory DischargeSummaryData.fromJson(Map<String, dynamic> json) {
    return DischargeSummaryData(
      typeOfDischarge: json['typeOfDischarge'] ?? '',
      patientName: json['patientName'] ?? '',
      ageSex: json['ageSex'] ?? '',
      uhidIpdNumber: json['uhidIpdNumber'] ?? '',
      consultantInCharge: json['consultantInCharge'] ?? '',
      detailedAddress: json['detailedAddress'] ?? '',
      detailedAddress2: json['detailedAddress2'] ?? '',
      admissionDateAndTime: json['admissionDateAndTime'] ?? '',
      dischargeDateAndTime: json['dischargeDateAndTime'] ?? '',
      finalDiagnosis: json['finalDiagnosis'] ?? '',
      finalDiagnosis2: json['finalDiagnosis2'] ?? '',
      procedure: json['procedure'] ?? '',
      procedure2: json['procedure2'] ?? '',
      provisionalDiagnosis: json['provisionalDiagnosis'] ?? '',
      historyOfPresentIllness: json['historyOfPresentIllness'] ?? '',
      generalPhysicalExamination: json['generalPhysicalExamination'] ?? '',
      systemicExamination: json['systemicExamination'] ?? '',
      investigations: json['investigations'] ?? '',
      treatmentGiven: json['treatmentGiven'] ?? '',
      hospitalCourse: json['hospitalCourse'] ?? '',
      surgeryProcedureDetails: json['surgeryProcedureDetails'] ?? '',
      conditionAtDischarge: json['conditionAtDischarge'] ?? '',
      dischargeMedications: json['dischargeMedications'] ?? '',
      followUp: json['followUp'] ?? '',
      dischargeInstruction: json['dischargeInstruction'] ?? '',
      reportImmediatelyIf: json['reportImmediatelyIf'] ?? '',
      summaryPreparedBy: json['summaryPreparedBy'] ?? '',
      summaryVerifiedBy: json['summaryVerifiedBy'] ?? '',
      summaryExplainedBy: json['summaryExplainedBy'] ?? '',
      summaryExplainedTo: json['summaryExplainedTo'] ?? '',
      emergencyContact: json['emergencyContact'] ?? '',
      date: json['date'] ?? '',
      time: json['time'] ?? '',
    );
  }

  DischargeSummaryData copyWith({
    String? typeOfDischarge,
    String? patientName,
    String? ageSex,
    String? uhidIpdNumber,
    String? consultantInCharge,
    String? detailedAddress,
    String? detailedAddress2,
    String? admissionDateAndTime,
    String? dischargeDateAndTime,
    String? finalDiagnosis,
    String? finalDiagnosis2,
    String? procedure,
    String? procedure2,
    String? provisionalDiagnosis,
    String? historyOfPresentIllness,
    String? generalPhysicalExamination,
    String? systemicExamination,
    String? investigations,
    String? treatmentGiven,
    String? hospitalCourse,
    String? surgeryProcedureDetails,
    String? conditionAtDischarge,
    String? dischargeMedications,
    String? followUp,
    String? dischargeInstruction,
    String? reportImmediatelyIf,
    String? summaryPreparedBy,
    String? summaryVerifiedBy,
    String? summaryExplainedBy,
    String? summaryExplainedTo,
    String? emergencyContact,
    String? date,
    String? time,
  }) {
    return DischargeSummaryData(
      typeOfDischarge: typeOfDischarge ?? this.typeOfDischarge,
      patientName: patientName ?? this.patientName,
      ageSex: ageSex ?? this.ageSex,
      uhidIpdNumber: uhidIpdNumber ?? this.uhidIpdNumber,
      consultantInCharge: consultantInCharge ?? this.consultantInCharge,
      detailedAddress: detailedAddress ?? this.detailedAddress,
      detailedAddress2: detailedAddress2 ?? this.detailedAddress2,
      admissionDateAndTime: admissionDateAndTime ?? this.admissionDateAndTime,
      dischargeDateAndTime: dischargeDateAndTime ?? this.dischargeDateAndTime,
      finalDiagnosis: finalDiagnosis ?? this.finalDiagnosis,
      finalDiagnosis2: finalDiagnosis2 ?? this.finalDiagnosis2,
      procedure: procedure ?? this.procedure,
      procedure2: procedure2 ?? this.procedure2,
      provisionalDiagnosis: provisionalDiagnosis ?? this.provisionalDiagnosis,
      historyOfPresentIllness: historyOfPresentIllness ?? this.historyOfPresentIllness,
      generalPhysicalExamination: generalPhysicalExamination ?? this.generalPhysicalExamination,
      systemicExamination: systemicExamination ?? this.systemicExamination,
      investigations: investigations ?? this.investigations,
      treatmentGiven: treatmentGiven ?? this.treatmentGiven,
      hospitalCourse: hospitalCourse ?? this.hospitalCourse,
      surgeryProcedureDetails: surgeryProcedureDetails ?? this.surgeryProcedureDetails,
      conditionAtDischarge: conditionAtDischarge ?? this.conditionAtDischarge,
      dischargeMedications: dischargeMedications ?? this.dischargeMedications,
      followUp: followUp ?? this.followUp,
      dischargeInstruction: dischargeInstruction ?? this.dischargeInstruction,
      reportImmediatelyIf: reportImmediatelyIf ?? this.reportImmediatelyIf,
      summaryPreparedBy: summaryPreparedBy ?? this.summaryPreparedBy,
      summaryVerifiedBy: summaryVerifiedBy ?? this.summaryVerifiedBy,
      summaryExplainedBy: summaryExplainedBy ?? this.summaryExplainedBy,
      summaryExplainedTo: summaryExplainedTo ?? this.summaryExplainedTo,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      date: date ?? this.date,
      time: time ?? this.time,
    );
  }
}

// --- REAL Microphone Service ---
class MicrophoneService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<void> startRecording() async {
    if (!await Permission.microphone.request().isGranted) {
      throw Exception("Microphone permission not granted");
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/temp_audio.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: _path!);
  }

  Future<Uint8List> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) {
      throw Exception("Failed to stop recording or no path found.");
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete();
    _path = null;
    return bytes;
  }

  void dispose() {
    _recorder.dispose();
  }
}

// --- REAL Gemini API Service ---
class GeminiApiService {
  static const String _apiKey = "AIzaSyC0VlnIQ5n_Jv6pX17dNdqKPOzqsukdKeo";
  static const String _model = "gemini-2.5-flash";

  Future<String> getTranscriptionFromAudio(
      Uint8List audioData, String fieldName) async {
    final model = GenerativeModel(model: _model, apiKey: _apiKey);
    final prompt = """
      You are a specialized medical transcriptionist. 
      Transcribe the dictation in the audio file.
      The output must be relevant to the clinical note field: "$fieldName".
      Formatting Rules:
      1. Use UPPERCASE for medical terms if that is the standard style.
      2. If dictating medications, list them clearly (e.g., INJ MONOCEF 1GM IV x BD).
      3. Return ONLY the transcribed text. No markdown, no introductions.
    """;
    final audioPart = DataPart('audio/m4a', audioData);
    final textPart = TextPart(prompt);
    final response = await model.generateContent([
      Content.multi([textPart, audioPart])
    ]);
    if (response.text == null) {
      throw Exception("AI returned an empty transcription.");
    }
    return response.text!.trim();
  }

  Future<Map<String, dynamic>> getSummaryFromAudio(
      Uint8List audioData) async {
    final model = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
    final prompt = """
      You are a specialized medical scribe for an Obstetric/Gynecology department. 
      Listen to the doctor's dictation and extract the data into a JSON object.
      Map the dictation strictly to the following JSON keys. 
      Use UPPERCASE for the content values (except units like mmhg).
      
      JSON Schema to return:
      {
        "provisionalDiagnosis": "string",
        "finalDiagnosis": "string",
        "historyOfPresentIllness": "string",
        "generalPhysicalExamination": "string",
        "systemicExamination": "string",
        "investigations": "string",
        "treatmentGiven": "string",
        "conditionAtDischarge": "string",
        "dischargeInstruction": "string",
        "followUp": "string",
        "procedure": "string"
      }
      If a field is not mentioned, return an empty string "".
    """;
    final audioPart = DataPart('audio/m4a', audioData);
    final textPart = TextPart(prompt);
    final response = await model.generateContent([
      Content.multi([textPart, audioPart])
    ]);
    if (response.text == null) {
      throw Exception("AI returned an empty response.");
    }
    final jsonText = response.text!
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    return jsonDecode(jsonText) as Map<String, dynamic>;
  }
}

// --- UPDATED VoiceInput Component ---
class VoiceInput extends StatefulWidget {
  final String fieldName;
  final String currentValue;
  final ValueChanged<String> onChanged;
  final bool disabled;
  final bool disableVoiceFill;
  final VoidCallback? onVoiceFill;
  final VoidCallback? onHistoryClick; // NEW: Callback for fetching past history
  final bool isRecording;
  final bool isProcessing;
  final bool isAnyRecordingOrProcessing;
  final String? jsonKey;

  const VoiceInput({
    super.key,
    required this.fieldName,
    required this.currentValue,
    required this.onChanged,
    this.disabled = false,
    this.disableVoiceFill = false,
    this.onVoiceFill,
    this.onHistoryClick,
    this.isRecording = false,
    this.isProcessing = false,
    this.isAnyRecordingOrProcessing = false,
    this.jsonKey,
  });

  @override
  State<VoiceInput> createState() => _VoiceInputState();
}

class _VoiceInputState extends State<VoiceInput> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _removeOverlay();
      }
    });
  }

  void _onTextChanged(String text) {
    widget.onChanged(text);

    if (widget.jsonKey == null || widget.disabled) return;

    // --- Suggestion Logic ---
    final selection = _controller.selection;
    if (!selection.isValid || selection.start < 0) return;

    final cursorPosition = selection.start;
    final textBeforeCursor = text.substring(0, cursorPosition);
    
    // Find the word being typed (split by space, newline, comma, etc.)
    // We want the last token before cursor.
    // Regex: Split by anything that is NOT a letter/digit/underscore/hyphen?
    // User SQL uses \n \r . ,
    // Let's rely on space and comma/dot/newline as separators.
    final lastSeparatorIndex = textBeforeCursor.lastIndexOf(RegExp(r'[\s,\.\n]'));
    final currentWordStartIndex = lastSeparatorIndex + 1;
    
    if (currentWordStartIndex > cursorPosition) {
       _removeOverlay();
       return;
    }
    
    final currentWord = textBeforeCursor.substring(currentWordStartIndex);

    if (currentWord.trim().length < 2) {
      _removeOverlay();
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(currentWord.trim());
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    try {
      final res = await SupabaseConfig.client.rpc(
        'get_field_suggestions',
        params: {'target_field': widget.jsonKey!, 'search_text': query},
      );
      
      if (!mounted) return;
      
      final List<dynamic> data = res as List<dynamic>;
      // Filter out duplicate suggestions and same as query
      final suggestions = data
          .map((e) => e['suggestion'] as String)
          .where((s) => s.toLowerCase() != query.toLowerCase())
          .toList();

      setState(() {
        _suggestions = suggestions;
      });

      if (_suggestions.isNotEmpty) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } catch (e) {
      debugPrint("Suggestion fetch error: $e");
    }
  }

  void _showOverlay() {
    if (!mounted) return;
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width - 20, // Slightly smaller than container
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 5.0),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            shadowColor: Colors.black26,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(suggestion, style: const TextStyle(fontSize: 14)),
                    onTap: () => _applySuggestion(suggestion),
                    hoverColor: Colors.indigo.shade50,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _applySuggestion(String suggestion) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid || selection.start < 0) return;

    final cursorPosition = selection.start;
    final textBeforeCursor = text.substring(0, cursorPosition);
    final textAfterCursor = text.substring(cursorPosition);

    final lastSeparatorIndex = textBeforeCursor.lastIndexOf(RegExp(r'[\s,\.\n]'));
    final currentWordStartIndex = lastSeparatorIndex + 1;
    
    final newTextBeforeCursor = textBeforeCursor.substring(0, currentWordStartIndex) + suggestion;
    
    final newText = newTextBeforeCursor + textAfterCursor;
    
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newTextBeforeCursor.length),
    );
    
    widget.onChanged(newText);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  @override
  void didUpdateWidget(covariant VoiceInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentValue != _controller.text) {
      // Avoid overwriting if user is typing (handled by parent update usually, but careful here)
      // If the update comes from outside (e.g. voice fill), we update.
      // We check if the controller text matches widget.currentValue to avoid cursor jumps?
      // Actually the standard pattern is:
      _controller.text = widget.currentValue;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      contentPadding: const EdgeInsets.only(bottom: 8.0),
      isDense: true,
      border: InputBorder.none,
      enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey, width: 1.0)),
      focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.indigo.shade600, width: 2.0)),
      filled: true,
      fillColor: Colors.transparent,
    );

    final inputWidget = CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onTextChanged,
        keyboardType: TextInputType.multiline,
        maxLines: null,
        decoration: inputDecoration,
        enabled: !widget.disabled && !widget.isProcessing,
        textDirection: ui.TextDirection.ltr,
        style: const TextStyle(fontSize: 14),
      ),
    );

    final voiceButton = !widget.disableVoiceFill && widget.onVoiceFill != null
        ? IconButton(
      icon: widget.isProcessing
          ? const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
        widget.isRecording ? Icons.mic_off : Icons.flash_on,
        color: widget.isRecording
            ? Colors.red.shade600
            : widget.isProcessing
            ? Colors.yellow.shade800
            : widget.isAnyRecordingOrProcessing
            ? Colors.grey
            : Colors.indigo.shade600,
      ),
      onPressed: widget.disabled ||
          (widget.isAnyRecordingOrProcessing &&
              !widget.isRecording &&
              !widget.isProcessing)
          ? null
          : widget.onVoiceFill,
      tooltip: 'Voice Fill',
    )
        : const SizedBox.shrink();

    // NEW: Small icon to fetch input from previous record
    final historyButton = widget.onHistoryClick != null
        ? IconButton(
      icon: const Icon(Icons.history_rounded, size: 20, color: Colors.teal),
      tooltip: 'Fetch from previous record',
      onPressed: widget.disabled ? null : widget.onHistoryClick,
    )
        : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '${widget.fieldName}:',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    // Place the history icon right next to the label
                    historyButton,
                  ],
                ),
              ),
              voiceButton,
            ],
          ),
        ),
        inputWidget,
        const SizedBox(height: 8),
      ],
    );
  }
}

// --- Main Discharge Summary Page Widget ---
class DischargeSummaryPage extends StatefulWidget {
  final int ipdId;
  final String uhid;
  final String patientName;
  final String ageSex;

  const DischargeSummaryPage({
    super.key,
    required this.ipdId,
    required this.uhid,
    required this.patientName,
    required this.ageSex,
  });

  @override
  State<DischargeSummaryPage> createState() => _DischargeSummaryPageState();
}

class _DischargeSummaryPageState extends State<DischargeSummaryPage> {
  final SupabaseClient supabase = SupabaseConfig.client;

  late DischargeSummaryData _formData;
  ClinicalNotesData? _clinicalData;
  bool _isLoading = true;
  bool _isSaving = false;

  // --- PiP Window State ---
  String? _healthRecordId;
  List<DrawingGroup>? _allPatientGroups;
  bool _isLoadingAllGroups = false;
  bool _isPipWindowVisible = false;
  PipSelectedPageData? _pipSelectedPageData;
  Offset _pipPosition = const Offset(50, 50);
  Size _pipSize = const Size(400, 565);
  final Map<String, String> _groupToColumnMap = groupToColumnMap;

  // Audio/AI State
  bool _isRecording = false;
  bool _isProcessingAudio = false;
  String? _isFieldRecording;
  String? _isFieldProcessing;

  final GeminiApiService _geminiService = GeminiApiService();
  final MicrophoneService _micService = MicrophoneService();




  @override
  void initState() {
    super.initState();
    _initializeFormData();
    _fetchDischargeData();
  }

  @override
  void dispose() {
    _micService.dispose();
    super.dispose();
  }

  void _initializeFormData() {
    final now = DateTime.now();
    _formData = DischargeSummaryData(
      typeOfDischarge: "Regular",
      patientName: widget.patientName,
      ageSex: widget.ageSex,
      uhidIpdNumber: '${widget.uhid}/${widget.ipdId}',
      consultantInCharge: '',
      detailedAddress: '',
      detailedAddress2: '',
      admissionDateAndTime: '',
      dischargeDateAndTime:
      '${DateFormat('dd-MM-yyyy').format(now)} ${DateFormat('hh:mm a').format(now)}',
      finalDiagnosis: '',
      finalDiagnosis2: '',
      procedure: '',
      procedure2: '',
      provisionalDiagnosis: '',
      historyOfPresentIllness: '',
      generalPhysicalExamination: '',
      systemicExamination: '',
      investigations: '',
      treatmentGiven: '',
      hospitalCourse: '',
      surgeryProcedureDetails: '',
      conditionAtDischarge: '',
      dischargeMedications: '',
      followUp: '',
      dischargeInstruction: '',
      reportImmediatelyIf: '',
      summaryPreparedBy: '',
      summaryVerifiedBy: '',
      summaryExplainedBy: '',
      summaryExplainedTo: '',
      emergencyContact: '',
      date: DateFormat('yyyy-MM-dd').format(now),
      time: DateFormat('hh:mm a').format(now),
    );
  }

  Future<void> _fetchDischargeData() async {
    setState(() => _isLoading = true);
    try {
      final ipdResponse = await supabase
          .from('ipd_registration')
          .select('admission_date, admission_time, created_at')
          .eq('ipd_id', widget.ipdId)
          .maybeSingle();

      String fetchedAdmissionDate = '';
      if (ipdResponse != null) {
        if (ipdResponse['admission_date'] != null) {
          String rawTime = ipdResponse['admission_time'] ?? '';
          String formattedTime = rawTime;
          if (rawTime.isNotEmpty) {
            try {
              final tempDate = DateFormat('HH:mm').parse(rawTime.split('.')[0]);
              formattedTime = DateFormat('hh:mm a').format(tempDate);
            } catch (e) {}
          }
          fetchedAdmissionDate =
              "${ipdResponse['admission_date']} $formattedTime".trim();
        } else if (ipdResponse['created_at'] != null) {
          final createdAt = DateTime.parse(ipdResponse['created_at']);
          fetchedAdmissionDate =
              DateFormat('dd-MM-yyyy hh:mm a').format(createdAt);
        }
      }

      final response = await supabase
          .from("user_health_details")
          .select(
          'id, dischare_summary_written, clinical_notes_data, patient_detail(address, age, gender)')
          .eq("ipd_registration_id", widget.ipdId)
          .maybeSingle();

      _healthRecordId = response?['id'] as String?;

      String address = '';
      String fetchedAgeSex = widget.ageSex;

      if (response != null && response['patient_detail'] != null) {
        final rawPatient = response['patient_detail'];
        final patientData = (rawPatient is List && rawPatient.isNotEmpty)
            ? rawPatient[0]
            : (rawPatient is Map ? rawPatient : null);

        if (patientData != null) {
          address = patientData['address'] ?? '';
          final age = patientData['age']?.toString() ?? '';
          final gender = patientData['gender'] ?? '';
          if (age.isNotEmpty && gender.isNotEmpty) {
            fetchedAgeSex = '$age / $gender';
          }
        }
      }

      if (response != null && response['dischare_summary_written'] != null) {
        final summaryData = response['dischare_summary_written'];
        if (summaryData is List && summaryData.isNotEmpty) {
          _formData = DischargeSummaryData.fromJson(summaryData.first);
        } else if (summaryData is Map<String, dynamic>) {
          _formData = DischargeSummaryData.fromJson(summaryData);
        }
        if (_formData.admissionDateAndTime.trim().isEmpty) {
          _formData.admissionDateAndTime = fetchedAdmissionDate;
        }
      } else {
        _formData.admissionDateAndTime = fetchedAdmissionDate;
      }

      // We still fetch clinical notes to have them in memory, but we don't show the buttons anymore
      if (response != null && response['clinical_notes_data'] != null) {
        final clinicalDataRaw = response['clinical_notes_data'];
        if (clinicalDataRaw is List && clinicalDataRaw.isNotEmpty) {
          _clinicalData = ClinicalNotesData.fromJson(clinicalDataRaw.first);
        } else if (clinicalDataRaw is Map<String, dynamic>) {
          _clinicalData = ClinicalNotesData.fromJson(clinicalDataRaw);
        }
      }

      _formData = _formData.copyWith(
        detailedAddress: _formData.detailedAddress.isEmpty
            ? (address.split('\n').firstOrNull ?? address)
            : _formData.detailedAddress,
        detailedAddress2: _formData.detailedAddress2.isEmpty
            ? (address.split('\n').skip(1).join(', '))
            : _formData.detailedAddress2,
        ageSex: fetchedAgeSex,
      );
    } catch (e) {
      debugPrint("Error fetching data: $e");
      _showSnackbar('Failed to load data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- NEW: SINGLE FIELD HISTORY FETCH ---
  Future<void> _fetchSingleFieldHistory(
      String currentFieldName, String jsonKey) async {
    try {
      // 1. Fetch latest previous summary
      final response = await supabase
          .from('user_health_details')
          .select('dischare_summary_written, updated_at')
          .eq('patient_uhid', widget.uhid)
          .neq('ipd_registration_id', widget.ipdId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null || response['dischare_summary_written'] == null) {
        _showSnackbar(
            "No previous history found for this patient.",
            isError: true);
        return;
      }

      // 2. Parse Data
      final rawData = response['dischare_summary_written'];
      Map<String, dynamic> pastDataMap;

      if (rawData is List && rawData.isNotEmpty) {
        pastDataMap = rawData.first;
      } else if (rawData is Map<String, dynamic>) {
        pastDataMap = rawData;
      } else {
        return;
      }

      // 3. Extract the specific field
      final String pastValue = pastDataMap[jsonKey] ?? '';

      if (pastValue.trim().isEmpty) {
        _showSnackbar("Previous record for $currentFieldName is empty.", isError: true);
        return;
      }

      // 4. Show Confirmation Dialog
      if (!mounted) return;

      final String pastDate = response['updated_at'] != null
          ? DateFormat('dd MMM yyyy').format(DateTime.parse(response['updated_at']))
          : 'Unknown Date';

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Past Data: $currentFieldName"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("From: $pastDate", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                child: Text(pastValue, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                // Append
                final currentVal = _formData.toJson()[jsonKey] ?? '';
                final newVal = currentVal.isEmpty ? pastValue : "$currentVal\n$pastValue";
                _handleInputChange(newVal, jsonKey);
                Navigator.pop(ctx);
              },
              child: const Text("Append"),
            ),
            TextButton(
              onPressed: () {
                // Replace
                _handleInputChange(pastValue, jsonKey);
                Navigator.pop(ctx);
              },
              child: const Text("Replace"),
            ),
          ],
        ),
      );

    } catch (e) {
      _showSnackbar("Error fetching history: $e", isError: true);
    }
  }

  // --- GLOBAL COPY FROM PAST HISTORY ---
  Future<void> _attemptCopyFromPast() async {
    try {
      final response = await supabase
          .from('user_health_details')
          .select('dischare_summary_written, updated_at')
          .eq('patient_uhid', widget.uhid)
          .neq('ipd_registration_id', widget.ipdId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null || response['dischare_summary_written'] == null) {
        _showSnackbar(
            "No previous discharge summary found for UHID: ${widget.uhid}",
            isError: true);
        return;
      }

      DischargeSummaryData pastData;
      final rawData = response['dischare_summary_written'];
      if (rawData is List && rawData.isNotEmpty) {
        pastData = DischargeSummaryData.fromJson(rawData.first);
      } else if (rawData is Map<String, dynamic>) {
        pastData = DischargeSummaryData.fromJson(rawData);
      } else {
        return;
      }

      final String pastDateStr = response['updated_at'] != null
          ? DateFormat('dd MMM yyyy')
          .format(DateTime.parse(response['updated_at']))
          : "Past Date";

      final bool? confirmCopy = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Copy Past Summary?"),
          content: Text(
              "Found a discharge summary from $pastDateStr. Do you want to copy details from it?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("No")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Yes")),
          ],
        ),
      );

      if (confirmCopy != true) return;

      final bool? confirmErase = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("WARNING: Data Replacement"),
          content: const Text(
            "This will replace your current unsaved Diagnosis, History, Treatment, and Instructions with the old data.\n\n"
                "NOTE: Consultant, Admission Date, Discharge Date, Address, and Signatures will NOT be changed.",
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("Yes, Replace")),
          ],
        ),
      );

      if (confirmErase != true) return;

      setState(() {
        _formData = pastData.copyWith(
          patientName: _formData.patientName,
          ageSex: _formData.ageSex,
          uhidIpdNumber: _formData.uhidIpdNumber,
          consultantInCharge: _formData.consultantInCharge,
          admissionDateAndTime: _formData.admissionDateAndTime,
          dischargeDateAndTime: _formData.dischargeDateAndTime,
          detailedAddress: _formData.detailedAddress,
          detailedAddress2: _formData.detailedAddress2,
          summaryPreparedBy: _formData.summaryPreparedBy,
          summaryVerifiedBy: _formData.summaryVerifiedBy,
          summaryExplainedBy: _formData.summaryExplainedBy,
          summaryExplainedTo: _formData.summaryExplainedTo,
          date: _formData.date,
          time: _formData.time,
        );
      });

      _showSnackbar("Discharge Summary details copied from past record.");
    } catch (e) {
      _showSnackbar("Error copying past record: $e", isError: true);
    }
  }

  // --- PiP Functions ---
  Future<void> _loadAllGroupsForPip() async {
    if (_healthRecordId == null) return;
    setState(() => _isLoadingAllGroups = true);
    try {
      final response = await supabase.rpc(
        'get_group_page_metadata',
        params: {'record_id': _healthRecordId!},
      );
      if (response is List) {
        List<DrawingGroup> allGroups = (response as List<dynamic>)
            .map((groupData) {
          if (groupData is Map<String, dynamic>) {
            return DrawingGroup.fromJson(groupData);
          }
          throw Exception('Invalid group data format in RPC response.');
        })
            .where((group) => group.pages.isNotEmpty)
            .toList();
        allGroups.sort((a, b) => a.groupName.compareTo(b.groupName));
        setState(() {
          _allPatientGroups = allGroups;
        });
      }
    } catch (e) {
      debugPrint('Error fetching all groups via RPC: $e');
      if (mounted) {
        _showSnackbar('Failed to load all groups: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAllGroups = false);
      }
    }
  }

  Future<void> _togglePipWindow() async {
    if (_isPipWindowVisible) {
      setState(() => _isPipWindowVisible = false);
      return;
    }
    if (_allPatientGroups == null && !_isLoadingAllGroups) {
      await _loadAllGroupsForPip();
    }
    if (_allPatientGroups != null && _healthRecordId != null) {
      setState(() {
        _isPipWindowVisible = true;
        _pipSelectedPageData = null;
      });
    } else if (!_isLoadingAllGroups) {
      _showSnackbar('Could not load patient groups for reference window.',
          isError: true);
    }
  }

  // --- Input & Save Handlers ---
  void _handleInputChange(String value, String field) {
    setState(() {
      final dataMap = _formData.toJson();
      dataMap[field] = value;
      _formData = DischargeSummaryData.fromJson(dataMap);
    });
  }

  void _handleRadioChange(String value) {
    setState(() {
      _formData.typeOfDischarge = value;
    });
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final session = supabase.auth.currentUser;
      if (session == null) {
        throw Exception("User not authenticated.");
      }
      await supabase.from("user_health_details").upsert({
        'ipd_registration_id': widget.ipdId,
        'patient_uhid': widget.uhid,
        'dischare_summary_written': _formData.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'ipd_registration_id, patient_uhid');
      _showSnackbar("Discharge summary saved successfully!");
    } catch (error) {
      _showSnackbar("Failed to save data: $error", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Voice Fill Logic ---
  void _toggleFieldRecording(String field, String fieldName) {
    if (_isFieldRecording == field) {
      _stopFieldRecording(field, fieldName);
    } else {
      _startFieldRecording(field, fieldName);
    }
  }

  Future<void> _startFieldRecording(String field, String fieldName) async {
    if (_isRecording || _isProcessingAudio || _isFieldRecording != null) {
      _showSnackbar("Please stop the current operation first.");
      return;
    }
    try {
      await _micService.startRecording();
      setState(() => _isFieldRecording = field);
      _showSnackbar("Recording started for $fieldName...");
    } catch (e) {
      _showSnackbar("Failed to start recording: $e", isError: true);
    }
  }

  Future<void> _stopFieldRecording(String field, String fieldName) async {
    if (_isFieldRecording != field) return;
    try {
      final audioData = await _micService.stopRecording();
      setState(() {
        _isFieldRecording = null;
        _isFieldProcessing = field;
      });
      await _processFieldAudio(audioData, field, fieldName);
    } catch (e) {
      _showSnackbar("Failed to stop recording: $e", isError: true);
      setState(() {
        _isFieldRecording = null;
        _isFieldProcessing = null;
      });
    }
  }

  Future<void> _processFieldAudio(
      Uint8List audioData, String field, String fieldName) async {
    try {
      final transcription =
      await _geminiService.getTranscriptionFromAudio(audioData, fieldName);
      if (mounted) {
        setState(() {
          final currentContent =
          (_formData.toJson()[field] as String? ?? '').trim();
          final newContent = transcription.trim();
          final separator =
          field.contains("Diagnosis") || field.contains("Procedure")
              ? "; "
              : "\n\n";
          final updatedContent = currentContent.isNotEmpty
              ? currentContent + separator + newContent
              : newContent;
          final dataMap = _formData.toJson();
          dataMap[field] = updatedContent;
          _formData = DischargeSummaryData.fromJson(dataMap);
          _isFieldProcessing = null;
        });
        _showSnackbar("'$fieldName' updated! Transcription appended.");
      }
    } catch (e) {
      _showSnackbar("Transcription failed: $e", isError: true);
      if (mounted) setState(() => _isFieldProcessing = null);
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isProcessingAudio || _isFieldRecording != null) {
      _showSnackbar("Please stop the current operation first.");
      return;
    }
    try {
      await _micService.startRecording();
      setState(() => _isRecording = true);
      _showSnackbar("Recording FULL summary started...");
    } catch (e) {
      _showSnackbar("Failed to start recording: $e", isError: true);
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final audioData = await _micService.stopRecording();
      setState(() {
        _isRecording = false;
        _isProcessingAudio = true;
      });
      await _processFullSummaryAudio(audioData);
    } catch (e) {
      _showSnackbar("Failed to stop recording: $e", isError: true);
      setState(() {
        _isRecording = false;
        _isProcessingAudio = false;
      });
    }
  }

  Future<void> _processFullSummaryAudio(Uint8List audioData) async {
    try {
      final aiData = await _geminiService.getSummaryFromAudio(audioData);
      if (mounted) {
        setState(() {
          final currentMap = _formData.toJson();
          aiData.forEach((key, value) {
            if (value != null && (value as String).isNotEmpty) {
              if (key == 'dischargeInstruction') {
                currentMap['dischargeInstruction'] = value;
              } else if (currentMap.containsKey(key)) {
                currentMap[key] = value;
              }
            }
          });
          _formData = DischargeSummaryData.fromJson(currentMap);
          _isProcessingAudio = false;
        });
        _showSnackbar("AI analysis complete! Summary fields updated.");
      }
    } catch (e) {
      _showSnackbar("Full summary analysis failed: $e", isError: true);
      if (mounted) setState(() => _isProcessingAudio = false);
    }
  }

  Future<void> _generateAndSavePdf() async {
    setState(() => _isSaving = true);
    _showSnackbar("Generating PDF...");
    try {
      final doc = pw.Document();
      final data = _formData;
      final letterheadByteData = await rootBundle.load('assets/letterhead.png');
      final letterheadImage =
      pw.MemoryImage(letterheadByteData.buffer.asUint8List());

      final PdfColor primaryColor = PdfColor.fromInt(0xff177589);
      const PdfColor accentColor = PdfColors.grey50;
      final PdfColor textColor = PdfColors.grey900;
      const double fsLabel = 7;
      const double fsValue = 9;
      const double fsHeader = 9;
      const double fsBody = 9;

      pw.Widget _buildPatientInfoItem(String label, String value) {
        return pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(
                      color: primaryColor,
                      fontSize: fsLabel,
                      fontWeight: pw.FontWeight.bold)),
              pw.Text(value,
                  style: pw.TextStyle(
                      color: textColor,
                      fontSize: fsValue,
                      fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
      }

      pw.Widget _buildSectionHeader(String title) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: primaryColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          width: double.infinity,
          child: pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: fsHeader,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5),
          ),
        );
      }

      List<pw.Widget> _buildPdfSection(String label, String value) {
        if (value.trim().isEmpty) return [];
        final paragraphs = value.split('\n');
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 1),
            child: pw.Text(label,
                style: pw.TextStyle(
                    color: primaryColor,
                    fontSize: fsBody,
                    fontWeight: pw.FontWeight.bold)),
          ),
          ...paragraphs.map((text) {
            if (text.trim().isEmpty) return pw.SizedBox(height: 2);
            return pw.Container(
              padding: const pw.EdgeInsets.only(left: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.grey300, width: 1.5)),
              ),
              child: pw.Paragraph(
                text: text,
                style: const pw.TextStyle(fontSize: fsBody, lineSpacing: 1.3),
                margin: const pw.EdgeInsets.only(bottom: 2),
              ),
            );
          }).toList(),
          pw.SizedBox(height: 2),
        ];
      }

      pw.Widget _buildSigRow(String label, String value) {
        if (value.trim().isEmpty) return pw.SizedBox();
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text("$label: ",
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.only(
                top: 140, bottom: 50, left: 40, right: 40),
            buildBackground: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(letterheadImage, fit: pw.BoxFit.cover),
              );
            },
          ),
          build: (pw.Context context) => [
            pw.Center(
              child: pw.Text('DISCHARGE SUMMARY',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                      decoration: pw.TextDecoration.underline)),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding:
              const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: accentColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: primaryColor, width: 0.5),
              ),
              child: pw.Column(
                children: [
                  pw.Row(children: [
                    _buildPatientInfoItem('Patient Name', data.patientName),
                    _buildPatientInfoItem('Age / Sex', data.ageSex),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    _buildPatientInfoItem('UHID / IPD No.', data.uhidIpdNumber),
                    _buildPatientInfoItem(
                        'Consultant', data.consultantInCharge),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    _buildPatientInfoItem(
                        'Admission Date', data.admissionDateAndTime),
                    _buildPatientInfoItem(
                        'Discharge Date', data.dischargeDateAndTime),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    _buildPatientInfoItem(
                        'Discharge Type', data.typeOfDischarge),
                    _buildPatientInfoItem('Address',
                        '${data.detailedAddress} ${data.detailedAddress2}'),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            _buildSectionHeader('Clinical Diagnosis'),
            ..._buildPdfSection(
                'Provisional Diagnosis', data.provisionalDiagnosis),
            ..._buildPdfSection('Final Diagnosis',
                '${data.finalDiagnosis}\n${data.finalDiagnosis2}'.trim()),
            ..._buildPdfSection(
                'Procedure / Surgeries',
                '${data.procedure}\n${data.procedure2}\n${data.surgeryProcedureDetails}'
                    .trim()),
            _buildSectionHeader('Clinical Summary'),
            ..._buildPdfSection(
                'History of Present Illness', data.historyOfPresentIllness),
            ..._buildPdfSection('General Physical Examination',
                data.generalPhysicalExamination),
            ..._buildPdfSection(
                'Systemic Examination', data.systemicExamination),
            ..._buildPdfSection('Investigations', data.investigations),
            ..._buildPdfSection('Treatment Given', data.treatmentGiven),
            ..._buildPdfSection('Hospital Course', data.hospitalCourse),
            _buildSectionHeader('Discharge Advice'),
            ..._buildPdfSection(
                'Condition at Discharge', data.conditionAtDischarge),
            if (data.dischargeMedications.isNotEmpty) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4, bottom: 1),
                child: pw.Text('Discharge Medications',
                    style: pw.TextStyle(
                        color: primaryColor,
                        fontSize: fsBody,
                        fontWeight: pw.FontWeight.bold)),
              ),
              pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(3))),
                  child: pw.Text(data.dischargeMedications,
                      style: const pw.TextStyle(fontSize: fsBody))),
              pw.SizedBox(height: 4),
            ],
            ..._buildPdfSection('Follow Up', data.followUp),
            ..._buildPdfSection('Instructions', data.dischargeInstruction),
            if (data.reportImmediatelyIf.isNotEmpty)
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 8),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: pw.Border.all(color: PdfColors.red800),
                  borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("!",
                        style: pw.TextStyle(
                            color: PdfColors.red800,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('EMERGENCY: REPORT IMMEDIATELY IF:',
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.red900,
                                  fontSize: 9)),
                          pw.Text(data.reportImmediatelyIf,
                              style: const pw.TextStyle(
                                  color: PdfColors.red900, fontSize: 9)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (data.emergencyContact.isNotEmpty)
                      pw.Text('Emergency Contact: ${data.emergencyContact}',
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: ${data.date}   Time: ${data.time}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _buildSigRow('Prepared By', data.summaryPreparedBy),
                    _buildSigRow('Verified By', data.summaryVerifiedBy),
                    _buildSigRow('Explained By', data.summaryExplainedBy),
                    _buildSigRow('Explained To', data.summaryExplainedTo),
                    pw.SizedBox(height: 15),
                    pw.Text("Authorized Signatory",
                        style: const pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      if (kIsWeb) {
        await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => doc.save());
      } else {
        final output = await getTemporaryDirectory();
        final file = File(
            "${output.path}/DischargeSummary_${widget.uhid}_${widget.ipdId}.pdf");
        await file.writeAsBytes(await doc.save());
        await OpenFile.open(file.path);
      }
    } catch (e) {
      debugPrint("PDF Error: $e");
      _showSnackbar('Failed to generate PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnyRecordingOrProcessing = _isRecording ||
        _isProcessingAudio ||
        _isFieldRecording != null ||
        _isFieldProcessing != null;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Discharge Summary')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.indigo.shade600),
              const SizedBox(height: 16),
              const Text("Loading Discharge Summary...",
                  style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (!_isSaving && !isAnyRecordingOrProcessing) {
          await _handleSave();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discharge Summary'),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.history, color: Colors.indigo),
              tooltip: 'Copy From Previous Discharge Summary',
              onPressed:
              _isSaving || isAnyRecordingOrProcessing || _isLoading
                  ? null
                  : _attemptCopyFromPast,
            ),
            IconButton(
              icon: Icon(Icons.picture_in_picture_alt_outlined,
                  color: _isPipWindowVisible
                      ? Colors.red
                      : Colors.indigo.shade600),
              tooltip: 'Open Reference Window',
              onPressed: _togglePipWindow,
            ),
            IconButton(
              onPressed:
              _isSaving || isAnyRecordingOrProcessing ? null : _handleSave,
              icon: _isSaving
                  ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18, color: Colors.indigo),
              tooltip: 'Save Summary',
            ),
            IconButton(
              onPressed: _isSaving || isAnyRecordingOrProcessing
                  ? null
                  : _generateAndSavePdf,
              icon: const Icon(Icons.picture_as_pdf,
                  size: 18, color: Colors.indigo),
              tooltip: 'Download PDF',
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              behavior: HitTestBehavior.translucent,
              child: Stack(
                children: [
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPatientDetailsHeader(),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text('DISCHARGE SUMMARY',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                        const SizedBox(height: 16),
                        _buildFullSummaryVoiceControl(
                            isAnyRecordingOrProcessing),
                        _buildTopSection(isAnyRecordingOrProcessing),
                        const Divider(thickness: 2, height: 32),
                        _buildBottomSection(isAnyRecordingOrProcessing),
                        const Divider(thickness: 2, height: 32),
                        _buildSignatureSection(isAnyRecordingOrProcessing),
                        const Divider(thickness: 2, height: 32),
                        _buildContactDateSection(isAnyRecordingOrProcessing),
                        _buildActionButtons(isAnyRecordingOrProcessing),
                      ],
                    ),
                  ),
                ),
                if (_isPipWindowVisible && _healthRecordId != null)
                  Positioned(
                    left: _pipPosition.dx,
                    top: _pipPosition.dy,
                    child: PipReferenceWindow(
                      key: const ValueKey('pip_discharge_window'),
                      patientUhid: widget.uhid,
                      allGroups:
                      (_allPatientGroups ?? []) as List<DrawingGroup>,
                      selectedPageData: _pipSelectedPageData,
                      initialSize: _pipSize,
                      healthRecordId: _healthRecordId!,
                      groupToColumnMap: _groupToColumnMap,
                      onClose: () {
                        setState(() => _isPipWindowVisible = false);
                      },
                      onPageSelected: (dynamic group, dynamic page) {
                        setState(() {
                          _pipSelectedPageData =
                          (group as DrawingGroup, page as DrawingPage);
                        });
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
                          final newWidth = (_pipSize.width + delta.dx)
                              .clamp(300.0, constraints.maxWidth);
                          const double dummyAspectRatio = 1.414;
                          double newHeight = newWidth * dummyAspectRatio;

                          if (newHeight >
                              constraints.maxHeight - _pipPosition.dy) {
                            newHeight =
                                constraints.maxHeight - _pipPosition.dy;
                            final recalculatedWidth =
                                newHeight / dummyAspectRatio;
                            _pipSize = Size(
                                recalculatedWidth.clamp(
                                    300.0, constraints.maxWidth),
                                newHeight);
                          } else {
                            _pipSize = Size(newWidth, newHeight);
                          }
                        });
                      },
                    ),
                  ),
              ],
            ),
           );
          },
        ),
      ),
    );
  }

  Widget _buildPatientDetailsHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Patient Name', _formData.patientName),
          _buildInfoRow('Age/Sex', _formData.ageSex),
          _buildInfoRow('UHID/IPD No.', _formData.uhidIpdNumber),
          _buildInfoRow('Admission Date', _formData.admissionDateAndTime),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text('$label:',
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFullSummaryVoiceControl(bool isAnyRecordingOrProcessing) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _isRecording ? _stopRecording : _startRecording,
          icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
          label: Text(
            _isProcessingAudio
                ? "ANALYZING DICTATION..."
                : _isRecording
                ? "STOP FULL RECORDING & PROCESS SUMMARY"
                : "DICTATE FULL SUMMARY (AI Voice Fill)",
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isProcessingAudio
                ? Colors.yellow.shade700
                : _isRecording
                ? Colors.red.shade600
                : Colors.indigo.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        if (isAnyRecordingOrProcessing)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              _isProcessingAudio
                  ? "AI is extracting and updating summary fields."
                  : _isRecording
                  ? "Full summary dictation in progress."
                  : _isFieldRecording != null
                  ? "Recording in progress for $_isFieldRecording."
                  : _isFieldProcessing != null
                  ? "Processing $_isFieldProcessing..."
                  : "Only one dictation/processing can run at a time.",
              style: TextStyle(
                  color:
                  _isProcessingAudio ? Colors.orange : Colors.indigo),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildTopSection(bool isAnyRecordingOrProcessing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Type of Discharge:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 16),
            ...["Regular", "DAMA", "Transfer", "DOR (Discharge On Request)"]
                .map((type) => Row(
              children: [
                Radio<String>(
                  value: type,
                  groupValue: _formData.typeOfDischarge,
                  onChanged: _isProcessingAudio
                      ? null
                      : (v) => _handleRadioChange(v!),
                ),
                Text(type, style: const TextStyle(fontSize: 13)),
              ],
            )),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: VoiceInput(
                fieldName: 'Consultant In-Charge',
                currentValue: _formData.consultantInCharge,
                onChanged: (v) => _handleInputChange(v, 'consultantInCharge'),
                disabled: _isProcessingAudio,
                onVoiceFill: () => _toggleFieldRecording(
                    'consultantInCharge', 'Consultant In-Charge'),
                isRecording: _isFieldRecording == 'consultantInCharge',
                isProcessing: _isFieldProcessing == 'consultantInCharge',
                isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
                jsonKey: 'consultantInCharge',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VoiceInput(
                fieldName: 'Admission Date & Time',
                currentValue: _formData.admissionDateAndTime,
                onChanged: (v) =>
                    _handleInputChange(v, 'admissionDateAndTime'),
                disabled: _isProcessingAudio,
                onVoiceFill: () => _toggleFieldRecording(
                    'admissionDateAndTime', 'Admission Date & Time'),
                isRecording: _isFieldRecording == 'admissionDateAndTime',
                isProcessing: _isFieldProcessing == 'admissionDateAndTime',
                isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
                jsonKey: 'admissionDateAndTime',
              ),
            ),
          ],
        ),
        VoiceInput(
          fieldName: 'Discharge Date & Time',
          currentValue: _formData.dischargeDateAndTime,
          onChanged: (v) => _handleInputChange(v, 'dischargeDateAndTime'),
          disabled: _isProcessingAudio,
          disableVoiceFill: true,
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Detailed Address',
          currentValue: _formData.detailedAddress,
          onChanged: (v) => _handleInputChange(v, 'detailedAddress'),
          disabled: _isProcessingAudio,
          disableVoiceFill: true,
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Detailed Address (Line 2)',
          currentValue: _formData.detailedAddress2,
          onChanged: (v) => _handleInputChange(v, 'detailedAddress2'),
          disabled: _isProcessingAudio,
          disableVoiceFill: true,
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),

        // --- UPDATED FIELDS WITH HISTORY ICON ---

        VoiceInput(
          fieldName: 'Provisional Diagnosis',
          currentValue: _formData.provisionalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'provisionalDiagnosis'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'provisionalDiagnosis', 'Provisional Diagnosis'),
          onHistoryClick: () => _fetchSingleFieldHistory('Provisional Diagnosis', 'provisionalDiagnosis'),
          isRecording: _isFieldRecording == 'provisionalDiagnosis',
          isProcessing: _isFieldProcessing == 'provisionalDiagnosis',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'provisionalDiagnosis',
        ),
        VoiceInput(
          fieldName: 'Final Diagnosis 1',
          currentValue: _formData.finalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'finalDiagnosis'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('finalDiagnosis', 'Final Diagnosis 1'),
          onHistoryClick: () => _fetchSingleFieldHistory('Final Diagnosis 1', 'finalDiagnosis'),
          isRecording: _isFieldRecording == 'finalDiagnosis',
          isProcessing: _isFieldProcessing == 'finalDiagnosis',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'finalDiagnosis',
        ),
        VoiceInput(
          fieldName: 'Final Diagnosis 2',
          currentValue: _formData.finalDiagnosis2,
          onChanged: (v) => _handleInputChange(v, 'finalDiagnosis2'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('finalDiagnosis2', 'Final Diagnosis 2'),
          onHistoryClick: () => _fetchSingleFieldHistory('Final Diagnosis 2', 'finalDiagnosis2'),
          isRecording: _isFieldRecording == 'finalDiagnosis2',
          isProcessing: _isFieldProcessing == 'finalDiagnosis2',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'finalDiagnosis2',
        ),
        VoiceInput(
          fieldName: 'Procedure 1',
          currentValue: _formData.procedure,
          onChanged: (v) => _handleInputChange(v, 'procedure'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('procedure', 'Procedure 1'),
          onHistoryClick: () => _fetchSingleFieldHistory('Procedure 1', 'procedure'),
          isRecording: _isFieldRecording == 'procedure',
          isProcessing: _isFieldProcessing == 'procedure',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'procedure',
        ),
        VoiceInput(
          fieldName: 'Procedure 2',
          currentValue: _formData.procedure2,
          onChanged: (v) => _handleInputChange(v, 'procedure2'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('procedure2', 'Procedure 2'),
          onHistoryClick: () => _fetchSingleFieldHistory('Procedure 2', 'procedure2'),
          isRecording: _isFieldRecording == 'procedure2',
          isProcessing: _isFieldProcessing == 'procedure2',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'procedure2',
        ),
        VoiceInput(
          fieldName: 'History of Present Illness',
          currentValue: _formData.historyOfPresentIllness,
          onChanged: (v) => _handleInputChange(v, 'historyOfPresentIllness'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'historyOfPresentIllness', 'History of Present Illness'),
          onHistoryClick: () => _fetchSingleFieldHistory('History of Present Illness', 'historyOfPresentIllness'),
          isRecording: _isFieldRecording == 'historyOfPresentIllness',
          isProcessing: _isFieldProcessing == 'historyOfPresentIllness',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'historyOfPresentIllness',
        ),
        VoiceInput(
          fieldName: 'General Physical Examination',
          currentValue: _formData.generalPhysicalExamination,
          onChanged: (v) =>
              _handleInputChange(v, 'generalPhysicalExamination'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'generalPhysicalExamination', 'General Physical Examination'),
          onHistoryClick: () => _fetchSingleFieldHistory('General Physical Examination', 'generalPhysicalExamination'),
          isRecording: _isFieldRecording == 'generalPhysicalExamination',
          isProcessing: _isFieldProcessing == 'generalPhysicalExamination',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'generalPhysicalExamination',
        ),
        VoiceInput(
          fieldName: 'Systemic Examination',
          currentValue: _formData.systemicExamination,
          onChanged: (v) => _handleInputChange(v, 'systemicExamination'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'systemicExamination', 'Systemic Examination'),
          onHistoryClick: () => _fetchSingleFieldHistory('Systemic Examination', 'systemicExamination'),
          isRecording: _isFieldRecording == 'systemicExamination',
          isProcessing: _isFieldProcessing == 'systemicExamination',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'systemicExamination',
        ),
        VoiceInput(
          fieldName: 'Investigations',
          currentValue: _formData.investigations,
          onChanged: (v) => _handleInputChange(v, 'investigations'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('investigations', 'Investigations'),
          onHistoryClick: () => _fetchSingleFieldHistory('Investigations', 'investigations'),
          isRecording: _isFieldRecording == 'investigations',
          isProcessing: _isFieldProcessing == 'investigations',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'investigations',
        ),
        VoiceInput(
          fieldName: 'Treatment Given',
          currentValue: _formData.treatmentGiven,
          onChanged: (v) => _handleInputChange(v, 'treatmentGiven'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('treatmentGiven', 'Treatment Given'),
          onHistoryClick: () => _fetchSingleFieldHistory('Treatment Given', 'treatmentGiven'),
          isRecording: _isFieldRecording == 'treatmentGiven',
          isProcessing: _isFieldProcessing == 'treatmentGiven',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'treatmentGiven',
        ),
      ],
    );
  }

  Widget _buildBottomSection(bool isAnyRecordingOrProcessing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VoiceInput(
          fieldName: 'Hospital Course',
          currentValue: _formData.hospitalCourse,
          onChanged: (v) => _handleInputChange(v, 'hospitalCourse'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('hospitalCourse', 'Hospital Course'),
          onHistoryClick: () => _fetchSingleFieldHistory('Hospital Course', 'hospitalCourse'),
          isRecording: _isFieldRecording == 'hospitalCourse',
          isProcessing: _isFieldProcessing == 'hospitalCourse',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'hospitalCourse',
        ),
        VoiceInput(
          fieldName: 'Surgery / Procedure Details',
          currentValue: _formData.surgeryProcedureDetails,
          onChanged: (v) => _handleInputChange(v, 'surgeryProcedureDetails'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'surgeryProcedureDetails', 'Surgery / Procedure Details'),
          onHistoryClick: () => _fetchSingleFieldHistory('Surgery / Procedure Details', 'surgeryProcedureDetails'),
          isRecording: _isFieldRecording == 'surgeryProcedureDetails',
          isProcessing: _isFieldProcessing == 'surgeryProcedureDetails',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'surgeryProcedureDetails',
        ),
        VoiceInput(
          fieldName: 'Condition at time of Discharge',
          currentValue: _formData.conditionAtDischarge,
          onChanged: (v) => _handleInputChange(v, 'conditionAtDischarge'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'conditionAtDischarge', 'Condition at time of Discharge'),
          onHistoryClick: () => _fetchSingleFieldHistory('Condition at time of Discharge', 'conditionAtDischarge'),
          isRecording: _isFieldRecording == 'conditionAtDischarge',
          isProcessing: _isFieldProcessing == 'conditionAtDischarge',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'conditionAtDischarge',
        ),
        VoiceInput(
          fieldName: 'Discharge Medications',
          currentValue: _formData.dischargeMedications,
          onChanged: (v) => _handleInputChange(v, 'dischargeMedications'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'dischargeMedications', 'Discharge Medications'),
          onHistoryClick: () => _fetchSingleFieldHistory('Discharge Medications', 'dischargeMedications'),
          isRecording: _isFieldRecording == 'dischargeMedications',
          isProcessing: _isFieldProcessing == 'dischargeMedications',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'dischargeMedications',
        ),
        VoiceInput(
          fieldName: 'Follow Up',
          currentValue: _formData.followUp,
          onChanged: (v) => _handleInputChange(v, 'followUp'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('followUp', 'Follow Up'),
          onHistoryClick: () => _fetchSingleFieldHistory('Follow Up', 'followUp'),
          isRecording: _isFieldRecording == 'followUp',
          isProcessing: _isFieldProcessing == 'followUp',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'followUp',
        ),
        VoiceInput(
          fieldName: 'Discharge Instruction (diet, activity, etc.)',
          currentValue: _formData.dischargeInstruction,
          onChanged: (v) => _handleInputChange(v, 'dischargeInstruction'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'dischargeInstruction', 'Discharge Instruction'),
          onHistoryClick: () => _fetchSingleFieldHistory('Discharge Instruction', 'dischargeInstruction'),
          isRecording: _isFieldRecording == 'dischargeInstruction',
          isProcessing: _isFieldProcessing == 'dischargeInstruction',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'dischargeInstruction',
        ),
        VoiceInput(
          fieldName: 'Report immediately to hospital if you notice',
          currentValue: _formData.reportImmediatelyIf,
          onChanged: (v) => _handleInputChange(v, 'reportImmediatelyIf'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('reportImmediatelyIf',
              'Report immediately to hospital if you notice'),
          onHistoryClick: () => _fetchSingleFieldHistory('Report immediately to hospital if you notice', 'reportImmediatelyIf'),
          isRecording: _isFieldRecording == 'reportImmediatelyIf',
          isProcessing: _isFieldProcessing == 'reportImmediatelyIf',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
          jsonKey: 'reportImmediatelyIf',
        ),
      ],
    );
  }

  Widget _buildSignatureSection(bool isAnyRecordingOrProcessing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSignatureRow('Summary Prepared by', 'summaryPreparedBy',
            isAnyRecordingOrProcessing),
        _buildSignatureRow('Summary Verified by', 'summaryVerifiedBy',
            isAnyRecordingOrProcessing),
        _buildSignatureRow('Summary Explained By', 'summaryExplainedBy',
            isAnyRecordingOrProcessing),
        _buildSignatureRow('Summary Explained To', 'summaryExplainedTo',
            isAnyRecordingOrProcessing),
      ],
    );
  }

  Widget _buildSignatureRow(
      String label, String field, bool isAnyRecordingOrProcessing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: TextFormField(
              initialValue: _formData.toJson()[field],
              onChanged: (v) => _handleInputChange(v, field),
              enabled: !_isProcessingAudio && !isAnyRecordingOrProcessing,
              textDirection: ui.TextDirection.ltr,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.only(bottom: 8.0),
                border: UnderlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactDateSection(bool isAnyRecordingOrProcessing) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 8.0,
        children: [
          SizedBox(
            width: 250,
            child: VoiceInput(
              fieldName: 'Emergency Contact No.',
              currentValue: _formData.emergencyContact,
              onChanged: (v) => _handleInputChange(v, 'emergencyContact'),
              disabled: _isProcessingAudio,
              disableVoiceFill: true,
              isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
            ),
          ),
          SizedBox(
            width: 150,
            child: VoiceInput(
              fieldName: 'Date',
              currentValue: _formData.date,
              onChanged: (v) => _handleInputChange(v, 'date'),
              disabled: _isProcessingAudio,
              disableVoiceFill: true,
              isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
            ),
          ),
          SizedBox(
            width: 150,
            child: VoiceInput(
              fieldName: 'Time',
              currentValue: _formData.time,
              onChanged: (v) => _handleInputChange(v, 'time'),
              disabled: _isProcessingAudio,
              disableVoiceFill: true,
              isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isAnyRecordingOrProcessing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            onPressed: _isSaving || isAnyRecordingOrProcessing
                ? null
                : _generateAndSavePdf,
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text("Download PDF"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed:
            _isSaving || isAnyRecordingOrProcessing ? null : _handleSave,
            icon: _isSaving
                ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? "Saving..." : "Save Discharge Summary"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}