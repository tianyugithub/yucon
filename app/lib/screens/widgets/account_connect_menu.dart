import 'package:flutter/material.dart';
import 'package:vault/screens/account_form_screen.dart';
import 'package:vault/screens/theme_define.dart';

Future<void> showAccountConnectMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<AccountFormIntent>(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final fill = dark ? const Color(0xFF232323) : const Color(0xFFEEEEF0);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          18 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: dark
                      ? ThemeDefine.kColorDarkLine
                      : ThemeDefine.kColorLine,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Text(
              '添加账号',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '接入已有站点，或直接在站点注册。',
              style: TextStyle(
                color: ThemeDefine.kColorText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            _ConnectChoiceCard(
              fill: fill,
              index: '01',
              title: '添加已有账号',
              subtitle: '密码登录、身份验证，或粘贴访问令牌',
              onTap: () => Navigator.pop(context, AccountFormIntent.add),
            ),
            const SizedBox(height: 8),
            _ConnectChoiceCard(
              fill: fill,
              index: '02',
              title: '注册新账号',
              subtitle: '调用站点接口注册，邮箱收到验证码后填入',
              onTap: () => Navigator.pop(context, AccountFormIntent.register),
            ),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) {
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => AccountFormScreen(intent: choice)));
}

class _ConnectChoiceCard extends StatelessWidget {
  const _ConnectChoiceCard({
    required this.fill,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color fill;
  final String index;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Text(
                index,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ThemeDefine.kColorPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: ThemeDefine.kColorText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: ThemeDefine.kColorText,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
