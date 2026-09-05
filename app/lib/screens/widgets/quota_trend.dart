import 'package:flutter/material.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/theme_define.dart';

class QuotaTrend extends StatelessWidget {
  const QuotaTrend({super.key, required this.points});

  final List<BalancePoint> points;

  @override
  Widget build(BuildContext context) {
    final latest = points.isEmpty ? 0.0 : points.last.value;
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('7 日额度趋势', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('来自最近同步', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                ],
              ),
            ),
            Text(
              formatCurrency(latest),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 86,
            width: double.infinity,
            child: CustomPaint(painter: _TrendPainter(points.map((point) => point.value).toList())),
          ),
        ],
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = (max - min).abs();
    final paddedMin = (min - (span * 0.2 < 1 ? 1 : span * 0.2)).clamp(0, double.infinity);
    final paddedMax = max + (span * 0.2 < 1 ? 1 : span * 0.2);
    final denom = paddedMax - paddedMin <= 0 ? 1.0 : paddedMax - paddedMin;
    Offset pointAt(int index) {
      final x = values.length == 1 ? size.width / 2 : size.width * index / (values.length - 1);
      final y = 8 + ((paddedMax - values[index]) / denom) * (size.height - 28);
      return Offset(x, y);
    }

    final dash = Paint()
      ..color = const Color(0x2E7D8490)
      ..strokeWidth = 1;
    _dashLine(canvas, Offset(0, size.height - 20), Offset(size.width, size.height - 20), dash);

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pointAt(i).dx, pointAt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(pointAt(values.length - 1).dx, size.height - 20)
      ..lineTo(pointAt(0).dx, size.height - 20)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x38FA2C19), Color(0x03FA2C19)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = ThemeDefine.kColorPrimary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
    canvas.drawCircle(last, 3.2, Paint()..color = ThemeDefine.kColorPrimary);
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 5.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(Offset(x, a.dy), Offset((x + dash).clamp(a.dx, b.dx), a.dy), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}
