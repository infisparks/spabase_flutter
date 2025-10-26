import 'package:flutter/foundation.dart';

/// Enum to define how pages can be added to a group.
enum AddBehavior {
  /// Can only add ONE single page, ever.
  singlePageOnly,

  /// Can only add ONE pair of pages (front/back), ever.
  singlePairOnly,

  /// Can add multiple single pages from a specific template tag.
  multiPageSingle,

  /// Can add multiple single pages, prompting for a custom name each time.
  multiPageSingleCustomName,

  /// Can add multiple page pairs (front/back) from a specific template tag.
  multiPagePaired,

  /// Can add multiple pages, selected from a list of templates matching a tag.
  multiPageFromList,

  /// Can only add ONE set of pages (a "book") from a specific template name.
  singleBook,

  /// Behavior for user-created custom groups.
  multiPageCustom,
}

/// Holds the configuration for a single IPD group.
///
/// This defines its display name, database column, and how pages are added.
@immutable
class GroupConfig {
  final String groupName;
  final String columnName;
  final AddBehavior behavior;

  /// Used for behaviors requiring a template tag.
  /// e.g., 't1', 't6', 't10', 't14', 't18', 't19'
  final String? templateTag;

  /// Used for behaviors: singleBook.
  /// e.g., 'OT Form'
  final String? templateName;

  /// A friendly name for the page type, used in naming new pages.
  /// e.g., "Clinical Note", "ICU Chart", "Prescription"
  final String pageNamePrefix;

  const GroupConfig({
    required this.groupName,
    required this.columnName,
    required this.behavior,
    this.templateTag,
    this.templateName,
    this.pageNamePrefix = 'Page', // Default prefix
  });
}

/// This list is the new "single source of truth" for the IPD group structure.
///
/// It defines the **display order** of the groups in the UI,
/// their corresponding database [columnName], and their [behavior]
/// (e.g., how new pages are added).
final List<GroupConfig> ipdGroupStructure = [
  // --- Admission & Initial Assessment ---
  const GroupConfig(
    groupName: 'Indoor Patient File',
    columnName: 'indoor_patient_file_data',
    behavior: AddBehavior.singlePageOnly,
    templateTag: 't1',
    pageNamePrefix: 'Patient File',
  ),
  const GroupConfig(
    groupName: 'Pt Admission Assessment (Nursing)',
    columnName: 'pt_admission_assessment_nursing_data',
    behavior: AddBehavior.singlePairOnly,
    templateTag: 't6',
    pageNamePrefix: 'Admission Assessment',
  ),
  const GroupConfig(
    groupName: 'Casualty Note',
    columnName: 'casualty_note_data',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 't15',
    pageNamePrefix: 'Casualty Note',
  ),

  // --- Doctor & Progress Notes ---
  const GroupConfig(
    groupName: 'Clinical Notes',
    columnName: 'clinical_notes_data',
    behavior: AddBehavior.singlePairOnly,
    templateTag: 't7',
    pageNamePrefix: 'Clinical Note',
  ),
  const GroupConfig(
    groupName: 'Dr Visit Form',
    columnName: 'dr_visit_form_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't3',
    pageNamePrefix: 'Doctor Visit',
  ),
  const GroupConfig(
    groupName: 'Indoor Patient Progress Digital',
    columnName: 'indoor_patient_progress_digital_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't9',
    pageNamePrefix: 'Progress Note',
  ),
  const GroupConfig(
    groupName: 'Progress Notes',
    columnName: 'progress_notes_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't9',
    pageNamePrefix: 'Progress Note',
  ),
  const GroupConfig(
    groupName: 'Nursing Notes',
    columnName: 'nursing_notes_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't11',
    pageNamePrefix: 'Nursing Note',
  ),

  // --- Charts & Vitals ---
  const GroupConfig(
    groupName: 'Daily Drug Chart',
    columnName: 'daily_drug_chart_data',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 't2',
    pageNamePrefix: 'Daily Drug Chart',
  ),
  const GroupConfig(
    groupName: 'Prescription Sheet',
    columnName: 'prescription_sheet_data', // Define a new DB column
    behavior: AddBehavior.multiPageSingleCustomName, // Use the new behavior
    templateTag: 't18', // Your new template tag
    pageNamePrefix: 'Prescription', // Default prefix for the name dialog
  ),
  const GroupConfig(
    groupName: 'Icu chart',
    columnName: 'icu_chart_data',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 't16',
    pageNamePrefix: 'ICU Chart',
  ),
  const GroupConfig(
    groupName: 'TPR / Intake / Output',
    columnName: 'tpr_intake_output_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't12',
    pageNamePrefix: 'TPR/Intake/Output',
  ),
  const GroupConfig(
    groupName: 'Glucose Monitoring Sheet',
    columnName: 'glucose_monitoring_sheet_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't5',
    pageNamePrefix: 'Glucose Monitoring',
  ),

  // --- Investigations & Special Forms ---
  const GroupConfig(
    groupName: 'Investigation Sheet',
    columnName: 'investigation_sheet_data',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 't8',
    pageNamePrefix: 'Investigation',
  ),
  const GroupConfig(
    groupName: 'Consent',
    columnName: 'consent_data',
    behavior: AddBehavior.multiPageFromList,
    templateTag: 't10',
    pageNamePrefix: 'Consent Form',
  ),
  const GroupConfig(
    groupName: 'OT',
    columnName: 'ot_data',
    behavior: AddBehavior.singleBook,
    templateName: 'OT Form',
    pageNamePrefix: 'OT Form',
  ),

  // --- Admin & Discharge ---
  // --- NEW GROUP ADDED HERE ---
  const GroupConfig(
    groupName: 'Billing Consent',
    columnName: 'billing_consent_data', // <-- MUST ADD THIS to user_health_details
    behavior: AddBehavior.multiPageFromList,
    templateTag: 't19',
    pageNamePrefix: 'Billing Form',
  ),
  // --- END NEW GROUP ---
  const GroupConfig(
    groupName: 'Patient Charges Form',
    columnName: 'patient_charges_form_data',
    behavior: AddBehavior.multiPageSingle,
    templateTag: 't4',
    pageNamePrefix: 'Patient Charges',
  ),
  const GroupConfig(
    groupName: 'Transfer Summary',
    columnName: 'transfer_summary_data',
    behavior: AddBehavior.multiPagePaired,
    templateTag: 't17',
    pageNamePrefix: 'Transfer Summary',
  ),
  const GroupConfig(
    groupName: 'Discharge / Dama',
    columnName: 'discharge_dama_data',
    behavior: AddBehavior.multiPageFromList,
    templateTag: 't14',
    pageNamePrefix: 'Discharge/Dama',
  ),
];

// --- HELPERS ---
// You can now import and use these maps in your pages,
// replacing the old hard-coded ones.

/// A map of {groupName: columnName} generated from the structure list.
final Map<String, String> groupToColumnMap = {
  for (var config in ipdGroupStructure) config.groupName: config.columnName
};

/// A list of all database column names for default groups.
final List<String> allGroupColumnNames = [
  for (var config in ipdGroupStructure) config.columnName
];

/// Helper to find a group's config by its name.
GroupConfig? findGroupConfigByName(String groupName) {
  try {
    return ipdGroupStructure.firstWhere((g) => g.groupName == groupName);
  } catch (e) {
    return null; // Not a default group
  }
}