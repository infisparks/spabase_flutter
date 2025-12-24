// File: investigation_sheet_page.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';

// --- Configuration (WARNING: Use secure method in production) ---
// Note: Flutter doesn't have a direct equivalent to NEXT_PUBLIC_ENV.
// For this example, we hardcode the URL and API key.
const String LAB_API_URL = "https://labapi.infispark.in";
const String LAB_API_KEY =
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc1NDMyMjQ4MCwiZXhwIjo0OTA5OTk2MDgwLCJyb2xlIjoiYW5vbiJ9.6cRfh-LkLXv7STWB-nfKM3EbOxm9A9GVGwPus9vtMf4";

// --- Colors ---
const Color primaryBlue = Color(0xFF3B82F6);
const Color darkText = Color(0xFF1E293B);
const Color mediumGreyText = Color(0xFF64748B);
const Color lightBackground = Color(0xFFF8FAFC);
const Color greenIndicator = Color(0xFF10B981);
const Color redIndicator = Color(0xFFEF4444);
const Color yellowIndicator = Color(0xFFFBBF24);

// --- Type Definitions ---
class Subheading {
  final bool is100;
  final String title;
  final List<String> parameterNames;
  Subheading({required this.is100, required this.title, required this.parameterNames});
}

class Test {
  final dynamic testId;
  final String testName;
  final double price;
  final double? tpaPrice;
  Test({required this.testId, required this.testName, required this.price, this.tpaPrice});
}

class Parameter {
  final String name;
  final String? unit;
  final dynamic range; // String or Map<String, dynamic>
  final dynamic value; // String or double
  final String? valueType;
  final List<Parameter>? subparameters;
  Parameter({required this.name, this.unit, this.range, required this.value, this.valueType, this.subparameters});
}

class BloodTestData {
  final String reportedOn;
  final List<Parameter> parameters;
  final List<Subheading>? subheadings;
  BloodTestData({required this.reportedOn, required this.parameters, this.subheadings});
}

class PatientDetail {
  final String name;
  final int age;
  final String gender;
  final String? ageUnit;
  final int? totalDay;
  final String? uhid;
  PatientDetail({required this.name, required this.age, required this.gender, this.ageUnit, this.totalDay, this.uhid});
}

class Registration {
  final int id;
  final int registrationId;
  final String visitType;
  final String createdAt;
  final List<Test> bloodTests;
  final Map<String, BloodTestData> bloodtestDetail;
  final String name;
  final int age;
  final String gender;
  final String? dayType;
  final int? totalDay;
  final String? hospitalName;
  final String? uhid;
  final dynamic sourceIpdId;
  final String reportDate;

  Registration({
    required this.id, required this.registrationId, required this.visitType, required this.createdAt,
    required this.bloodTests, required this.bloodtestDetail, required this.name, required this.age,
    required this.gender, this.dayType, this.totalDay, this.hospitalName, this.uhid,
    this.sourceIpdId, required this.reportDate
  });

