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

// --- NEW IMPORTS FOR AI & MIC ---
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert'; // For jsonDecode

// Assuming these helpers/configs exist in your Flutter project
import 'supabase_config.dart';
import 'floating_reference_window.dart'; // Contains PipReferenceWindow
import 'ipd_structure.dart'; // <-- Import for groupToColumnMap
import 'drawing_models.dart'; // <-- NEW: Assumed source for DrawingGroup, DrawingPage, PipSelectedPageData

// --- Utility Functions (Kept for local use) ---

String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
}

List<Offset> simplify(List<Offset> points, double epsilon) {
  if (points.length < 3) {
    return points;
  }

  double findPerpendicularDistance(
      Offset point, Offset lineStart, Offset lineEnd) {
    double dx = lineEnd.dx - lineStart.dx;
    double dy = lineEnd.dy - lineStart.dy;
    if (dx == 0 && dy == 0) return (point - lineStart).distance;
    double t =
        ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) /
            (dx * dx + dy * dy);
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

// --- Type Definitions for Clinical/Discharge Data (No change) ---
class ClinicalNotesData {
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
        systemicExaminationCardiovascular =
            json['systemicExaminationCardiovascular'] ?? '',
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

  Map<String, dynamic> toJson() => {
    'mainComplaintsDuration': mainComplaintsDuration,
    'pastHistory': pastHistory,
    'familySocialHistory': familySocialHistory,
    'generalPhysicalExamination': generalPhysicalExamination,
    'systemicExaminationCardiovascular': systemicExaminationCardiovascular,
    'respiratory': respiratory,
    'perAbdomen': perAbdomen,
    'neurology': neurology,
    'skeletal': skeletal,
    'otherFindings': otherFindings,
    'summary': summary,
    'provisionalDiagnosis1': provisionalDiagnosis1,
    'provisionalDiagnosis2': provisionalDiagnosis2,
    'provisionalDiagnosis3': provisionalDiagnosis3,
    'otherNotes': otherNotes,
  };
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

  // --- NEW FIELDS ---
  String generalPhysicalExamination;
  String systemicExamination;
  // ------------------

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
    required this.generalPhysicalExamination, // Added
    required this.systemicExamination,        // Added
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
    'generalPhysicalExamination': generalPhysicalExamination, // Added
    'systemicExamination': systemicExamination,               // Added
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
      generalPhysicalExamination: json['generalPhysicalExamination'] ?? '', // Added
      systemicExamination: json['systemicExamination'] ?? '',               // Added
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
    String? generalPhysicalExamination, // Added
    String? systemicExamination,        // Added
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
      generalPhysicalExamination: generalPhysicalExamination ?? this.generalPhysicalExamination, // Added
      systemicExamination: systemicExamination ?? this.systemicExamination, // Added
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
// --- REAL Microphone Service (No change) ---
class MicrophoneService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<void> startRecording() async {
    // 1. Check permissions
    if (!await Permission.microphone.request().isGranted) {
      throw Exception("Microphone permission not granted");
    }

    // 2. Get temp path
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/temp_audio.m4a';

    // 3. Start recording
    // Using aacLc encoder which produces an m4a file, compatible with Gemini
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: _path!);
  }

  Future<Uint8List> stopRecording() async {
    // 1. Stop recorder
    final path = await _recorder.stop();
    if (path == null) {
      throw Exception("Failed to stop recording or no path found.");
    }

    // 2. Read file as bytes
    final file = File(path);
    final bytes = await file.readAsBytes();

    // 3. Clean up temp file
    await file.delete();
    _path = null;

    // 4. Return bytes
    return bytes;
  }

  // Call this from the main widget's dispose method
  void dispose() {
    _recorder.dispose();
  }
}

// --- REAL Gemini API Service (No change) ---
class GeminiApiService {
  // --- PASTE YOUR API KEY HERE ---
  static const String _apiKey = "YOUR_API_KEY_HERE"; // PASTE YOUR KEY
  static const String _model = "gemini-1.5-flash"; // Use 1.5-flash

  /// Transcribes audio for a single field
  Future<String> getTranscriptionFromAudio(
      Uint8List audioData, String fieldName) async {
    final model = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
    );

