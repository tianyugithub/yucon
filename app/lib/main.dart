import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/splash_screen.dart';
import 'package:vault/screens/theme_data_dark.dart';
import 'package:vault/screens/theme_data_light.dart';
import 'package:vault/screens/themes.dart';
import 'package:vault/screens/widgets/feedback_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YuconApp());
}

class YuconApp extends StatefulWidget {
  const YuconApp({super.key});

  @override
  State<YuconApp> createState() => _YuconAppState();
}

class _YuconAppState extends State<YuconApp> with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hide =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (hide != _obscured) {
      setState(() => _obscured = hide);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Themes()),
        ChangeNotifierProvider(create: (_) => VaultStore()),
        ChangeNotifierProvider.value(value: HttpRequestLogger.instance),
      ],
      child: Consumer<Themes>(
        builder: (context, themes, _) {
          return MaterialApp(
            title: 'Yucon 钥仓',
            debugShowCheckedModeBanner: false,
            theme: ThemeDataLight.theme(context),
            darkTheme: ThemeDataDark.theme(context),
            themeMode: themes.themeMode(),
            builder: (context, child) => FeedbackOverlay(
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  if (_obscured) const AppPrivacyCover(),
                ],
              ),
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
