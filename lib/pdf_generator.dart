import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'drawing_models.dart';
import 'ipd_structure.dart'; // <-- IMPORTED the structure file

// Helper extension for list safety
extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

class PdfGenerator {
  static const String kBaseImageUrl = 'https://apimmedford.infispark.in/';
  // These constants define the SOURCE coordinate space from the Flutter app's canvas.
  static const double kSourceCanvasWidth = 1000;
  static const double kSourceCanvasHeight = 1414;

  static String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  /// --- NEW FUNCTION TO DOWNLOAD THE ENTIRE PATIENT RECORD ---
  static Future<void> downloadFullRecordAsPdf({
    required BuildContext context,
    required SupabaseClient supabase,
    required String? healthRecordId,
  }) async {
    if (healthRecordId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot download, health record not loaded.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Generating Full Record PDF..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      // Define all columns to fetch, based on ipd_structure.dart
      final List<String> allDataColumns = [
        'id',
        ...allGroupColumnNames, // From ipd_structure.dart
        'custom_groups_data',
      ];

      // Fetch all group data in one call
      final response = await supabase
          .from('user_health_details')
          .select(allDataColumns.join(','))
          .eq('id', healthRecordId)
          .single();

      final List<DrawingPage> allPages = [];

      // 1. Add pages from default groups, in the order defined by ipdGroupStructure
      for (final config in ipdGroupStructure) {
        final columnName = config.columnName;
        if (response.containsKey(columnName)) {
          final List<dynamic>? rawPages = response[columnName] as List?;
          if (rawPages != null) {
            final pages = rawPages
                .map((p) => DrawingPage.fromJson(p as Map<String, dynamic>))
                .toList();
            pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
            allPages.addAll(pages);
          }
        }
      }

      // 2. Add pages from custom groups
      final List<dynamic>? rawCustomGroups =
      response['custom_groups_data'] as List?;
      if (rawCustomGroups != null) {
        final customGroups = rawCustomGroups
            .map((g) => DrawingGroup.fromJson(g as Map<String, dynamic>))
            .toList();
        for (final group in customGroups) {
          final pages = group.pages;
          pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
          allPages.addAll(pages);
        }
      }

      if (allPages.isEmpty) {
        throw Exception("No pages found in this record to download.");
      }

      // --- PDF Generation Logic (Same as your original function) ---
      final doc = pw.Document();

      Future<Uint8List?> _fetchImageBytes(String url) async {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            return response.bodyBytes;
          }
        } catch (e) {
          debugPrint('Failed to fetch image $url: $e');
        }
        return null;
      }

