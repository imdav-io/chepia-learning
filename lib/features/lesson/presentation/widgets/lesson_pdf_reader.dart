import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../shared/services/cache_providers.dart';

final _dio = Dio();

class LessonPdfReader extends ConsumerStatefulWidget {
  const LessonPdfReader({
    super.key,
    required this.pdfUrl,
    this.cacheKey,
    this.startPage,
    this.jumpToPage,
    this.emptyMessage = 'Este libro aún no tiene PDF asociado.',
    this.onPageChanged,
  });

  final String? pdfUrl;

  /// Identifica el archivo de manera estable a través de URLs firmadas
  /// que cambian. Normalmente es `storage_path` del asset.
  final String? cacheKey;
  final int? startPage;
  final String emptyMessage;

  /// Cuando este valor cambia, el lector salta a esa página.
  final int? jumpToPage;

  /// Notifica cambios de página (para persistir progreso, por ejemplo).
  final ValueChanged<int>? onPageChanged;

  @override
  ConsumerState<LessonPdfReader> createState() => _LessonPdfReaderState();
}

class _LessonPdfReaderState extends ConsumerState<LessonPdfReader> {
  PdfController? _controller;
  Object? _error;
  bool _loading = false;
  int _currentPage = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfUrl != widget.pdfUrl ||
        oldWidget.cacheKey != widget.cacheKey) {
      _controller?.dispose();
      _controller = null;
      _error = null;
      _load();
      return;
    }
    if (oldWidget.jumpToPage != widget.jumpToPage &&
        widget.jumpToPage != null &&
        _controller != null) {
      _controller!.animateToPage(
        widget.jumpToPage!,
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Future<void> _load() async {
    final url = widget.pdfUrl;
    if (url == null) return;
    setState(() => _loading = true);
    try {
      Uint8List bytes;
      final key = widget.cacheKey;
      if (key != null && key.isNotEmpty) {
        final cache = ref.read(assetCacheProvider);
        bytes = await cache.getOrDownload(key: key, url: url, kind: 'pdf');
      } else {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(res.data ?? const []);
      }
      // pdfx en web puede transferir/detachar el ArrayBuffer recibido.
      // Abrimos una copia para que la caché conserve bytes reutilizables.
      final document = await PdfDocument.openData(Uint8List.fromList(bytes));
      final initialPage = widget.startPage ?? widget.jumpToPage ?? 1;
      final controller = PdfController(
        document: Future.value(document),
        initialPage: initialPage,
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _pageCount = document.pagesCount;
        _currentPage = initialPage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pdfUrl == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(widget.emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudo cargar el PDF: $_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: PdfView(
            controller: _controller!,
            scrollDirection: Axis.vertical,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (page) {
              if (mounted && page != _currentPage) {
                setState(() => _currentPage = page);
                widget.onPageChanged?.call(page);
              }
            },
          ),
        ),
        _PdfPageBar(
          currentPage: _currentPage,
          pageCount: _pageCount,
          onPrev: _currentPage > 1
              ? () => _controller!.animateToPage(
                  _currentPage - 1,
                  curve: Curves.easeOut,
                  duration: const Duration(milliseconds: 200),
                )
              : null,
          onNext: _currentPage < _pageCount
              ? () => _controller!.animateToPage(
                  _currentPage + 1,
                  curve: Curves.easeOut,
                  duration: const Duration(milliseconds: 200),
                )
              : null,
        ),
      ],
    );
  }
}

class _PdfPageBar extends StatelessWidget {
  const _PdfPageBar({
    required this.currentPage,
    required this.pageCount,
    required this.onPrev,
    required this.onNext,
  });
  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Página anterior',
              onPressed: onPrev,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                pageCount > 0 ? '$currentPage / $pageCount' : '$currentPage',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Página siguiente',
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}