  factory Registration.fromJson(Map<String, dynamic> json) {
    return Registration(
      id: json['registration_id'],
      registrationId: json['registration_id'],
      visitType: json['visit_type'] ?? "",
      createdAt: json['registration_time'],
      bloodTests: (json['bloodtest_data'] as List? ?? []).map((t) =>
          Test(
            testId: t['testId'],
            testName: t['testName'] ?? "",
            price: (t['price'] as num?)?.toDouble() ?? 0.0,
            tpaPrice: (t['tpa_price'] as num?)?.toDouble(),
          )
      ).toList(),
      bloodtestDetail: (json['bloodtest_detail'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(
          k,
          BloodTestData(
            reportedOn: v['reportedOn'],
            parameters: (v['parameters'] as List? ?? []).map((p) => _parseParameter(p)).toList(),
            subheadings: (v['subheadings'] as List? ?? []).map((s) =>
                Subheading(
                    is100: s['is100'] ?? false,
                    title: s['title'] ?? "",
                    parameterNames: (s['parameterNames'] as List? ?? []).map((name) => name.toString()).toList()
                )
            ).toList(),
          )
      )),
      name: json['patient_name'] ?? "Unknown",
      age: json['patient_age'] ?? 0,
      gender: json['patient_gender'] ?? "N/A",
      dayType: json['patient_age_unit'],
      totalDay: json['patient_total_day'] ?? 0,
      uhid: json['patient_code'],
      sourceIpdId: json['ipd_id'],
      hospitalName: json['hospital_name'],
      reportDate: DateTime.now().toIso8601String(),
    );
  }

  static Parameter _parseParameter(Map<String, dynamic> json) {
    return Parameter(
      name: json['name'],
      unit: json['unit'],
      range: json['range'],
      value: json['value'],
      valueType: json['valueType'],
      subparameters: (json['subparameters'] as List? ?? []).map((p) => _parseParameter(p)).toList(),
    );
  }
}

class ComparisonColumnHeader {
  final String testKey;
  final String testDisplayName;
  final String reportedOn;
  final String dateKey;
  final int regId;
  ComparisonColumnHeader({required this.testKey, required this.testDisplayName, required this.reportedOn, required this.dateKey, required this.regId});
}

class ComparisonRowData {
  final String testName;
  final String testKey;
  final String parameterName;
  final String unit;
  final String range;
  final Map<String, String> values;
  final bool isOutOfRange;
  final bool isTextType;
  final int indent;
  final String? subheadingTitle;
  ComparisonRowData({
    required this.testName, required this.testKey, required this.parameterName, required this.unit,
    required this.range, required this.values, required this.isOutOfRange, required this.isTextType,
    required this.indent, this.subheadingTitle
  });
}

class TestTab {
  final String testKey;
  final String testName;
  final int reportCount;
  TestTab({required this.testKey, required this.testName, required this.reportCount});
}

// --- Constants ---
const int MAX_COMPARISON_COLUMNS = 30;

// --- Utility Functions ---

String formatTestKey(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[\s-]'), "_");
}

String getPatientRangeString(PatientDetail patient, Parameter param) {
  if (param.range is String) {
    return param.range;
  }
  if (param.range is! Map || param.range == null) {
    return "";
  }

  final rangeObj = param.range as Map<String, dynamic>;
  final parseRangeKey = (String key) {
    key = key.trim();
    final suf = key.substring(key.length - 1);
    int mul = 1;
    if (suf == "m") mul = 30;
    else if (suf == "y") mul = 365;
    final core = key.replaceAll(RegExp(r'[dmy]$'), "");
    final parts = core.split("-");
    final lower = (double.tryParse(parts[0]) ?? 0) * mul;
    final upper = (parts.length > 1 ? (double.tryParse(parts[1]) ?? double.infinity) : double.infinity) * mul;
    return {'lower': lower, 'upper': upper};
  };

  final genderKey = patient.gender.toLowerCase();
  final ageDays = patient.totalDay ?? (patient.age * 365);
  String rangeStr = "";

  final arr = rangeObj[genderKey] ?? rangeObj["any"] ?? [];

  for (final r in arr) {
    final rangeMap = parseRangeKey(r['rangeKey']);
    final lower = rangeMap['lower'] ?? 0;
    final upper = rangeMap['upper'] ?? double.infinity;
    if (ageDays >= lower && ageDays <= upper) {
      rangeStr = r['rangeValue'];
      break;
    }
  }
  if (rangeStr.isEmpty && arr.isNotEmpty) rangeStr = arr.last['rangeValue'];

  return rangeStr;
}

Map<String, double>? parseNumericRangeString(String str) {
  if (str.isEmpty) return null;
  final upMatch = RegExp(r'^\s*up\s*(?:to\s*)?([\d.]+)\s*$', caseSensitive: false).firstMatch(str);
  if (upMatch != null) {
    final upper = double.tryParse(upMatch.group(1)!);
    return upper == null ? null : {'lower': 0, 'upper': upper};
  }
  final rangeMatch = RegExp(r'^\s*([\d.]+)\s*(?:-|to)\s*([\d.]+)\s*$').firstMatch(str);
  if (rangeMatch != null) {
    final lower = double.tryParse(rangeMatch.group(1)!);
    final upper = double.tryParse(rangeMatch.group(2)!);
    return (lower == null || upper == null) ? null : {'lower': lower, 'upper': upper};
  }
  return null;
}

List<ComparisonRowData> extractParameters(
    String testDisplayName,
    String testKey,
    BloodTestData bloodTestData,
    PatientDetail patientDetails,
    String dateKey,
    ) {
  if (bloodTestData.parameters.isEmpty) return [];

  final List<ComparisonRowData> rows = [];

  void processParameter(Parameter param, int indent) {
    final rangeStr = getPatientRangeString(patientDetails, param);
    final numRange = parseNumericRangeString(rangeStr);
    final rawValue = (param.value ?? "").toString().trim();
    final numVal = double.tryParse(rawValue);

    String valueWithIndicator = rawValue;
    bool isOutOfRange = false;
    bool isTextType = param.valueType == "text" || numVal == null;

    if (!isTextType && numRange != null && numVal != null) {
      if (numVal < numRange['lower']!) {
        isOutOfRange = true;
        valueWithIndicator = "$rawValue L";
      } else if (numVal > numRange['upper']!) {
        isOutOfRange = true;
        valueWithIndicator = "$rawValue H";
      }
    }

    final Map<String, String> values = {dateKey: valueWithIndicator.isNotEmpty ? valueWithIndicator : "-"};

    rows.add(ComparisonRowData(
      testName: testDisplayName,
      testKey: testKey,
      parameterName: param.name,
      unit: param.unit ?? "",
      range: rangeStr,
      values: values,
      isOutOfRange: isOutOfRange,
      isTextType: isTextType,
      indent: indent,
    ));

    if (param.subparameters != null) {
      param.subparameters!.forEach((subParam) => processParameter(subParam, indent + 2));
    }
  }

  bloodTestData.parameters.forEach((param) => processParameter(param, 0));
  return rows;
}

bool isTestValueAdded(Registration registration, Test test) {
  if (registration.bloodtestDetail.isEmpty) return false;
  final testKey = formatTestKey(test.testName);
  return registration.bloodtestDetail.containsKey(testKey) && registration.bloodtestDetail[testKey]!.parameters.isNotEmpty;
}

String formatRegistrationDate(String isoDateString, {bool includeTime = true}) {
  final d = DateTime.tryParse(isoDateString)?.toLocal();
  if (d == null) return "Invalid Date";
  String format = 'dd/MM/yyyy';
  if (includeTime) format += ' hh:mm a';
  return DateFormat(format).format(d);
}

// --- Main Component ---
class InvestigationSheetPage extends StatefulWidget {
  final String ipdId;

