import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/theme_define.dart';

class BalanceOverviewCard extends StatefulWidget {
  const BalanceOverviewCard({
    super.key,
    required this.totalQuota,
    required this.todayUsage,
    required this.accountCount,
    required this.checkinDone,
    required this.checkinTotal,
    required this.loading,
    required this.onRefresh,
    required this.onCheckin,
  });

  final double totalQuota;
  final double todayUsage;
  final int accountCount;
  final int checkinDone;
  final int checkinTotal;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onCheckin;

  @override
  State<BalanceOverviewCard> createState() => _BalanceOverviewCardState();
}

class _BalanceOverviewCardState extends State<BalanceOverviewCard> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x3D2C1C19), blurRadius: 25, offset: Offset(0, 12))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => _BalanceBackdrop(progress: _motion.value),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '全部账号可用额度',
                            style: TextStyle(color: Color(0xA3FFFFFF), fontSize: 12, letterSpacing: 0.2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(widget.totalQuota),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0x4DFFFFFF)),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0x17FFFFFF),
                      ),
                      child: const Text(
                        '钥',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0x2EFFFFFF))),
                  ),
                  child: Row(
                    children: [
                      _metric(formatCurrency(widget.todayUsage), '今日用量'),
                      _metric('${widget.accountCount}', '管理账号'),
                      _metric(
                        widget.checkinTotal == 0 ? '—' : '${widget.checkinDone}/${widget.checkinTotal}',
                        '今日签到',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _ghostButton(widget.loading ? '同步中' : '刷新余额', widget.onRefresh)),
                    if (widget.checkinTotal > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _whiteButton('全部签到', widget.onCheckin)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Color(0xA3FFFFFF), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 33,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0x24FFFFFF),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 33),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          alignment: Alignment.center,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _whiteButton(String label, VoidCallback onTap) {
    return SizedBox(
      height: 33,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ThemeDefine.kColorPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 33),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          alignment: Alignment.center,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _BalanceBackdrop extends StatelessWidget {
  const _BalanceBackdrop({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = progress * 2 * math.pi;
    final wave = 0.5 + 0.5 * math.sin(t);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.85 + 0.22 * math.sin(t), -1),
                    end: Alignment(1.12, 1.05 + 0.28 * math.cos(t * 0.8)),
                    colors: const [Color(0xFF1A1A1A), Color(0xFF2F1814), Color(0xFFFA2C19)],
                    stops: [0.08, 0.40 + 0.12 * wave, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.78 + 0.14 * math.sin(t * 0.7),
                      -0.72 + 0.12 * math.cos(t * 0.6),
                    ),
                    radius: 0.46 + 0.08 * math.sin(t * 0.5),
                    colors: [
                      Color.fromRGBO(255, 255, 255, 0.14 + 0.06 * math.sin(t * 0.8)),
                      const Color.fromRGBO(255, 255, 255, 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -62 + 24 * math.sin(t),
              right: -28 + 28 * math.cos(t * 0.85),
              child: Transform.scale(
                scale: 0.88 + 0.22 * wave,
                child: _glow(168, const Color(0xFFFA2C19), 0.28 + 0.08 * math.sin(t)),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * 0.28 + 40 * math.sin(t * 0.7),
              bottom: -46 + 22 * math.cos(t * 0.8),
              child: Transform.scale(
                scale: 0.9 + 0.2 * (0.5 + 0.5 * math.cos(t * 0.9)),
                child: _glow(120, const Color(0xFFFFAD9D), 0.26 + 0.08 * math.cos(t * 0.9)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glow(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
