import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class LessonAudioPlayer extends StatefulWidget {
  const LessonAudioPlayer({super.key, required this.audioUrl});
  final String? audioUrl;

  @override
  State<LessonAudioPlayer> createState() => _LessonAudioPlayerState();
}

class _LessonAudioPlayerState extends State<LessonAudioPlayer> {
  late final AudioPlayer _player;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _loadUrl();
  }

  @override
  void didUpdateWidget(covariant LessonAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _loadUrl();
    }
  }

  Future<void> _loadUrl() async {
    final url = widget.audioUrl;
    if (url == null) return;
    try {
      await _player.setUrl(url);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
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
    if (widget.audioUrl == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esta lección aún no tiene audio asociado.\nSube uno con upload-content.mjs y registra el asset en Supabase.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No se pudo cargar el audio: $_error', textAlign: TextAlign.center),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.headphones, size: 96),
          const SizedBox(height: 24),
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (_, durationSnap) {
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (_, positionSnap) {
                  final duration = durationSnap.data ?? Duration.zero;
                  final position = positionSnap.data ?? Duration.zero;
                  final clamped = position > duration ? duration : position;
                  return Column(
                    children: [
                      Slider(
                        value: clamped.inMilliseconds.toDouble(),
                        max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                        onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(clamped)),
                            Text(_fmt(duration)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 36,
                onPressed: () => _player.seek(_player.position - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 16),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  final processing = snap.data?.processingState;
                  if (processing == ProcessingState.loading ||
                      processing == ProcessingState.buffering) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  return IconButton.filled(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    iconSize: 40,
                    onPressed: () {
                      if (playing) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                    },
                  );
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 36,
                onPressed: () => _player.seek(_player.position + const Duration(seconds: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [0.75, 1.0, 1.25, 1.5].map((s) {
              return StreamBuilder<double>(
                stream: _player.speedStream,
                builder: (_, snap) {
                  final selected = (snap.data ?? 1.0) == s;
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: selected,
                    onSelected: (_) => _player.setSpeed(s),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
