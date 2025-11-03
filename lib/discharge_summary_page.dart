import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'dart:async';
import 'dart:ui' as ui; // <-- FIX 1: Add aliased 'dart:ui' import
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:collection/collection.dart';

// --- ADDED FOR PDF GENERATION ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart'; // To open the file on mobile
import 'dart:io';
// ----------------------------------

// Assuming these helpers/configs exist in your Flutter project
import 'supabase_config.dart';

// --- Type Definitions (Ported from React) ---

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
      historyOfPresentIllness:
      historyOfPresentIllness ?? this.historyOfPresentIllness,
      investigations: investigations ?? this.investigations,
      treatmentGiven: treatmentGiven ?? this.treatmentGiven,
      hospitalCourse: hospitalCourse ?? this.hospitalCourse,
      surgeryProcedureDetails:
      surgeryProcedureDetails ?? this.surgeryProcedureDetails,
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

// --- Placeholder Services for Gemini/Audio (Simulated) ---

class MicrophoneService {
  Future<void> startRecording() async {
    // Implement real microphone recording
  }
  Future<Uint8List> stopRecording() async {
    // Implement real microphone stop
    return Uint8List(0); // Dummy data
  }
}

class GeminiApiService {
  Future<String> getTranscriptionFromAudio(
      Uint8List audioData, String fieldName) async {
    await Future.delayed(const Duration(seconds: 3));
    return "Simulated transcription for $fieldName.";
  }

  Future<Map<String, dynamic>> getSummaryFromAudio(Uint8List audioData) async {
    await Future.delayed(const Duration(seconds: 5));
    return {
      'finalDiagnosis': 'Simulated AI Final Diagnosis.',
      'historyOfPresentIllness': 'Simulated AI History.',
      'dischargeMedications': 'Simulated AI Meds.',
    };
  }
}

