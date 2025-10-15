import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Application Colors (Used for styling the modal)
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);
const Color mediumGreyText = Color(0xFF64748B);
const Color lightBackground = Color(0xFFF8FAFC);

/// A modal that fetches and displays essential patient identifying and clinical information
/// from multiple database tables when opened.
class PatientInfoModal extends StatefulWidget {
  final SupabaseClient supabase;
  final int ipdId;
  final String uhid;
  final String? healthRecordId;

  const PatientInfoModal({
    super.key,
    required this.supabase,
    required this.ipdId,
    required this.uhid,
    this.healthRecordId,
  });

  @override
  State<PatientInfoModal> createState() => _PatientInfoModalState();
}

class _PatientInfoModalState extends State<PatientInfoModal> {
  bool _isLoading = true;
  String _errorMessage = '';

  // Data to be populated from the database
  String _patientName = 'N/A';
  Map<String, dynamic> _patientDetails = {};
  Map<String, dynamic> _ipdRegistrationDetails = {};
  Map<String, dynamic> _bedDetails = {};

  @override
  void initState() {
    super.initState();
    _fetchPatientDetails();
  }

  Future<void> _fetchPatientDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      // Fetch detailed IPD, Patient, and Bed information in a single join query
      final ipdResponse = await widget.supabase
          .from('ipd_registration')
      // Select IPD, join patient_detail and bed_management.
          .select('*, patient_detail(*), bed_management(*)')
          .eq('uhid', widget.uhid)
          .eq('ipd_id', widget.ipdId)
          .maybeSingle();

      if (ipdResponse != null) {
        _ipdRegistrationDetails = ipdResponse;
        _patientDetails = ipdResponse['patient_detail'] as Map<String, dynamic>? ?? {};
        _bedDetails = ipdResponse['bed_management'] as Map<String, dynamic>? ?? {};

        // Final name assignment
        _patientName = _patientDetails['name'] as String? ?? 'N/A';
      } else {
        _errorMessage = "No IPD record found for UHID: ${widget.uhid}, IPD ID: ${widget.ipdId}.";
      }
    } catch (e) {
      _errorMessage = "Failed to load patient data: ${e.toString()}";
      debugPrint(_errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Patient Details",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: mediumGreyText),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 16, color: mediumGreyText),

            _buildContent()
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        heightFactor: 3,
        child: CircularProgressIndicator(color: primaryBlue),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          _errorMessage,
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
      );
    }

    // Extract necessary fields using null checks
    final int? age = _patientDetails['age'] as int?;
    final String? ageUnit = _patientDetails['age_unit'] as String?;
    final String? dob = _patientDetails['dob'] as String?;
    final String? phoneNumber = (_patientDetails['number'] as num?)?.toString();
    final String? address = _patientDetails['address'] as String?;

    final String? underCareOfDoctor = _ipdRegistrationDetails['under_care_of_doctor'] as String?;
    final String? admissionDate = _ipdRegistrationDetails['admission_date'] as String?;
    final String? admissionTime = _ipdRegistrationDetails['admission_time'] as String?;
    final String? admissionType = _ipdRegistrationDetails['admission_type'] as String?;
    final String? admissionSource = _ipdRegistrationDetails['admission_source'] as String?;
    final bool? isTpa = _ipdRegistrationDetails['tpa'] as bool?;

    final String? relativeName = _ipdRegistrationDetails['relative_name'] as String?;
    final String? relativePhNo = (_ipdRegistrationDetails['relative_ph_no'] as num?)?.toString();
    final String? relativeAddress = _ipdRegistrationDetails['relative_address'] as String?;

    final String? roomType = _bedDetails['room_type'] as String?;
    final String? bedNumber = _bedDetails['bed_number'] as String?;

    // Build the detailed layout once data is loaded
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Section 1: Core Patient & IPD Info ---
        _buildSectionHeader("Core Registration Information", Icons.local_hospital_outlined),
        _buildDetailRow(Icons.person_outline, "Patient Name", _patientName, Colors.green),
        _buildDetailRow(Icons.tag_rounded, "UHID", widget.uhid, darkText),
        _buildDetailRow(Icons.receipt_long, "IPD Registration ID", widget.ipdId.toString(), darkText),

        _buildInfoCard(
            title: "Clinical & Admission",
            details: [
              if (underCareOfDoctor != null) _buildDetailRow(Icons.medical_services_outlined, "Under Care Of Doctor", underCareOfDoctor),
              if (admissionDate != null) _buildDetailRow(Icons.calendar_month, "Admission Date", "$admissionDate (${admissionTime ?? 'N/A'})"),
              if (admissionType != null) _buildDetailRow(Icons.vpn_key_outlined, "Admission Type", admissionType),
              if (admissionSource != null) _buildDetailRow(Icons.login, "Admission Source", admissionSource),
              if (isTpa != null) _buildDetailRow(Icons.credit_card, "TPA/Insurance", isTpa ? "Yes" : "No"),
            ]
        ),

        // --- Section 2: Patient Full Details ---
        _buildSectionHeader("Full Patient Demographics", Icons.description_outlined),
        _buildInfoCard(
            title: "Patient Demographics",
            details: [
              if (age != null) _buildDetailRow(Icons.cake_outlined, "Age", "$age ${ageUnit ?? 'years'} ($dob)"),
              if (_patientDetails['gender'] != null) _buildDetailRow(Icons.man_outlined, "Gender", _patientDetails['gender']),
              if (phoneNumber != null) _buildDetailRow(Icons.phone_iphone_outlined, "Phone Number", phoneNumber),
              if (address != null) _buildDetailRow(Icons.location_on_outlined, "Address", address),
            ]
        ),

        // --- Section 3: Bed & Room Details ---
        _buildSectionHeader("Current Bed Assignment", Icons.bed_outlined),
        _buildInfoCard(
          title: "Bed Details",
          details: [
            if (roomType != null) _buildDetailRow(Icons.house_outlined, "Room Type", roomType),
            if (bedNumber != null) _buildDetailRow(Icons.bed, "Bed Number", bedNumber),
          ],
        ),

        // --- Section 4: Relative Details ---
        if (relativeName != null || relativePhNo != null || relativeAddress != null)
          _buildSectionHeader("Relative/Contact Person", Icons.family_restroom_outlined),
        _buildInfoCard(
          title: "Relative Contact",
          details: [
            if (relativeName != null) _buildDetailRow(Icons.badge_outlined, "Relative Name", relativeName),
            if (relativePhNo != null) _buildDetailRow(Icons.phone_in_talk_outlined, "Phone Number", relativePhNo),
            if (relativeAddress != null) _buildDetailRow(Icons.location_city_outlined, "Address", relativeAddress),
          ],
        ),

        // --- Footer / Internal ID ---
        if (widget.healthRecordId != null)
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: _buildDetailRow(
              Icons.vpn_key,
              "Internal Health Record ID",
              widget.healthRecordId!,
              Colors.grey,
              12.0,
            ),
          ),

        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            "Reference these IDs when making manual entries on the page.",
            style: TextStyle(fontSize: 12, color: mediumGreyText.withOpacity(0.8), fontStyle: FontStyle.italic),
          ),
        )
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: darkText),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required List<Widget> details}) {
    if (details.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0.5,
      color: lightBackground,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details,
        ),
      ),
    );
  }


  Widget _buildDetailRow(IconData icon, String label, String value, [Color iconColor = primaryBlue, double fontSize = 16.0]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: mediumGreyText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: darkText,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
