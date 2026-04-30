import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../shared/services/cache_providers.dart';

final _dio = Dio();

const double _kSidebarWidth = 196;
const double _kToolbarHeight = 56;
const double _kThumbnailWidth = 136;
const double _kThumbnailHeight = 182;
const double _kThumbnailTileExtent = 250;
const double _kCanvasInset = 14;
const double _kPageGap = 18;
const double _kZoomStep = 0.25;
const double _kZoomMin = 0.6;
const double _kZoomMax = 3.0;

const Color _kToolbarColor = Color(0xFF242424);
const Color _kToolbarStroke = Color(0xFF3A3A3A);
const Color _kToolbarControl = Color(0xFF303030);
const Color _kToolbarControlHover = Color(0xFF3F3F3F);
const Color _kSidebarColor = Color(0xFF252525);
const Color _kSidebarSelected = Color(0xFF2F7DFF);
const Color _kCanvasColor = Color(0xFFE9E7E2);

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
  final String? cacheKey;
  final int? startPage;
  final int? jumpToPage;
  final String emptyMessage;
  final ValueChanged<int>? onPageChanged;

  @override
  ConsumerState<LessonPdfReader> createState() => _LessonPdfReaderState();
}

class _LessonPdfReaderState extends ConsumerState<LessonPdfReader> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  PdfDocument? _document;
  _PageRenderer? _pages;
  _ThumbnailRenderer? _thumbnails;
  _PdfLayoutMetrics? _layout;
  Object? _error;
  bool _loading = false;
  double _downloadProgress = 0;
  int _currentPage = 1;
  int _pageCount = 0;
  int? _pendingPage;
  bool _isSidebarVisible = true;
  double _zoomLevel = 1.0;
  List<double> _pageAspects = const [];

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_syncCurrentPageWithScroll);
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfUrl != widget.pdfUrl ||
        oldWidget.cacheKey != widget.cacheKey) {
      _disposeDocument();
      _load();
      return;
    }
    if (oldWidget.jumpToPage != widget.jumpToPage &&
        widget.jumpToPage != null) {
      _goToPage(widget.jumpToPage!);
    }
  }

  @override
  void dispose() {
    _verticalController
      ..removeListener(_syncCurrentPageWithScroll)
      ..dispose();
    _horizontalController.dispose();
    _disposeDocument();
    super.dispose();
  }

  void _disposeDocument() {
    _pages?.dispose();
    _pages = null;
    _thumbnails?.dispose();
    _thumbnails = null;
    final document = _document;
    _document = null;
    if (document != null) {
      unawaited(document.close());
    }
    _layout = null;
    _pageAspects = const [];
  }

  Future<void> _load() async {
    final url = widget.pdfUrl;
    if (url == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _downloadProgress = 0;
      _zoomLevel = 1.0;
      _pageCount = 0;
      _currentPage = 1;
    });

    try {
      Uint8List bytes;
      final key = widget.cacheKey;
      if (key != null && key.isNotEmpty) {
        final cache = ref.read(assetCacheProvider);
        bytes = await cache.getOrDownload(key: key, url: url, kind: 'pdf');
        if (mounted) setState(() => _downloadProgress = 1.0);
      } else {
        final res = await _dio.get<List<int>>(
          url,
          onReceiveProgress: (count, total) {
            if (total > 0 && mounted) {
              setState(() => _downloadProgress = count / total);
            }
          },
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(res.data ?? const []);
      }

      // Copia defensiva: pdfx puede detachar el ArrayBuffer en web.
      final document = await PdfDocument.openData(Uint8List.fromList(bytes));
      final aspects = await _readInitialPageAspects(document);
      final initialPage = _clampPageValue(
        widget.startPage ?? widget.jumpToPage ?? 1,
        document.pagesCount,
      );
      final renderQueue = _RenderQueue();

      if (!mounted) {
        await document.close();
        return;
      }

      setState(() {
        _document = document;
        _pageCount = document.pagesCount;
        _pageAspects = aspects;
        _pages = _PageRenderer(document, renderQueue);
        _thumbnails = _ThumbnailRenderer(document, renderQueue);
        _currentPage = initialPage;
        _pendingPage = initialPage;
        _loading = false;
      });
      unawaited(_refreshPageAspects(document));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<List<double>> _readInitialPageAspects(PdfDocument document) async {
    if (document.pagesCount <= 0) return const [];
    final page = await document.getPage(1);
    try {
      final width = page.width;
      final height = page.height;
      final aspect = width <= 0 ? 1.35 : height / width;
      return List<double>.filled(document.pagesCount, aspect);
    } finally {
      await page.close();
    }
  }

  Future<void> _refreshPageAspects(PdfDocument document) async {
    try {
      final aspects = await _readPageAspects(document);
      if (!mounted || _document != document) return;
      setState(() => _pageAspects = aspects);
    } catch (_) {
      // Las proporciones iniciales son suficientes para PDFs escaneados.
    }
  }

  Future<List<double>> _readPageAspects(PdfDocument document) async {
    final aspects = <double>[];
    for (var i = 1; i <= document.pagesCount; i++) {
      final page = await document.getPage(i);
      try {
        final width = page.width;
        final height = page.height;
        aspects.add(width <= 0 ? 1.35 : height / width);
      } finally {
        await page.close();
      }
    }
    return aspects;
  }

  int _clampPage(int page) => _clampPageValue(page, _pageCount);

  static int _clampPageValue(int page, int pageCount) {
    if (pageCount <= 0) return 1;
    return page.clamp(1, pageCount).toInt();
  }

  void _syncCurrentPageWithScroll() {
    final layout = _layout;
    if (layout == null || !_verticalController.hasClients) return;
    final viewportCenter =
        _verticalController.offset +
        _verticalController.position.viewportDimension * 0.38;
    final page = layout.pageForOffset(viewportCenter);
    if (page != null) _onPdfPageChanged(page);
  }

  void _onPdfPageChanged(int page) {
    if (!mounted || page == _currentPage) return;
    setState(() => _currentPage = page);
    widget.onPageChanged?.call(page);
  }

  void _goToPage(int page) {
    final clamped = _clampPage(page);
    _onPdfPageChanged(clamped);
    if (_layout == null || !_verticalController.hasClients) {
      _pendingPage = clamped;
      return;
    }
    _scrollToPage(clamped, animated: true);
  }

  void _scrollToPage(int page, {required bool animated}) {
    final layout = _layout;
    if (layout == null || !_verticalController.hasClients) {
      _pendingPage = page;
      return;
    }

    final target = layout
        .scrollOffsetForPage(page)
        .clamp(0.0, _verticalController.position.maxScrollExtent);
    if (animated) {
      unawaited(
        _verticalController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _verticalController.jumpTo(target);
    }
  }

  void _setZoom(double scale) {
    final target = scale.clamp(_kZoomMin, _kZoomMax).toDouble();
    if ((target - _zoomLevel).abs() < 0.01) return;
    final page = _currentPage;
    setState(() => _zoomLevel = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPage(page, animated: false);
    });
  }

  void _zoomIn() => _setZoom(_zoomLevel + _kZoomStep);
  void _zoomOut() => _setZoom(_zoomLevel - _kZoomStep);
  void _fitWidth() => _setZoom(1.0);

  String _displayName() {
    final key = widget.cacheKey;
    if (key != null && key.trim().isNotEmpty) {
      final name = Uri.decodeComponent(key.split('/').last);
      if (name.trim().isNotEmpty) return name;
    }

    final url = widget.pdfUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    final path = uri?.pathSegments.isEmpty ?? true
        ? null
        : uri!.pathSegments.last;
    if (path != null && path.trim().isNotEmpty) {
      return Uri.decodeComponent(path);
    }
    return 'PDF';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pdfUrl == null) {
      return _CenteredMessage(message: widget.emptyMessage);
    }
    if (_error != null) {
      return _CenteredMessage(
        message: 'No se pudo cargar el PDF.',
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }
    if (_loading || _document == null || _pages == null) {
      return Center(
        child: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
              const SizedBox(height: 12),
              Text(
                _downloadProgress > 0 && _downloadProgress < 1
                    ? 'Descargando PDF · ${(_downloadProgress * 100).toInt()}%'
                    : 'Preparando páginas…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowSidebar = constraints.maxWidth >= 760;
        final sidebarVisible = _isSidebarVisible && canShowSidebar;

        return ColoredBox(
          color: _kCanvasColor,
          child: Column(
            children: [
              _PdfPreviewToolbar(
                fileName: _displayName(),
                currentPage: _currentPage,
                pageCount: _pageCount,
                zoomPercent: (_zoomLevel * 100).round(),
                sidebarVisible: sidebarVisible,
                canToggleSidebar: canShowSidebar,
                onPrev: _currentPage > 1
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                onNext: _currentPage < _pageCount
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                onJumpToPage: _goToPage,
                onToggleSidebar: () =>
                    setState(() => _isSidebarVisible = !_isSidebarVisible),
                onZoomIn: _zoomLevel < _kZoomMax - 0.01 ? _zoomIn : null,
                onZoomOut: _zoomLevel > _kZoomMin + 0.01 ? _zoomOut : null,
                onFitWidth: _fitWidth,
              ),
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: sidebarVisible ? _kSidebarWidth : 0,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: _kSidebarWidth,
                          maxWidth: _kSidebarWidth,
                          child: _PdfThumbnailSidebar(
                            pageCount: _pageCount,
                            currentPage: _currentPage,
                            thumbnails: _thumbnails,
                            onPageSelected: _goToPage,
                          ),
                        ),
                      ),
                    ),
                    if (sidebarVisible)
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Color(0xFF141414),
                      ),
                    Expanded(
                      child: _PdfDocumentViewport(
                        aspects: _pageAspects,
                        currentPage: _currentPage,
                        pageRenderer: _pages!,
                        zoomLevel: _zoomLevel,
                        verticalController: _verticalController,
                        horizontalController: _horizontalController,
                        onLayout: (layout) {
                          _layout = layout;
                          final pending = _pendingPage;
                          if (pending != null) {
                            _pendingPage = null;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _scrollToPage(pending, animated: false);
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PdfDocumentViewport extends StatelessWidget {
  const _PdfDocumentViewport({
    required this.aspects,
    required this.currentPage,
    required this.pageRenderer,
    required this.zoomLevel,
    required this.verticalController,
    required this.horizontalController,
    required this.onLayout,
  });

  final List<double> aspects;
  final int currentPage;
  final _PageRenderer pageRenderer;
  final double zoomLevel;
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final ValueChanged<_PdfLayoutMetrics> onLayout;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final fitWidth = (viewportWidth - (_kCanvasInset * 2)).clamp(
          240.0,
          double.infinity,
        );
        final pageWidth = (fitWidth * zoomLevel).clamp(180.0, 4200.0);
        final contentWidth = pageWidth + (_kCanvasInset * 2);
        final layout = _PdfLayoutMetrics(
          aspects: aspects,
          pageWidth: pageWidth,
          topPadding: _kCanvasInset,
          gap: _kPageGap,
        );
        onLayout(layout);
        pageRenderer.precacheAround(
          centerPage: currentPage,
          aspects: aspects,
          displayWidth: pageWidth,
          devicePixelRatio: dpr,
        );

        return Scrollbar(
          controller: horizontalController,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: Scrollbar(
                controller: verticalController,
                notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                child: ListView.builder(
                  controller: verticalController,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: layout.topPadding,
                    bottom: layout.topPadding + 12,
                  ),
                  itemCount: aspects.length,
                  itemBuilder: (context, index) {
                    final pageNumber = index + 1;
                    final aspect = aspects[index];
                    final renderPriority =
                        10000 - (pageNumber - currentPage).abs();
                    return Padding(
                      padding: EdgeInsets.only(
                        left: _kCanvasInset,
                        right: _kCanvasInset,
                        bottom: index == aspects.length - 1 ? 0 : _kPageGap,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _PdfPageTile(
                          key: ValueKey('page-$pageNumber'),
                          pageNumber: pageNumber,
                          aspect: aspect,
                          displayWidth: pageWidth,
                          isCurrent: pageNumber == currentPage,
                          renderPriority: renderPriority,
                          devicePixelRatio: dpr,
                          renderer: pageRenderer,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PdfLayoutMetrics {
  _PdfLayoutMetrics({
    required this.aspects,
    required this.pageWidth,
    required this.topPadding,
    required this.gap,
  }) {
    var top = topPadding;
    for (final aspect in aspects) {
      pageTops.add(top);
      final height = pageWidth * aspect;
      pageHeights.add(height);
      top += height + gap;
    }
  }

  final List<double> aspects;
  final double pageWidth;
  final double topPadding;
  final double gap;
  final pageTops = <double>[];
  final pageHeights = <double>[];

  int? pageForOffset(double offset) {
    if (pageTops.isEmpty) return null;
    for (var i = 0; i < pageTops.length; i++) {
      final top = pageTops[i];
      final bottom = top + pageHeights[i] + gap;
      if (offset >= top && offset < bottom) return i + 1;
    }
    if (offset < pageTops.first) return 1;
    return pageTops.length;
  }

  double scrollOffsetForPage(int page) {
    if (pageTops.isEmpty) return 0;
    final index = page.clamp(1, pageTops.length).toInt() - 1;
    return (pageTops[index] - 8).clamp(0.0, double.infinity);
  }
}

class _PdfPageTile extends StatefulWidget {
  const _PdfPageTile({
    super.key,
    required this.pageNumber,
    required this.aspect,
    required this.displayWidth,
    required this.isCurrent,
    required this.renderPriority,
    required this.devicePixelRatio,
    required this.renderer,
  });

  final int pageNumber;
  final double aspect;
  final double displayWidth;
  final bool isCurrent;
  final int renderPriority;
  final double devicePixelRatio;
  final _PageRenderer renderer;

  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  Uint8List? _bytes;
  bool _failed = false;
  int _loadedRenderWidth = 0;
  int _requestedRenderWidth = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PdfPageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextWidth = _targetRenderWidth();
    if (oldWidget.renderer != widget.renderer ||
        oldWidget.pageNumber != widget.pageNumber) {
      _bytes = null;
      _loadedRenderWidth = 0;
      _requestedRenderWidth = 0;
      _failed = false;
      _resolve();
      return;
    }
    if (nextWidth > _loadedRenderWidth && nextWidth != _requestedRenderWidth) {
      _failed = false;
      _resolve();
      return;
    }
    if (_bytes == null &&
        oldWidget.renderPriority != widget.renderPriority &&
        _requestedRenderWidth > 0) {
      widget.renderer.prioritize(
        pageNumber: widget.pageNumber,
        renderWidth: _requestedRenderWidth,
        priority: widget.renderPriority,
      );
    }
  }

  int _targetRenderWidth() {
    return _targetRenderWidthFor(widget.displayWidth, widget.devicePixelRatio);
  }

  Future<void> _resolve() async {
    final renderWidth = _targetRenderWidth();
    if (_bytes != null && _loadedRenderWidth >= renderWidth) {
      _requestedRenderWidth = renderWidth;
      return;
    }
    _requestedRenderWidth = renderWidth;
    try {
      final bytes = await widget.renderer.page(
        pageNumber: widget.pageNumber,
        renderWidth: renderWidth,
        aspect: widget.aspect,
        priority: widget.renderPriority,
      );
      if (!mounted || _requestedRenderWidth != renderWidth) return;
      if (bytes.isEmpty) {
        if (_bytes == null) setState(() => _failed = true);
      } else {
        setState(() {
          _bytes = bytes;
          _loadedRenderWidth = renderWidth;
          _failed = false;
        });
      }
    } catch (_) {
      if (!mounted || _requestedRenderWidth != renderWidth) return;
      if (_bytes == null) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.displayWidth * widget.aspect;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: widget.displayWidth,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: widget.isCurrent
              ? _kSidebarSelected.withValues(alpha: 0.22)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _failed
          ? const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF6B7280),
                size: 36,
              ),
            )
          : _bytes == null
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true),
                if (_requestedRenderWidth > _loadedRenderWidth)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: _kSidebarSelected.withValues(alpha: 0.58),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PdfPreviewToolbar extends StatefulWidget {
  const _PdfPreviewToolbar({
    required this.fileName,
    required this.currentPage,
    required this.pageCount,
    required this.zoomPercent,
    required this.sidebarVisible,
    required this.canToggleSidebar,
    required this.onPrev,
    required this.onNext,
    required this.onJumpToPage,
    required this.onToggleSidebar,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitWidth,
  });

  final String fileName;
  final int currentPage;
  final int pageCount;
  final int zoomPercent;
  final bool sidebarVisible;
  final bool canToggleSidebar;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int> onJumpToPage;
  final VoidCallback onToggleSidebar;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onFitWidth;

  @override
  State<_PdfPreviewToolbar> createState() => _PdfPreviewToolbarState();
}

class _PdfPreviewToolbarState extends State<_PdfPreviewToolbar> {
  late final TextEditingController _pageController;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(text: '${widget.currentPage}');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _PdfPreviewToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage && !_focusNode.hasFocus) {
      _pageController.text = '${widget.currentPage}';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitPageInput();
    } else {
      _pageController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _pageController.text.length,
      );
    }
  }

  void _commitPageInput() {
    final value = int.tryParse(_pageController.text);
    if (value != null && value >= 1 && value <= widget.pageCount) {
      widget.onJumpToPage(value);
    } else {
      _pageController.text = '${widget.currentPage}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kToolbarColor,
      child: Container(
        height: _kToolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF141414))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTitle = constraints.maxWidth >= 610;
            final showPageText = constraints.maxWidth >= 430;
            final showZoomControls = constraints.maxWidth >= 300;
            final showFitButton = constraints.maxWidth >= 370;

            return Row(
              children: [
                if (widget.canToggleSidebar)
                  _ToolbarIconButton(
                    tooltip: widget.sidebarVisible
                        ? 'Ocultar miniaturas'
                        : 'Mostrar miniaturas',
                    icon: widget.sidebarVisible
                        ? Icons.view_sidebar
                        : Icons.view_sidebar_outlined,
                    onPressed: widget.onToggleSidebar,
                  ),
                if (showTitle) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Tooltip(
                      message: widget.fileName,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.fileName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            'Página ${widget.currentPage} de ${widget.pageCount}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.58),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                _ToolbarCluster(
                  children: [
                    _ToolbarIconButton(
                      tooltip: 'Página anterior',
                      icon: Icons.chevron_left,
                      onPressed: widget.onPrev,
                    ),
                    _ToolbarDivider(),
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _pageController,
                        focusNode: _focusNode,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFF1C1C1C),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                            borderSide: BorderSide(color: _kToolbarStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                            borderSide: BorderSide(color: _kToolbarStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                            borderSide: BorderSide(color: Colors.white70),
                          ),
                        ),
                        onSubmitted: (_) {
                          _commitPageInput();
                          _focusNode.unfocus();
                        },
                      ),
                    ),
                    if (showPageText)
                      Padding(
                        padding: const EdgeInsets.only(left: 7, right: 4),
                        child: Text(
                          '/ ${widget.pageCount}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.64),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _ToolbarDivider(),
                    _ToolbarIconButton(
                      tooltip: 'Página siguiente',
                      icon: Icons.chevron_right,
                      onPressed: widget.onNext,
                    ),
                  ],
                ),
                if (showZoomControls) ...[
                  const SizedBox(width: 8),
                  _ToolbarCluster(
                    children: [
                      _ToolbarIconButton(
                        tooltip: 'Alejar',
                        icon: Icons.zoom_out,
                        onPressed: widget.onZoomOut,
                      ),
                      _ToolbarDivider(),
                      Tooltip(
                        message: 'Ajustar al ancho',
                        child: InkWell(
                          onTap: widget.onFitWidth,
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(
                            width: 56,
                            height: 36,
                            child: Center(
                              child: Text(
                                '${widget.zoomPercent}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _ToolbarDivider(),
                      _ToolbarIconButton(
                        tooltip: 'Acercar',
                        icon: Icons.zoom_in,
                        onPressed: widget.onZoomIn,
                      ),
                    ],
                  ),
                ],
                if (showFitButton) ...[
                  const SizedBox(width: 8),
                  _ToolbarCluster(
                    children: [
                      _ToolbarIconButton(
                        tooltip: 'Ajustar al ancho',
                        icon: Icons.fit_screen,
                        onPressed: widget.onFitWidth,
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ToolbarCluster extends StatelessWidget {
  const _ToolbarCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: _kToolbarControl,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kToolbarStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 22, color: _kToolbarStroke);
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 20,
        color: Colors.white.withValues(alpha: 0.82),
        disabledColor: Colors.white.withValues(alpha: 0.26),
        hoverColor: _kToolbarControlHover,
        highlightColor: Colors.white.withValues(alpha: 0.08),
        icon: Icon(icon),
      ),
    );
  }
}

class _PdfThumbnailSidebar extends StatefulWidget {
  const _PdfThumbnailSidebar({
    required this.pageCount,
    required this.currentPage,
    required this.thumbnails,
    required this.onPageSelected,
  });

  final int pageCount;
  final int currentPage;
  final _ThumbnailRenderer? thumbnails;
  final ValueChanged<int> onPageSelected;

  @override
  State<_PdfThumbnailSidebar> createState() => _PdfThumbnailSidebarState();
}

class _PdfThumbnailSidebarState extends State<_PdfThumbnailSidebar> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(false),
    );
  }

  @override
  void didUpdateWidget(covariant _PdfThumbnailSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToCurrent(true),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent(bool animated) {
    if (!_scrollController.hasClients || widget.pageCount <= 0) return;
    final position = _scrollController.position;
    final raw =
        (widget.currentPage - 1) * _kThumbnailTileExtent -
        position.viewportDimension * 0.22;
    final target = raw.clamp(0.0, position.maxScrollExtent).toDouble();
    if (animated) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSidebarWidth,
      color: _kSidebarColor,
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF171717))),
            ),
            child: Text(
              'Miniaturas',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                primary: false,
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemExtent: _kThumbnailTileExtent,
                itemCount: widget.pageCount,
                itemBuilder: (context, index) {
                  final pageNumber = index + 1;
                  return _ThumbnailTile(
                    key: ValueKey('thumb-$pageNumber'),
                    pageNumber: pageNumber,
                    isSelected: pageNumber == widget.currentPage,
                    renderer: widget.thumbnails,
                    onTap: () => widget.onPageSelected(pageNumber),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailTile extends StatefulWidget {
  const _ThumbnailTile({
    super.key,
    required this.pageNumber,
    required this.isSelected,
    required this.renderer,
    required this.onTap,
  });

  final int pageNumber;
  final bool isSelected;
  final _ThumbnailRenderer? renderer;
  final VoidCallback onTap;

  @override
  State<_ThumbnailTile> createState() => _ThumbnailTileState();
}

class _ThumbnailTileState extends State<_ThumbnailTile> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderer != widget.renderer ||
        oldWidget.pageNumber != widget.pageNumber) {
      _bytes = null;
      _failed = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final renderer = widget.renderer;
    if (renderer == null) return;
    try {
      final bytes = await renderer.thumbnail(widget.pageNumber);
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _failed = true);
      } else {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
            decoration: BoxDecoration(
              color: widget.isSelected ? _kSidebarSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Container(
                  width: _kThumbnailWidth,
                  height: _kThumbnailHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: widget.isSelected
                          ? Colors.white.withValues(alpha: 0.54)
                          : Colors.black.withValues(alpha: 0.26),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _failed
                      ? const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF6B7280),
                            size: 28,
                          ),
                        )
                      : _bytes == null
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        )
                      : Image.memory(
                          _bytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.pageNumber}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(
                      alpha: widget.isSelected ? 1 : 0.64,
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenderQueue {
  final _jobs = <_RenderJob>[];
  var _running = false;
  var _sequence = 0;

  Future<T> run<T>({
    required String key,
    required int priority,
    required Future<T> Function() task,
  }) {
    final completer = Completer<T>();
    _jobs.add(
      _RenderJob(
        key: key,
        priority: priority,
        sequence: _sequence++,
        task: () async => task(),
        complete: (value) {
          if (!completer.isCompleted) completer.complete(value as T);
        },
        completeError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );
    _pump();
    return completer.future;
  }

  void boost(String key, int priority) {
    for (final job in _jobs) {
      if (job.key == key && priority > job.priority) {
        job.priority = priority;
      }
    }
  }

  void _pump() {
    if (_running || _jobs.isEmpty) return;
    _jobs.sort((a, b) {
      final priorityOrder = b.priority.compareTo(a.priority);
      if (priorityOrder != 0) return priorityOrder;
      return a.sequence.compareTo(b.sequence);
    });
    final job = _jobs.removeAt(0);
    _running = true;
    job.task().then(job.complete, onError: job.completeError).whenComplete(() {
      _running = false;
      _pump();
    });
  }
}

class _RenderJob {
  _RenderJob({
    required this.key,
    required this.priority,
    required this.sequence,
    required this.task,
    required this.complete,
    required this.completeError,
  });

  final String key;
  int priority;
  final int sequence;
  final Future<Object?> Function() task;
  final void Function(Object? value) complete;
  final void Function(Object error, StackTrace stackTrace) completeError;
}

class _PageRenderer {
  _PageRenderer(this._document, this._queue);

  static const int _maxCachedPages = 28;

  final PdfDocument _document;
  final _RenderQueue _queue;
  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List>> _pending = {};
  final List<String> _cacheOrder = [];
  bool _disposed = false;

  Future<Uint8List> page({
    required int pageNumber,
    required int renderWidth,
    required double aspect,
    required int priority,
  }) {
    if (_disposed) {
      return Future.error(StateError('renderer disposed'));
    }
    final key = '$pageNumber@$renderWidth';
    final reusable = _reusableCached(pageNumber, renderWidth);
    if (reusable != null) return Future.value(reusable);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);
    final pending = _pending[key];
    if (pending != null) {
      _queue.boost(key, priority);
      return pending;
    }

    final future = _renderInternal(
      key: key,
      pageNumber: pageNumber,
      renderWidth: renderWidth,
      aspect: aspect,
      priority: priority,
    );
    _pending[key] = future;
    return future;
  }

  void precacheAround({
    required int centerPage,
    required List<double> aspects,
    required double displayWidth,
    required double devicePixelRatio,
  }) {
    if (_disposed || aspects.isEmpty) return;
    final renderWidth = _targetRenderWidthFor(displayWidth, devicePixelRatio);
    for (final delta in const [0, 1, -1, 2, -2]) {
      final pageNumber = centerPage + delta;
      if (pageNumber < 1 || pageNumber > aspects.length) continue;
      final key = '$pageNumber@$renderWidth';
      if (_cache.containsKey(key) || _pending.containsKey(key)) continue;
      unawaited(
        page(
          pageNumber: pageNumber,
          renderWidth: renderWidth,
          aspect: aspects[pageNumber - 1],
          priority: 7000 - delta.abs(),
        ).catchError((_) => Uint8List(0)),
      );
    }
  }

  void prioritize({
    required int pageNumber,
    required int renderWidth,
    required int priority,
  }) {
    _queue.boost('$pageNumber@$renderWidth', priority);
  }

  Uint8List? _reusableCached(int pageNumber, int targetWidth) {
    final prefix = '$pageNumber@';
    Uint8List? bestAtOrAbove;
    var bestAtOrAboveWidth = 1 << 30;

    for (final entry in _cache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final width = int.tryParse(entry.key.substring(prefix.length));
      if (width == null) continue;
      if (width >= targetWidth && width < bestAtOrAboveWidth) {
        bestAtOrAbove = entry.value;
        bestAtOrAboveWidth = width;
      }
    }

    return bestAtOrAbove;
  }

  Future<Uint8List> _renderInternal({
    required String key,
    required int pageNumber,
    required int renderWidth,
    required double aspect,
    required int priority,
  }) async {
    return _queue.run(
      key: key,
      priority: priority,
      task: () async {
        PdfPage? page;
        try {
          if (_disposed) return Uint8List(0);
          page = await _document.getPage(pageNumber);
          final width = renderWidth.toDouble();
          final image = await page.render(
            width: width,
            height: width * aspect,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          final bytes = image?.bytes ?? Uint8List(0);
          if (!_disposed) _remember(key, bytes);
          return bytes;
        } finally {
          _pending.remove(key);
          await page?.close();
        }
      },
    );
  }

  void _remember(String key, Uint8List bytes) {
    _cache[key] = bytes;
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
    while (_cacheOrder.length > _maxCachedPages) {
      final old = _cacheOrder.removeAt(0);
      _cache.remove(old);
    }
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _pending.clear();
    _cacheOrder.clear();
  }
}

int _targetRenderWidthFor(double displayWidth, double devicePixelRatio) {
  const bucket = 160;
  final raw = (displayWidth * devicePixelRatio).clamp(420.0, 2600.0);
  return ((raw / bucket).ceil() * bucket).clamp(420, 2600).toInt();
}

class _ThumbnailRenderer {
  _ThumbnailRenderer(this._document, this._queue);

  final PdfDocument _document;
  final _RenderQueue _queue;
  final Map<int, Uint8List> _cache = {};
  final Map<int, Future<Uint8List>> _pending = {};
  bool _disposed = false;

  Future<Uint8List> thumbnail(int pageNumber) {
    if (_disposed) {
      return Future.error(StateError('renderer disposed'));
    }
    final cached = _cache[pageNumber];
    if (cached != null) return Future.value(cached);
    final pending = _pending[pageNumber];
    if (pending != null) return pending;

    final future = _renderInternal(pageNumber);
    _pending[pageNumber] = future;
    return future;
  }

  Future<Uint8List> _renderInternal(int pageNumber) async {
    return _queue.run(
      key: 'thumb-$pageNumber',
      priority: -1000,
      task: () async {
        PdfPage? page;
        try {
          if (_disposed) return Uint8List(0);
          page = await _document.getPage(pageNumber);
          final aspect = page.width == 0 ? 1.35 : page.height / page.width;
          const renderWidth = 220.0;
          final image = await page.render(
            width: renderWidth,
            height: renderWidth * aspect,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          final bytes = image?.bytes ?? Uint8List(0);
          if (!_disposed) _cache[pageNumber] = bytes;
          return bytes;
        } finally {
          _pending.remove(pageNumber);
          await page?.close();
        }
      },
    );
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _pending.clear();
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