  const InvestigationSheetPage({super.key, required this.ipdId});

  @override
  State<InvestigationSheetPage> createState() => _InvestigationSheetPageState();
}

class _InvestigationSheetPageState extends State<InvestigationSheetPage> {
  List<Registration> _registrations = [];
  bool _isLoading = true;
  String? _error;
  bool _showComparisonModal = false;
  String _activeTab = "";

  late PatientDetail? _patientDetails;
  late List<TestTab> _availableTabs;
  late List<ComparisonColumnHeader> _allUniqueDateColumns;

  get lightBlue => null;

  @override
  void initState() {
    super.initState();
    _fetchRegistrationsByIpdId(widget.ipdId);
  }

  void _updateDerivedData() {
    if (_registrations.isEmpty) {
      _patientDetails = null;
      _availableTabs = [];
      _allUniqueDateColumns = [];
      return;
    }

    final reg = _registrations.first;
    _patientDetails = PatientDetail(
      name: reg.name, age: reg.age, gender: reg.gender,
      ageUnit: reg.dayType, totalDay: reg.totalDay, uhid: reg.uhid,
    );

    final testMap = <String, TestTab>{};
    final dateColumns = <ComparisonColumnHeader>[];

    for (final reg in _registrations) {
      if (reg.bloodtestDetail.isNotEmpty) {
        reg.bloodtestDetail.forEach((testKey, testData) {
          if (testData.reportedOn.isNotEmpty) {
            final testDisplayName = reg.bloodTests.firstWhere(
                    (t) => formatTestKey(t.testName) == testKey,
                orElse: () => Test(testId: null, testName: testKey.replaceAll("_", " ").toUpperCase(), price: 0)
            ).testName;

            if (!testMap.containsKey(testKey)) {
              testMap[testKey] = TestTab(testKey: testKey, testName: testDisplayName, reportCount: 0);
            }
            testMap[testKey] = TestTab(
                testKey: testKey,
                testName: testDisplayName,
                reportCount: testMap[testKey]!.reportCount + 1
            );

            final dateKey = "$testKey@${testData.reportedOn}@${reg.id}";
            dateColumns.add(ComparisonColumnHeader(
              testKey: testKey,
              testDisplayName: testDisplayName,
              reportedOn: testData.reportedOn,
              dateKey: dateKey,
              regId: reg.id,
            ));
          }
        });
      }
    }

    dateColumns.sort((a, b) => b.reportedOn.compareTo(a.reportedOn));

    _availableTabs = testMap.values.toList()..sort((a, b) => a.testName.compareTo(b.testName));
    _allUniqueDateColumns = dateColumns;

    if (_availableTabs.isNotEmpty && _activeTab.isEmpty) {
      _activeTab = _availableTabs.first.testKey;
    }
  }

