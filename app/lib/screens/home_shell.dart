import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/accounts_screen.dart';
import 'package:vault/screens/dashboard_screen.dart';
import 'package:vault/screens/key_form_screen.dart';
import 'package:vault/screens/keys_screen.dart';
import 'package:vault/screens/logs_screen.dart';
import 'package:vault/screens/profile_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/themes.dart';
import 'package:vault/screens/widgets/account_connect_menu.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late bool _bootstrapped;

  @override
  void initState() {
    super.initState();
    _bootstrapped = context.read<VaultStore>().hydrated;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final store = context.read<VaultStore>();
    if (!store.hydrated) {
      await store.hydrate();
    }
    if (!mounted) {
      return;
    }
    final themes = context.read<Themes>();
    themes.setTheme(store.settings.darkMode ? 'dark' : 'light', notify: true);
    setState(() => _bootstrapped = true);
    final refreshed = await store.refreshAllAccounts();
    if (refreshed) {
      await store.autoCheckinAccounts();
    }
    unawaited(store.checkAppUpdate(notifyIfAvailable: true));
  }

  void _openCreate() {
    showAccountConnectMenu(context);
  }

  @override
  Widget build(BuildContext context) {
    final checkinTotal = context.select(
      (VaultStore store) => store.todayCheckinStatus.total,
    );
    final keysAccount = context.select((VaultStore store) {
      final account = store.selectedKeysAccount;
      return (account?.id, account?.status);
    });
    final themes = context.watch<Themes>();
    final dark = themes.isDark(context);
    final page = dark ? ThemeDefine.kColorDarkPage : ThemeDefine.kColorPage;
    final card = dark ? ThemeDefine.kColorDarkCard : ThemeDefine.kColorCard;

    Widget title;
    List<Widget> actions = const [];
    switch (_tab) {
      case 0:
        title = const BrandMark(size: 41);
        actions = [HeaderPlusAction(onPressed: _openCreate, tooltip: '添加')];
        break;
      case 1:
        title = const YuconHeaderTitle(title: '账号', subtitle: '管理已连接的站点账号');
        actions = [HeaderPlusAction(onPressed: _openCreate, tooltip: '添加')];
        break;
      case 2:
        title = const YuconHeaderTitle(title: '密钥管理', subtitle: '按账号查看和复制密钥');
        final canAddKey =
            keysAccount.$1 != null &&
            keysAccount.$2 != AccountStatus.expired &&
            keysAccount.$2 != AccountStatus.blocked;
        if (canAddKey) {
          actions = [
            HeaderPill(
              label: '添加密钥',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => KeyFormScreen(accountId: keysAccount.$1!),
                  ),
                );
              },
            ),
          ];
        }
        break;
      case 3:
        title = const YuconHeaderTitle(title: '日志', subtitle: '调用记录、消耗额度与签到');
        if (checkinTotal > 0) {
          actions = [
            HeaderPill(
              label: '全部签到',
              onPressed: () async {
                final store = context.read<VaultStore>();
                final summary = store.summarizeCheckin(
                  await store.checkinAll(),
                );
                store.notify(summary.message, summary.type);
              },
            ),
          ];
        }
        break;
      default:
        title = const YuconHeaderTitle(title: '我的', subtitle: '同步设置和偏好');
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: themes.getStatusBarIconBrightness(context),
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: page,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: page,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: _tab == 0 ? 52 : 62,
          titleSpacing: 15,
          title: SizedBox(
            height: _tab == 0 ? 52 : 62,
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
          actions: actions,
        ),
        body: !_bootstrapped
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _tab,
                children: [
                  DashboardScreen(
                    active: _tab == 0,
                    onOpenAccounts: () => setState(() => _tab = 1),
                    onOpenKeys: () => setState(() => _tab = 2),
                    onOpenLogs: () => setState(() => _tab = 3),
                  ),
                  AccountsScreen(active: _tab == 1),
                  KeysScreen(active: _tab == 2),
                  LogsScreen(active: _tab == 3),
                  ProfileScreen(active: _tab == 4),
                ],
              ),
        bottomNavigationBar: Material(
          color: card.withValues(alpha: 0.98),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: card.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                top: BorderSide(
                  color: dark
                      ? const Color(0x14FFFFFF)
                      : const Color(0x0F111827),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: dark
                      ? const Color(0x47000000)
                      : const Color(0x14191D25),
                  blurRadius: 14,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    _tabItem(0, YuconTabIcon.dashboard, '看板'),
                    _tabItem(1, YuconTabIcon.accounts, '账号'),
                    _tabItem(2, YuconTabIcon.keys, '密钥'),
                    _tabItem(3, YuconTabIcon.logs, '日志'),
                    _tabItem(4, YuconTabIcon.profile, '我的'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabItem(int index, YuconTabIcon icon, String label) {
    final selected = _tab == index;
    final color = selected
        ? ThemeDefine.kColorPrimary
        : ThemeDefine.kColorTabInactive;
    final showUpdateDot =
        index == 4 && context.select((VaultStore store) => store.hasAppUpdate);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                TabIcon(name: icon, size: 18, color: color),
                if (showUpdateDot)
                  const Positioned(
                    right: -3,
                    top: -2,
                    child: SizedBox(
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ThemeDefine.kColorPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
