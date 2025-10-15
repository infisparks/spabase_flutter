import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'supabase_config.dart'; // Your Supabase configuration
import 'manage_ipd_patient_page.dart'; // Import the next page

// --- Type Definitions ---
class PatientDetail {
  final int patientId;
  final String name;
  final String? number;
  final String uhid;
  final String? dob;

  PatientDetail({
    required this.patientId,
    required this.name,
    this.number,
    required this.uhid,
    this.dob,
  });

  factory PatientDetail.fromJson(Map<String, dynamic> json) {
    return PatientDetail(
      patientId: json['patient_id'] as int,
      name: json['name'] as String,
      number: json['number']?.toString(),
      uhid: json['uhid'] as String,
      dob: json['dob'] as String?,
    );
  }
}

class BedManagement {
  final int id;
  final String roomType;
  final String bedNumber;
  final String bedType;
  final String status;

  BedManagement({
    required this.id,
    required this.roomType,
    required this.bedNumber,
    required this.bedType,
    required this.status,
  });

  factory BedManagement.fromJson(Map<String, dynamic> json) {
    return BedManagement(
      id: json['id'] as int,
      roomType: json['room_type'] as String,
      bedNumber: json['bed_number'] as String,
      bedType: json['bed_type'] as String,
      status: json['status'] as String,
    );
  }
}

class PaymentDetailItem {
  final double amount;
  PaymentDetailItem({required this.amount});

