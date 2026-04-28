import 'package:equatable/equatable.dart';

class Lesson extends Equatable {
  const Lesson({
    required this.id,
    required this.bookId,
    required this.number,
    required this.title,
    this.pdfStartPage,
    this.pdfEndPage,
  });

  final String id;
  final String bookId;
  final int number;
  final String title;
  final int? pdfStartPage;
  final int? pdfEndPage;

  factory Lesson.fromMap(Map<String, dynamic> m) => Lesson(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        number: m['number'] as int,
        title: m['title'] as String,
        pdfStartPage: m['pdf_start_page'] as int?,
        pdfEndPage: m['pdf_end_page'] as int?,
      );

  @override
  List<Object?> get props => [id, bookId, number, title, pdfStartPage, pdfEndPage];
}
