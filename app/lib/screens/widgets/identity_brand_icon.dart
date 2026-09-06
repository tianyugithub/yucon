import 'package:flutter/material.dart';

class IdentityBrandIcon extends StatelessWidget {
  const IdentityBrandIcon.google({super.key, this.size = 28}) : provider = 'google';

  const IdentityBrandIcon.github({super.key, this.size = 28}) : provider = 'github';

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 8 / 28);
    if (provider == 'github') {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final background = dark ? const Color(0xFFF4F5F7) : const Color(0xFF24292F);
      final mark = dark ? const Color(0xFF24292F) : Colors.white;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: CustomPaint(
          size: Size.square(size * 0.62),
          painter: _GitHubMarkPainter(mark),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        'assets/model-brands/google.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, error, stack) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            color: const Color(0xFF4285F4),
            child: Text(
              'G',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.46,
                height: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GitHubMarkPainter extends CustomPainter {
  const _GitHubMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_githubMark, Paint()..color = color..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GitHubMarkPainter oldDelegate) => oldDelegate.color != color;
}

final _githubMark = Path()
  ..moveTo(12, 0.297)
  ..cubicTo(5.37, 0.297, 0, 5.67, 0, 12.297)
  ..cubicTo(0, 17.6, 3.438, 22.097, 8.205, 23.682)
  ..cubicTo(8.805, 23.795, 9.025, 23.424, 9.025, 23.105)
  ..cubicTo(9.025, 22.82, 9.015, 22.065, 9.01, 21.065)
  ..cubicTo(5.672, 21.789, 4.968, 19.455, 4.968, 19.455)
  ..cubicTo(4.422, 18.07, 3.633, 17.7, 3.633, 17.7)
  ..cubicTo(2.546, 16.956, 3.717, 16.971, 3.717, 16.971)
  ..cubicTo(4.922, 17.055, 5.555, 18.207, 5.555, 18.207)
  ..cubicTo(6.625, 20.042, 8.364, 19.512, 9.05, 19.205)
  ..cubicTo(9.158, 18.429, 9.467, 17.9, 9.81, 17.6)
  ..cubicTo(7.145, 17.3, 4.344, 16.268, 4.344, 11.67)
  ..cubicTo(4.344, 10.36, 4.809, 9.29, 5.579, 8.45)
  ..cubicTo(5.444, 8.147, 5.039, 6.927, 5.684, 5.274)
  ..cubicTo(5.684, 5.274, 6.689, 4.952, 8.984, 6.504)
  ..cubicTo(9.944, 6.237, 10.964, 6.105, 11.984, 6.099)
  ..cubicTo(13.004, 6.105, 14.024, 6.237, 14.984, 6.504)
  ..cubicTo(17.264, 4.952, 18.269, 5.274, 18.269, 5.274)
  ..cubicTo(18.914, 6.927, 18.509, 8.147, 18.389, 8.45)
  ..cubicTo(19.154, 9.29, 19.619, 10.36, 19.619, 11.67)
  ..cubicTo(19.619, 16.28, 16.814, 17.295, 14.144, 17.59)
  ..cubicTo(14.564, 17.95, 14.954, 18.686, 14.954, 19.81)
  ..cubicTo(14.954, 21.416, 14.939, 22.706, 14.939, 23.096)
  ..cubicTo(14.939, 23.411, 15.149, 23.786, 15.764, 23.666)
  ..cubicTo(20.565, 22.092, 24, 17.592, 24, 12.297)
  ..cubicTo(24, 5.67, 18.627, 0.297, 12, 0.297)
  ..close();
