import '/drawing_models.dart';

class MedicalMacro {
  final String id;
  final String name;
  final List<DrawingLine> lines;
  final List<DrawingImage> images;
  final String? userId;

  MedicalMacro({
    required this.id,
    required this.name,
    required this.lines,
    required this.images,
    this.userId,
  });

  factory MedicalMacro.fromJson(Map<String, dynamic> json) {
    // --- LAZY LOADING SUPPORT ---
    // If 'content' wasn't fetched, these will be null. We handle that safely.
    final content = json['content'] as Map<String, dynamic>?;

    return MedicalMacro(
      id: json['id'],
      name: json['name'],
      userId: json['user_id'],
      // If content is null, default to empty lists
      lines: content != null
          ? (content['lines'] as List<dynamic>?)?.map((e) => DrawingLine.fromJson(e)).toList() ?? []
          : [],
      images: content != null
          ? (content['images'] as List<dynamic>?)?.map((e) => DrawingImage.fromJson(e)).toList() ?? []
          : [],
    );
  }

  Map<String, dynamic> toContentJson() {
    return {
      'lines': lines.map((e) => e.toJson()).toList(),
      'images': images.map((e) => e.toJson()).toList(),
    };
  }
}