// --- Reusable Input Component with Voice Fill ---
class VoiceInput extends StatelessWidget {
  final String fieldName;
  final String currentValue;
  final ValueChanged<String> onChanged;
  final bool disabled;
  final bool isTextarea;
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
    this.isTextarea = false,
    this.disableVoiceFill = false,
    this.onVoiceFill,
    this.isRecording = false,
    this.isProcessing = false,
    this.isAnyRecordingOrProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      hintText: isTextarea ? 'Enter or dictate $fieldName...' : null,
      contentPadding: isTextarea
          ? const EdgeInsets.all(8.0)
          : const EdgeInsets.only(bottom: 8.0),
      isDense: true,
      border: isTextarea ? const OutlineInputBorder() : InputBorder.none,
      enabledBorder: isTextarea
          ? const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey, width: 1.0))
          : const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey, width: 1.0)),
      focusedBorder: isTextarea
          ? OutlineInputBorder(
          borderSide: BorderSide(color: Colors.indigo.shade600, width: 2.0))
          : UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.indigo.shade600, width: 2.0)),
      filled: !isTextarea,
      fillColor: Colors.transparent,
    );

    final inputWidget = isTextarea
        ? TextField(
      controller: TextEditingController(text: currentValue),
      onChanged: onChanged,
      minLines: 4,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      decoration: inputDecoration,
      enabled: !disabled && !isProcessing,
      // --- FIX 2: Force LTR typing using aliased import ---
      textDirection: ui.TextDirection.ltr,
      style: const TextStyle(fontSize: 14),
    )
        : TextFormField(
      initialValue: currentValue,
      onChanged: onChanged,
      keyboardType: TextInputType.text,
      decoration: inputDecoration,
      enabled: !disabled && !isProcessing,
      // --- FIX 2: Force LTR typing using aliased import ---
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
          padding: EdgeInsets.only(top: isTextarea ? 8.0 : 0),
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
  final SupabaseClient supabase = SupabaseConfig.client;
  // final GlobalKey _formKey = GlobalKey(); // Removed unused key

  late DischargeSummaryData _formData;
  ClinicalNotesData? _clinicalData;
  bool _isLoading = true;
  bool _isSaving = false;

  // Audio/AI State
  bool _isRecording = false;
  bool _isProcessingAudio = false;
  String? _isFieldRecording; // Field name currently recording
  String? _isFieldProcessing; // Field name currently processing

  // Services (Simulated)
  final GeminiApiService _geminiService = GeminiApiService();
  final MicrophoneService _micService = MicrophoneService();

  @override
  void initState() {
    super.initState();
    _initializeFormData();
    _fetchDischargeData();
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
      admissionDateAndTime: '', // Should be fetched with patient data
      dischargeDateAndTime:
      '${DateFormat('dd-MM-yyyy').format(now)} ${DateFormat('HH:mm').format(now)}',
      finalDiagnosis: '',
      finalDiagnosis2: '',
      procedure: '',
      procedure2: '',
      provisionalDiagnosis: '',
      historyOfPresentIllness: '',
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
      final response = await supabase
          .from("user_health_details")
          .select(
          'dischare_summary_written, clinical_notes_data, patient_detail(address, age, gender)')
          .eq("ipd_registration_id", widget.ipdId)
          .single();

      final patientDataList = response['patient_detail'];
      Map<String, dynamic>? patientData;
      if (patientDataList != null &&
          patientDataList is List &&
          patientDataList.isNotEmpty) {
        patientData = patientDataList[0] as Map<String, dynamic>?;
      } else if (patientDataList != null && patientDataList is Map) {
        patientData = patientDataList as Map<String, dynamic>?;
      }

      String address = '';
      String age = '';
      String gender = '';
      String fetchedAgeSex = widget.ageSex;

      if (patientData != null) {
        address = patientData['address'] ?? '';
        age = patientData['age']?.toString() ?? '';
        gender = patientData['gender'] ?? '';
        if (age.isNotEmpty && gender.isNotEmpty) {
          fetchedAgeSex = '$age / $gender';
        }
      }

      final summaryData = response['dischare_summary_written'];
      if (summaryData != null && summaryData is Map<String, dynamic>) {
        _formData = DischargeSummaryData.fromJson(summaryData);
      } else if (summaryData != null &&
          summaryData is List &&
          summaryData.isNotEmpty) {
        _formData = DischargeSummaryData.fromJson(
            summaryData.first as Map<String, dynamic>);
      }

      final clinicalDataRaw = response['clinical_notes_data'];
      if (clinicalDataRaw != null && clinicalDataRaw is Map<String, dynamic>) {
        _clinicalData = ClinicalNotesData.fromJson(clinicalDataRaw);
      } else if (clinicalDataRaw != null &&
          clinicalDataRaw is List &&
          clinicalDataRaw.isNotEmpty) {
        _clinicalData = ClinicalNotesData.fromJson(
            clinicalDataRaw.first as Map<String, dynamic>);
      }

      // Update prefill data (Address)
      _formData = _formData.copyWith(
        detailedAddress: address.split('\n').firstOrNull ?? address,
        detailedAddress2:
        address.split('\n').getRange(1, address.split('\n').length).join(', '),
        ageSex: fetchedAgeSex, // Update age/sex from DB if available
      );
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST116') {
        // Ignore "No rows found"
        _showSnackbar('Failed to fetch data: ${e.message}', isError: true);
      }
    } catch (e) {
      _showSnackbar('Failed to load summary and clinical data: $e',
          isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  // --- Voice Fill Logic (Single Field) ---
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

  // --- Voice Fill Logic (Full Summary) ---
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
          // Merge AI data into form data, overwriting only non-empty strings
          aiData.forEach((key, value) {
            if (value != null && (value as String).isNotEmpty) {
              currentMap[key] = value;
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

  // --- Clinical Data Fetching ---
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

  // --- PDF Generation ---
  Future<void> _generateAndSavePdf() async {
    setState(() => _isSaving = true); // Use _isSaving to show loading
    _showSnackbar("Generating PDF...");

    final doc = pw.Document();
    final data = _formData; // Use the current form data

    // Helper to build a styled text row
    pw.Widget _buildPdfRow(String label, String value) {
      if (value.isEmpty) return pw.Container();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 150,
              child: pw.Text(label,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
              child: pw.Text(value),
            ),
          ],
        ),
      );
    }

    // Helper to build a section (textarea)
    pw.Widget _buildPdfSection(String label, String value) {
      if (value.isEmpty) return pw.Container();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 13)),
            pw.Divider(height: 5),
            pw.Text(value),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Discharge Summary',
                style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          _buildPdfRow('Patient Name:', data.patientName),
          _buildPdfRow('Age/Sex:', data.ageSex),
          _buildPdfRow('UHID/IPD No.:', data.uhidIpdNumber),
          _buildPdfRow('Type of Discharge:', data.typeOfDischarge),
          _buildPdfRow('Consultant In-Charge:', data.consultantInCharge),
          _buildPdfRow('Admission Date:', data.admissionDateAndTime),
          _buildPdfRow('Discharge Date:', data.dischargeDateAndTime),
          _buildPdfRow(
              'Address:', '${data.detailedAddress}, ${data.detailedAddress2}'),
          pw.Divider(thickness: 2, height: 20),
          _buildPdfSection('Provisional Diagnosis:', data.provisionalDiagnosis),
          _buildPdfSection('Final Diagnosis:',
              '${data.finalDiagnosis}\n${data.finalDiagnosis2}'),
          _buildPdfSection(
              'Procedure:', '${data.procedure}\n${data.procedure2}'),
          _buildPdfSection(
              'History of Present Illness:', data.historyOfPresentIllness),
          _buildPdfSection('Investigations:', data.investigations),
          _buildPdfSection('Treatment Given:', data.treatmentGiven),
          _buildPdfSection('Hospital Course:', data.hospitalCourse),
          _buildPdfSection(
              'Surgery / Procedure Details:', data.surgeryProcedureDetails),
          _buildPdfSection(
              'Condition at time of Discharge:', data.conditionAtDischarge),
          _buildPdfSection('Discharge Medications:', data.dischargeMedications),
          _buildPdfSection('Follow Up:', data.followUp),
          _buildPdfSection('Discharge Instruction:', data.dischargeInstruction),
          _buildPdfSection('Report immediately if:', data.reportImmediatelyIf),
          pw.Divider(thickness: 2, height: 20),
          _buildPdfRow('Summary Prepared by:', data.summaryPreparedBy),
          _buildPdfRow('Summary Verified by:', data.summaryVerifiedBy),
          _buildPdfRow('Summary Explained By:', data.summaryExplainedBy),
          _buildPdfRow('Summary Explained To:', data.summaryExplainedTo),
          pw.SizedBox(height: 20),
          _buildPdfRow('Emergency Contact No.:', data.emergencyContact),
          _buildPdfRow('Date:', data.date),
          _buildPdfRow('Time:', data.time),
        ],
      ),
    );

    // --- Save and open the file ---
    try {
      if (kIsWeb) {
        // For web, use printing package to open a preview
        await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => doc.save());
      } else {
        // For mobile, save to temporary directory and open
        final output = await getTemporaryDirectory();
        final file = File(
            "${output.path}/DischargeSummary_${widget.uhid}_${widget.ipdId}.pdf");
        await file.writeAsBytes(await doc.save());

        // Open the file
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) {
          _showSnackbar('Could not open the saved PDF file: ${result.message}',
              isError: true);
        }
      }
    } catch (e) {
      _showSnackbar('Failed to save or open PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Utility ---
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

  // --- Build Methods ---
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discharge Summary'),
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // --- FIX: Removed the Form and _formKey as it was not being used ---
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPatientDetailsHeader(),
              const SizedBox(height: 16),
              const Center(
                child: Text('DISCHARGE SUMMARY',
                    style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(height: 16),
              _buildFullSummaryVoiceControl(isAnyRecordingOrProcessing),
              _buildTopSection(isAnyRecordingOrProcessing),
              const Divider(thickness: 2, height: 32),
              _buildBottomSection(isAnyRecordingOrProcessing),
              const Divider(thickness: 2, height: 32),
              _buildSignatureSection(isAnyRecordingOrProcessing),
              const SizedBox(height: 16),
              _buildContactDateSection(isAnyRecordingOrProcessing),
              _buildActionButtons(isAnyRecordingOrProcessing),
            ],
          ),
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
            Expanded(
              child: VoiceInput(
                fieldName: 'Discharge Date & Time',
                currentValue: _formData.dischargeDateAndTime,
                onChanged: (v) =>
                    _handleInputChange(v, 'dischargeDateAndTime'),
                disabled: _isProcessingAudio,
                disableVoiceFill: true,
                isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
              ),
            ),
          ],
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
        VoiceInput(
          fieldName: 'Provisional Diagnosis',
          currentValue: _formData.provisionalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'provisionalDiagnosis'),
          disabled: _isProcessingAudio,
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
          onVoiceFill: () => _toggleFieldRecording(
              'provisionalDiagnosis', 'Provisional Diagnosis'),
          isRecording: _isFieldRecording == 'provisionalDiagnosis',
          isProcessing: _isFieldProcessing == 'provisionalDiagnosis',
          isAnyRecordingOrProcessing: isAnyRecordingOrProcessing,
        ),
        if (_clinicalData != null)
          TextButton.icon(
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
        VoiceInput(
          fieldName: 'Final Diagnosis 1',
          currentValue: _formData.finalDiagnosis,
          onChanged: (v) => _handleInputChange(v, 'finalDiagnosis'),
          disabled: _isProcessingAudio,
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          fieldName: 'Investigations',
          currentValue: _formData.investigations,
          onChanged: (v) => _handleInputChange(v, 'investigations'),
          disabled: _isProcessingAudio,
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
          onVoiceFill: () =>
              _toggleFieldRecording('investigations', 'Investigations'),
          isRecording: _isFieldRecording == 'investigations',
          isProcessing: _isFieldProcessing == 'investigations',
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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
          // MODIFIED: Changed from isTextarea: true to false
          isTextarea: false,
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

              // --- THE MISSING FIX APPLIED HERE ---
              textDirection: ui.TextDirection.ltr,
              // -------------------------------------

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