  factory PaymentDetailItem.fromJson(Map<String, dynamic> json) {
    return PaymentDetailItem(
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

class IPDRegistration {
  final int ipdId;
  final DateTime? dischargeDate;
  final String uhid;
  final int? bedId;
  final String? dischargeType;
  final String? billNo;
  final List<dynamic>? paymentDetailRaw;
  final DateTime? createdAt;
  // Added fields to hold the joined data
  final PatientDetail? patientDetail;
  final BedManagement? bedManagement;

  IPDRegistration({
    required this.ipdId,
    this.dischargeDate,
    required this.uhid,
    this.bedId,
    this.dischargeType,
    this.billNo,
    this.paymentDetailRaw,
    this.createdAt,
    // Added to constructor
    this.patientDetail,
    this.bedManagement,
  });

  factory IPDRegistration.fromJson(Map<String, dynamic> json) {
    return IPDRegistration(
      ipdId: json['ipd_id'] as int,
      dischargeDate: json['discharge_date'] != null
          ? DateTime.parse(json['discharge_date'] as String)
          : null,
      uhid: json['uhid'] as String,
      bedId: json['bed_id'] as int?,
      dischargeType: json['discharge_type'] as String?,
      billNo: json['billno'] as String?,
      paymentDetailRaw: json['payment_detail'] as List<dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      // Parse the nested objects from the JOIN query
      patientDetail: json['patient_detail'] != null
          ? PatientDetail.fromJson(json['patient_detail'] as Map<String, dynamic>)
          : null,
      bedManagement: json['bed_management'] != null
          ? BedManagement.fromJson(json['bed_management'] as Map<String, dynamic>)
          : null,
    );
  }
}

enum PatientStatus {
  active,
  discharged,
  dischargedPartially,
  death,
}

class BillingRecord {
  final int ipdId;
  final String uhid;
  final String name;
  final String mobileNumber;
  final double depositAmount;
  final String roomType;
  final String bedNumber;
  final PatientStatus status;
  final DateTime? dischargeDate;
  final String? dischargeType;
  final String? billNo;

  BillingRecord({
    required this.ipdId,
    required this.uhid,
    required this.name,
    required this.mobileNumber,
    required this.depositAmount,
    required this.roomType,
    required this.bedNumber,
    required this.status,
    this.dischargeDate,
    this.dischargeType,
    this.billNo,
  });
}

class IpdManagementPage extends StatefulWidget {
  const IpdManagementPage({super.key});

  @override
  State<IpdManagementPage> createState() => _IpdManagementPageState();
}

class _IpdManagementPageState extends State<IpdManagementPage> with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = SupabaseConfig.client;
  List<IPDRegistration> _allIpdRecordsRaw = [];
  String _searchTerm = "";
  String _selectedTab = "non-discharge";
  String _selectedWard = "All";
  bool _isLoading = true;
  bool _isRefreshing = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != _tabController.previousIndex) {
        setState(() {
          if (_tabController.index == 0) {
            _selectedTab = "non-discharge";
          } else if (_tabController.index == 1) {
            _selectedTab = "discharge-partially";
          } else {
            _selectedTab = "discharge";
          }
        });
      }
    });
    _fetchIPDRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchIPDRecords() async {
    setState(() {
      _isRefreshing = true;
      if (_allIpdRecordsRaw.isEmpty) {
        _isLoading = true;
      }
    });

    try {
      // Single, efficient query with JOINs
      final response = await supabase
          .from('ipd_registration')
          .select(
          '*, ' // Select all columns from ipd_registration
              'patient_detail!inner(*), ' // Join and select all from patient_detail
              'bed_management(*)' // Join and select all from bed_management
      )
          .order("created_at", ascending: false);

      // **FIX:** Explicitly cast the List<dynamic> to List<Map<String, dynamic>>
      final List<Map<String, dynamic>> ipdData = List.from(response);
      _allIpdRecordsRaw = ipdData.map((json) => IPDRegistration.fromJson(json)).toList();

    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Supabase Error fetching data: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load IPD records: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  String _formatRoomType(String roomType) {
    if (roomType.isEmpty) return "N/A";
    final upperCaseTypes = ["icu", "nicu"];
    final lowerType = roomType.toLowerCase();
    if (upperCaseTypes.contains(lowerType)) {
      return roomType.toUpperCase();
    }
    return roomType.substring(0, 1).toUpperCase() + roomType.substring(1).toLowerCase();
  }

  List<BillingRecord> get _processedRecords {
    return _allIpdRecordsRaw.map((record) {
      final patientDetail = record.patientDetail; // Get from nested object
      final bedManagement = record.bedManagement; // Get from nested object

      List<PaymentDetailItem> payments = [];
      if (record.paymentDetailRaw != null) {
        try {
          payments = (record.paymentDetailRaw!)
              .map((item) => PaymentDetailItem.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('Error parsing payment_detail for IPD ID ${record.ipdId}: $e');
        }
      }

      final totalDeposit = payments.fold<double>(
        0.0,
            (sum, payment) => sum + (payment.amount),
      );

      final dischargeType = record.dischargeType;
      PatientStatus status;
      if (record.dischargeDate != null) {
        status = dischargeType == "Death" ? PatientStatus.death : PatientStatus.discharged;
      } else if (dischargeType == "Discharge Partially") {
        status = PatientStatus.dischargedPartially;
      } else {
        status = PatientStatus.active;
      }

      return BillingRecord(
        ipdId: record.ipdId,
        uhid: record.uhid,
        name: patientDetail?.name ?? "Unknown",
        mobileNumber: patientDetail?.number ?? "N/A",
        depositAmount: totalDeposit,
        roomType: bedManagement?.roomType != null
            ? _formatRoomType(bedManagement!.roomType)
            : "N/A",
        bedNumber: bedManagement?.bedNumber ?? "N/A",
        status: status,
        dischargeDate: record.dischargeDate,
        dischargeType: dischargeType,
        billNo: record.billNo,
      );
    }).toList();
  }

  List<BillingRecord> get _nonDischargedRecords =>
      _processedRecords.where((record) => record.status == PatientStatus.active).toList();

  List<BillingRecord> get _partiallyDischargedRecords => _processedRecords
      .where((record) => record.status == PatientStatus.dischargedPartially)
      .toList();

  List<BillingRecord> get _fullyDischargedRecords => _processedRecords
      .where((record) =>
  record.status == PatientStatus.discharged ||
      record.status == PatientStatus.death)
      .toList();

  List<BillingRecord> get _filteredRecords {
    List<BillingRecord> currentRecords = [];
    if (_selectedTab == "non-discharge") {
      currentRecords = _nonDischargedRecords;
    } else if (_selectedTab == "discharge-partially") {
      currentRecords = _partiallyDischargedRecords;
    } else {
      currentRecords = _fullyDischargedRecords;
    }

    final term = _searchTerm.trim().toLowerCase();
    List<BillingRecord> records = [...currentRecords];

    if (_selectedWard != "All") {
      records = records.where((rec) => rec.roomType.toLowerCase() == _selectedWard.toLowerCase()).toList();
    }

    if (term.isNotEmpty) {
      records = records.where(
            (rec) =>
        rec.ipdId.toString().toLowerCase().contains(term) ||
            rec.name.toLowerCase().contains(term) ||
            (rec.mobileNumber.toLowerCase().contains(term)) ||
            rec.uhid.toLowerCase().contains(term),
      ).toList();
    }
    return records;
  }

  List<String> get _uniqueWards {
    final wards = <String>{};
    for (final record in _allIpdRecordsRaw) {
      if (record.bedManagement != null && record.bedManagement!.roomType.isNotEmpty) {
        wards.add(_formatRoomType(record.bedManagement!.roomType));
      }
    }
    return wards.toList()..sort();
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return format.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF3B82F6)),
              SizedBox(height: 16),
              Text(
                "Loading IPD records...",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "IPD Management",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "IPD Billing Management",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Manage and track in-patient billing records and admissions",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: _tabController.index == 0
                                ? const Color(0xFF3B82F6)
                                : _tabController.index == 1
                                ? Colors.orange[600]
                                : Colors.green[600],
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.grey[700],
                          isScrollable: true,
                          tabs: [
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cancel_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Non-Discharged (${_nonDischargedRecords.length})'),
                                ],
                              ),
                            ),
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.content_paste_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Partially Discharged (${_partiallyDischargedRecords.length})'),
                                ],
                              ),
                            ),
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_outline, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Discharged (${_fullyDischargedRecords.length})'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: "Search by name, ID, mobile, or UHID",
                                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchTerm = value;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: _isRefreshing
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3B82F6),
                              ),
                            )
                                : const Icon(Icons.refresh),
                            onPressed: _isRefreshing ? null : _fetchIPDRecords,
                            tooltip: 'Refresh',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[100],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Filter by Room Type",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          ChoiceChip(
                            label: const Text('All Rooms'),
                            selected: _selectedWard == "All",
                            onSelected: (selected) {
                              setState(() {
                                _selectedWard = "All";
                              });
                            },
                            selectedColor: const Color(0xFF3B82F6),
                            labelStyle: TextStyle(
                              color: _selectedWard == "All" ? Colors.white : Colors.grey[700],
                            ),
                            backgroundColor: Colors.grey[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: _selectedWard == "All" ? Colors.transparent : Colors.grey[300]!,
                              ),
                            ),
                          ),
                          ..._uniqueWards.map(
                                (ward) => ChoiceChip(
                              label: Text(ward),
                              selected: _selectedWard == ward,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedWard = ward;
                                });
                              },
                              selectedColor: const Color(0xFF3B82F6),
                              labelStyle: TextStyle(
                                color: _selectedWard == ward ? Colors.white : Colors.grey[700],
                              ),
                              backgroundColor: Colors.grey[100],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: _selectedWard == ward ? Colors.transparent : Colors.grey[300]!,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildPatientsTable(_filteredRecords),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientsTable(List<BillingRecord> records) {
    if (records.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_off_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text(
                "No patients found",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                "Try adjusting your filters or search criteria.",
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            dataRowMinHeight: 60,
            dataRowMaxHeight: 80,
            headingRowColor: MaterialStateProperty.resolveWith<Color?>(
                  (Set<MaterialState> states) => Colors.grey[50],
            ),
            columns: const [
              DataColumn(label: Text('S.No.', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Patient Name', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Mobile Number', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Deposit (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Room Type', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List<DataRow>.generate(
              records.length,
                  (index) {
                final record = records[index];
                final displayId = record.ipdId.toString();

                return DataRow(
                  cells: [
                    DataCell(Text((index + 1).toString())),
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(record.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('IPD ID: $displayId', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          Text('UHID: ${record.uhid}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    DataCell(Text(record.mobileNumber)),
                    DataCell(Text(_formatCurrency(record.depositAmount),
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(
                      Chip(
                        label: Text(record.roomType),
                        backgroundColor: const Color(0xFFE0F2FE),
                        labelStyle: const TextStyle(color: Color(0xFF2563EB)),
                        side: BorderSide(color: Colors.blue.shade100),
                      ),
                    ),
                  ],
                  onSelectChanged: (isSelected) {
                    if (isSelected != null && isSelected) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ManageIpdPatientPage(
                            ipdId: record.ipdId,
                            uhid: record.uhid,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}