import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);
  final Color color;

  Path _star(Offset c, double r) {
    final p = Path()..moveTo(c.dx, c.dy - r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = color;
    final c = s.center(Offset.zero);
    canvas.drawPath(_star(c.translate(-s.width * 0.04, s.height * 0.04), s.width * 0.3), paint);
    canvas.drawPath(_star(Offset(s.width * 0.74, s.height * 0.27), s.width * 0.12), paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}

/// Small static brand mark (no animation => zero per-frame cost).
class AiMark extends StatelessWidget {
  const AiMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Brand.gradient),
        child: CustomPaint(painter: const _SparklePainter(Colors.white)),
      );
}

/// Big animated logo for the empty screen.
class AiOrb extends StatefulWidget {
  const AiOrb({super.key, this.size = 88});
  final double size;
  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s * 1.5,
        height: s * 1.5,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            final pulse = 1 + 0.05 * math.sin(t * 2 * math.pi);
            return Stack(alignment: Alignment.center, children: [
              Container(
                width: s * 1.3 * pulse,
                height: s * 1.3 * pulse,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: Brand.violet.withValues(alpha: 0.35), blurRadius: 50, spreadRadius: 2),
                  BoxShadow(color: Brand.cyan.withValues(alpha: 0.2), blurRadius: 70, spreadRadius: -4),
                ]),
              ),
              Transform.rotate(
                angle: t * 2 * math.pi,
                child: Container(
                  width: s,
                  height: s,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [Brand.violet, Brand.cyan, Brand.pink, Brand.violet]),
                  ),
                ),
              ),
              Container(
                width: s * 0.9,
                height: s * 0.9,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Brand.gradient),
                child: CustomPaint(painter: const _SparklePainter(Colors.white)),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// "● ● ●" typing indicator.
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
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Opacity(
                opacity: 0.25 + 0.75 * math.max(0, math.sin((_c.value * 2 * math.pi) - i * 0.9)).toDouble(),
                child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
              ),
            ),
        ]),
      ),
    );
  }
}
