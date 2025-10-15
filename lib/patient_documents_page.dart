// File: patient_documents_page.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:photo_view/photo_view.dart';
import 'investigation_sheet_page.dart'; // Import the new investigation page

// --- Data Models for Documents (No Changes Here) ---
class DocumentFile {
  final String name;
  final String uploadedAt;
  final String size;
  final IconData icon;
  final String path;

  DocumentFile({
    required this.name,
    required this.uploadedAt,
    required this.size,
    required this.icon,
    required this.path,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'uploadedAt': uploadedAt,
      'size': size,
      'path': path,
    };
  }

  factory DocumentFile.fromJson(Map<String, dynamic> json) {
    return DocumentFile(
      name: json['name'],
      uploadedAt: json['uploadedAt'],
      size: json['size'],
      path: json['path'],
      icon: _getIconFromPath(json['path']),
    );
  }

  static IconData _getIconFromPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}

class DocumentSubFolder {
  final String name;
  List<DocumentFile> files;
  final IconData icon;

  DocumentSubFolder({
    required this.name,
    required this.files,
    this.icon = Icons.folder_outlined,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'files': files.map((f) => f.toJson()).toList(),
    };
  }

  factory DocumentSubFolder.fromJson(Map<String, dynamic> json) {
    return DocumentSubFolder(
      name: json['name'],
      files: (json['files'] as List).map((f) => DocumentFile.fromJson(f)).toList(),
    );
  }
}

class DocumentFolder {
  final String name;
  final IconData icon;
  List<DocumentFile> files;
  List<DocumentSubFolder> subFolders;

  DocumentFolder({
    required this.name,
    required this.icon,
    this.files = const [],
    this.subFolders = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'files': files.map((f) => f.toJson()).toList(),
      'subFolders': subFolders.map((sf) => sf.toJson()).toList(),
    };
  }

  factory DocumentFolder.fromJson(Map<String, dynamic> json) {
    final folderName = json['name'];
    final icon = _getIconForFolder(folderName);

    return DocumentFolder(
      name: folderName,
      icon: icon,
      files: (json['files'] as List).map((f) => DocumentFile.fromJson(f)).toList(),
      subFolders: (json['subFolders'] as List).map((sf) => DocumentSubFolder.fromJson(sf)).toList(),
    );
  }

  static IconData _getIconForFolder(String folderName) {
    switch (folderName) {
      case 'X-Ray & Imaging':
        return Icons.monitor_heart_outlined;
      case 'Blood & Lab Tests':
        return Icons.biotech_outlined;
      case 'Other Documents':
        return Icons.folder_open_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
}

// --- The Main Widget ---
class PatientDocumentsPage extends StatefulWidget {
  final int ipdId;
  final String uhid;
  final String patientName;

  const PatientDocumentsPage({
    super.key,
    required this.ipdId,
    required this.uhid,
    required this.patientName,
  });

  @override
  State<PatientDocumentsPage> createState() => _PatientDocumentsPageState();
}

class _PatientDocumentsPageState extends State<PatientDocumentsPage> {
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mediumGreyText = Color(0xFF64748B);
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightBlue = Color(0xFFE3F2FD);

  // Split folders based on the new denormalized columns
  List<DocumentFolder> _imagingFolders = []; // Stored in imaging_doc
  List<DocumentFolder> _generalFolders = []; // Stored in bloodtestdoc

  bool _isLoading = true;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadDocumentsFromSupabase();
  }

  // --- START: DATA LOGIC ---

  Future<void> _loadDocumentsFromSupabase() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('user_health_details')
          .select('imaging_doc, bloodtestdoc') // Select both columns
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid)
          .maybeSingle();

      final dynamic imagingDoc = response?['imaging_doc'];
      final dynamic bloodTestDoc = response?['bloodtestdoc'];

      List<DocumentFolder> loadedImaging = [];
      List<DocumentFolder> loadedGeneral = [];

      if (imagingDoc != null) {
        for (final jsonFolder in imagingDoc) {
          loadedImaging.add(DocumentFolder.fromJson(jsonFolder));
        }
      }

      if (bloodTestDoc != null) {
        for (final jsonFolder in bloodTestDoc) {
          loadedGeneral.add(DocumentFolder.fromJson(jsonFolder));
        }
      }

