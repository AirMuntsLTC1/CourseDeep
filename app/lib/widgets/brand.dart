import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'logo.dart';

/// Small static brand mark (no animation => zero per-frame cost).
class AiMark extends StatelessWidget {
  const AiMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => CourseDeepLogo(size: size);
}

/// Hero logo for the empty screen and login. All motion is a compositor-only transform on
/// cached layers (RepaintBoundary + RotationTransition/ScaleTransition) => no per-frame repaint,
/// and no blurred shadows (those were the main cause of dropped frames).
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.size = 84});
  final double size;
  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  late final Animation<double> _pulse = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.05).chain(CurveTween(curve: Curves.easeInOut)), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.96).chain(CurveTween(curve: Curves.easeInOut)), weight: 1),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.55,
      height: s * 1.55,
      child: Stack(alignment: Alignment.center, children: [
        ScaleTransition(
          scale: _pulse,
          child: RepaintBoundary(
            child: Container(
              width: s * 1.55,
              height: s * 1.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Brand.violet.withValues(alpha: 0.38),
                  Brand.cyan.withValues(alpha: 0.10),
                  Colors.transparent,
                ], stops: const [0.25, 0.6, 1]),
              ),
            ),
          ),
        ),
        RotationTransition(
          turns: _c,
          child: RepaintBoundary(child: CustomPaint(size: Size.square(s * 1.18), painter: const _RingPainter())),
        ),
        CourseDeepLogo(size: s),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.width / 2 - 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(colors: [Colors.transparent, Brand.violet, Brand.cyan, Brand.pink, Colors.transparent], stops: [0, 0.25, 0.55, 0.8, 1]).createShader(r);
    canvas.drawArc(r, 0, math.pi * 2, false, p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => false;
}

/// "● ● ●" typing indicator — one painter driven by the animation, no widget rebuilds.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.color, this.size = 6});
  final Color? color;
  final double size;
  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.color ?? Theme.of(context).colorScheme.primary;
    final d = widget.size;
    return RepaintBoundary(
      child: CustomPaint(size: Size(d * 3 + 8, d), painter: _DotsPainter(_c, col, d)),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t, this.color, this.d) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final double d;

  @override
  void paint(Canvas canvas, Size s) {
    for (var i = 0; i < 3; i++) {
      final a = 0.25 + 0.75 * math.max(0, math.sin(t.value * 2 * math.pi - i * 0.9));
      canvas.drawCircle(Offset(d / 2 + i * (d + 4), d / 2), d / 2, Paint()..color = color.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}
