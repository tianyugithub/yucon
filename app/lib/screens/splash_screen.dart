import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/home_shell.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/themes.dart';

double _span(double t, double start, double end, Curve curve) {
  if (end <= start) {
    return t >= end ? 1 : 0;
  }
  return curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _pulse;
  late final AnimationController _leave;
  bool _revealHome = false;
  bool _splashGone = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _leave = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
    _intro.forward();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _pulse.repeat(reverse: true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final store = context.read<VaultStore>();
    final themes = context.read<Themes>();
    await Future.wait([
      _intro.forward(),
      store.hydrate(),
    ]);
    if (!mounted) {
      return;
    }
    themes.setTheme(store.settings.darkMode ? 'dark' : 'light', notify: true);
    setState(() => _revealHome = true);
    await _leave.forward();
    if (!mounted) {
      return;
    }
    _pulse.stop();
    setState(() => _splashGone = true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    _leave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = dark ? ThemeDefine.kColorDarkPage : ThemeDefine.kColorPage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_revealHome) const HomeShell(),
        if (!_splashGone)
          AnimatedBuilder(
            animation: Listenable.merge([_intro, _pulse, _leave]),
            builder: (context, _) => IgnorePointer(
              child: Opacity(
                opacity: (1 - Curves.easeIn.transform(_leave.value)).clamp(0.0, 1.0),
                child: _SplashStage(
                  intro: _intro.value,
                  pulse: _pulse.value,
                  page: page,
                  dark: dark,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashStage extends StatelessWidget {
  const _SplashStage({
    required this.intro,
    required this.pulse,
    required this.page,
    required this.dark,
  });

  final double intro;
  final double pulse;
  final Color page;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final drop = _span(intro, 0.02, 0.58, Curves.easeOutBack);
    final fade = _span(intro, 0.02, 0.28, Curves.easeOut);
    final ringA = _span(intro, 0.22, 0.82, Curves.easeOutCubic);
    final ringB = _span(intro, 0.38, 0.98, Curves.easeOutCubic);
    final title = _span(intro, 0.48, 0.82, Curves.easeOutCubic);
    final glow = 0.35 + 0.65 * pulse;
    final breathe = 1 + 0.08 * pulse;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: ColoredBox(
        color: page,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 0.7 + 0.45 * glow,
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              ThemeDefine.kColorPrimary.withValues(alpha: 0.42 * glow * fade),
                              ThemeDefine.kColorPrimary.withValues(alpha: 0.12 * glow * fade),
                              ThemeDefine.kColorPrimary.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.38, 1.0],
                          ),
                        ),
                      ),
                    ),
                    _ring(ringA, 2.8),
                    _ring(ringB, 1.8),
                    Opacity(
                      opacity: fade,
                      child: Transform.translate(
                        offset: Offset(0, 88 * (1 - drop)),
                        child: Transform.rotate(
                          angle: (1 - drop) * -0.42,
                          child: Transform.scale(
                            scale: (0.08 + 0.92 * drop) * breathe,
                            child: Image.asset(
                              'assets/brand/yucon-logo.png',
                              width: 148,
                              height: 148,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Opacity(
                opacity: title,
                child: Transform.translate(
                  offset: Offset(0, 28 * (1 - title)),
                  child: const Column(
                    children: [
                      Text(
                        '钥仓',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 8,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'YUCON',
                        style: TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double progress, double width) {
    final opacity = (1 - progress) * 0.7;
    return Transform.scale(
      scale: 0.25 + 1.55 * progress,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: ThemeDefine.kColorPrimary.withValues(alpha: 0.9),
              width: width,
            ),
          ),
        ),
      ),
    );
  }
}
