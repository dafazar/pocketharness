// lib/features/notes/data/note_model.dart

class NoteModel {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int colorIndex;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.colorIndex,
  });

  factory NoteModel.fromMap(Map<String, dynamic> m) => NoteModel(
        id: m['id'] as String,
        title: m['title'] as String,
        content: m['content'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        colorIndex: (m['colorIndex'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'colorIndex': colorIndex,
      };

  NoteModel copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? colorIndex,
  }) =>
      NoteModel(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        colorIndex: colorIndex ?? this.colorIndex,
      );
}
