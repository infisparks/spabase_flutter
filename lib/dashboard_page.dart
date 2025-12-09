import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// Assuming you have these files:
import 'supabase_config.dart'; // Your Supabase configuration
import 'manage_ipd_patient_page.dart'; // Import the next page

// ==========================================
//               MODELS
// ==========================================

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
      number: json['number']?.toString(), // Ensure safe string conversion
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
  final String? underCareOfDoctor; // <--- ADDED FIELD
  final List<dynamic>? paymentDetailRaw;
  final DateTime? createdAt;

  // Joins
  final PatientDetail? patientDetail;
  final BedManagement? bedManagement;

  IPDRegistration({
    required this.ipdId,
    this.dischargeDate,
    required this.uhid,
    this.bedId,
    this.dischargeType,
    this.billNo,
    this.underCareOfDoctor,
    this.paymentDetailRaw,
    this.createdAt,
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
      // Map the doctor field from SQL
      underCareOfDoctor: json['under_care_of_doctor'] as String?,
      paymentDetailRaw: json['payment_detail'] as List<dynamic>?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,

      // Parse Nested Objects
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

// View Model for UI
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
  final String doctorName; // <--- ADDED FIELD

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
    required this.doctorName,
  });
}

// ==========================================
//               MAIN PAGE
// ==========================================

class IpdManagementPage extends StatefulWidget {
  const IpdManagementPage({super.key});

  @override
  State<IpdManagementPage> createState() => _IpdManagementPageState();
}

