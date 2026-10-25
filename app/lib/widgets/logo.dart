import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The CourseDeep logo, drawn entirely in code (graduation cap + AI sparkles on the brand
/// gradient). Same geometry as branding/generate_icons.py, which makes the Android launcher icon.
class CourseDeepLogo extends StatelessWidget {
  const CourseDeepLogo({super.key, this.size = 64, this.background = true, this.round = false});
  final double size;
  final bool background; // false => only the white glyph (for use on gradients)
  final bool round; // circle instead of rounded square

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(size: Size.square(size), painter: _LogoPainter(background, round)),
      );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.background, this.round);
  final bool background;
  final bool round;

  Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 8; i++) {
      final a = -1.5707963 + i * 0.7853982;
      final rr = i.isEven ? r : r * 0.28;
      final o = Offset(c.dx + rr * _cos(a), c.dy + rr * _sin(a));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  static double _cos(double a) => Offset.fromDirection(a).dx;
  static double _sin(double a) => Offset.fromDirection(a).dy;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    Offset P(double x, double y) => Offset(x * w, y * w);

    if (background) {
      final rect = Offset.zero & s;
      final shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Brand.violet, Color(0xFF4F8CFF), Brand.cyan],
        stops: [0, 0.55, 1],
      ).createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(round ? w / 2 : w * 0.22)),
        Paint()..shader = shader,
      );
    }

    final white = Paint()..color = Colors.white..isAntiAlias = true;
    canvas.drawPath(Path()..addPolygon([P(.50, .30), P(.86, .46), P(.50, .62), P(.14, .46)], true), white);
    canvas.drawPath(
      Path()..addPolygon([P(.28, .55), P(.50, .65), P(.72, .55), P(.72, .68), P(.50, .79), P(.28, .68)], true),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawLine(P(.86, .46), P(.86, .66), Paint()..color = Colors.white..strokeWidth = w * 0.02..strokeCap = StrokeCap.butt);
    canvas.drawCircle(P(.86, .69), w * 0.028, white);
    canvas.drawPath(_star(P(.76, .22), w * .115), white);
    canvas.drawPath(_star(P(.22, .24), w * .055), Paint()..color = Colors.white.withValues(alpha: 0.86));
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.background != background || old.round != round;
}
