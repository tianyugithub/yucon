import 'package:flutter/material.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';

class PlatformBrandIcon extends StatelessWidget {
  const PlatformBrandIcon({
    super.key,
    required this.type,
    this.size = 32,
    this.radius,
  });

  final PlatformType type;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final preset = getPlatformPreset(type);
    final corner = radius ?? (size * 10 / 32).clamp(6.0, 14.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: Image.asset(
        preset.iconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, error, stack) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            color: Color(preset.color),
            child: Text(
              preset.shortLabel,
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