class _IpdManagementPageState extends State<IpdManagementPage> with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = SupabaseConfig.client;

  // Data State
  List<IPDRegistration> _allIpdRecordsRaw = [];
  List<BillingRecord> _dischargedSearchResults = [];

  // Filter State
  String _searchTerm = "";
  String _selectedTab = "non-discharge";
  String _selectedWard = "All";

  // UI State
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSearchingDischarged = false;

  // Controllers
  final TextEditingController _dischargeSearchController = TextEditingController();
  late TabController _tabController;

  // Colors Palette (Modern Medical Blue/Slate)
  final Color kPrimaryColor = const Color(0xFF0F172A); // Slate 900
  final Color kAccentColor = const Color(0xFF3B82F6); // Blue 500
  final Color kBackgroundColor = const Color(0xFFF1F5F9); // Slate 100
  final Color kCardColor = Colors.white;

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
            _dischargedSearchResults = [];
            _dischargeSearchController.clear();
          }
          // Reset local search when switching tabs
          if (_selectedTab != "discharge") {
            _searchTerm = "";
          }
        });
      }
    });
    // Initial Fetch
    _fetchIPDRecords(initialLoad: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dischargeSearchController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    // Implement your logout logic here
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logged out'), backgroundColor: kAccentColor),
      );
    }
  }

  // --- Fetch Active Records ---
  Future<void> _fetchIPDRecords({bool initialLoad = false}) async {
    setState(() {
      _isRefreshing = true;
      if (initialLoad) _isLoading = true;
    });

    try {
      final response = await supabase
          .from('ipd_registration')
          .select('*, patient_detail!inner(*), bed_management(*)')
          .or('discharge_date.is.null,discharge_type.eq.Discharge Partially')
          .order("created_at", ascending: false);

      final List<Map<String, dynamic>> ipdData = List.from(response);
      _allIpdRecordsRaw = ipdData.map((json) => IPDRegistration.fromJson(json)).toList();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
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

  // --- Search Discharged Records (FIXED) ---
  Future<void> _fetchDischargedRecordsBySearch() async {
    final searchInput = _dischargeSearchController.text.trim();

    if (searchInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Name, Mobile or UHID'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSearchingDischarged = true;
      _dischargedSearchResults = [];
    });

    try {
      // 1. Basic Query setup
      var query = supabase
          .from('ipd_registration')
          .select('*, patient_detail!inner(*), bed_management(*)')
          .not('discharge_date', 'is', null);

      // 2. Logic to handle Number vs Text search to avoid SQL Cast errors
      final isNumeric = double.tryParse(searchInput) != null;

      if (isNumeric) {
        // If numeric, exact match on the phone number (assuming column is bigint/numeric)
        // Note: We access the joined table column
        query = query.eq('patient_detail.number', searchInput);
      } else {
        // If text, Perform ILIKE on Name or UHID
        // We use !inner on join so we can filter by child columns
        query = query.or('name.ilike.%$searchInput%,uhid.ilike.%$searchInput%', referencedTable: 'patient_detail');
      }

      // 3. Execution
      final response = await query.order("discharge_date", ascending: false).limit(50);

      final List<Map<String, dynamic>> ipdData = List.from(response);
      final rawRecords = ipdData.map((json) => IPDRegistration.fromJson(json)).toList();

      _dischargedSearchResults = _processRawRecords(rawRecords);

    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed. Try searching by exact mobile number or name.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingDischarged = false;
        });
      }
    }
  }

  // --- Helpers ---

  String _formatRoomType(String roomType) {
    if (roomType.isEmpty) return "N/A";
    final upperCaseTypes = ["icu", "nicu"];
    if (upperCaseTypes.contains(roomType.toLowerCase())) return roomType.toUpperCase();
    return roomType.substring(0, 1).toUpperCase() + roomType.substring(1).toLowerCase();
  }

  List<BillingRecord> _processRawRecords(List<IPDRegistration> rawRecords) {
    return rawRecords.map((record) {
      final patient = record.patientDetail;
      final bed = record.bedManagement;

      // Calculate Payments
      double totalDeposit = 0.0;
      if (record.paymentDetailRaw != null) {
        try {
          final payments = (record.paymentDetailRaw!)
              .map((item) => PaymentDetailItem.fromJson(item as Map<String, dynamic>))
              .toList();
          totalDeposit = payments.fold(0.0, (sum, item) => sum + item.amount);
        } catch (_) {}
      }

      // Determine Status
      final dType = record.dischargeType;
      PatientStatus st;
      if (record.dischargeDate != null) {
        st = dType == "Death" ? PatientStatus.death : PatientStatus.discharged;
      } else if (dType == "Discharge Partially") {
        st = PatientStatus.dischargedPartially;
      } else {
        st = PatientStatus.active;
      }

      return BillingRecord(
        ipdId: record.ipdId,
        uhid: record.uhid,
        name: patient?.name ?? "Unknown",
        mobileNumber: patient?.number ?? "N/A",
        depositAmount: totalDeposit,
        roomType: bed?.roomType != null ? _formatRoomType(bed!.roomType) : "N/A",
        bedNumber: bed?.bedNumber ?? "N/A",
        status: st,
        dischargeDate: record.dischargeDate,
        dischargeType: dType,
        billNo: record.billNo,
        doctorName: record.underCareOfDoctor ?? "Not Assigned", // <--- MAPPED HERE
      );
    }).toList();
  }

  // --- Getters for Filters ---

  List<BillingRecord> get _activeFilteredRecords {
    List<BillingRecord> source = _selectedTab == "non-discharge"
        ? _processRawRecords(_allIpdRecordsRaw).where((r) => r.status == PatientStatus.active).toList()
        : _processRawRecords(_allIpdRecordsRaw).where((r) => r.status == PatientStatus.dischargedPartially).toList();

    final term = _searchTerm.trim().toLowerCase();

    // 1. Filter by Ward
    if (_selectedWard != "All") {
      source = source.where((r) => r.roomType.toLowerCase() == _selectedWard.toLowerCase()).toList();
    }

    // 2. Filter by Search Term (Local)
    if (term.isNotEmpty) {
      source = source.where((r) =>
      r.name.toLowerCase().contains(term) ||
          r.mobileNumber.contains(term) ||
          r.uhid.toLowerCase().contains(term) ||
          r.ipdId.toString().contains(term)
      ).toList();
    }
    return source;
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

  // ==========================================
  //               UI BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final isDischargedTab = _selectedTab == "discharge";
    final currentRecords = isDischargedTab ? _dischargedSearchResults : _activeFilteredRecords;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: kAccentColor))
          : CustomScrollView(
        slivers: [
          _buildAppBar(),
          _buildFiltersHeader(isDischargedTab),
          _buildRecordsList(currentRecords, isDischargedTab),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 80.0,
      floating: true,
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      leading: const Icon(Icons.local_hospital_rounded, color: Color(0xFF0F172A), size: 28),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "IPD Management",
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 20),
          ),
          Text(
            "Admission & Billing Overview",
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.power_settings_new_rounded),
          color: Colors.redAccent,
          tooltip: "Logout",
        )
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: Colors.grey[200], height: 1),
      ),
    );
  }

  Widget _buildFiltersHeader(bool isDischargedTab) {
    return SliverToBoxAdapter(
      child: Container(
        color: kBackgroundColor,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Custom Tab Bar ---
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.all(4),
                tabs: [
                  const Tab(text: "Active"),
                  const Tab(text: "Partial"),
                  const Tab(text: "History"),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- Search Area ---
            if (isDischargedTab)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dischargeSearchController,
                      decoration: InputDecoration(
                        hintText: "Search Name, Mobile, or UHID...",
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _fetchDischargedRecordsBySearch(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isSearchingDischarged ? null : _fetchDischargedRecordsBySearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: _isSearchingDischarged
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Find"),
                  ),
                ],
              )
            else
              TextField(
                onChanged: (val) => setState(() { _searchTerm = val; }),
                decoration: InputDecoration(
                  hintText: "Filter active patients...",
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.filter_list, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.refresh, color: kAccentColor),
                    onPressed: _fetchIPDRecords,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),

            // --- Ward Filters (Only for Active/Partial) ---
            if (!isDischargedTab && _uniqueWards.isNotEmpty) ...[
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip("All", _selectedWard == "All"),
                    ..._uniqueWards.map((w) => _buildFilterChip(w, _selectedWard == w)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            // Result Count
            if(!isDischargedTab || (isDischargedTab && _dischargedSearchResults.isNotEmpty))
              Text(
                "Showing ${isDischargedTab ? _dischargedSearchResults.length : _activeFilteredRecords.length} records",
                style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => setState(() => _selectedWard = label),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? kAccentColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? kAccentColor : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordsList(List<BillingRecord> records, bool isDischargedTab) {
    if (records.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  isDischargedTab ? Icons.person_search_outlined : Icons.bed_outlined,
                  size: 60, color: Colors.grey[300]
              ),
              const SizedBox(height: 16),
              Text(
                isDischargedTab ? "Search for closed files" : "No active patients found",
                style: TextStyle(color: Colors.grey[500], fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (context, index) {
            final record = records[index];
            return _buildPatientCard(record);
          },
          childCount: records.length,
        ),
      ),
    );
  }

  Widget _buildPatientCard(BillingRecord record) {
    final bool isDischarged = record.status == PatientStatus.discharged || record.status == PatientStatus.death;
    final color = isDischarged ? Colors.grey : (record.status == PatientStatus.dischargedPartially ? Colors.orange : kAccentColor);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ManageIpdPatientPage(
                ipdId: record.ipdId,
                uhid: record.uhid,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Bed & Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bed, size: 14, color: color),
                        const SizedBox(width: 6),
                        Text(
                          "${record.roomType} - ${record.bedNumber}",
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (isDischarged)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)
                      ),
                      child: Text(
                        record.status == PatientStatus.death ? "EXPIRED" : "DISCHARGED",
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Body: Avatar + Details
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[100],
                    child: Text(
                      record.name.isNotEmpty ? record.name[0].toUpperCase() : "?",
                      style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.name,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kPrimaryColor),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "UHID: ${record.uhid}",
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        if (record.mobileNumber != 'N/A')
                          Text(
                            "Mob: ${record.mobileNumber}",
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Footer: Doctor & Date
              Row(
                children: [
                  Icon(Icons.medical_services_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Dr. ${record.doctorName}", // <--- SHOWING DOCTOR NAME
                      style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDischarged && record.dischargeDate != null)
                    Text(
                      DateFormat('dd MMM yy').format(record.dischargeDate!),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}