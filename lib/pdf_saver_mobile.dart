// File: pdf_saver_mobile.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> saveAndOpenPdf(pw.Document doc, String fileName) async {
  final output = await getTemporaryDirectory();
  final file = File("${output.path}/$fileName.pdf");
  await file.writeAsBytes(await doc.save());

  final result = await OpenFile.open(file.path);
  if (result.type != ResultType.done) {
    throw Exception('Could not open the saved PDF file: ${result.message}');
  }
}