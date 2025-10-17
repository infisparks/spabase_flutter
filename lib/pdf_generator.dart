import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'drawing_models.dart';

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
  static const double canvasWidth = 1000;
  static const double canvasHeight = 1414;

  static String _getFullImageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    final baseUri = Uri.parse(kBaseImageUrl);
    final finalUri = baseUri.resolve(relativePath);
    return finalUri.toString();
  }

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
        final templateImageBytes = await _fetchImageBytes(_getFullImageUrl(pageData.templateImageUrl));
        if (templateImageBytes == null) {
          debugPrint("Skipping page ${pageData.pageName} due to missing template.");
          continue;
        }
        final templateImage = pw.MemoryImage(templateImageBytes);

        final Map<String, pw.MemoryImage> embeddedImages = {};
        for (final img in pageData.images) {
          final imgBytes = await _fetchImageBytes(img.imageUrl);
          if (imgBytes != null) {
            embeddedImages[img.imageUrl] = pw.MemoryImage(imgBytes);
          }
        }

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Stack(
                alignment: pw.Alignment.topLeft,
                children: [
                  pw.Image(templateImage, fit: pw.BoxFit.fill),
                  ...pageData.images.where((img) => embeddedImages.containsKey(img.imageUrl)).map((image) {
                    final scaleX = context.page.pageFormat.width / canvasWidth;
                    final scaleY = context.page.pageFormat.height / canvasHeight;
                    return pw.Positioned(
                      left: image.position.dx * scaleX,
                      top: image.position.dy * scaleY,
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
                        final scaleX = size.x / canvasWidth;
                        final scaleY = size.y / canvasHeight;

                        for (final line in pageData.lines) {
                          if (line.points.length < 2) continue;

                          canvas
                            ..saveContext()
                            ..setStrokeColor(PdfColor.fromInt(line.colorValue))
                            ..setLineWidth(line.strokeWidth * scaleX)
                            ..setLineCap(PdfLineCap.round);

                          canvas.moveTo(
                            line.points.first.dx * scaleX,
                            size.y - (line.points.first.dy * scaleY),
                          );

                          for (int i = 1; i < line.points.length; i++) {
                            canvas.lineTo(
                              line.points[i].dx * scaleX,
                              size.y - (line.points[i].dy * scaleY),
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