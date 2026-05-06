import 'dart:math' as math;

import 'package:flutter/material.dart';

class ContentLoadingScaffold extends StatelessWidget {
  const ContentLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: ContentLoadingView());
  }
}

class ContentLoadingView extends StatefulWidget {
  const ContentLoadingView({
    super.key,
    this.status = 'Preparando lecciones y audios...',
  });

  final String status;

  @override
  State<ContentLoadingView> createState() => _ContentLoadingViewState();
}

class _ContentLoadingViewState extends State<ContentLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF050712)
        : const Color(0xFFF7FBFF);
    final foreground = isDark ? Colors.white : const Color(0xFF101827);
    final muted = foreground.withValues(alpha: 0.7);
    final accent = isDark ? const Color(0xFF35DCEB) : colors.primary;

    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = _controller.value;
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 250,
                        height: 210,
                        child: CustomPaint(
                          painter: _ContentLoadingPainter(
                            progress: progress,
                            accent: accent,
                            foreground: foreground,
                            background: background,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _LoadingProgressRail(
                        progress: progress,
                        accent: accent,
                        trackColor: foreground.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        'CARGANDO...',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.status,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingProgressRail extends StatelessWidget {
  const _LoadingProgressRail({
    required this.progress,
    required this.accent,
    required this.trackColor,
  });

  final double progress;
  final Color accent;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      height: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth * 0.42;
          final left =
              (constraints.maxWidth + segmentWidth) * progress - segmentWidth;

          return ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: trackColor),
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0),
                          accent,
                          accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ContentLoadingPainter extends CustomPainter {
  const _ContentLoadingPainter({
    required this.progress,
    required this.accent,
    required this.foreground,
    required this.background,
  });

  final double progress;
  final Color accent;
  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final lift = -8 * math.sin(progress * math.pi).abs();
    final center = Offset(size.width * 0.5, size.height * 0.55 + lift);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.9),
        width: 130,
        height: 18,
      ),
      shadowPaint,
    );

    _drawFloatingBars(canvas, size, pulse);

    final glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.12 + pulse * 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 150, height: 150),
      glowPaint,
    );

    final bodyPaint = Paint()..color = background;
    final bodyRect = Rect.fromCenter(center: center, width: 112, height: 120);
    canvas.drawOval(bodyRect, bodyPaint);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          accent,
          const Color(0xFF2AF08C),
          const Color(0xFFE655FF).withValues(alpha: 0.85),
        ],
      ).createShader(bodyRect.inflate(12));
    canvas.drawArc(
      bodyRect.inflate(6),
      math.pi * 0.04,
      math.pi * 1.32,
      false,
      rimPaint,
    );

    final capPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFC9CDD3)],
      ).createShader(bodyRect);
    final cap = Path()
      ..moveTo(center.dx - 54, center.dy - 36)
      ..cubicTo(
        center.dx - 22,
        center.dy - 70,
        center.dx + 32,
        center.dy - 68,
        center.dx + 54,
        center.dy - 34,
      )
      ..cubicTo(
        center.dx + 24,
        center.dy - 44,
        center.dx - 12,
        center.dy - 32,
        center.dx - 54,
        center.dy - 36,
      );
    canvas.drawPath(cap, capPaint);

    final eyePaint = Paint()..color = accent;
    final pupilPaint = Paint()..color = const Color(0xFF02030A);
    final eyeOffset = 4 * math.sin(progress * math.pi * 2);
    canvas.drawCircle(
      Offset(center.dx - 27, center.dy - 5 + eyeOffset),
      22,
      eyePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + 28, center.dy - 7 - eyeOffset),
      24,
      eyePaint,
    );
    canvas.drawCircle(
      Offset(center.dx - 36, center.dy - 11 + eyeOffset),
      12,
      pupilPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + 18, center.dy - 13 - eyeOffset),
      13,
      pupilPaint,
    );

    final beakPaint = Paint()..color = foreground.withValues(alpha: 0.88);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 3, center.dy + 30),
        width: 25,
        height: 13,
      ),
      beakPaint,
    );

    final headphonePaint = Paint()
      ..color = foreground.withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - 2),
        width: 120,
        height: 108,
      ),
      math.pi * 1.07,
      math.pi * 0.86,
      false,
      headphonePaint,
    );

    final footPaint = Paint()..color = foreground.withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 38, center.dy + 66),
        width: 30,
        height: 13,
      ),
      footPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 40, center.dy + 68),
        width: 30,
        height: 13,
      ),
      footPaint,
    );
  }

  void _drawFloatingBars(Canvas canvas, Size size, double pulse) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent, accent.withValues(alpha: 0.06)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final spec in const [
      (0.16, 0.48, 42.0),
      (0.28, 0.24, 30.0),
      (0.78, 0.32, 58.0),
      (0.86, 0.56, 34.0),
    ]) {
      final x = size.width * spec.$1;
      final y = size.height * spec.$2;
      final height = spec.$3 + pulse * 8;
      final rect = Rect.fromLTWH(x, y, 15, height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 15, 14),
          const Radius.circular(5),
        ),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ContentLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.foreground != foreground ||
        oldDelegate.background != background;
  }
}
