import 'package:flutter/material.dart';

enum YuconTabIcon { dashboard, accounts, keys, logs, profile }

class TabIcon extends StatelessWidget {
  const TabIcon({super.key, required this.name, this.size = 18, this.color});

  final YuconTabIcon name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _TabIconPainter(name, color ?? IconTheme.of(context).color ?? Colors.black),
      ),
    );
  }
}

class _TabIconPainter extends CustomPainter {
  _TabIconPainter(this.name, this.color);

  final YuconTabIcon name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s, s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final path = Path();
    switch (name) {
      case YuconTabIcon.dashboard:
        path.addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3.25, 3.25, 17.5, 17.5), const Radius.circular(3)));
        canvas.drawPath(path, stroke);
        canvas.drawLine(const Offset(3.5, 9.25), const Offset(20.5, 9.25), stroke);
        canvas.drawLine(const Offset(9.25, 20.5), const Offset(9.25, 9.5), stroke);
        break;
      case YuconTabIcon.accounts:
        path.addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 4.5, 18, 15), const Radius.circular(2.75)));
        canvas.drawPath(path, stroke);
        canvas.drawCircle(const Offset(8.25, 11.5), 2, stroke);
        canvas.drawLine(const Offset(12.5, 9.25), const Offset(17.5, 9.25), stroke);
        canvas.drawLine(const Offset(12.5, 13), const Offset(17.5, 13), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(6, 16.25)
            ..cubicTo(6.6, 14.95, 7.35, 14.3, 8.25, 14.3)
            ..cubicTo(9.15, 14.3, 9.9, 14.95, 10.5, 16.25),
          stroke,
        );
        break;
      case YuconTabIcon.keys:
        canvas.drawCircle(const Offset(8.5, 12), 3.75, stroke);
        canvas.drawLine(const Offset(11.15, 14.65), const Offset(20.25, 5.55), stroke);
        canvas.drawLine(const Offset(16.5, 9.3), const Offset(18.75, 11.55), stroke);
        canvas.drawLine(const Offset(14.25, 11.55), const Offset(16.5, 13.8), stroke);
        break;
      case YuconTabIcon.logs:
        canvas.drawLine(const Offset(4.5, 7.25), const Offset(4.5, 4.5), stroke);
        canvas.drawLine(const Offset(4.5, 4.5), const Offset(7.25, 4.5), stroke);
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 12), radius: 8.5), -0.85, 5.4, false, stroke);
        canvas.drawLine(const Offset(12, 7.5), const Offset(12, 12), stroke);
        canvas.drawLine(const Offset(12, 12), const Offset(15.25, 14), stroke);
        break;
      case YuconTabIcon.profile:
        canvas.drawCircle(const Offset(12, 8), 3.25, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(5, 20.5)
            ..cubicTo(5.6, 16.95, 8.05, 15, 12, 15)
            ..cubicTo(15.95, 15, 18.4, 16.95, 19, 20.5),
          stroke,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter oldDelegate) =>
      oldDelegate.name != name || oldDelegate.color != color;
}
