import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/constants/open_source.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/data_backup_screen.dart';
import 'package:vault/screens/developer_options_screen.dart';
import 'package:vault/screens/open_source_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/themes.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/network_proxy_panel.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const SizedBox.expand();
    }
    final store = context.watch<VaultStore>();
    final themes = context.watch<Themes>();

    return SecureScope(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
      children: [
        YuconCard(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              const Expanded(child: BrandMark(size: 47)),
              StatusChip(
                label: store.accounts.isEmpty ? '等待连接' : '已连接站点',
                color: const Color(0xFFD91D0D),
                background: ThemeDefine.kColorSoft,
              ),
            ],
          ),
        ),
        YuconCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SquareIcon(
                size: 32,
                radius: 10,
                color: ThemeDefine.kColorPrimary,
                child: TabIcon(name: YuconTabIcon.accounts, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已管理 ${store.accounts.length} 个账号',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summarizePlatformTypes(store.accounts),
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle(text: '管理概览'),
        GroupCard(
          children: [
            GroupTile(
              title: '全部可用额度',
              value: formatCurrency(store.totalQuota),
              leading: _cellIcon('￥', const Color(0xFFFA2C19)),
            ),
            GroupTile(
              title: '累计已用额度',
              value: formatCurrency(store.totalUsedQuota),
              leading: _cellIconWidget(
                const TabIcon(name: YuconTabIcon.logs, size: 14, color: Colors.white),
                const Color(0xFF3178DF),
              ),
            ),
            GroupTile(
              title: '可用密钥',
              value: '${store.activeApiKeyCount} 个',
              leading: _cellIconWidget(
                const TabIcon(name: YuconTabIcon.keys, size: 14, color: Colors.white),
                const Color(0xFF21A366),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 13),
          child: NetworkProxyPanel(
            value: store.settings.networkProxy,
            showFollowGlobal: false,
            onChanged: (proxy) {
              final next = proxy.mode == NetworkProxyMode.followGlobal
                  ? (proxy.copy()..mode = NetworkProxyMode.custom)
                  : proxy;
              store.updateSettings(store.settings.copyWith(networkProxy: next));
            },
          ),
        ),
        const SectionTitle(text: '偏好设置'),
        GroupCard(
          children: [
            GroupTile(
              title: '额度预警',
              value: '低于 \$${store.settings.lowQuotaThreshold.toStringAsFixed(2)} 时提醒',
              leading: _cellIcon('!', const Color(0xFFED8A19)),
              onTap: () => _editThreshold(context, store),
            ),
            GroupTile(
              title: '额度通知',
              leading: _cellIcon('✓', ThemeDefine.kColorPrimary),
              trailing: Switch(
                value: store.settings.notificationEnabled,
                onChanged: (value) {
                  store.updateSettings(store.settings.copyWith(notificationEnabled: value));
                  store.notify(value ? '额度通知已开启' : '额度通知已关闭', FeedbackType.text);
                },
              ),
            ),
            GroupTile(
              title: '记录使用时的 IP',
              leading: _cellIconWidget(
                const TabIcon(name: YuconTabIcon.logs, size: 14, color: Colors.white),
                const Color(0xFF3178DF),
              ),
              trailing: Switch(
                value: store.settings.recordIpLog,
                onChanged: (value) {
                  store.updateSettings(store.settings.copyWith(recordIpLog: value));
                  store.notify(value ? '已开启 IP 记录' : '已关闭 IP 记录', FeedbackType.text);
                },
              ),
            ),
            GroupTile(
              title: '深色模式',
              leading: _cellIcon('◐', const Color(0xFF25272B)),
              trailing: Switch(
                value: themes.isDark(context),
                onChanged: (_) {
                  themes.toggleNight(context);
                  store.updateSettings(store.settings.copyWith(darkMode: !store.settings.darkMode));
                },
              ),
            ),
          ],
        ),
        const SectionTitle(text: '数据与关于'),
        GroupCard(
          children: [
            GroupTile(
              title: '数据备份',
              subtitle: '导入、备份和导出本机数据',
              leading: _cellIconWidget(
                const Icon(Icons.unarchive_outlined, size: 16, color: Colors.white),
                const Color(0xFF1F6FEB),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DataBackupScreen()),
                );
              },
            ),
            GroupTile(
              title: '开发者选项',
              subtitle: '请求记录等调试工具',
              leading: _cellIconWidget(
                const Icon(Icons.developer_mode, size: 16, color: Colors.white),
                const Color(0xFF8257E6),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeveloperOptionsScreen()),
                );
              },
            ),
            GroupTile(
              title: '本地数据说明',
              value: '登录信息保存在本机',
              leading: _cellIconWidget(
                const TabIcon(name: YuconTabIcon.accounts, size: 14, color: Colors.white),
                const Color(0xFF8257E6),
              ),
              onTap: () => _showSheet(
                context,
                '本地数据说明',
                '账号列表、登录状态、登录密码和最近同步结果保存在本机。登录密码只放在本机加密存储里，备份文件也会再加密一次。额度、密钥和日志都从对应站点读取。换机或重装前，到「数据备份」导出一份。',
              ),
            ),
            GroupTile(
              title: '开源与致谢',
              subtitle: '本软件、兼容网关与许可证',
              leading: _cellIconWidget(
                const Icon(Icons.code, size: 16, color: Colors.white),
                const Color(0xFF24292F),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OpenSourceScreen()),
                );
              },
            ),
            GroupTile(
              title: '关于 Yucon 钥仓',
              value: '多站点额度管理',
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/brand/yucon-app-icon.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
              onTap: () => _showAbout(context),
            ),
          ],
        ),
      ],
    ),
    );
  }

  Widget _cellIcon(String text, Color color) {
    return SquareIcon(
      size: 28,
      radius: 8,
      color: color,
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }

  Widget _cellIconWidget(Widget child, Color color) {
    return SquareIcon(size: 28, radius: 8, color: color, child: child);
  }

  Future<void> _editThreshold(BuildContext context, VaultStore store) async {
    final controller = TextEditingController(text: store.settings.lowQuotaThreshold.toStringAsFixed(2));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('额度预警', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('当任意账号额度低于该值时显示提醒。'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '提醒额度（美元）'),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: '保存设置',
                onPressed: () {
                  final value = double.tryParse(controller.text);
                  if (value == null || value < 0) {
                    store.notify('请输入有效的提醒额度', FeedbackType.error);
                    return;
                  }
                  store.updateSettings(store.settings.copyWith(lowQuotaThreshold: value));
                  store.notify('提醒额度已更新');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 54),
              const SizedBox(height: 16),
              const Text('Yucon 钥仓', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '独立客户端。连接 ${platformLabelSlash()} 站点，在本机管理额度、密钥与调用记录。',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.5, color: ThemeDefine.kColorText),
              ),
              const SizedBox(height: 14),
              const StatusChip(
                label: 'v$kAppVersion',
                color: Color(0xFF69707C),
                background: Color(0xFFF1F3F6),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OpenSourceScreen()),
                  );
                },
                child: const Text('开源与致谢'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSheet(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(height: 1.5)),
            ],
          ),
        );
      },
    );
  }
}
