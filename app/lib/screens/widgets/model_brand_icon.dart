import 'package:flutter/material.dart';
import 'package:vault/app/constants/model_brands.dart';

enum ModelBrandIconSize { sm, md }

class ModelBrandIcon extends StatelessWidget {
  const ModelBrandIcon({
    super.key,
    required this.model,
    this.size = ModelBrandIconSize.md,
  });

  final String model;
  final ModelBrandIconSize size;

  double get _box => size == ModelBrandIconSize.sm ? 14 : 18;
  double get _radius => size == ModelBrandIconSize.sm ? 4 : 5;

  @override
  Widget build(BuildContext context) {
    final brand = detectModelBrand(model);
    final asset = modelBrandAsset(brand.key);
    final initial = (brand.label.isEmpty ? '?' : brand.label.substring(0, 1)).toUpperCase();
    return Tooltip(
      message: brand.label,
      child: Container(
        width: _box,
        height: _box,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: asset == null ? const Color(0xFF69707C) : const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(_radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: asset == null
            ? Text(
                initial,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size == ModelBrandIconSize.sm ? 8 : 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              )
            : Image.asset(
                asset,
                width: _box,
                height: _box,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, error, stack) => Text(
                  initial,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF69707C),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
      ),
    );
  }
}

class ModelBrandStack extends StatelessWidget {
  const ModelBrandStack({super.key, required this.models, this.maxVisible = 4});

  final List<String> models;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = models.take(maxVisible).toList();
    const overlap = 4.0;
    const icon = 14.0;
    final width = icon + (shown.length - 1) * (icon - overlap);
    final surface = Theme.of(context).cardColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: icon,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * (icon - overlap),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [BoxShadow(color: surface, spreadRadius: 1.5)],
                    ),
                    child: ModelBrandIcon(model: shown[i], size: ModelBrandIconSize.sm),
                  ),
                ),
            ],
          ),
        ),
        if (models.length > maxVisible) ...[
          const SizedBox(width: 4),
          Text(
            '+${models.length - maxVisible}',
            style: const TextStyle(
              color: Color(0xFF7D8490),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}
