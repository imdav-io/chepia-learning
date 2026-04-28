import 'package:equatable/equatable.dart';

enum AssetKind { pdf, audio, studyGuide }

class Asset extends Equatable {
  const Asset({
    required this.id,
    required this.kind,
    required this.storagePath,
    this.lessonId,
    this.bookId,
    this.mimeType,
    this.sizeBytes,
    this.durationSec,
    this.pages,
    this.version = 1,
  });

  final String id;
  final AssetKind kind;
  /// Puede ser una URL absoluta (demo / CDN externo) o un path dentro del
  /// bucket "content" de Supabase Storage.
  final String storagePath;
  final String? lessonId;
  final String? bookId;
  final String? mimeType;
  final int? sizeBytes;
  final int? durationSec;
  final int? pages;
  final int version;

  bool get isAbsoluteUrl =>
      storagePath.startsWith('http://') || storagePath.startsWith('https://');

  static AssetKind _parseKind(String raw) {
    switch (raw) {
      case 'pdf':
        return AssetKind.pdf;
      case 'audio':
        return AssetKind.audio;
      case 'study_guide':
        return AssetKind.studyGuide;
      default:
        throw ArgumentError('AssetKind desconocido: $raw');
    }
  }

  factory Asset.fromMap(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        kind: _parseKind(m['kind'] as String),
        storagePath: m['storage_path'] as String,
        lessonId: m['lesson_id'] as String?,
        bookId: m['book_id'] as String?,
        mimeType: m['mime_type'] as String?,
        sizeBytes: (m['size_bytes'] as num?)?.toInt(),
        durationSec: (m['duration_sec'] as num?)?.toInt(),
        pages: (m['pages'] as num?)?.toInt(),
        version: (m['version'] as num?)?.toInt() ?? 1,
      );

  @override
  List<Object?> get props =>
      [id, kind, storagePath, lessonId, bookId, version];
}
