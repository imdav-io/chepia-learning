import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

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
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  late final AudioPlayer _player;
  Timer? _persistTimer;
  StreamSubscription<PlayerState>? _playerStateSub;
  Object? _error;
  String? _restoredUrl;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _loadUrl();
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
      _loadUrl();
      return;
    }
    if (oldWidget.restorePositionSec != widget.restorePositionSec) {
      _restorePositionIfNeeded();
    }
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

  @override
  void dispose() {
    _persistTimer?.cancel();
    _playerStateSub?.cancel();
    if (widget.onPositionPersist != null && _player.position.inSeconds > 0) {
      widget.onPositionPersist!(
        _player.position.inSeconds,
        _player.duration?.inSeconds,
      );
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasUrl = widget.audioUrl != null;

    return Material(
      elevation: 6,
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
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
                                        SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 3,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6,
                                                ),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                  overlayRadius: 12,
                                                ),
                                          ),
                                          child: Slider(
                                            value: clamped.inMilliseconds
                                                .toDouble(),
                                            max: maxMs,
                                            onChanged: (v) => _player.seek(
                                              Duration(milliseconds: v.toInt()),
                                            ),
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