    // Prompt copied directly from your React code
    final prompt = """
      You are a medical transcriptionist. Transcribe the dictation in the provided audio file.
      The transcription should be relevant to the clinical note field: "$fieldName".
      Return ONLY the clean transcribed text. Do not add any extra commentary or formatting.
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

  /// Transcribes a full summary and returns a JSON map
  Future<Map<String, dynamic>> getSummaryFromAudio(
      Uint8List audioData) async {
    // This model is configured to return JSON
    final model = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json', // Enforce JSON output
      ),
    );

    // Prompt copied directly from your React code
    final prompt = """
      You are a highly specialized medical transcriber. The doctor is dictating a detailed Discharge Summary.
      The dictation will cover most of the fields required for the document.
      Extract the following fields from the audio and return them STRICTLY as a clean JSON object.
      If a field is not explicitly dictated, return an empty string "" for that field, but keep the field present in the JSON.

      Format the output only as JSON.

      The JSON schema you must follow is:
      {
        "type": "object",
        "properties": {
          "finalDiagnosis": { "type": "string" },
          "finalDiagnosis2": { "type": "string" },
          "procedure": { "type": "string" },
          "procedure2": { "type": "string" },
          "provisionalDiagnosis": { "type": "string" },
          "historyOfPresentIllness": { "type": "string" },
          "investigations": { "type": "string" },
          "treatmentGiven": { "type": "string" },
          "hospitalCourse": { "type": "string" },
          "surgeryProcedureDetails": { "type": "string" },
          "conditionAtDischarge": { "type": "string" },
          "dischargeMedications": { "type": "string" },
          "followUp": { "type": "string" },
          "dischargeInstruction": { "type": "string" },
          "reportImmediatelyIf": { "type": "string" }
        }
      }
    """;

    final audioPart = DataPart('audio/m4a', audioData);
    final textPart = TextPart(prompt);

    final response = await model.generateContent([
      Content.multi([textPart, audioPart])
    ]);

    if (response.text == null) {
      throw Exception("AI returned an empty response.");
    }

    // Clean the response text (in case it includes ```json ... ```)
    final jsonText = response.text!
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Decode the JSON string into a Map
    return jsonDecode(jsonText) as Map<String, dynamic>;
  }
}

// --- Reusable Input Component (No change) ---
class VoiceInput extends StatelessWidget {
  final String fieldName;
  final String currentValue;
  final ValueChanged<String> onChanged;
  final bool disabled;
  final bool disableVoiceFill;
  final VoidCallback? onVoiceFill;
  final bool isRecording;
  final bool isProcessing;
  final bool isAnyRecordingOrProcessing;

  const VoiceInput({
    super.key,
    required this.fieldName,
    required this.currentValue,
    required this.onChanged,
    this.disabled = false,
    this.disableVoiceFill = false,
    this.onVoiceFill,
    this.isRecording = false,
    this.isProcessing = false,
    this.isAnyRecordingOrProcessing = false,
  });



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

    final inputWidget = TextFormField(
      initialValue: currentValue,
      onChanged: onChanged,
      keyboardType: TextInputType.multiline,
      maxLines: null,
      decoration: inputDecoration,
      enabled: !disabled && !isProcessing,
      textDirection: ui.TextDirection.ltr,
      style: const TextStyle(fontSize: 14),
    );

    final voiceButton = !disableVoiceFill && onVoiceFill != null
        ? IconButton(
      icon: isProcessing
          ? const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
        isRecording ? Icons.mic_off : Icons.flash_on,
        color: isRecording
            ? Colors.red.shade600
            : isProcessing
            ? Colors.yellow.shade800
            : isAnyRecordingOrProcessing
            ? Colors.grey
            : Colors.indigo.shade600,
      ),
      onPressed: disabled ||
          (isAnyRecordingOrProcessing && !isRecording && !isProcessing)
          ? null
          : onVoiceFill,
      tooltip: isRecording
          ? 'Stop Recording'
          : isProcessing
          ? 'Processing...'
          : 'Voice Fill (Appends)',
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
                child: Text(
                  '$fieldName:',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
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
  final String ageSex; // Prefill data

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
  // NOTE: Assuming SupabaseConfig and its client are correctly imported/available
  final SupabaseClient supabase = SupabaseConfig.client;

  late DischargeSummaryData _formData;
  ClinicalNotesData? _clinicalData;
  bool _isLoading = true;
  bool _isSaving = false;

  // --- PiP Window State ---
  String? _healthRecordId;
  // Types DrawingGroup/PipSelectedPageData are now imported
  List<DrawingGroup>? _allPatientGroups;
  bool _isLoadingAllGroups = false;
  bool _isPipWindowVisible = false;
  PipSelectedPageData? _pipSelectedPageData;
  Offset _pipPosition = const Offset(50, 50); // Initial position
  Size _pipSize = const Size(400, 565); // A4 aspect ratio

  // Mapping constant: NOW USING THE groupToColumnMap from the imported ipd_structure.dart
  final Map<String, String> _groupToColumnMap = groupToColumnMap;

  // Audio/AI State
  bool _isRecording = false;
  bool _isProcessingAudio = false;
  String? _isFieldRecording; // Field name currently recording
  String? _isFieldProcessing; // Field name currently processing

  // --- USE REAL SERVICES ---
  final GeminiApiService _geminiService = GeminiApiService();
  final MicrophoneService _micService = MicrophoneService();

  @override
  void initState() {
    super.initState();
    _initializeFormData();
    _fetchDischargeData();
  }

  // --- ADD DISPOSE METHOD ---
  @override
  void dispose() {
    _micService.dispose(); // Dispose the audio recorder
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
      '${DateFormat('dd-MM-yyyy').format(now)} ${DateFormat('HH:mm').format(now)}',
      finalDiagnosis: '',
      finalDiagnosis2: '',
      procedure: '',
      procedure2: '',
      provisionalDiagnosis: '',
      historyOfPresentIllness: '',
      // --- ADDED ---
      generalPhysicalExamination: '',
      systemicExamination: '',
      // -------------
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
      time: DateFormat('HH:mm').format(now),
    );
  }

  // --- Data Fetching ---
  Future<void> _fetchDischargeData() async {
    setState(() => _isLoading = true);
    try {
      // 1. FETCH IPD DETAILS (Safe Admission Date)
      final ipdResponse = await supabase
          .from('ipd_registration')
          .select('admission_date, admission_time, created_at')
          .eq('ipd_id', widget.ipdId)
          .maybeSingle();

      String fetchedAdmissionDate = '';
      if (ipdResponse != null) {
        if (ipdResponse['admission_date'] != null) {
          fetchedAdmissionDate = "${ipdResponse['admission_date']} ${ipdResponse['admission_time'] ?? ''}".trim();
        } else if (ipdResponse['created_at'] != null) {
          final createdAt = DateTime.parse(ipdResponse['created_at']);
          fetchedAdmissionDate = DateFormat('dd-MM-yyyy HH:mm').format(createdAt);
        }
      }

      // 2. FETCH EXISTING SUMMARY
      final response = await supabase
          .from("user_health_details")
          .select('id, dischare_summary_written, clinical_notes_data, patient_detail(address, age, gender)')
          .eq("ipd_registration_id", widget.ipdId)
          .maybeSingle();

      _healthRecordId = response?['id'] as String?;

      // Handle Patient Details
      String address = '';
      String fetchedAgeSex = widget.ageSex;

      if (response != null && response['patient_detail'] != null) {
        // Handle if patient_detail returns a List or a Map
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

      // 3. MERGE DATA (CRASH FIX HERE)
      if (response != null && response['dischare_summary_written'] != null) {
        final summaryData = response['dischare_summary_written'];

        // Check if list is not empty before accessing .first
        if (summaryData is List && summaryData.isNotEmpty) {
          _formData = DischargeSummaryData.fromJson(summaryData.first);
        } else if (summaryData is Map<String, dynamic>) {
          _formData = DischargeSummaryData.fromJson(summaryData);
        }

        // Fallback for admission date
        if (_formData.admissionDateAndTime.trim().isEmpty) {
          _formData.admissionDateAndTime = fetchedAdmissionDate;
        }
      } else {
        _formData.admissionDateAndTime = fetchedAdmissionDate;
      }

      // 4. LOAD CLINICAL NOTES (CRASH FIX HERE)
      if (response != null && response['clinical_notes_data'] != null) {
        final clinicalDataRaw = response['clinical_notes_data'];

        if (clinicalDataRaw is List && clinicalDataRaw.isNotEmpty) {
          _clinicalData = ClinicalNotesData.fromJson(clinicalDataRaw.first);
        } else if (clinicalDataRaw is Map<String, dynamic>) {
          _clinicalData = ClinicalNotesData.fromJson(clinicalDataRaw);
        }
      }

      _formData = _formData.copyWith(
        detailedAddress: _formData.detailedAddress.isEmpty ? (address.split('\n').firstOrNull ?? address) : _formData.detailedAddress,
        detailedAddress2: _formData.detailedAddress2.isEmpty ? (address.split('\n').skip(1).join(', ')) : _formData.detailedAddress2,
        ageSex: fetchedAgeSex,
      );

    } catch (e) {
      debugPrint("Error fetching data: $e");
      _showSnackbar('Failed to load data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

      // Safely map dynamic list elements to DrawingGroup objects.
      if (response is List) {
        List<DrawingGroup> allGroups = (response as List<dynamic>)
            .map((groupData) {
          // Ensure each item is a Map<String, dynamic> before passing to fromJson
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
      } else {
        throw Exception(
            'Unexpected response format from RPC: ${response.runtimeType}');
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

    // Load groups if not already loaded
    if (_allPatientGroups == null && !_isLoadingAllGroups) {
      await _loadAllGroupsForPip();
    }

    // Check again in case fetch failed or is in progress
    if (_allPatientGroups != null && _healthRecordId != null) {
      setState(() {
        _isPipWindowVisible = true;
        // Setting _pipSelectedPageData to null is correct when opening the selector
        _pipSelectedPageData = null;
      });
    } else if (!_isLoadingAllGroups) {
      _showSnackbar('Could not load patient groups for reference window.', isError: true);
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

      await supabase.from("user_health_details").upsert(
          {
            'ipd_registration_id': widget.ipdId,
            'patient_uhid': widget.uhid,
            'dischare_summary_written': _formData.toJson(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict:
          'ipd_registration_id, patient_uhid');

      _showSnackbar("Discharge summary saved successfully!");
    } catch (error) {
      _showSnackbar("Failed to save data: $error", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Voice Fill Logic (Omitted for brevity) ---
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
              if (currentMap.containsKey(key)) {
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

  // --- Clinical Data Fetching (Omitted for brevity) ---
  void _handleFetchClinicalData(String targetField, dynamic sourceField) {
    if (_clinicalData == null) {
      _showSnackbar("No Clinical Notes Data available to fetch.");
      return;
    }

    String fetchedValue = "";

    if (sourceField is String) {
      final fieldMap = _clinicalData!.toJson();
      fetchedValue = fieldMap[sourceField] ?? "";
    } else if (sourceField is List<String>) {
      final fieldMap = _clinicalData!.toJson();
      fetchedValue = sourceField
          .map((field) => fieldMap[field] ?? "")
          .where((val) => val.isNotEmpty)
          .join("; ");
    }

    if (fetchedValue.trim().isNotEmpty) {
      setState(() {
        final dataMap = _formData.toJson();
        dataMap[targetField] = fetchedValue;
        _formData = DischargeSummaryData.fromJson(dataMap);
      });
      _showSnackbar("Data fetched from Clinical Notes for $targetField.");
    } else {
      _showSnackbar("Clinical Notes field(s) for $targetField are empty.",
          isError: true);
    }
  }


  // --- PDF Generation (Omitted for brevity) ---
// --- PDF Generation ---
  // --- PDF Generation ---
  // --- PDF Generation ---
  // --- PDF Generation ---
  // --- PDF Generation ---
  Future<void> _generateAndSavePdf() async {
    setState(() => _isSaving = true);
    _showSnackbar("Generating PDF...");

    try {
      final doc = pw.Document();
      final data = _formData;

      final letterheadByteData = await rootBundle.load('assets/letterhead.png');
      final letterheadImage = pw.MemoryImage(letterheadByteData.buffer.asUint8List());

      // --- THEME ---
      final PdfColor primaryColor = PdfColor.fromInt(0xff177589);
      const PdfColor accentColor = PdfColors.grey50; // Lighter background
      final PdfColor textColor = PdfColors.grey900;

      // Font Sizes (Reduced)
      const double fsLabel = 7;
      const double fsValue = 9;
      const double fsHeader = 9;
      const double fsBody = 9;

      // --- Helper: Compact Patient Info Item ---
      pw.Widget _buildPatientInfoItem(String label, String value) {
        return pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(color: primaryColor, fontSize: fsLabel, fontWeight: pw.FontWeight.bold)),
              pw.Text(value,
                  style: pw.TextStyle(color: textColor, fontSize: fsValue, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
      }

      // --- Helper: Compact Section Header ---
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
                color: PdfColors.white, fontSize: fsHeader, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
          ),
        );
      }

      // --- Helper: Content Generator ---
      List<pw.Widget> _buildPdfSection(String label, String value) {
        if (value.trim().isEmpty) return [];
        final paragraphs = value.split('\n');

        return [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 1),
            child: pw.Text(label,
                style: pw.TextStyle(color: primaryColor, fontSize: fsBody, fontWeight: pw.FontWeight.bold)),
          ),
          ...paragraphs.map((text) {
            if (text.trim().isEmpty) return pw.SizedBox(height: 2);
            return pw.Container(
              padding: const pw.EdgeInsets.only(left: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(color: PdfColors.grey300, width: 1.5)),
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

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.only(top: 140, bottom: 50, left: 40, right: 40),
            buildBackground: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(letterheadImage, fit: pw.BoxFit.cover),
              );
            },
          ),
          build: (pw.Context context) => [
            // Title
            pw.Center(
              child: pw.Text('DISCHARGE SUMMARY',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: primaryColor, decoration: pw.TextDecoration.underline)),
            ),
            pw.SizedBox(height: 10),

            // Patient Info Card (Compact)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
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
                  pw.SizedBox(height: 4), // Reduced Spacing
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 4), // Reduced Spacing
                  pw.Row(children: [
                    _buildPatientInfoItem('UHID / IPD No.', data.uhidIpdNumber),
                    _buildPatientInfoItem('Consultant', data.consultantInCharge),
                  ]),
                  pw.SizedBox(height: 4), // Reduced Spacing
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 4), // Reduced Spacing
                  pw.Row(children: [
                    _buildPatientInfoItem('Admission Date', data.admissionDateAndTime),
                    _buildPatientInfoItem('Discharge Date', data.dischargeDateAndTime),
                  ]),
                  pw.SizedBox(height: 4), // Reduced Spacing
                  pw.Row(children: [
                    _buildPatientInfoItem('Discharge Type', data.typeOfDischarge),
                    _buildPatientInfoItem('Address', '${data.detailedAddress} ${data.detailedAddress2}'),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // Content
            _buildSectionHeader('Clinical Diagnosis'),
            ..._buildPdfSection('Provisional Diagnosis', data.provisionalDiagnosis),
            ..._buildPdfSection('Final Diagnosis', '${data.finalDiagnosis}\n${data.finalDiagnosis2}'.trim()),
            ..._buildPdfSection('Procedure / Surgeries', '${data.procedure}\n${data.procedure2}\n${data.surgeryProcedureDetails}'.trim()),

            _buildSectionHeader('Clinical Summary'),
            ..._buildPdfSection('History of Present Illness', data.historyOfPresentIllness),
            ..._buildPdfSection('General Physical Examination', data.generalPhysicalExamination),
            ..._buildPdfSection('Systemic Examination', data.systemicExamination),
            ..._buildPdfSection('Investigations', data.investigations),
            ..._buildPdfSection('Treatment Given', data.treatmentGiven),
            ..._buildPdfSection('Hospital Course', data.hospitalCourse),

            _buildSectionHeader('Discharge Advice'),
            ..._buildPdfSection('Condition at Discharge', data.conditionAtDischarge),

            if (data.dischargeMedications.isNotEmpty) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4, bottom: 1),
                child: pw.Text('Discharge Medications',
                    style: pw.TextStyle(color: primaryColor, fontSize: fsBody, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3))
                  ),
                  child: pw.Text(data.dischargeMedications, style: const pw.TextStyle(fontSize: fsBody))
              ),
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
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("!", style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('EMERGENCY: REPORT IMMEDIATELY IF:',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900, fontSize: 9)),
                          pw.Text(data.reportImmediatelyIf, style: const pw.TextStyle(color: PdfColors.red900, fontSize: 9)),
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
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    if (data.emergencyContact.isNotEmpty)
                      pw.Text('Emergency Contact: ${data.emergencyContact}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${data.date}   Time: ${data.time}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text(data.summaryPreparedBy.isNotEmpty ? data.summaryPreparedBy : "Doctor's Signature",
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 15),
                    pw.Text("Authorized Signatory", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ]),
                ]
            ),
          ],
        ),
      );

      if (kIsWeb) {
        await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
      } else {
        final output = await getTemporaryDirectory();
        final file = File("${output.path}/DischargeSummary_${widget.uhid}_${widget.ipdId}.pdf");
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
  // --- Utility (Omitted for brevity) ---
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

    // --- WRAPPED IN WillPopScope FOR AUTO-SAVE ---
    return WillPopScope(
      onWillPop: () async {
        // Auto-save if not currently saving or recording
        if (!_isSaving && !isAnyRecordingOrProcessing) {
          // Trigger save but don't block UI excessively (or show a quick toast)
          await _handleSave();
        }
        // Allow pop
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discharge Summary'),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(Icons.picture_in_picture_alt_outlined,
                  color: _isPipWindowVisible ? Colors.red : Colors.indigo.shade600),
              tooltip: 'Open Reference Window',
              onPressed: _togglePipWindow,
            ),
            // Save button kept on top as requested
            IconButton(
              onPressed: _isSaving || isAnyRecordingOrProcessing ? null : _handleSave,
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
              onPressed:
              _isSaving || isAnyRecordingOrProcessing ? null : _generateAndSavePdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18, color: Colors.indigo),
              tooltip: 'Download PDF',
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
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
                        _buildFullSummaryVoiceControl(isAnyRecordingOrProcessing),
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

                // PiP Window
                if (_isPipWindowVisible && _healthRecordId != null)
                  Positioned(
                    left: _pipPosition.dx,
                    top: _pipPosition.dy,
                    child: PipReferenceWindow(
                      key: const ValueKey('pip_discharge_window'),
                      patientUhid: widget.uhid,
                      allGroups: (_allPatientGroups ?? []) as List<DrawingGroup>,
                      selectedPageData: _pipSelectedPageData,
                      initialSize: _pipSize,
                      healthRecordId: _healthRecordId!,
                      groupToColumnMap: _groupToColumnMap,
                      onClose: () {
                        setState(() => _isPipWindowVisible = false);
                      },
                      onPageSelected: (dynamic group, dynamic page) {
                        setState(() {
                          _pipSelectedPageData = (group as DrawingGroup, page as DrawingPage);
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
                          final newWidth = (_pipSize.width + delta.dx).clamp(300.0, constraints.maxWidth);
                          const double dummyAspectRatio = 1.414;
                          double newHeight = newWidth * dummyAspectRatio;

                          if (newHeight > constraints.maxHeight - _pipPosition.dy) {
                            newHeight = constraints.maxHeight - _pipPosition.dy;
                            final recalculatedWidth = newHeight / dummyAspectRatio;
                            _pipSize = Size(recalculatedWidth.clamp(300.0, constraints.maxWidth), newHeight);
                          } else {
                            _pipSize = Size(newWidth, newHeight);
                          }
                        });
                      },
                    ),
                  ),
              ],
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
                  color: _isProcessingAudio ? Colors.orange : Colors.indigo),
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
        // --- Discharge Type Radio Buttons ---
        Row(
          children: [
            const Text('Type of Discharge:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 16),
            ...["Regular", "DAMA", "Transfer"].map((type) => Row(
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

        // --- Row: Consultant & Admission Date (Editable) ---
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
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VoiceInput(
                fieldName: 'Admission Date & Time', // Now Editable
                currentValue: _formData.admissionDateAndTime,
                onChanged: (v) => _handleInputChange(v, 'admissionDateAndTime'),
                disabled: _isProcessingAudio,
                // Optional: Enable voice fill if you want to dictate the date
                onVoiceFill: () => _toggleFieldRecording(
                    'admissionDateAndTime', 'Admission Date & Time'),
                isRecording: _isFieldRecording == 'admissionDateAndTime',
                isProcessing: _isFieldProcessing == 'admissionDateAndTime',
                isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
              ),
            ),
          ],
        ),

        // --- Row: Discharge Date ---
        VoiceInput(
          fieldName: 'Discharge Date & Time',
          currentValue: _formData.dischargeDateAndTime,
          onChanged: (v) => _handleInputChange(v, 'dischargeDateAndTime'),
          disabled: _isProcessingAudio,
          disableVoiceFill: true, // Usually auto-filled, but editable
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),

        // --- Address Fields ---
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

        // --- Diagnosis Section ---
        VoiceInput(
          fieldName: 'Provisional Diagnosis',
          currentValue: _formData.provisionalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'provisionalDiagnosis'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'provisionalDiagnosis', 'Provisional Diagnosis'),
          isRecording: _isFieldRecording == 'provisionalDiagnosis',
          isProcessing: _isFieldProcessing == 'provisionalDiagnosis',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.data_object, size: 16),
              label: const Text('Fetch from Clinical Notes (Diagnosis 1-3)'),
              onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                  ? null
                  : () => _handleFetchClinicalData('provisionalDiagnosis', [
                'provisionalDiagnosis1',
                'provisionalDiagnosis2',
                'provisionalDiagnosis3'
              ]),
            ),
          ),
        VoiceInput(
          fieldName: 'Final Diagnosis 1',
          currentValue: _formData.finalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'finalDiagnosis'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('finalDiagnosis', 'Final Diagnosis 1'),
          isRecording: _isFieldRecording == 'finalDiagnosis',
          isProcessing: _isFieldProcessing == 'finalDiagnosis',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Final Diagnosis 2',
          currentValue: _formData.finalDiagnosis2,
          onChanged: (v) => _handleInputChange(v, 'finalDiagnosis2'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('finalDiagnosis2', 'Final Diagnosis 2'),
          isRecording: _isFieldRecording == 'finalDiagnosis2',
          isProcessing: _isFieldProcessing == 'finalDiagnosis2',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Procedure 1',
          currentValue: _formData.procedure,
          onChanged: (v) => _handleInputChange(v, 'procedure'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('procedure', 'Procedure 1'),
          isRecording: _isFieldRecording == 'procedure',
          isProcessing: _isFieldProcessing == 'procedure',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Procedure 2',
          currentValue: _formData.procedure2,
          onChanged: (v) => _handleInputChange(v, 'procedure2'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('procedure2', 'Procedure 2'),
          isRecording: _isFieldRecording == 'procedure2',
          isProcessing: _isFieldProcessing == 'procedure2',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'History of Present Illness',
          currentValue: _formData.historyOfPresentIllness,
          onChanged: (v) => _handleInputChange(v, 'historyOfPresentIllness'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'historyOfPresentIllness', 'History of Present Illness'),
          isRecording: _isFieldRecording == 'historyOfPresentIllness',
          isProcessing: _isFieldProcessing == 'historyOfPresentIllness',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text(
                'Fetch from Clinical Notes (Main Complaints & Duration)'),
            onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                ? null
                : () => _handleFetchClinicalData(
                'historyOfPresentIllness', 'mainComplaintsDuration'),
          ),
        VoiceInput(
          fieldName: 'General Physical Examination',
          currentValue: _formData.generalPhysicalExamination,
          onChanged: (v) => _handleInputChange(v, 'generalPhysicalExamination'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'generalPhysicalExamination', 'General Physical Examination'),
          isRecording: _isFieldRecording == 'generalPhysicalExamination',
          isProcessing: _isFieldProcessing == 'generalPhysicalExamination',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('Fetch from Clinical Notes (General Exam)'),
            onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                ? null
                : () => _handleFetchClinicalData(
                'generalPhysicalExamination', 'generalPhysicalExamination'),
          ),

        VoiceInput(
          fieldName: 'Systemic Examination',
          currentValue: _formData.systemicExamination,
          onChanged: (v) => _handleInputChange(v, 'systemicExamination'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'systemicExamination', 'Systemic Examination'),
          isRecording: _isFieldRecording == 'systemicExamination',
          isProcessing: _isFieldProcessing == 'systemicExamination',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('Fetch from Clinical Notes (Systemic Exams)'),
            onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                ? null
                : () => _handleFetchClinicalData(
                'systemicExamination', [
              'systemicExaminationCardiovascular',
              'respiratory',
              'perAbdomen',
              'neurology',
              'skeletal',
              'otherFindings'
            ]),
          ),
        // ----------------------------
        VoiceInput(
          fieldName: 'Investigations',
          currentValue: _formData.investigations,
          onChanged: (v) => _handleInputChange(v, 'investigations'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('investigations', 'Investigations'),
          isRecording: _isFieldRecording == 'investigations',
          isProcessing: _isFieldProcessing == 'investigations',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Treatment Given',
          currentValue: _formData.treatmentGiven,
          onChanged: (v) => _handleInputChange(v, 'treatmentGiven'),
          disabled: _isProcessingAudio,
          onVoiceFill: () =>
              _toggleFieldRecording('treatmentGiven', 'Treatment Given'),
          isRecording: _isFieldRecording == 'treatmentGiven',
          isProcessing: _isFieldProcessing == 'treatmentGiven',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
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
          isRecording: _isFieldRecording == 'hospitalCourse',
          isProcessing: _isFieldProcessing == 'hospitalCourse',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('Fetch from Clinical Notes (Summary)'),
            onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                ? null
                : () => _handleFetchClinicalData('hospitalCourse', 'summary'),
          ),
        VoiceInput(
          fieldName: 'Surgery / Procedure Details',
          currentValue: _formData.surgeryProcedureDetails,
          onChanged: (v) => _handleInputChange(v, 'surgeryProcedureDetails'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'surgeryProcedureDetails', 'Surgery / Procedure Details'),
          isRecording: _isFieldRecording == 'surgeryProcedureDetails',
          isProcessing: _isFieldProcessing == 'surgeryProcedureDetails',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('Fetch from Clinical Notes (Other Findings)'),
            onPressed: _isProcessingAudio || isAnyRecordingOrProcessing
                ? null
                : () => _handleFetchClinicalData(
                'surgeryProcedureDetails', 'otherFindings'),
          ),
        VoiceInput(
          fieldName: 'Condition at time of Discharge',
          currentValue: _formData.conditionAtDischarge,
          onChanged: (v) => _handleInputChange(v, 'conditionAtDischarge'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'conditionAtDischarge', 'Condition at time of Discharge'),
          isRecording: _isFieldRecording == 'conditionAtDischarge',
          isProcessing: _isFieldProcessing == 'conditionAtDischarge',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Discharge Medications',
          currentValue: _formData.dischargeMedications,
          onChanged: (v) => _handleInputChange(v, 'dischargeMedications'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'dischargeMedications', 'Discharge Medications'),
          isRecording: _isFieldRecording == 'dischargeMedications',
          isProcessing: _isFieldProcessing == 'dischargeMedications',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Follow Up',
          currentValue: _formData.followUp,
          onChanged: (v) => _handleInputChange(v, 'followUp'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('followUp', 'Follow Up'),
          isRecording: _isFieldRecording == 'followUp',
          isProcessing: _isFieldProcessing == 'followUp',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Discharge Instruction (diet, activity, etc.)',
          currentValue: _formData.dischargeInstruction,
          onChanged: (v) => _handleInputChange(v, 'dischargeInstruction'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording(
              'dischargeInstruction', 'Discharge Instruction'),
          isRecording: _isFieldRecording == 'dischargeInstruction',
          isProcessing: _isFieldProcessing == 'dischargeInstruction',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        VoiceInput(
          fieldName: 'Report immediately to hospital if you notice',
          currentValue: _formData.reportImmediatelyIf,
          onChanged: (v) => _handleInputChange(v, 'reportImmediatelyIf'),
          disabled: _isProcessingAudio,
          onVoiceFill: () => _toggleFieldRecording('reportImmediatelyIf',
              'Report immediately to hospital if you notice'),
          isRecording: _isFieldRecording == 'reportImmediatelyIf',
          isProcessing: _isFieldProcessing == 'reportImmediatelyIf',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
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
            onPressed:
            _isSaving || isAnyRecordingOrProcessing ? null : _generateAndSavePdf,
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text("Download PDF"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _isSaving || isAnyRecordingOrProcessing ? null : _handleSave,
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