      if (loadedImaging.isEmpty && loadedGeneral.isEmpty) {
        _initializeFolders();
      } else {
        _imagingFolders = loadedImaging;
        _generalFolders = loadedGeneral;
      }
    } catch (e) {
      debugPrint('Error loading documents: $e');
      _initializeFolders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load documents: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _initializeFolders() {
    // Initialize imaging folder separately
    _imagingFolders = [
      DocumentFolder(
        name: 'X-Ray & Imaging',
        icon: Icons.monitor_heart_outlined,
        files: [],
      ),
    ];

    // Initialize general folders
    _generalFolders = [
      DocumentFolder(
        name: 'Blood & Lab Tests',
        icon: Icons.biotech_outlined,
        files: [],
        subFolders: [],
      ),
      DocumentFolder(
        name: 'Other Documents',
        icon: Icons.folder_open_outlined,
        files: [],
      ),
    ];
  }

  Future<void> _saveDocumentsToSupabase() async {
    try {
      final List<Map<String, dynamic>> jsonImaging = _imagingFolders.map((folder) => folder.toJson()).toList();
      final List<Map<String, dynamic>> jsonGeneral = _generalFolders.map((folder) => folder.toJson()).toList();

      final Map<String, dynamic> dataToSave = {
        'imaging_doc': jsonImaging,
        'bloodtestdoc': jsonGeneral,
      };

      await supabase
          .from('user_health_details')
          .update(dataToSave)
          .eq('ipd_registration_id', widget.ipdId)
          .eq('patient_uhid', widget.uhid);

    } on PostgrestException catch (e) {
      if (e.code == '23503' || e.code == '42P01') { // Foreign key violation or table/column not found (new DB record/column)
        await _insertInitialRecord();
        await _saveDocumentsToSupabase(); // Retry saving
      } else {
        rethrow;
      }
    } catch (e) {
      debugPrint('Error saving documents: $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save documents: $e")),
        );
      }
    }
  }

  Future<void> _insertInitialRecord() async {
    // Create and insert a full record, which will include the default empty JSON arrays
    final List<Map<String, dynamic>> jsonImaging = _imagingFolders.map((folder) => folder.toJson()).toList();
    final List<Map<String, dynamic>> jsonGeneral = _generalFolders.map((folder) => folder.toJson()).toList();

    await supabase.from('user_health_details').insert({
      'ipd_registration_id': widget.ipdId,
      'patient_uhid': widget.uhid,
      'imaging_doc': jsonImaging,
      'bloodtestdoc': jsonGeneral,
    });
  }

  // --- END: DATA LOGIC ---


  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.bitLength - 1) ~/ 10 : 0;
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(1)} ${suffixes[i]}';
  }

  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _pickAndAddFile({
    required DocumentFolder folder, // Now required
    DocumentSubFolder? subFolder,
  }) async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);

    if (file != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final String fileExtension = file.name.split('.').last;
        final String folderPath = subFolder != null
            ? '${folder.name}/${subFolder.name}'
            : folder.name;

        final String timestamp = DateTime.now().microsecondsSinceEpoch.toString();
        final random = Random().nextInt(10000).toString();
        final String uniqueName = '${timestamp}_$random';

        final String storagePath = '${widget.uhid}/$folderPath/$uniqueName.${fileExtension.toLowerCase()}'.replaceAll('//', '/');

        final Uint8List fileBytes = await file.readAsBytes();

        await supabase.storage.from('reports').uploadBinary(
          storagePath,
          fileBytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/$fileExtension',
          ),
        );

        final now = DateFormat('dd MMM yyyy').format(DateTime.now());
        final newFile = DocumentFile(
          name: file.name,
          uploadedAt: now,
          size: _formatBytes(fileBytes.length),
          icon: _getFileIcon(fileExtension),
          path: storagePath,
        );

        // Update local state and save
        setState(() {
          if (subFolder != null) {
            subFolder.files.add(newFile);
          } else {
            folder.files.add(newFile);
          }
        });

        await _saveDocumentsToSupabase();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }

      } catch (e) {
        debugPrint('Error uploading file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload file: ${file.name}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _createNewSubFolder(DocumentFolder parentFolder) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Create New Sub-Folder", style: TextStyle(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "Enter sub-folder name",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: primaryBlue, width: 2),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: mediumGreyText)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  setState(() {
                    parentFolder.subFolders.add(DocumentSubFolder(name: controller.text, files: []));
                  });
                  await _saveDocumentsToSupabase();
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _openPhotoViewer(List<DocumentFile> folderFiles, DocumentFile tappedFile) {
    final List<DocumentFile> imageFiles = folderFiles
        .where((file) => DocumentFile._getIconFromPath(file.path) == Icons.image)
        .toList();

    final int initialIndex = imageFiles.indexOf(tappedFile);

    if (imageFiles.isNotEmpty && initialIndex != -1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoViewerPage(
            imageFiles: imageFiles,
            initialIndex: initialIndex,
            supabaseClient: supabase,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tappedFile.name} is not a viewable image.')),
      );
    }
  }

  // --- NEW METHOD FOR INVESTIGATION PAGE ---
  void _openInvestigationPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvestigationSheetPage(
          ipdId: widget.ipdId.toString(), // Pass IPD ID as string to match API logic
        ),
      ),
    );
  }
  // --- END NEW METHOD ---

  String _truncateFileName(String fileName, {int maxLength = 8}) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) {
      return fileName.length > maxLength
          ? '${fileName.substring(0, maxLength)}...'
          : fileName;
    }

    String baseName = fileName.substring(0, dotIndex);
    String extension = fileName.substring(dotIndex);

    if (baseName.length > maxLength) {
      baseName = '${baseName.substring(0, maxLength)}...';
    }

    return baseName + extension;
  }

  /// Function to handle image deletion
  Future<void> _deleteFile({
    required DocumentFile fileToDelete,
    DocumentFolder? parentFolder,
    DocumentSubFolder? parentSubFolder,
  }) async {
    // 1. Show confirmation dialog
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Confirm Deletion", style: TextStyle(color: darkText, fontWeight: FontWeight.bold)),
          content: Text("Are you sure you want to delete '${_truncateFileName(fileToDelete.name)}'? This action cannot be undone.", style: const TextStyle(color: mediumGreyText)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: mediumGreyText)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      setState(() {
        _isLoading = true; // Show loading indicator during deletion
      });

      try {
        // 2. Delete from Supabase Storage
        final List<String> pathsToRemove = [fileToDelete.path];
        await supabase.storage.from('reports').remove(pathsToRemove);

        // 3. Remove from local state
        setState(() {
          if (parentSubFolder != null) {
            parentSubFolder.files.removeWhere((file) => file.path == fileToDelete.path);
          } else if (parentFolder != null) {
            parentFolder.files.removeWhere((file) => file.path == fileToDelete.path);
          }
        });


        // 4. Save updated document structure to Supabase Database
        await _saveDocumentsToSupabase();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${_truncateFileName(fileToDelete.name)}" deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete file: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double horizontalPadding = screenWidth > 600 ? 24.0 : 16.0;

    final allFolders = [..._imagingFolders, ..._generalFolders];

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: const Text(
          "Patient Documents",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: darkText),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withAlpha((255 * 0.08).round()),
        toolbarHeight: 60,
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryBlue))
          : CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 16.0, horizontalPadding, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Patient Information",
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: darkText),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.person_outline, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("Name: ${widget.patientName}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.medical_information_outlined, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              // IPD ID DISPLAYED HERE
                              Text("IPD ID: ${widget.ipdId}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.credit_card_outlined, color: primaryBlue, size: 18),
                              const SizedBox(width: 6),
                              Text("UHID: ${widget.uhid}", style: const TextStyle(fontSize: 15, color: mediumGreyText)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- NEW INVESTIGATION FOLDER BUTTON ---
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(Icons.class_outlined, color: primaryBlue, size: 28),
                      title: const Text("Investigation (In-House)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: mediumGreyText),
                      onTap: _openInvestigationPage,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- END NEW FOLDER ---

                  const Text(
                    "Document Folders",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, folderIndex) {
                final folder = allFolders[folderIndex];
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6.0),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Icon(folder.icon, color: primaryBlue, size: 24),
                        title: Text(folder.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
                        trailing: (folder.name == 'Blood & Lab Tests')
                            ? IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined, color: primaryBlue, size: 24),
                          onPressed: () => _createNewSubFolder(folder),
                          tooltip: "Create New Sub-folder",
                        )
                            : IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: primaryBlue, size: 24),
                          onPressed: () => _pickAndAddFile(folder: folder),
                          tooltip: "Add File to ${folder.name}",
                        ),
                        iconColor: primaryBlue,
                        collapsedIconColor: mediumGreyText,
                        childrenPadding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 8.0),
                        children: [
                          const Divider(height: 1, thickness: 1, color: lightBackground),
                          if (folder.subFolders.isEmpty && folder.files.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                "No documents found. Click the '+' icon to add one.",
                                style: TextStyle(color: mediumGreyText, fontStyle: FontStyle.italic, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (folder.subFolders.isNotEmpty)
                            ...folder.subFolders.map((subFolder) {
                              return ExpansionTile(
                                leading: Icon(subFolder.icon, color: Colors.blueGrey, size: 22),
                                title: Text(subFolder.name, style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 16)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: primaryBlue, size: 22),
                                  onPressed: () => _pickAndAddFile(folder: folder, subFolder: subFolder),
                                  tooltip: "Add File to ${subFolder.name}",
                                ),
                                childrenPadding: const EdgeInsets.only(left: 24.0, right: 12.0, bottom: 8.0),
                                children: [
                                  if (subFolder.files.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text("No files in this sub-folder.", style: TextStyle(color: mediumGreyText, fontStyle: FontStyle.italic)),
                                    ),
                                  ...subFolder.files.map((file) {
                                    return GestureDetector(
                                      onLongPress: () => _deleteFile(fileToDelete: file, parentFolder: folder, parentSubFolder: subFolder),
                                      child: ListTile(
                                        leading: Icon(file.icon, color: mediumGreyText, size: 20),
                                        title: Text(
                                          _truncateFileName(file.name),
                                          style: const TextStyle(fontWeight: FontWeight.w500, color: darkText, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text("${file.uploadedAt} • ${file.size}", style: const TextStyle(color: mediumGreyText, fontSize: 12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        onTap: () {
                                          _openPhotoViewer(subFolder.files, file);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ],
                              );
                            }).toList(),

                          if (folder.files.isNotEmpty)
                            ...folder.files.map((file) {
                              return GestureDetector(
                                onLongPress: () => _deleteFile(fileToDelete: file, parentFolder: folder),
                                child: ListTile(
                                  leading: Icon(file.icon, color: mediumGreyText, size: 22),
                                  title: Text(
                                    _truncateFileName(file.name),
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: darkText, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text("Uploaded: ${file.uploadedAt} • ${file.size}", style: const TextStyle(color: mediumGreyText, fontSize: 13)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  hoverColor: lightBlue.withAlpha((255 * 0.5).round()),
                                  onTap: () {
                                    _openPhotoViewer(folder.files, file);
                                  },
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: allFolders.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

/// --- PHOTO VIEWER WIDGET (No Changes Here) ---
class PhotoViewerPage extends StatefulWidget {
  final List<DocumentFile> imageFiles;
  final int initialIndex;
  final SupabaseClient supabaseClient;

  const PhotoViewerPage({
    super.key,
    required this.imageFiles,
    required this.initialIndex,
    required this.supabaseClient,
  });

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _getPublicUrl(String path) async {
    try {
      final url = await widget.supabaseClient.storage
          .from('reports')
          .createSignedUrl(path, 3600);
      return url;
    } catch (e) {
      debugPrint('Error getting signed URL: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Image ${_currentIndex + 1} of ${widget.imageFiles.length}',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageFiles.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final imageFile = widget.imageFiles[index];
          return FutureBuilder<String>(
            future: _getPublicUrl(imageFile.path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 8),
                      Text('Failed to load image', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                );
              }

              final imageUrl = snapshot.data!;
              return PhotoView(
                imageProvider: NetworkImage(imageUrl),
                minScale: PhotoViewComputedScale.contained * 0.8,
                maxScale: PhotoViewComputedScale.covered * 2.0,
                heroAttributes: PhotoViewHeroAttributes(tag: imageFile.path),
                loadingBuilder: (context, event) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            },
          );
        },
      ),
    );
  }
}