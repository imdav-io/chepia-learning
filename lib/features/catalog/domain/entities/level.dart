import 'package:equatable/equatable.dart';

class Level extends Equatable {
  const Level({
    required this.id,
    required this.code,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String code; // beginner | intermediate | advanced
  final String name;
  final int sortOrder;

  factory Level.fromMap(Map<String, dynamic> m) => Level(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  @override
  List<Object?> get props => [id, code, name, sortOrder];
}
