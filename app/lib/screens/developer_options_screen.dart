import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/http_request_logs_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class DeveloperOptionsScreen extends StatelessWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final logger = context.watch<HttpRequestLogger>();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SecureScope(
      child: Scaffold(
      appBar: const YuconAppBar(title: '开发者选项', subtitle: '仅本机有效的调试工具'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
        children: [
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF3A241F) : ThemeDefine.kColorSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'HTTP',
                        style: TextStyle(
                          color: ThemeDefine.kColorPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('请求记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                _DevRow(
                  icon: logger.enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  title: '启用记录',
                  subtitle: '打开后记录应用内每个请求。只放在内存里，关掉应用后会丢失。',
                  trailing: Switch(
                    value: logger.enabled,
                    onChanged: (value) {
                      store.updateSettings(store.settings.copyWith(developerLogEnabled: value));
                      store.notify(value ? '已开始记录请求' : '已停止记录请求', FeedbackType.text);
                    },
                  ),
                ),
                const Divider(height: 1),
                _DevRow(
                  icon: Icons.receipt_long_outlined,
                  title: '查看请求记录',
                  subtitle: '实时查看记录 / 搜索 / 筛选',
                  trailing: const Icon(Icons.chevron_right, color: ThemeDefine.kColorText),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HttpRequestLogsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: ThemeDefine.kColorText),
                    SizedBox(width: 6),
                    Text('提示', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '• 敏感字段默认脱敏，详情页可点眼睛临时查看原文。\n'
                  '• 内存中最多保留 500 条，超出后丢掉最早的。\n'
                  '• 关掉开关不会清空已有记录，需要在列表页手动清空。',
                  style: TextStyle(
                    color: dark ? ThemeDefine.kColorDarkText : ThemeDefine.kColorText,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _DevRow extends StatelessWidget {
  const _DevRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SquareIcon(
            size: 34,
            radius: 10,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFF3F4F6),
            child: Icon(icon, size: 18, color: ThemeDefine.kColorText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: row);
  }
}
