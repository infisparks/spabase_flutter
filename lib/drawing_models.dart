import 'dart:math';
import 'package:flutter/material.dart';

// --- Utility Functions ---

String generateUniqueId() {
  return DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
}

/// A more robust implementation of the Ramer-Douglas-Peucker algorithm.
List<Offset> simplify(List<Offset> points, double epsilon) {
  if (points.length < 3) {
    return points;
  }

  double findPerpendicularDistance(
      Offset point, Offset lineStart, Offset lineEnd) {
    double dx = lineEnd.dx - lineStart.dx;
    double dy = lineEnd.dy - lineStart.dy;
    if (dx == 0 && dy == 0) return (point - lineStart).distance;
    double t =
        ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) /
            (dx * dx + dy * dy);
    t = max(0, min(1, t));
    double closestX = lineStart.dx + t * dx;
    double closestY = lineStart.dy + t * dy;
    return sqrt(pow(point.dx - closestX, 2) + pow(point.dy - closestY, 2));
  }

  double dMax = 0;
  int index = 0;
  for (int i = 1; i < points.length - 1; i++) {
    double d = findPerpendicularDistance(points[i], points.first, points.last);
    if (d > dMax) {
      index = i;
      dMax = d;
    }
  }

  if (dMax > epsilon) {
    var recResults1 = simplify(points.sublist(0, index + 1), epsilon);
    var recResults2 = simplify(points.sublist(index, points.length), epsilon);
    return recResults1.sublist(0, recResults1.length - 1) + recResults2;
  } else {
    return [points.first, points.last];
  }
}

// --- Data Models ---

// 1. DrawingLine
class DrawingLine {
  final List<Offset> points;
  final int colorValue;
  final double strokeWidth;
  final List<double>? pressure;

  DrawingLine({
    required this.points,
    required this.colorValue,
    required this.strokeWidth,
    this.pressure,
  });

  factory DrawingLine.fromJson(Map<String, dynamic> json) {
    final pointsList = <Offset>[];
    final pointsData = json['points'];
    final color = (json['colorValue'] as num?)?.toInt() ?? Colors.black.value;
    final width = (json['strokeWidth'] as num?)?.toDouble() ?? 2.0;

    final pressureList = (json['pressure'] as List?)
        ?.whereType<num>()
        .map((e) => e.toDouble())
        .toList();

    if (pointsData is List && pointsData.isNotEmpty) {
      if (pointsData[0] is Map) {
        for (var pointJson in pointsData) {
          if (pointJson is Map) {
            pointsList.add(Offset(
              (pointJson['dx'] as num?)?.toDouble() ?? 0.0,
              (pointJson['dy'] as num?)?.toDouble() ?? 0.0,
            ));
          }
        }
      } else if (pointsData[0] is num) {
        if (pointsData.length >= 2) {
          double lastX = (pointsData[0] as num).toDouble() / 100.0;
          double lastY = (pointsData[1] as num).toDouble() / 100.0;
          pointsList.add(Offset(lastX, lastY));

          for (int i = 2; i < pointsData.length; i += 2) {
            if (i + 1 < pointsData.length) {
              lastX += (pointsData[i] as num).toDouble() / 100.0;
              lastY += (pointsData[i + 1] as num).toDouble() / 100.0;
              pointsList.add(Offset(lastX, lastY));
            }
          }
        }
      }
    }

    return DrawingLine(
      points: pointsList,
      colorValue: color,
      strokeWidth: width,
      pressure: pressureList,
    );
  }

  Map<String, dynamic> toJson() {
    final jsonMap = {
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
      'pressure': pressure,
    };

    if (points.isEmpty) {
      jsonMap['points'] = [];
      return jsonMap;
    }

    final simplifiedPoints = simplify(points, 0.2);
    if (simplifiedPoints.isEmpty) {
      jsonMap['points'] = [];
      return jsonMap;
    }

    final compressedPoints = <int>[];
    int lastX = (simplifiedPoints.first.dx * 100).round();
    int lastY = (simplifiedPoints.first.dy * 100).round();
    compressedPoints.add(lastX);
    compressedPoints.add(lastY);

    for (int i = 1; i < simplifiedPoints.length; i++) {
      int currentX = (simplifiedPoints[i].dx * 100).round();
      int currentY = (simplifiedPoints[i].dy * 100).round();
      compressedPoints.add(currentX - lastX);
      compressedPoints.add(currentY - lastY);
      lastX = currentX;
      lastY = currentY;
    }

    jsonMap['points'] = compressedPoints;
    return jsonMap;
  }

  DrawingLine copyWith({
    List<Offset>? points,
    int? colorValue,
    double? strokeWidth,
    List<double>? pressure,
  }) {
    return DrawingLine(
      points: points ?? this.points,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      pressure: pressure ?? this.pressure,
    );
  }
}

// 2. DrawingImage
class DrawingImage {
  final String id;
  final String imageUrl;
  final Offset position;
  final double width;
  final double height;

  DrawingImage({
    required this.id,
    required this.imageUrl,
    required this.position,
    required this.width,
    required this.height,
  });

