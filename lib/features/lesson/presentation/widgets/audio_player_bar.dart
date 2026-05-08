import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../app/route_observer.dart';

typedef AudioPositionPersist = void Function(int positionSec, int? durationSec);

class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({
    super.key,
    required this.audioUrl,
    required this.title,
    this.onPositionPersist,
    this.restorePositionSec,
  });
  final String? audioUrl;
  final String title;

  /// Llamado cada ~5s con el segundo actual de reproducción para persistir.
  final AudioPositionPersist? onPositionPersist;

  /// Si se provee, al cargar la URL se hace seek a este segundo.
  final int? restorePositionSec;

  @override
  State<AudioPlayerBar> createState() => AudioPlayerBarState();
}

class AudioPlayerBarState extends State<AudioPlayerBar>
    with RouteAware, WidgetsBindingObserver {
  late final AudioPlayer _player;
  Timer? _persistTimer;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  ModalRoute<dynamic>? _route;
  Object? _error;
  String? _restoredUrl;
  Duration? _loopStart;
  Duration? _loopEnd;
  bool _segmentSeeking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = AudioPlayer();
    _loadUrl();
    _positionSub = _player.positionStream.listen(_handlePositionTick);
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          widget.onPositionPersist != null) {
        final duration = _player.duration?.inSeconds;
        final position = duration ?? _player.position.inSeconds;
        if (position > 0) {
          widget.onPositionPersist!(position, duration);
        }
      }
    });
    _persistTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing && widget.onPositionPersist != null) {
        widget.onPositionPersist!(
          _player.position.inSeconds,
          _player.duration?.inSeconds,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant AudioPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _clearSegmentLoop(notify: false);
      _loadUrl();
      return;
    }
    if (oldWidget.restorePositionSec != widget.restorePositionSec) {
      _restorePositionIfNeeded();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (nextRoute == null || nextRoute == _route) return;
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    _route = nextRoute;
    appRouteObserver.subscribe(this, nextRoute);
  }

  Future<void> _loadUrl() async {
    final url = widget.audioUrl;
    setState(() => _error = null);
    _restoredUrl = null;
    if (url == null) {
      await _player.stop();
      return;
    }
    try {
      await _player.setUrl(url);
      if (!mounted || widget.audioUrl != url) return;
      await _restorePositionIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _restorePositionIfNeeded() async {
    final url = widget.audioUrl;
    final restore = widget.restorePositionSec;
    if (url == null || restore == null || restore <= 0 || _restoredUrl == url) {
      return;
    }
    try {
      final durationSec = _player.duration?.inSeconds;
      final target = durationSec != null && durationSec > 0
          ? restore.clamp(0, durationSec).toInt()
          : restore;
      await _player.seek(Duration(seconds: target));
      _restoredUrl = url;
      widget.onPositionPersist?.call(target, durationSec);
    } catch (_) {
      // El restore es una mejora de UX; si falla, dejamos reproducir desde 0.
    }
  }

  Future<void> _toggleRepeat(LoopMode mode) async {
    await _player.setLoopMode(
      mode == LoopMode.one ? LoopMode.off : LoopMode.one,
    );
  }

  void _handlePositionTick(Duration position) {
    final start = _loopStart;
    final end = _loopEnd;
    if (start == null || end == null || end <= start) return;
    if (_segmentSeeking || position < end) return;
    _segmentSeeking = true;
    unawaited(
      _player.seek(start).whenComplete(() {
        _segmentSeeking = false;
      }),
    );
  }

  Future<void> _repeatLastFiveSeconds() async {
    final target = _player.position - const Duration(seconds: 5);
    await _player.seek(target.isNegative ? Duration.zero : target);
  }

  void _markSegmentStart() {
    final position = _player.position;
    setState(() {
      _loopStart = position;
      if (_loopEnd != null && _loopEnd! <= position) {
        _loopEnd = null;
      }
    });
  }

  void _markSegmentEnd() {
    final position = _player.position;
    setState(() {
      if (_loopStart == null || position > _loopStart!) {
        _loopEnd = position;
      } else {
        _loopStart = position;
        _loopEnd = null;
      }
    });
  }

  void _clearSegmentLoop({bool notify = true}) {
    if (!notify) {
      _loopStart = null;
      _loopEnd = null;
      return;
    }
    setState(() {
      _loopStart = null;
      _loopEnd = null;
    });
  }

  void _persistCurrentPosition() {
    if (widget.onPositionPersist != null && _player.position.inSeconds > 0) {
      widget.onPositionPersist!(
        _player.position.inSeconds,
        _player.duration?.inSeconds,
      );
    }
  }

  Future<void> pauseAndPersist() async {
    _persistCurrentPosition();
    try {
      await _player.pause();
    } catch (_) {
      // La pausa es defensiva al salir de la ruta; si falla, no bloqueamos UI.
    }
  }

  @override
  void didPushNext() {
    unawaited(pauseAndPersist());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(pauseAndPersist());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _persistTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    // Pausa síncrona inmediata: se aplica antes del siguiente frame, evitando
    // que el audio siga sonando mientras stop+dispose terminan en background.
    _persistCurrentPosition();
    unawaited(_player.pause().catchError((Object _) {}));
    unawaited(
      _player
          .stop()
          .catchError((Object _) {})
          .whenComplete(() => _player.dispose()),
    );
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _practiceTooltip() {
    final start = _loopStart;
    final end = _loopEnd;
    if (start != null && end != null) {
      return 'Loop A-B activo: ${_fmt(start)} a ${_fmt(end)}';
    }
    if (start != null) {
      return 'Inicio A marcado en ${_fmt(start)}. Marca B para repetir el segmento.';
    }
    return 'Herramientas de escucha: repetir 5s y loop A-B';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasUrl = widget.audioUrl != null;

    return Material(
      elevation: 6,
      color: colors.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.primary.withValues(alpha: 0.16)),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: !hasUrl
              ? Row(
                  children: [
                    const Icon(Icons.headphones_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Selecciona una lección con audio',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (_, snap) {
                        final playing = snap.data?.playing ?? false;
                        final processing = snap.data?.processingState;
                        if (processing == ProcessingState.loading ||
                            processing == ProcessingState.buffering) {
                          return const SizedBox(
                            width: 48,
                            height: 48,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return IconButton.filled(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          iconSize: 28,
                          onPressed: () =>
                              playing ? _player.pause() : _player.play(),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      tooltip: 'Atrás 10s',
                      onPressed: () => _player.seek(
                        _player.position - const Duration(seconds: 10),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      tooltip: 'Adelante 10s',
                      onPressed: () => _player.seek(
                        _player.position + const Duration(seconds: 10),
                      ),
                    ),
                    StreamBuilder<LoopMode>(
                      stream: _player.loopModeStream,
                      builder: (_, snap) {
                        final loopMode = snap.data ?? LoopMode.off;
                        final repeatEnabled = loopMode == LoopMode.one;
                        return IconButton(
                          icon: Icon(
                            repeatEnabled ? Icons.repeat_on : Icons.repeat,
                          ),
                          tooltip: repeatEnabled
                              ? 'No repetir audio'
                              : 'Repetir audio',
                          color: repeatEnabled ? colors.primary : null,
                          isSelected: repeatEnabled,
                          selectedIcon: const Icon(Icons.repeat_on),
                          onPressed: () => _toggleRepeat(loopMode),
                        );
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: _practiceTooltip(),
                      onSelected: (value) {
                        switch (value) {
                          case 'repeat5':
                            _repeatLastFiveSeconds();
                            break;
                          case 'markA':
                            _markSegmentStart();
                            break;
                          case 'markB':
                            _markSegmentEnd();
                            break;
                          case 'clear':
                            _clearSegmentLoop();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'repeat5',
                          child: ListTile(
                            leading: Icon(Icons.replay_5),
                            title: Text('Repetir últimos 5s'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'markA',
                          child: ListTile(
                            leading: const Icon(Icons.looks_one_outlined),
                            title: const Text('Marcar inicio A'),
                            subtitle: _loopStart == null
                                ? null
                                : Text(_fmt(_loopStart!)),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'markB',
                          child: ListTile(
                            leading: const Icon(Icons.looks_two_outlined),
                            title: const Text('Marcar fin B'),
                            subtitle: _loopEnd == null
                                ? null
                                : Text(_fmt(_loopEnd!)),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          enabled: _loopStart != null || _loopEnd != null,
                          child: const ListTile(
                            leading: Icon(Icons.close),
                            title: Text('Limpiar A-B'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.hearing_outlined,
                          color: _loopStart != null && _loopEnd != null
                              ? colors.primary
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (_error != null)
                            Text(
                              'Error al cargar audio',
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 12,
                              ),
                            )
                          else
                            StreamBuilder<Duration?>(
                              stream: _player.durationStream,
                              builder: (_, dSnap) {
                                final duration = dSnap.data ?? Duration.zero;
                                return StreamBuilder<Duration>(
                                  stream: _player.positionStream,
                                  builder: (_, pSnap) {
                                    final pos = pSnap.data ?? Duration.zero;
                                    final clamped = pos > duration
                                        ? duration
                                        : pos;
                                    final maxMs = duration.inMilliseconds
                                        .toDouble()
                                        .clamp(1.0, double.infinity);
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _AudioPositionSlider(
                                          position: clamped,
                                          duration: duration,
                                          loopStart: _loopStart,
                                          loopEnd: _loopEnd,
                                          maxMilliseconds: maxMs,
                                          onChanged: (v) => _player.seek(
                                            Duration(milliseconds: v.toInt()),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _fmt(clamped),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              Text(
                                                _fmt(duration),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StreamBuilder<double>(
                      stream: _player.speedStream,
                      builder: (_, snap) {
                        final speed = snap.data ?? 1.0;
                        return PopupMenuButton<double>(
                          tooltip: 'Velocidad',
                          initialValue: speed,
                          onSelected: _player.setSpeed,
                          itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                              .map(
                                (s) => PopupMenuItem(
                                  value: s,
                                  child: Text('${s}x'),
                                ),
                              )
                              .toList(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '${speed}x',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AudioPositionSlider extends StatelessWidget {
  const _AudioPositionSlider({
    required this.position,
    required this.duration,
    required this.loopStart,
    required this.loopEnd,
    required this.maxMilliseconds,
    required this.onChanged,
  });

  final Duration position;
  final Duration duration;
  final Duration? loopStart;
  final Duration? loopEnd;
  final double maxMilliseconds;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: position.inMilliseconds.toDouble(),
                max: maxMilliseconds,
                onChanged: onChanged,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SegmentLoopPainter(
                  startRatio: _ratioFor(loopStart),
                  endRatio: _ratioFor(loopEnd),
                  color: colors.primary,
                  labelColor: colors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _ratioFor(Duration? marker) {
    if (marker == null || duration.inMilliseconds <= 0) return null;
    final value = marker.inMilliseconds.clamp(0, duration.inMilliseconds);
    return value / duration.inMilliseconds;
  }
}

class _SegmentLoopPainter extends CustomPainter {
  const _SegmentLoopPainter({
    required this.startRatio,
    required this.endRatio,
    required this.color,
    required this.labelColor,
  });

  final double? startRatio;
  final double? endRatio;
  final Color color;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final start = startRatio;
    final end = endRatio;
    if (size.width <= 0 || (start == null && end == null)) return;

    const horizontalInset = 24.0;
    final usableWidth = (size.width - horizontalInset * 2).clamp(
      0.0,
      double.infinity,
    );
    final y = size.height / 2;

    double xFor(double ratio) => horizontalInset + usableWidth * ratio;

    if (start != null && end != null && end > start) {
      final left = xFor(start);
      final right = xFor(end);
      final rangePaint = Paint()..color = color.withValues(alpha: 0.16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y - 9, right - left, 18),
          const Radius.circular(99),
        ),
        rangePaint,
      );
    }

    if (start != null) {
      _drawMarker(canvas, Offset(xFor(start), y), 'A');
    }
    if (end != null) {
      _drawMarker(canvas, Offset(xFor(end), y), 'B');
    }
  }

  void _drawMarker(Canvas canvas, Offset center, String label) {
    final markerPaint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy - 12),
      Offset(center.dx, center.dy + 12),
      markerPaint,
    );
    canvas.drawCircle(center, 4, Paint()..color = color);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - 17),
        width: 16,
        height: 14,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(labelRect, Paint()..color = color);
    textPainter.paint(
      canvas,
      Offset(
        labelRect.outerRect.center.dx - textPainter.width / 2,
        labelRect.outerRect.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _SegmentLoopPainter oldDelegate) {
    return startRatio != oldDelegate.startRatio ||
        endRatio != oldDelegate.endRatio ||
        color != oldDelegate.color ||
        labelColor != oldDelegate.labelColor;
  }
}