      for (final pageData in allPages) {
        final templateImageBytes =
        await _fetchImageBytes(_getFullImageUrl(pageData.templateImageUrl));
        if (templateImageBytes == null) {
          debugPrint(
              "Skipping page ${pageData.pageName} due to missing template.");
          continue;
        }
        final templateImage = pw.MemoryImage(templateImageBytes);

        final dynamicPageFormat = PdfPageFormat(
          templateImage.width!.toDouble(),
          templateImage.height!.toDouble(),
          marginAll: 0,
        );

        final Map<String, pw.MemoryImage> embeddedImages = {};
        for (final img in pageData.images) {
          final imgBytes = await _fetchImageBytes(img.imageUrl);
          if (imgBytes != null) {
            embeddedImages[img.imageUrl] = pw.MemoryImage(imgBytes);
          }
        }

        final double imageWidth = templateImage.width!.toDouble();
        final double imageHeight = templateImage.height!.toDouble();
        final double canvasAspectRatio =
            kSourceCanvasWidth / kSourceCanvasHeight;
        final double imageAspectRatio = imageWidth / imageHeight;

        double sourceContentWidth;
        double sourceContentHeight;
        double offsetX;
        double offsetY;

        if (imageAspectRatio > canvasAspectRatio) {
          sourceContentWidth = kSourceCanvasWidth;
          sourceContentHeight = kSourceCanvasWidth / imageAspectRatio;
          offsetX = 0;
          offsetY = (kSourceCanvasHeight - sourceContentHeight) / 2.0;
        } else {
          sourceContentHeight = kSourceCanvasHeight;
          sourceContentWidth = kSourceCanvasHeight * imageAspectRatio;
          offsetX = (kSourceCanvasWidth - sourceContentWidth) / 2.0;
          offsetY = 0;
        }

        final double scaleX = imageWidth / sourceContentWidth;
        final double scaleY = imageHeight / sourceContentHeight;

        doc.addPage(
          pw.Page(
            pageFormat: dynamicPageFormat,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Stack(
                alignment: pw.Alignment.topLeft,
                children: [
                  pw.Image(templateImage, fit: pw.BoxFit.fill),
                  ...pageData.images
                      .where((img) => embeddedImages.containsKey(img.imageUrl))
                      .map((image) {
                    return pw.Positioned(
                      left: (image.position.dx - offsetX) * scaleX,
                      top: (image.position.dy - offsetY) * scaleY,
                      child: pw.Image(
                        embeddedImages[image.imageUrl]!,
                        width: image.width * scaleX,
                        height: image.height * scaleY,
                        fit: pw.BoxFit.contain,
                      ),
                    );
                  }).toList(),
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (final line in pageData.lines) {
                          if (line.points.length < 2) continue;

                          canvas
                            ..saveContext()
                            ..setStrokeColor(PdfColor.fromInt(line.colorValue))
                            ..setLineWidth(
                                line.strokeWidth * scaleX) // Scale stroke
                            ..setLineCap(PdfLineCap.round);

                          final firstPoint = line.points.first;
                          final transformedFirstX =
                              (firstPoint.dx - offsetX) * scaleX;
                          final transformedFirstY =
                              (firstPoint.dy - offsetY) * scaleY;

                          canvas.moveTo(
                            transformedFirstX,
                            size.y -
                                transformedFirstY, // Invert Y-axis for PDF
                          );

                          for (int i = 1; i < line.points.length; i++) {
                            final point = line.points[i];
                            final transformedX = (point.dx - offsetX) * scaleX;
                            final transformedY = (point.dy - offsetY) * scaleY;
                            canvas.lineTo(
                              transformedX,
                              size.y -
                                  transformedY, // Invert Y-axis for PDF
                            );
                          }
                          canvas.strokePath();
                          canvas.restoreContext();
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      if (context.mounted) Navigator.of(context).pop();

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      debugPrint('Error generating PDF: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  /// --- Original function to download a single group ---
  static Future<void> downloadGroupAsPdf({
    required BuildContext context,
    required SupabaseClient supabase,
    required String? healthRecordId,
    required String groupName,
    required String groupId,
    required Map<String, String> groupToColumnMap,
  }) async {
    if (healthRecordId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot download, health record not loaded.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Generating PDF..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      final columnName = groupToColumnMap[groupName] ?? 'custom_groups_data';
      List<dynamic>? rawPages;

      if (columnName != 'custom_groups_data') {
        final response = await supabase
            .from('user_health_details')
            .select(columnName)
            .eq('id', healthRecordId)
            .single();
        rawPages = response[columnName] as List?;
      } else {
        final response = await supabase
            .from('user_health_details')
            .select('custom_groups_data')
            .eq('id', healthRecordId)
            .single();
        final allGroups = (response['custom_groups_data'] as List?)
            ?.map((g) => DrawingGroup.fromJson(g))
            .toList() ??
            [];
        final currentGroup =
        allGroups.firstWhereOrNull((g) => g.id == groupId);
        rawPages = currentGroup?.pages.map((p) => p.toJson()).toList();
      }

      if (rawPages == null || rawPages.isEmpty) {
        throw Exception("No pages found in this group to download.");
      }

      final List<DrawingPage> allPages = rawPages
          .map((p) => DrawingPage.fromJson(p as Map<String, dynamic>))
          .toList();
      allPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

      final doc = pw.Document();

      Future<Uint8List?> _fetchImageBytes(String url) async {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            return response.bodyBytes;
          }
        } catch (e) {
          debugPrint('Failed to fetch image $url: $e');
        }
        return null;
      }

      for (final pageData in allPages) {
        final templateImageBytes =
        await _fetchImageBytes(_getFullImageUrl(pageData.templateImageUrl));
        if (templateImageBytes == null) {
          debugPrint(
              "Skipping page ${pageData.pageName} due to missing template.");
          continue;
        }
        final templateImage = pw.MemoryImage(templateImageBytes);

        final dynamicPageFormat = PdfPageFormat(
          templateImage.width!.toDouble(),
          templateImage.height!.toDouble(),
          marginAll: 0,
        );

        final Map<String, pw.MemoryImage> embeddedImages = {};
        for (final img in pageData.images) {
          final imgBytes = await _fetchImageBytes(img.imageUrl);
          if (imgBytes != null) {
            embeddedImages[img.imageUrl] = pw.MemoryImage(imgBytes);
          }
        }

        // --- ✅ FIX START: COORDINATE TRANSFORMATION LOGIC ---
        // This logic reverses the `BoxFit.contain` effect from the Flutter UI.
        final double imageWidth = templateImage.width!.toDouble();
        final double imageHeight = templateImage.height!.toDouble();

        final double canvasAspectRatio =
            kSourceCanvasWidth / kSourceCanvasHeight;
        final double imageAspectRatio = imageWidth / imageHeight;

        double sourceContentWidth;
        double sourceContentHeight;
        double offsetX;
        double offsetY;

        // Calculate the size and position of the image as it was displayed
        // within the source canvas in the Flutter app.
        if (imageAspectRatio > canvasAspectRatio) {
          // Letterboxed: Image is wider than canvas ratio. Width is constrained.
          sourceContentWidth = kSourceCanvasWidth;
          sourceContentHeight = kSourceCanvasWidth / imageAspectRatio;
          offsetX = 0;
          offsetY = (kSourceCanvasHeight - sourceContentHeight) / 2.0;
        } else {
          // Pillarboxed: Image is taller than canvas ratio. Height is constrained.
          sourceContentHeight = kSourceCanvasHeight;
          sourceContentWidth = kSourceCanvasHeight * imageAspectRatio;
          offsetX = (kSourceCanvasWidth - sourceContentWidth) / 2.0;
          offsetY = 0;
        }

        // These are the final scaling factors to map from the content area
        // of the source canvas to the final PDF page size.
        final double scaleX = imageWidth / sourceContentWidth;
        final double scaleY = imageHeight / sourceContentHeight;
        // --- ✅ FIX END ---

        doc.addPage(
          pw.Page(
            pageFormat: dynamicPageFormat,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Stack(
                alignment: pw.Alignment.topLeft,
                children: [
                  pw.Image(templateImage, fit: pw.BoxFit.fill),
                  ...pageData.images
                      .where((img) => embeddedImages.containsKey(img.imageUrl))
                      .map((image) {
                    // Apply the transformation to image position and size
                    return pw.Positioned(
                      left: (image.position.dx - offsetX) * scaleX,
                      top: (image.position.dy - offsetY) * scaleY,
                      child: pw.Image(
                        embeddedImages[image.imageUrl]!,
                        width: image.width * scaleX,
                        height: image.height * scaleY,
                        fit: pw.BoxFit.contain,
                      ),
                    );
                  }).toList(),
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (final line in pageData.lines) {
                          if (line.points.length < 2) continue;

                          canvas
                            ..saveContext()
                            ..setStrokeColor(PdfColor.fromInt(line.colorValue))
                            ..setLineWidth(
                                line.strokeWidth * scaleX) // Scale stroke
                            ..setLineCap(PdfLineCap.round);

                          // Transform the first point and move to it
                          final firstPoint = line.points.first;
                          final transformedFirstX =
                              (firstPoint.dx - offsetX) * scaleX;
                          final transformedFirstY =
                              (firstPoint.dy - offsetY) * scaleY;

                          canvas.moveTo(
                            transformedFirstX,
                            size.y -
                                transformedFirstY, // Invert Y-axis for PDF
                          );

                          // Transform all subsequent points and draw lines to them
                          for (int i = 1; i < line.points.length; i++) {
                            final point = line.points[i];
                            final transformedX = (point.dx - offsetX) * scaleX;
                            final transformedY = (point.dy - offsetY) * scaleY;
                            canvas.lineTo(
                              transformedX,
                              size.y -
                                  transformedY, // Invert Y-axis for PDF
                            );
                          }
                          canvas.strokePath();
                          canvas.restoreContext();
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      if (context.mounted) Navigator.of(context).pop();

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      debugPrint('Error generating PDF: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate PDF: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }
}