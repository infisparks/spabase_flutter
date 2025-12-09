import 'package:flutter/material.dart';

/// This class holds all coordinate configurations for auto-filling text
/// onto different types of medical pages.
class PageLayoutDefinitions {
  // ==============================================================================
  // 1. LAYOUT DEFINITIONS (COORDINATES)
  // ==============================================================================

  /// Layout for: Progress Notes, Nursing Notes, TPR, Dr Visit, Glucose, Patient Charges
  /// Standard Header Layout
  static const Map<String, Map<String, double>> commonHeaderLayout = {
    'patient_name': {'x': 194, 'y': 228},
    'uhid':         {'x': 500, 'y': 258},
    'room_ward':    {'x': 200, 'y': 258},
    'ipd_no':       {'x': 682, 'y': 258},
    'age':          {'x': 834, 'y': 228},
    'doa':          {'x': 808, 'y': 258},
    'consultant':   {'x': 155, 'y': 289},
    // 'so_wo_do':     {'x': 194, 'y': 258}, // Adjusted slightly based on typical flow
  };

  /// Layout for: Indoor Patient File (Cover Page)
  static const Map<String, Map<String, dynamic>> indoorFileLayout = {
    'patient_name':   {'x': 191.0, 'y': 740.0, 'width': 400.0},
    'so_wo_do':       {'x': 194.0, 'y': 780.0, 'width': 200.0},
    'age':            {'x': 113.0, 'y': 823.0, 'width': 80.0},
    'sex':            {'x': 215.0, 'y': 823.0, 'width': 80.0},
    'admission_date': {'x': 445.0, 'y': 823.0, 'width': 200.0},
    'admission_time': {'x': 745.0, 'y': 823.0, 'width': 100.0},
    'uhid':           {'x': 156.0, 'y': 862.0, 'width': 200.0},
    'ipd_no':         {'x': 461.0, 'y': 862.0, 'width': 180.0},
    'address':        {'x': 740.0, 'y': 862.0, 'width': 300.0},
    'address_line_2': {'x': 73.0,  'y': 903.0, 'width': 1000.0},
    'contact':        {'x': 175.0, 'y': 947.0, 'width': 400.0},
    'consultant':     {'x': 233.0, 'y': 989.0, 'width': 450.0},
    'bed_details':    {'x': 214.0, 'y': 1031.0, 'width': 300.0},
    'referred_dr':    {'x': 574.0, 'y': 1031.0, 'width': 300.0},
  };
  static const Map<String, Map<String, dynamic>> dailyDrugChartLayout = {
    'patient_name':   {'x': 108.0, 'y': 475.0, 'fontSize': 11.0},
    'age':            {'x': 65.0,  'y': 492.0, 'fontSize': 11.0},
    'sex':            {'x': 132.0, 'y': 492.0, 'fontSize': 11.0},
    'uhid':           {'x': 232.0, 'y': 492.0, 'fontSize': 11.0},
    'admission_date': {'x': 331.0, 'y': 492.0, 'fontSize': 11.0},
  };
  // ==============================================================================
  // 2. LOGIC TO SELECT LAYOUT
  // ==============================================================================

  static Map<String, dynamic>? getLayoutForGroup(String groupName) {
    final String gName = groupName.toLowerCase();

    if (groupName == 'Indoor Patient File') return indoorFileLayout;

    // Explicit check for Daily Drug Chart
    if (gName.contains('drug chart') || groupName == 'Daily Drug Chart') {
      return dailyDrugChartLayout;
    }

    if (gName.contains('progress') ||
        gName.contains('nursing notes') ||
        gName.contains('dr visit') ||
        gName.contains('glucose') ||
        gName.contains('patient charges') ||
        gName.contains('tpr') ||
        gName.contains('intake') ||
        gName.contains('clinical notes') ||
        gName.contains('admission assessment') ||
        gName.contains('investigation')) {
      return commonHeaderLayout;
    }

    return null;
  }
}