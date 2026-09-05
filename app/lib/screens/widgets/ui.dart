import 'package:flutter/material.dart';
import 'package:vault/screens/theme_define.dart';

class YuconCard extends StatelessWidget {
  const YuconCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.onTap,
    this.borderColor,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(ThemeDefine.kCardRadius);
    final padded = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Theme.of(context).cardColor) : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? const Color(0x0A16191F)),
        boxShadow: ThemeDefine.kCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? padded
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: padded,
              ),
            ),
    );
  }
}

class HeaderPill extends StatelessWidget {
  const HeaderPill({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: SizedBox(
        height: 31,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: ThemeDefine.kColorPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 31),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            alignment: Alignment.center,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.outlined = false,
    this.height = 41,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outlined ? ThemeDefine.kColorPrimary : Colors.white,
            ),
          )
        : Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          );
    final button = outlined
        ? OutlinedButton(
            onPressed: busy ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeDefine.kColorPrimary,
              side: const BorderSide(color: ThemeDefine.kColorPrimary),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.center,
            ),
            child: child,
          )
        : FilledButton(
            onPressed: busy ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: ThemeDefine.kColorPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: ThemeDefine.kColorDisable,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size(0, height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.center,
            ),
            child: child,
          );
    return SizedBox(width: double.infinity, height: height, child: button);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, height: 1, leadingDistribution: TextLeadingDistribution.even)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 22, 1, 10),
      child: Row(
        children: [
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: const TextStyle(
                  color: ThemeDefine.kColorPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 41,
    this.showWordmark = true,
    this.compact = false,
  });

  /// Height in logical pixels. Matches the old rpx size at 750 design width (size / 2).
  final double size;
  final bool showWordmark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final height = showWordmark && compact ? size * 0.9 : size;
    final ratio = showWordmark ? 3.78 : 1.0;
    final asset = !showWordmark
        ? 'assets/brand/yucon-app-icon.png'
        : (dark ? 'assets/brand/yucon-lockup-dark.png' : 'assets/brand/yucon-lockup-light.png');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Image.asset(
        asset,
        width: height * ratio,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class YuconHeaderTitle extends StatelessWidget {
  const YuconHeaderTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, fontWeight: FontWeight.w400),
          ),
        ],
      ],
    );
  }
}

class YuconAppBar extends StatelessWidget implements PreferredSizeWidget {
  const YuconAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle == null ? 52.0 : 62.0) + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      titleSpacing: 15,
      title: SizedBox(
        height: subtitle == null ? 52 : 62,
        child: Align(
          alignment: Alignment.centerLeft,
          child: YuconHeaderTitle(title: title, subtitle: subtitle),
        ),
      ),
      actions: actions,
      toolbarHeight: subtitle == null ? 52 : 62,
      bottom: bottom,
    );
  }
}

class HeaderTextAction extends StatelessWidget {
  const HeaderTextAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: ThemeDefine.kColorPrimary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: ThemeDefine.kColorSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: ThemeDefine.kColorPrimary,
              shape: BoxShape.circle,
            ),
            child: const Text(
              'i',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFC54638), fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.requiredMark = false,
    this.hint,
    this.last = false,
  });

  final String label;
  final Widget child;
  final bool requiredMark;
  final String? hint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              if (requiredMark)
                const Text(' *', style: TextStyle(color: ThemeDefine.kColorPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

InputDecoration inCardInput({String? hint, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    filled: false,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    suffixIcon: suffix,
    suffixIconConstraints: suffix == null
        ? null
        : const BoxConstraints(minWidth: 32, minHeight: 32),
  );
}

Widget secretVisibilityButton({
  required bool visible,
  required VoidCallback onPressed,
}) {
  return IconButton(
    onPressed: onPressed,
    tooltip: visible ? '隐藏' : '显示',
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    visualDensity: VisualDensity.compact,
    icon: Icon(
      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      size: 20,
      color: ThemeDefine.kColorText,
    ),
  );
}

class SquareIcon extends StatelessWidget {
  const SquareIcon({
    super.key,
    required this.child,
    required this.color,
    this.size = 32,
    this.radius = 10,
  });

  final Widget child;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: IconTheme(
        data: IconThemeData(size: size * 0.52, color: Colors.white),
        child: DefaultTextStyle.merge(
          style: const TextStyle(height: 1, leadingDistribution: TextLeadingDistribution.even),
          child: child,
        ),
      ),
    );
  }
}

class YuconRefresh extends StatelessWidget {
  const YuconRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: ThemeDefine.kColorPrimary,
      backgroundColor: Theme.of(context).cardColor,
      displacement: 36,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
