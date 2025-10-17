import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
// Assuming you have these files:
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

  // --- State for Discharged Search ---
  final TextEditingController _dischargeNameController = TextEditingController();
  final TextEditingController _dischargeNumberController = TextEditingController();
  List<BillingRecord> _dischargedSearchResults = [];
  bool _isSearchingDischarged = false;
  // ----------------------------------------

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
            // Clear previous search results and controllers when switching to Discharged tab
            _dischargedSearchResults = [];
            _dischargeNameController.clear();
            _dischargeNumberController.clear();
          }
          // Reset search term for non-discharged tabs
          if (_selectedTab != "discharge") {
            _searchTerm = "";
          }
        });
      }
    });
    // Only fetch non-discharged records initially
    _fetchIPDRecords(initialLoad: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dischargeNameController.dispose();
    _dischargeNumberController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      // **TODO: Implement actual Supabase sign-out logic**
      // await supabase.auth.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out successfully! (Placeholder)'),
            backgroundColor: Color(0xFF3B82F6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchIPDRecords({bool initialLoad = false}) async {
    setState(() {
      _isRefreshing = true;
      if (initialLoad) {
        _isLoading = true;
      }
    });

    try {
      // Fetch ONLY active and partially discharged records for in-memory filtering.
      final response = await supabase
          .from('ipd_registration')
          .select(
          '*, '
              'patient_detail!inner(*), '
              'bed_management(*)'
      )
          .or('discharge_date.is.null,discharge_type.eq.Discharge Partially')
          .order("created_at", ascending: false);

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

  // --- Function to search Discharged Records (FIXED) ---
  Future<void> _fetchDischargedRecordsBySearch() async {
    final nameSearch = _dischargeNameController.text.trim();
    final numberSearch = _dischargeNumberController.text.trim();

    if (nameSearch.isEmpty && numberSearch.isEmpty) {
      setState(() {
        _dischargedSearchResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name or mobile number to search.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSearchingDischarged = true;
      _dischargedSearchResults = []; // Clear previous results immediately
    });

    try {
      // 1. Start query chain and select columns
      var query = supabase
          .from('ipd_registration')
          .select(
          '*, '
              'patient_detail!inner(*), '
              'bed_management(*)'
      );

      // 2. Apply the main filter (must be discharged)
      query = query.not('discharge_date', 'is', null);

      // 3. Apply search filters
      if (nameSearch.isNotEmpty) {
        query = query.like('patient_detail.name', '%$nameSearch%');
      }

      if (numberSearch.isNotEmpty) {
        // DEFINITIVE FIX: Use .filter() with ILIKE and PostgreSQL casting
        // to resolve the "bigint ~~ unknown" error.
        query = query.filter('patient_detail.number::text', 'ilike', '%$numberSearch%');
      }

      // 4. Apply ordering and limit *last*
      final response = await query
          .order("discharge_date", ascending: false)
          .limit(50);

      final List<Map<String, dynamic>> ipdData = List.from(response);
      final rawRecords = ipdData.map((json) => IPDRegistration.fromJson(json)).toList();

      // Convert raw records to BillingRecord format for display
      _dischargedSearchResults = _processRawRecords(rawRecords);

    } on PostgrestException catch (e) {
      if (mounted) {
        // Show the Supabase error for debugging
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Supabase Error searching data: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to search discharged records: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
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
  // ----------------------------------------

  String _formatRoomType(String roomType) {
    if (roomType.isEmpty) return "N/A";
    final upperCaseTypes = ["icu", "nicu"];
    final lowerType = roomType.toLowerCase();
    if (upperCaseTypes.contains(lowerType)) {
      return roomType.toUpperCase();
    }
    return roomType.substring(0, 1).toUpperCase() + roomType.substring(1).toLowerCase();
  }

  // Helper function to process raw IPDRegistration list into BillingRecord list
  List<BillingRecord> _processRawRecords(List<IPDRegistration> rawRecords) {
    return rawRecords.map((record) {
      final patientDetail = record.patientDetail;
      final bedManagement = record.bedManagement;

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
      _processRawRecords(_allIpdRecordsRaw).where((record) => record.status == PatientStatus.active).toList();

  List<BillingRecord> get _partiallyDischargedRecords => _processRawRecords(_allIpdRecordsRaw)
      .where((record) => record.status == PatientStatus.dischargedPartially)
      .toList();

  List<BillingRecord> get _activeFilteredRecords {
    List<BillingRecord> currentRecords = [];
    if (_selectedTab == "non-discharge") {
      currentRecords = _nonDischargedRecords;
    } else { // "discharge-partially"
      currentRecords = _partiallyDischargedRecords;
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
    // Only get wards from currently loaded active/partial records
    for (final record in _allIpdRecordsRaw) {
      if (record.bedManagement != null && record.bedManagement!.roomType.isNotEmpty) {
        wards.add(_formatRoomType(record.bedManagement!.roomType));
      }
    }
    return wards.toList()..sort();
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
                "Loading active IPD records...",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final isDischargedTab = _selectedTab == "discharge";
    final currentRecords = isDischargedTab ? _dischargedSearchResults : _activeFilteredRecords;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFEF4444)),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[200],
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
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
                                      Text('Active (${_nonDischargedRecords.length})'),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.content_paste_outlined, size: 18),
                                      const SizedBox(width: 8),
                                      Text('Partial Discharge (${_partiallyDischargedRecords.length})'),
                                    ],
                                  ),
                                ),
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 18),
                                      const SizedBox(width: 8),
                                      const Text('Closed (Search Only)'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- Search/Filter UI based on Selected Tab ---
                          if (isDischargedTab) ...[
                            _buildDischargedSearch(),
                          ] else ...[
                            _buildActiveSearch(),
                          ],

                          const SizedBox(height: 16),
                          const Text(
                            "Filter by Ward/Room Type",
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
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isDischargedTab
                        ? "${currentRecords.length} Search Results"
                        : "${currentRecords.length} Records Found",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _buildPatientsList(currentRecords, isDischargedTab),
        ],
      ),
    );
  }

  Widget _buildActiveSearch() {
    return Row(
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
          tooltip: 'Refresh Active Records',
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey[100],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildDischargedSearch() {
    return Column(
      children: [
        // Search by Name
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _dischargeNameController,
                decoration: InputDecoration(
                  hintText: "Search by Patient Name",
                  prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSearchingDischarged ? null : _fetchDischargedRecordsBySearch,
              icon: _isSearchingDischarged
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 20),
              label: const Text('Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search by Number
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _dischargeNumberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "Search by Mobile Number",
                  prefixIcon: const Icon(Icons.phone_android, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSearchingDischarged ? null : _fetchDischargedRecordsBySearch,
              icon: _isSearchingDischarged
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 20),
              label: const Text('Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildPatientsList(List<BillingRecord> records, bool isDischargedTab) {
    if (isDischargedTab && records.isEmpty && !_isSearchingDischarged) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    "Search Discharged Records",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Please use the search fields above to find closed patient records.",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (records.isEmpty && _isSearchingDischarged) {
      // Show loading indicator if search is active
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
            ),
          ),
        ),
      );
    }

    if (records.isEmpty) {
      // Show no results found if search finished with 0 results or if active tabs are empty
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Card(
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
                    isDischargedTab
                        ? "No records matched your search criteria."
                        : "Try adjusting your filters or search criteria.",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // The list uses SliverList inside SliverPadding, which automatically takes the full available width (responsive for tablet).
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (context, index) {
            final record = records[index];
            return Padding(
              padding: EdgeInsets.only(bottom: index == records.length - 1 ? 16.0 : 8.0),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
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
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Patient/Admission Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Patient Name
                              Text(
                                record.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              // IPD ID & UHID
                              Text(
                                'IPD ID: ${record.ipdId} | UHID: ${record.uhid}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Mobile Number (Optional)
                              if (record.mobileNumber != 'N/A')
                                Row(
                                  children: [
                                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      record.mobileNumber,
                                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              // Discharge Date/Bill No for discharged tab
                              if (isDischargedTab && record.dischargeDate != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Discharged: ${DateFormat('dd MMM yyyy').format(record.dischargeDate!)}'
                                        '${record.billNo != null ? ' (Bill: ${record.billNo})' : ''}',
                                    style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Right side: Room and Action
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Room/Bed Info Chip
                            Chip(
                              label: Text('${record.roomType} - ${record.bedNumber}'),
                              backgroundColor: const Color(0xFFE0F2FE),
                              labelStyle: const TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              side: BorderSide(color: Colors.blue.shade100),
                            ),
                            const SizedBox(height: 12),
                            // Action Indicator
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: records.length,
        ),
      ),
    );
  }
}