  DrawingImage copyWith({
    String? id,
    String? imageUrl,
    Offset? position,
    double? width,
    double? height,
  }) {
    return DrawingImage(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  factory DrawingImage.fromJson(Map<String, dynamic> json) {
    return DrawingImage(
      id: (json['id'] as String?) ?? generateUniqueId(),
      imageUrl: (json['imageUrl'] as String?) ?? '',
      position: Offset(
        (json['position']?['dx'] as num?)?.toDouble() ?? 0.0,
        (json['position']?['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      width: (json['width'] as num?)?.toDouble() ?? 200.0,
      height: (json['height'] as num?)?.toDouble() ?? 200.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'position': {'dx': position.dx, 'dy': position.dy},
      'width': width,
      'height': height,
    };
  }
}

// --- 3. DrawingText (THIS WAS MISSING) ---
class DrawingText {
  final String id;
  final String text;
  final Offset position;
  final int colorValue;
  final double fontSize;

  DrawingText({
    required this.id,
    required this.text,
    required this.position,
    required this.colorValue,
    required this.fontSize,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'position': {'dx': position.dx, 'dy': position.dy},
    'colorValue': colorValue,
    'fontSize': fontSize,
  };

  factory DrawingText.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>? ?? {'dx': 0.0, 'dy': 0.0};
    return DrawingText(
      id: json['id'] as String? ?? generateUniqueId(),
      text: json['text'] as String? ?? '',
      position: Offset(
        (positionJson['dx'] as num?)?.toDouble() ?? 0.0,
        (positionJson['dy'] as num?)?.toDouble() ?? 0.0,
      ),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? Colors.black.value,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
    );
  }

  DrawingText copyWith({
    String? text,
    Offset? position,
    int? colorValue,
    double? fontSize,
  }) {
    return DrawingText(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

// 4. DrawingPage (UPDATED TO INCLUDE texts)
class DrawingPage {
  final String id;
  final int pageNumber;
  final String pageName;
  final String groupName;
  final String templateImageUrl;
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  final List<DrawingText> texts; // <--- ADDED THIS

  DrawingPage({
    required this.id,
    required this.pageNumber,
    required this.pageName,
    required this.groupName,
    required this.templateImageUrl,
    this.lines = const [],
    this.images = const [],
    this.texts = const [], // <--- ADDED THIS
  });

  DrawingPage copyWith({
    String? id,
    int? pageNumber,
    String? pageName,
    String? groupName,
    String? templateImageUrl,
    List<DrawingLine>? lines,
    List<DrawingImage>? images,
    List<DrawingText>? texts, // <--- ADDED THIS
  }) {
    return DrawingPage(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      pageName: pageName ?? this.pageName,
      groupName: groupName ?? this.groupName,
      templateImageUrl: templateImageUrl ?? this.templateImageUrl,
      lines: lines ?? this.lines,
      images: images ?? this.images,
      texts: texts ?? this.texts, // <--- ADDED THIS
    );
  }

  factory DrawingPage.fromJson(Map<String, dynamic> json) {
    return DrawingPage(
      id: (json['id'] as String?) ?? '',
      pageNumber: (json['pageNumber'] as int?) ?? 0,
      pageName: json['pageName'] as String? ?? 'Unnamed Page',
      groupName: json['groupName'] as String? ?? 'Unnamed Group',
      templateImageUrl: (json['templateImageUrl'] as String?) ?? '',
      lines: (json['lines'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((lineJson) => DrawingLine.fromJson(lineJson))
          .toList() ??
          [],
      images: (json['images'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((imageJson) => DrawingImage.fromJson(imageJson))
          .toList() ??
          [],
      texts: (json['texts'] as List<dynamic>?) // <--- ADDED THIS
          ?.whereType<Map<String, dynamic>>()
          .map((textJson) => DrawingText.fromJson(textJson))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pageNumber': pageNumber,
      'pageName': pageName,
      'groupName': groupName,
      'templateImageUrl': templateImageUrl,
      'lines': lines.map((line) => line.toJson()).toList(),
      'images': images.map((image) => image.toJson()).toList(),
      'texts': texts.map((text) => text.toJson()).toList(), // <--- ADDED THIS
    };
  }
}

// 5. DrawingGroup
class DrawingGroup {
  final String id;
  final String groupName;
  final List<DrawingPage> pages;

  DrawingGroup({
    required this.id,
    required this.groupName,
    this.pages = const [],
  });

  DrawingGroup copyWith({
    String? id,
    String? groupName,
    List<DrawingPage>? pages,
  }) {
    return DrawingGroup(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      pages: pages ?? this.pages,
    );
  }

  factory DrawingGroup.fromJson(Map<String, dynamic> json) {
    return DrawingGroup(
      id: (json['id'] as String?) ?? '',
      groupName: json['groupName'] as String? ?? json['name'] as String? ?? 'Unnamed Group',
      pages: (json['pages'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((pageJson) =>
          DrawingPage.fromJson(pageJson as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupName': groupName,
      'pages': pages.map((page) => page.toJson()).toList(),
    };
  }
}

// 6. StampImage
class StampImage {
  final int id;
  final String name;
  final String stampUrl;

  StampImage({required this.id, required this.name, required this.stampUrl});

  factory StampImage.fromJson(Map<String, dynamic> json) {
    return StampImage(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unnamed Stamp',
      stampUrl: json['stamp_url'] as String? ?? '',
    );
  }
}