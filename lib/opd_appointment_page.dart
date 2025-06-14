import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

class OpdAppointmentPage extends StatefulWidget {
  const OpdAppointmentPage({super.key});

  @override
  State<OpdAppointmentPage> createState() => _OpdAppointmentPageState();
}

class _OpdAppointmentPageState extends State<OpdAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController       = TextEditingController();
  final _phoneController      = TextEditingController();
  final _ageController        = TextEditingController();
  final _messageController    = TextEditingController();
  final _opdTypeController    = TextEditingController();
  final _referredByController = TextEditingController();
  final _studyController      = TextEditingController();

  DateTime?   _selectedDate;
  TimeOfDay?  _selectedTime;
  bool        _isSaving = false;

  // Fixed values for now:
  final String _appointmentType = 'visithospital';
  final String _visitType       = 'first';

  // Example static modalities/payment — you could make these dynamic
  final List<Map<String, dynamic>> _modalities = [
    {
      "charges":    400,
      "doctor":     "Dr. Shweta Nakhwa",
      "specialist": "Gastroenterology",
      "type":       "consultation",
      "visitType":  "first"
    },
    {
      "charges":    400,
      "doctor":     "Dr. Dipesh Pimpale",
      "specialist": "Neuro-Physician",
      "type":       "consultation",
      "visitType":  "first"
    }
  ];
  final Map<String, dynamic> _payment = {
    "cashAmount":   700,
    "discount":     50,
    "onlineAmount": 50,
    "paymentMethod":"mixed",
    "totalCharges": 800,
    "totalPaid":    750
  };

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate:  today.add(const Duration(days: 365)),
    );
    if (result != null) setState(() => _selectedDate = result);
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result != null) setState(() => _selectedTime = result);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date & time")),
      );
      return;
    }

    setState(() => _isSaving = true);

    final supabase = Supabase.instance.client;
    final userId   = supabase.auth.currentUser!.id;

    // 1️⃣ Upsert profile
    final phone = _phoneController.text.trim();
    final age   = int.parse(_ageController.text.trim());
    final profileResp = await supabase
        .from('profiles')
        .upsert({'id': userId, 'phone': phone, 'age': age})
        .execute();

    if (profileResp.error != null) {
      _showError("Profile save failed: ${profileResp.error!.message}");
      setState(() => _isSaving = false);
      return;
    }

    // 2️⃣ Insert OPD appointment
    final appointmentData = {
      'patient_id':       userId,
      'appointment_type': _appointmentType,
      'date':             _selectedDate!.toIso8601String(),
      'time':             _selectedTime!.format(context),
      'message':          _messageController.text.trim(),
      'opd_type':         _opdTypeController.text.trim(),
      'referred_by':      _referredByController.text.trim(),
      'study':            _studyController.text.trim(),
      'visit_type':       _visitType,
      'modalities':       _modalities,
      'payment':          _payment,
    };

    final opdResp = await supabase
        .from('opd_appointments')
        .insert(appointmentData)
        .execute();

    setState(() => _isSaving = false);

    if (opdResp.error != null) {
      _showError("Appointment save failed: ${opdResp.error!.message}");
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Appointment saved successfully!")),
      );
      Navigator.of(context).pop(); // go back
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("OPD Appointment"),
        backgroundColor: const Color(0xFF2A5298),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Patient Name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v!.isEmpty ? "Enter name" : null,
              ),
              const SizedBox(height: 16),

              // Age
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: "Age",
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v!);
                  return (n == null || n <= 0) ? "Enter valid age" : null;
                },
              ),
              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? "Enter phone" : null,
              ),
              const SizedBox(height: 16),

              // Message
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: "Message",
                  prefixIcon: Icon(Icons.message_outlined),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // OPD Type
              TextFormField(
                controller: _opdTypeController,
                decoration: const InputDecoration(
                  labelText: "OPD Type",
                  prefixIcon: Icon(Icons.local_hospital_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Referred By
              TextFormField(
                controller: _referredByController,
                decoration: const InputDecoration(
                  labelText: "Referred By",
                  prefixIcon: Icon(Icons.person_search_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Study
              TextFormField(
                controller: _studyController,
                decoration: const InputDecoration(
                  labelText: "Study",
                  prefixIcon: Icon(Icons.search_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Date & Time Pickers
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _selectedDate == null
                            ? "Select Date"
                            : "${_selectedDate!.toLocal()}".split(' ')[0],
                      ),
                      onPressed: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text(
                        _selectedTime == null
                            ? "Select Time"
                            : _selectedTime!.format(context),
                      ),
                      onPressed: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Submit
              SizedBox(
                width: double.infinity,
                child: _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A5298),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("Submit Appointment"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on PostgrestResponse {
  get error => null;
}
