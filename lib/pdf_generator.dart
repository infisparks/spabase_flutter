import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'drawing_models.dart';
import 'ipd_structure.dart';

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
  static const double kSourceCanvasWidth = 1000;
  static const double kSourceCanvasHeight = 1414;

  static String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

  /// --- DOWNLOAD FULL PATIENT RECORD ---
  static Future<void> downloadFullRecordAsPdf({
    required BuildContext context,
    required SupabaseClient supabase,
    required String? healthRecordId,
    required String patientName,
    required String uhid,
  }) async {
    if (healthRecordId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot download, health record not loaded.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    final String safePatientName =
    patientName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final String pdfName = '${safePatientName}_${uhid}.pdf';

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
      final List<String> allDataColumns = [
        'id',
        ...allGroupColumnNames,
        'custom_groups_data',
      ];

      final response = await supabase
          .from('user_health_details')
          .select(allDataColumns.join(','))
          .eq('id', healthRecordId)
          .single();

      final List<DrawingPage> allPages = [];

      // 1. Add pages from default groups
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
        // A. Fetch Background Template
        final templateImageBytes =
        await _fetchImageBytes(_getFullImageUrl(pageData.templateImageUrl));
        if (templateImageBytes == null) continue;
        final templateImage = pw.MemoryImage(templateImageBytes);

        // B. Fetch Added Images (Stamps/Photos)
        final Map<String, pw.MemoryImage> embeddedImages = {};
        for (final img in pageData.images) {
          // Ensure we have a valid URL. If stored relatively, use helper.
          String url = img.imageUrl;
          if (!url.startsWith('http')) url = _getFullImageUrl(url);

          final imgBytes = await _fetchImageBytes(url);
          if (imgBytes != null) {
            embeddedImages[img.imageUrl] = pw.MemoryImage(imgBytes);
          }
        }

        final dynamicPageFormat = PdfPageFormat(
          templateImage.width!.toDouble(),
          templateImage.height!.toDouble(),
          marginAll: 0,
        );

        // Calculate Scale Logic
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
                  // 1. Background Template
                  pw.Image(templateImage, fit: pw.BoxFit.fill),

                  // 2. Added Images (Stamps/Photos)
                  ...pageData.images.map((image) {
                    if (!embeddedImages.containsKey(image.imageUrl)) {
                      return pw.SizedBox();
                    }
                    return pw.Positioned(
                      left: (image.position.dx - offsetX) * scaleX,
                      top: (image.position.dy - offsetY) * scaleY,
                      child: pw.Image(
                        embeddedImages[image.imageUrl]!,
                        width: image.width * scaleX,
                        height: image.height * scaleY,
                        fit: pw.BoxFit.fill,
                      ),
                    );
                  }).toList(),

                  // 3. Auto-filled Texts
                  if (pageData.texts.isNotEmpty)
                    ...pageData.texts.map((textItem) {
                      return pw.Positioned(
                        left: (textItem.position.dx - offsetX) * scaleX,
                        top: (textItem.position.dy - offsetY) * scaleY,
                        child: pw.Text(
                          textItem.text,
                          style: pw.TextStyle(
                            fontSize: textItem.fontSize * scaleX,
                            color: PdfColor.fromInt(textItem.colorValue),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),

                  // 4. Handwritten Lines
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (final line in pageData.lines) {
                          if (line.points.length < 2) continue;

                          canvas
                            ..saveContext()
                            ..setStrokeColor(PdfColor.fromInt(line.colorValue))
                            ..setLineWidth(line.strokeWidth * scaleX)
                            ..setLineCap(PdfLineCap.round);

                          final firstPoint = line.points.first;
                          final transformedFirstX =
                              (firstPoint.dx - offsetX) * scaleX;
                          final transformedFirstY =
                              (firstPoint.dy - offsetY) * scaleY;

                          canvas.moveTo(
                            transformedFirstX,
                            size.y - transformedFirstY,
                          );

                          for (int i = 1; i < line.points.length; i++) {
                            final point = line.points[i];
                            final transformedX = (point.dx - offsetX) * scaleX;
                            final transformedY = (point.dy - offsetY) * scaleY;
                            canvas.lineTo(
                              transformedX,
                              size.y - transformedY,
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
        name: pdfName,
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

  /// --- DOWNLOAD SINGLE GROUP AS PDF ---
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
        final currentGroup = allGroups.firstWhereOrNull((g) => g.id == groupId);
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
        // A. Fetch Background Template
        final templateImageBytes =
        await _fetchImageBytes(_getFullImageUrl(pageData.templateImageUrl));
        if (templateImageBytes == null) continue;
        final templateImage = pw.MemoryImage(templateImageBytes);

        // B. Fetch Added Images (Stamps/Photos)
        final Map<String, pw.MemoryImage> embeddedImages = {};
        for (final img in pageData.images) {
          // Ensure we have a valid URL
          String url = img.imageUrl;
          if (!url.startsWith('http')) url = _getFullImageUrl(url);

          final imgBytes = await _fetchImageBytes(url);
          if (imgBytes != null) {
            embeddedImages[img.imageUrl] = pw.MemoryImage(imgBytes);
          }
        }

        final dynamicPageFormat = PdfPageFormat(
          templateImage.width!.toDouble(),
          templateImage.height!.toDouble(),
          marginAll: 0,
        );

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
                  // 1. Background
                  pw.Image(templateImage, fit: pw.BoxFit.fill),

                  // 2. Added Images
                  ...pageData.images.map((image) {
                    if (!embeddedImages.containsKey(image.imageUrl)) {
                      return pw.SizedBox();
                    }
                    return pw.Positioned(
                      left: (image.position.dx - offsetX) * scaleX,
                      top: (image.position.dy - offsetY) * scaleY,
                      child: pw.Image(
                        embeddedImages[image.imageUrl]!,
                        width: image.width * scaleX,
                        height: image.height * scaleY,
                        fit: pw.BoxFit.fill,
                      ),
                    );
                  }).toList(),

                  // 3. Auto-filled Texts
                  if (pageData.texts.isNotEmpty)
                    ...pageData.texts.map((textItem) {
                      return pw.Positioned(
                        left: (textItem.position.dx - offsetX) * scaleX,
                        top: (textItem.position.dy - offsetY) * scaleY,
                        child: pw.Text(
                          textItem.text,
                          style: pw.TextStyle(
                            fontSize: textItem.fontSize * scaleX,
                            color: PdfColor.fromInt(textItem.colorValue),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),

                  // 4. Lines
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (final line in pageData.lines) {
                          if (line.points.length < 2) continue;

                          canvas
                            ..saveContext()
                            ..setStrokeColor(PdfColor.fromInt(line.colorValue))
                            ..setLineWidth(line.strokeWidth * scaleX)
                            ..setLineCap(PdfLineCap.round);

                          final firstPoint = line.points.first;
                          final transformedFirstX =
                              (firstPoint.dx - offsetX) * scaleX;
                          final transformedFirstY =
                              (firstPoint.dy - offsetY) * scaleY;

                          canvas.moveTo(
                            transformedFirstX,
                            size.y - transformedFirstY,
                          );

                          for (int i = 1; i < line.points.length; i++) {
                            final point = line.points[i];
                            final transformedX = (point.dx - offsetX) * scaleX;
                            final transformedY = (point.dy - offsetY) * scaleY;
                            canvas.lineTo(
                              transformedX,
                              size.y - transformedY,
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