import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_providers.dart';
import '../../../../shared/services/cache_providers.dart';

const double _kToolbarHeight = 56;
const double _kSidebarWidth = 196;
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

class LessonPageImageReader extends ConsumerStatefulWidget {
  const LessonPageImageReader({
    super.key,
    required this.manifestUrl,
    required this.manifestCacheKey,
    this.startPage,
    this.jumpToPage,
    this.onPageChanged,
  });

  final String manifestUrl;
  final String manifestCacheKey;
  final int? startPage;
  final int? jumpToPage;
  final ValueChanged<int>? onPageChanged;

  @override
  ConsumerState<LessonPageImageReader> createState() =>
      _LessonPageImageReaderState();
}

class _LessonPageImageReaderState extends ConsumerState<LessonPageImageReader> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();
  _PageManifest? _manifest;
  _ImagePageLoader? _loader;
  _ImageLayoutMetrics? _layout;
  Object? _error;
  bool _loading = true;
  var _currentPage = 1;
  int? _pendingPage;
  var _isSidebarVisible = true;
  var _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_syncCurrentPageWithScroll);
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonPageImageReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manifestUrl != widget.manifestUrl ||
        oldWidget.manifestCacheKey != widget.manifestCacheKey) {
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _manifest = null;
      _loader = null;
      _currentPage = 1;
    });

    try {
      final bytes = await ref
          .read(assetCacheProvider)
          .getOrDownload(
            key: widget.manifestCacheKey,
            url: widget.manifestUrl,
            kind: 'page-manifest',
          );
      final manifest = _PageManifest.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      final initialPage = _clampPageValue(
        widget.startPage ?? widget.jumpToPage ?? 1,
        manifest.pages.length,
      );
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _loader = _ImagePageLoader(ref, manifest);
        _currentPage = initialPage;
        _pendingPage = initialPage;
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

  int _clampPage(int page) =>
      _clampPageValue(page, _manifest?.pages.length ?? 0);

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
    if (page != null) _onPageChanged(page);
  }

  void _onPageChanged(int page) {
    if (!mounted || page == _currentPage) return;
    setState(() => _currentPage = page);
    widget.onPageChanged?.call(page);
  }

  void _goToPage(int page) {
    final clamped = _clampPage(page);
    _onPageChanged(clamped);
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
          duration: const Duration(milliseconds: 200),
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

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    final loader = _loader;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || manifest == null || loader == null) {
      return _CenteredMessage(
        message: 'No se pudieron cargar las páginas optimizadas.',
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
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
              _ImageToolbar(
                fileName: '${manifest.bookSlug} pages',
                currentPage: _currentPage,
                pageCount: manifest.pages.length,
                zoomPercent: (_zoomLevel * 100).round(),
                sidebarVisible: sidebarVisible,
                canToggleSidebar: canShowSidebar,
                onPrev: _currentPage > 1
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                onNext: _currentPage < manifest.pages.length
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                onJumpToPage: _goToPage,
                onToggleSidebar: () =>
                    setState(() => _isSidebarVisible = !_isSidebarVisible),
                onZoomIn: _zoomLevel < _kZoomMax - 0.01
                    ? () => _setZoom(_zoomLevel + _kZoomStep)
                    : null,
                onZoomOut: _zoomLevel > _kZoomMin + 0.01
                    ? () => _setZoom(_zoomLevel - _kZoomStep)
                    : null,
                onFitWidth: () => _setZoom(1),
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
                          child: _ImageThumbnailSidebar(
                            pages: manifest.pages,
                            currentPage: _currentPage,
                            loader: loader,
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
                      child: _ImageDocumentViewport(
                        pages: manifest.pages,
                        currentPage: _currentPage,
                        loader: loader,
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

class _ImageDocumentViewport extends StatelessWidget {
  const _ImageDocumentViewport({
    required this.pages,
    required this.currentPage,
    required this.loader,
    required this.zoomLevel,
    required this.verticalController,
    required this.horizontalController,
    required this.onLayout,
  });

  final List<_ImagePage> pages;
  final int currentPage;
  final _ImagePageLoader loader;
  final double zoomLevel;
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final ValueChanged<_ImageLayoutMetrics> onLayout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final fitWidth = (viewportWidth - (_kCanvasInset * 2)).clamp(
          240.0,
          double.infinity,
        );
        final pageWidth = (fitWidth * zoomLevel).clamp(180.0, 4200.0);
        final contentWidth = pageWidth + (_kCanvasInset * 2);
        final layout = _ImageLayoutMetrics(
          pages: pages,
          pageWidth: pageWidth,
          topPadding: _kCanvasInset,
          gap: _kPageGap,
        );
        onLayout(layout);
        loader.precacheAround(currentPage);

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
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        left: _kCanvasInset,
                        right: _kCanvasInset,
                        bottom: index == pages.length - 1 ? 0 : _kPageGap,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _ImagePageTile(
                          key: ValueKey('image-page-${page.pageNumber}'),
                          page: page,
                          displayWidth: pageWidth,
                          isCurrent: page.pageNumber == currentPage,
                          loader: loader,
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

class _ImagePageTile extends StatelessWidget {
  const _ImagePageTile({
    super.key,
    required this.page,
    required this.displayWidth,
    required this.isCurrent,
    required this.loader,
  });

  final _ImagePage page;
  final double displayWidth;
  final bool isCurrent;
  final _ImagePageLoader loader;

  @override
  Widget build(BuildContext context) {
    final height = displayWidth * page.aspect;
    return Container(
      width: displayWidth,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: isCurrent
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
      child: FutureBuilder<Uint8List>(
        future: loader.page(page),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            );
          }
          return Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
        },
      ),
    );
  }
}

class _ImageThumbnailSidebar extends StatefulWidget {
  const _ImageThumbnailSidebar({
    required this.pages,
    required this.currentPage,
    required this.loader,
    required this.onPageSelected,
  });

  final List<_ImagePage> pages;
  final int currentPage;
  final _ImagePageLoader loader;
  final ValueChanged<int> onPageSelected;

  @override
  State<_ImageThumbnailSidebar> createState() => _ImageThumbnailSidebarState();
}

class _ImageThumbnailSidebarState extends State<_ImageThumbnailSidebar> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(false),
    );
  }

  @override
  void didUpdateWidget(covariant _ImageThumbnailSidebar oldWidget) {
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
    if (!_scrollController.hasClients || widget.pages.isEmpty) return;
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
                itemCount: widget.pages.length,
                itemBuilder: (context, index) {
                  final page = widget.pages[index];
                  return _ImageThumbnailTile(
                    page: page,
                    isSelected: page.pageNumber == widget.currentPage,
                    loader: widget.loader,
                    onTap: () => widget.onPageSelected(page.pageNumber),
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

class _ImageThumbnailTile extends StatelessWidget {
  const _ImageThumbnailTile({
    required this.page,
    required this.isSelected,
    required this.loader,
    required this.onTap,
  });

  final _ImagePage page;
  final bool isSelected;
  final _ImagePageLoader loader;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
            decoration: BoxDecoration(
              color: isSelected ? _kSidebarSelected : Colors.transparent,
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
                      color: isSelected
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
                  child: FutureBuilder<Uint8List>(
                    future: loader.page(page),
                    builder: (context, snap) {
                      final bytes = snap.data;
                      if (bytes == null) {
                        return const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        );
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${page.pageNumber}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(
                      alpha: isSelected ? 1 : 0.64,
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

class _ImageToolbar extends StatefulWidget {
  const _ImageToolbar({
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
  State<_ImageToolbar> createState() => _ImageToolbarState();
}

class _ImageToolbarState extends State<_ImageToolbar> {
  late final TextEditingController _pageController;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(text: '${widget.currentPage}');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ImageToolbar oldWidget) {
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
                      InkWell(
                        onTap: widget.onFitWidth,
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(
                          width: 56,
                          height: 36,
                          child: Center(
                            child: Text(
                              '${widget.zoomPercent}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ImageLayoutMetrics {
  _ImageLayoutMetrics({
    required this.pages,
    required this.pageWidth,
    required this.topPadding,
    required this.gap,
  }) {
    var top = topPadding;
    for (final page in pages) {
      pageTops.add(top);
      final height = pageWidth * page.aspect;
      pageHeights.add(height);
      top += height + gap;
    }
  }

  final List<_ImagePage> pages;
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

class _ImagePageLoader {
  _ImagePageLoader(this.ref, this.manifest);

  final WidgetRef ref;
  final _PageManifest manifest;
  final _urlCache = <String, Future<String>>{};
  final _pageCache = <String, Future<Uint8List>>{};

  Future<Uint8List> page(_ImagePage page) {
    return _pageCache.putIfAbsent(page.storagePath, () async {
      final url = await _signedUrl(page.storagePath);
      return ref
          .read(assetCacheProvider)
          .getOrDownload(key: page.storagePath, url: url, kind: 'page-image');
    });
  }

  void precacheAround(int centerPage) {
    for (final delta in const [0, 1, -1, 2, -2, 3]) {
      final pageNumber = centerPage + delta;
      if (pageNumber < 1 || pageNumber > manifest.pages.length) continue;
      unawaited(
        page(manifest.pages[pageNumber - 1]).catchError((_) => Uint8List(0)),
      );
    }
  }

  Future<String> _signedUrl(String storagePath) {
    return _urlCache.putIfAbsent(storagePath, () {
      return ref
          .read(supabaseClientProvider)
          .storage
          .from('content')
          .createSignedUrl(storagePath, 3600);
    });
  }
}

class _PageManifest {
  const _PageManifest({required this.bookSlug, required this.pages});

  final String bookSlug;
  final List<_ImagePage> pages;

  factory _PageManifest.fromJson(Map<String, dynamic> json) {
    final pages =
        (json['pages'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(_ImagePage.fromJson)
            .toList()
          ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    return _PageManifest(
      bookSlug: json['bookSlug'] as String? ?? 'book',
      pages: pages,
    );
  }
}

class _ImagePage {
  const _ImagePage({
    required this.pageNumber,
    required this.storagePath,
    required this.width,
    required this.height,
  });

  final int pageNumber;
  final String storagePath;
  final int width;
  final int height;

  double get aspect => width <= 0 ? 1.35 : height / width;

  factory _ImagePage.fromJson(Map<String, dynamic> json) {
    return _ImagePage(
      pageNumber: (json['pageNumber'] as num).toInt(),
      storagePath: json['storagePath'] as String,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
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