  Future<void> _fetchRegistrationsByIpdId(String id) async {
    if (id.isEmpty) {
      setState(() { _error = "No IPD ID provided."; _isLoading = false; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse("$LAB_API_URL/rest/v1/rpc/get_registrations_by_ipd"),
        headers: {
          "apikey": LAB_API_KEY,
          "Content-Type": "application/json",
        },
        body: jsonEncode({"p_ipd_id": id}),
      );

      if (response.statusCode != 200) {
        throw Exception("API error ${response.statusCode}: ${response.body}");
      }

      final data = jsonDecode(response.body) as List<dynamic>;

      if (data.isEmpty) {
        setState(() {
          _error = "No registrations found associated with IPD ID: $id.";
          _registrations = [];
        });
        return;
      }

      final mappedData = data.map((regRow) => Registration.fromJson(regRow as Map<String, dynamic>)).toList();

      setState(() {
        _registrations = mappedData;
        _updateDerivedData();
      });

    } catch (e) {
      print("Error fetching registrations: $e");
      setState(() { _error = "Failed to load registrations: ${e.toString()}"; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Map<String, dynamic> _getSingleTestComparisonData() {
    if (_patientDetails == null || _activeTab.isEmpty) {
      return {'selectedColumns': [], 'tableRows': []};
    }

    final selectedColumns = _allUniqueDateColumns
        .where((col) => col.testKey == _activeTab)
        .take(MAX_COMPARISON_COLUMNS)
        .toList();

    if (selectedColumns.isEmpty) {
      return {'selectedColumns': [], 'tableRows': []};
    }

    final groupedData = <String, ComparisonRowData>{};

    for (final reg in _registrations) {
      final testData = reg.bloodtestDetail[_activeTab];
      if (testData == null || testData.reportedOn.isEmpty) continue;

      final dateKey = "${_activeTab}@${testData.reportedOn}@${reg.id}";
      final columnHeader = selectedColumns.firstWhere(
              (col) => col.dateKey == dateKey,
          orElse: () => ComparisonColumnHeader(testKey: '', testDisplayName: '', reportedOn: '', dateKey: '', regId: 0)
      );

      if (columnHeader.dateKey.isEmpty) continue;

      final testDisplayName = reg.bloodTests.firstWhere(
              (t) => formatTestKey(t.testName) == _activeTab,
          orElse: () => Test(testId: null, testName: _activeTab.replaceAll("_", " ").toUpperCase(), price: 0)
      ).testName;

      final newRows = extractParameters(testDisplayName, _activeTab, testData, _patientDetails!, dateKey);

      for (final row in newRows) {
        final uniqueKey = row.parameterName;
        if (!groupedData.containsKey(uniqueKey)) {
          groupedData[uniqueKey] = row;
        } else {
          groupedData[uniqueKey]?.values[dateKey] = row.values[dateKey]!;
        }
      }
    }

    final finalTableData = <ComparisonRowData>[];
    final addedParameters = <String>{};

    final latestTestDetail = _registrations
        .map((reg) => reg.bloodtestDetail[_activeTab])
        .where((detail) => detail != null && detail.parameters.isNotEmpty)
        .toList().cast<BloodTestData>()
        .reduce((a, b) => DateTime.parse(a.reportedOn).isAfter(DateTime.parse(b.reportedOn)) ? a : b);

    final orderedParams = latestTestDetail.parameters;
    final subheadings = latestTestDetail.subheadings ?? [];

    void addParameterRow(Parameter param, int indent, {String? currentSubheadingTitle}) {
      final row = groupedData[param.name];
      if (row != null && !addedParameters.contains(param.name)) {
        final finalValues = <String, String>{};
        for (final col in selectedColumns) {
          finalValues[col.dateKey] = row.values[col.dateKey] ?? "-";
        }

        finalTableData.add(ComparisonRowData(
          testName: row.testName,
          testKey: row.testKey,
          parameterName: row.parameterName,
          unit: row.unit,
          range: row.range,
          values: finalValues,
          isOutOfRange: row.isOutOfRange,
          isTextType: row.isTextType,
          indent: indent,
          subheadingTitle: currentSubheadingTitle,
        ));
        addedParameters.add(param.name);
      }
      param.subparameters?.forEach((sp) => addParameterRow(sp, indent + 2, currentSubheadingTitle: currentSubheadingTitle));
    }

    // --- Subheading Logic (Simplified from React code for Flutter) ---
    final subheadedParamNames = <String>{};
    subheadings.forEach((sh) => subheadedParamNames.addAll(sh.parameterNames));

    // Add un-subheaded parameters first
    orderedParams.where((p) => !subheadedParamNames.contains(p.name)).forEach((p) => addParameterRow(p, 0));

    // Then add subheadings and their content
    subheadings.forEach((sh) {
      finalTableData.add(ComparisonRowData(
        testName: _activeTab.replaceAll("_", " ").toUpperCase(),
        testKey: _activeTab,
        parameterName: sh.title,
        unit: "SUBHEADING",
        range: "",
        values: const {},
        isOutOfRange: false,
        isTextType: true,
        indent: 0,
      ));

      sh.parameterNames.forEach((paramName) {
        final param = orderedParams.firstWhere((p) => p.name == paramName, orElse: () => Parameter(name: 'N/A', value: 'N/A'));
        if (param.name != 'N/A') {
          addParameterRow(param, 0, currentSubheadingTitle: sh.title);
        }
      });
    });

    return {
      'selectedColumns': selectedColumns,
      'tableRows': finalTableData,
    };
  }

  void _handleOpenComparison() {
    setState(() {
      _showComparisonModal = true;
    });
  }

  // --- UI Components ---
  Widget _buildLoading() {
    return Container(
      alignment: Alignment.center,
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: primaryBlue),
          const SizedBox(height: 20),
          const Text(
            "Loading Investigation Data...",
            style: TextStyle(fontSize: 18, color: darkText),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: redIndicator, size: 48),
            const SizedBox(height: 16),
            const Text(
              "No Lab Report Found",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkText),
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: mediumGreyText)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _fetchRegistrationsByIpdId(widget.ipdId),
              icon: const Icon(Icons.refresh),
              label: const Text("Try Again"),
              style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonModal(Map<String, dynamic> comparisonData) {
    final List<ComparisonColumnHeader> selectedColumns = comparisonData['selectedColumns'];
    final List<ComparisonRowData> tableRows = comparisonData['tableRows'];

    return Stack(
      children: [
        // Modal Background
        ModalBarrier(
          dismissible: true,
          color: Colors.black.withOpacity(0.75),
          onDismiss: () => setState(() => _showComparisonModal = false),
        ),
        // Modal Content
        Center(
          child: Container(
            width: min(1200, MediaQuery.of(context).size.width * 0.95),
            height: MediaQuery.of(context).size.height * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Modal Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.trending_up, color: primaryBlue, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "Test Comparison - ${_patientDetails?.name ?? 'N/A'}",
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkText),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: mediumGreyText),
                        onPressed: () => setState(() => _showComparisonModal = false),
                      ),
                    ],
                  ),
                ),

                // Tab Selector
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: _availableTabs.map((tab) {
                      final isSelected = tab.testKey == _activeTab;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ActionChip(
                          avatar: Text(tab.reportCount.toString(), style: TextStyle(color: isSelected ? Colors.white : primaryBlue)),
                          label: Text(tab.testName, style: TextStyle(color: isSelected ? Colors.white : primaryBlue, fontWeight: FontWeight.w600)),
                          onPressed: () => setState(() => _activeTab = tab.testKey),
                          backgroundColor: isSelected ? primaryBlue : primaryBlue.withOpacity(0.1),
                          side: BorderSide(color: isSelected ? primaryBlue : Colors.transparent),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const Divider(),

                // Comparison Table
                Expanded(
                  child: selectedColumns.isEmpty
                      ? const Center(child: Text("Select a test to view comparison data."))
                      : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 10,
                        horizontalMargin: 8,
                        headingRowColor: MaterialStatePropertyAll(primaryBlue),
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 60,
                        columns: [
                          DataColumn(label: Container(width: 200, child: const Text("Parameter", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                          const DataColumn(label: Text("Unit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text("Range", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          ...selectedColumns.map((col) => DataColumn(
                            label: Container(
                              width: 100,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(DateFormat('dd MMM').format(DateTime.parse(col.reportedOn)), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  Text(DateFormat('hh:mm a').format(DateTime.parse(col.reportedOn)), style: const TextStyle(color: Colors.white, fontSize: 10)),
                                ],
                              ),
                            ),
                          )),
                        ],
                        rows: tableRows.map((row) {
                          final isSubheading = row.unit == "SUBHEADING";
                          return DataRow(
                            selected: isSubheading,
                            color: isSubheading ? MaterialStatePropertyAll(Colors.blueGrey.shade50) : null,
                            cells: [
                              DataCell(
                                Padding(
                                  padding: EdgeInsets.only(left: (row.indent * 8).toDouble()),
                                  child: Text(
                                    row.parameterName,
                                    style: TextStyle(fontWeight: isSubheading ? FontWeight.bold : FontWeight.normal),
                                  ),
                                ),
                                onTap: isSubheading ? null : () {},
                              ),
                              DataCell(Text(isSubheading ? "" : row.unit)),
                              DataCell(Text(isSubheading ? "" : row.range)),
                              ...selectedColumns.map((col) {
                                final value = row.values[col.dateKey] ?? '-';
                                final isHigh = value.endsWith(' H');
                                final isLow = value.endsWith(' L');
                                final displayValue = value.replaceAll(RegExp(r' [HL]$'), '');

                                return DataCell(
                                  Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      isSubheading ? '' : displayValue,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isHigh || isLow ? redIndicator : greenIndicator,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: lightBackground, body: _buildLoading());
    if (_error != null) return Scaffold(backgroundColor: lightBackground, body: _buildError(_error!));

    final primaryRegistration = _registrations.first;
    final comparisonData = _getSingleTestComparisonData();
    String ageUnit = "Y";
    if (primaryRegistration.dayType == "month") ageUnit = "M";
    else if (primaryRegistration.dayType == "day") ageUnit = "D";

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: const Text("Investigation Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryBlue,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Block
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: [primaryBlue, primaryBlue.withOpacity(0.8)]),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Investigation Dashboard", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text("IPD ID: ${widget.ipdId}", style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9))),
                        ],
                      ),
                      if (_availableTabs.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: _handleOpenComparison,
                          icon: const Icon(Icons.trending_up, size: 18),
                          label: const Text("Advanced Analysis"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primaryBlue),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Patient Info Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Patient Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                        const Divider(),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _buildInfoChip(Icons.person, "Name:", primaryRegistration.name),
                            _buildInfoChip(Icons.credit_card, "UHID:", primaryRegistration.uhid ?? "N/A"),
                            _buildInfoChip(Icons.calendar_today, "Age/Gender:", "${primaryRegistration.age} $ageUnit / ${primaryRegistration.gender}"),
                            _buildInfoChip(Icons.local_hospital, "Hospital:", primaryRegistration.hospitalName ?? "Not Specified"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Registration History List
                Text(
                  "Registration History (${_registrations.length} records)",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkText),
                ),
                const SizedBox(height: 16),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _registrations.length,
                  itemBuilder: (context, index) {
                    final reg = _registrations[index];
                    return _buildRegistrationCard(reg);
                  },
                ),
              ],
            ),
          ),
          if (_showComparisonModal) _buildComparisonModal(comparisonData),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: primaryBlue, size: 18),
          const SizedBox(width: 8),
          Text(
            "$label ",
            style: const TextStyle(fontWeight: FontWeight.w500, color: mediumGreyText),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, color: darkText),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationCard(Registration reg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(reg.visitType == 'ipd' ? Icons.bed : Icons.person_pin, color: primaryBlue),
        title: Text(
          "Registration ID: ${reg.id}",
          style: const TextStyle(fontWeight: FontWeight.bold, color: darkText),
        ),
        subtitle: Text(
          formatRegistrationDate(reg.createdAt, includeTime: true),
          style: const TextStyle(color: mediumGreyText),
        ),
        trailing: Chip(
          label: Text(reg.visitType.toUpperCase(), style: TextStyle(color: reg.visitType == 'ipd' ? greenIndicator : primaryBlue)),
          backgroundColor: reg.visitType == 'ipd' ? Colors.green.shade50 : lightBlue,
        ),
        children: [
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Tests in this Registration:", style: TextStyle(fontWeight: FontWeight.w600, color: darkText)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reg.bloodTests.length,
                  itemBuilder: (context, index) {
                    final test = reg.bloodTests[index];
                    final isAdded = isTestValueAdded(reg, test);
                    final testKey = formatTestKey(test.testName);
                    final testDetail = reg.bloodtestDetail[testKey];

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                      leading: Icon(Icons.flag, color: isAdded ? greenIndicator : mediumGreyText),
                      title: Text(test.testName, style: TextStyle(fontWeight: FontWeight.w500, color: darkText)),
                      subtitle: Text(
                          isAdded
                              ? "Reported On: ${formatRegistrationDate(testDetail!.reportedOn, includeTime: false)}"
                              : "Price: ₹${test.price.toStringAsFixed(2)}",
                          style: TextStyle(color: isAdded ? mediumGreyText : redIndicator)
                      ),
                      trailing: Chip(
                        label: Text(isAdded ? "Completed" : "Pending", style: TextStyle(fontSize: 12, color: isAdded ? greenIndicator : redIndicator)),
                        backgroundColor: isAdded ? Colors.green.shade50 : Colors.red.shade50,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}