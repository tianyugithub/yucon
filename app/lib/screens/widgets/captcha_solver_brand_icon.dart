import 'package:flutter/material.dart';
import 'package:vault/app/api/captcha_solver.dart';
import 'package:vault/app/models/domain.dart';

class CaptchaSolverBrandIcon extends StatelessWidget {
  const CaptchaSolverBrandIcon({
    super.key,
    required this.type,
    this.size = 32,
    this.radius,
  });

  final CaptchaSolverType type;
  final double size;
  final double? radius;

  static Color brandColor(CaptchaSolverType type) {
    switch (type) {
      case CaptchaSolverType.yesCaptcha:
        return const Color(0xFFDE7362);
      case CaptchaSolverType.twoCaptcha:
        return const Color(0xFF3BBBBC);
      case CaptchaSolverType.capMonsterCloud:
        return const Color(0xFF8C77FF);
      case CaptchaSolverType.capSolver:
        return const Color(0xFF69D370);
    }
  }

  static Color brandSoft(CaptchaSolverType type, {required bool dark}) {
    if (dark) {
      return brandColor(type).withValues(alpha: 0.18);
    }
    switch (type) {
      case CaptchaSolverType.yesCaptcha:
        return const Color(0xFFFFF1EE);
      case CaptchaSolverType.twoCaptcha:
        return const Color(0xFFE7F7F6);
      case CaptchaSolverType.capMonsterCloud:
        return const Color(0xFFF1EEFF);
      case CaptchaSolverType.capSolver:
        return const Color(0xFFECF9EE);
    }
  }

  @override
  Widget build(BuildContext context) {
    final corner = radius ?? (size * 10 / 32).clamp(6.0, 14.0);
    final mark = captchaSolverTypeLabel(type).substring(0, 1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: Image.asset(
        captchaSolverIconAsset(type),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, error, stack) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            color: brandColor(type),
            child: Text(
              mark,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          );
        },
      ),
    );
  }
}
