import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/key_test_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class ApiKeyCard extends StatelessWidget {
  const ApiKeyCard({
    super.key,
    required this.apiKey,
    required this.store,
    required this.onOpen,
  });

  final ApiKey apiKey;
  final VaultStore store;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final meta = apiKeyStatusMeta(apiKey.status);
    final quotaText = apiKey.unlimitedQuota ? '无限额度' : formatCurrency(apiKey.remainQuota);
    final expiryText = apiKey.expiresAt == null ? '永不过期' : formatShortDate(apiKey.expiresAt!);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF1C1C1C) : const Color(0xFFF6F7F9);

    return YuconCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SquareIcon(
                size: 31,
                radius: 10,
                color: Color(0xFFEDF4FF),
                child: TabIcon(name: YuconTabIcon.keys, size: 16, color: Color(0xFF3178DF)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apiKey.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.tokenGroupLabel(apiKey.accountId, apiKey.group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                    if (apiKey.modelLimits.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      ModelBrandStack(models: apiKey.modelLimits),
                    ],
                  ],
                ),
              ),
              StatusChip(label: meta.label, color: meta.color, background: meta.background),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        final value = await store.revealApiKey(apiKey.id);
                        await Clipboard.setData(ClipboardData(text: value));
                        store.notify('复制成功');
                      } catch (error) {
                        store.notify(userFacingError(error, '复制失败'), FeedbackType.error);
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('密钥', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          maskSecret(apiKey.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => KeyTestScreen(keyId: apiKey.id)),
                    );
                  },
                  child: const Text(
                    '测试',
                    style: TextStyle(color: ThemeDefine.kColorPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () async {
                    try {
                      final value = await store.revealApiKey(apiKey.id);
                      await Clipboard.setData(ClipboardData(text: value));
                      store.notify('复制成功');
                    } catch (error) {
                      store.notify(userFacingError(error, '复制失败'), FeedbackType.error);
                    }
                  },
                  child: const Text(
                    '复制',
                    style: TextStyle(color: ThemeDefine.kColorPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ThemeDefine.kColorLine)),
            ),
            child: Row(
              children: [
                _meta('剩余额度', quotaText, CrossAxisAlignment.start),
                _meta('已使用', formatCurrency(apiKey.usedQuota), CrossAxisAlignment.center),
                _meta('有效期', expiryText, CrossAxisAlignment.end),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value, CrossAxisAlignment align) {
    final textAlign = align == CrossAxisAlignment.center
        ? TextAlign.center
        : align == CrossAxisAlignment.end
        ? TextAlign.right
        : TextAlign.left;
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              label,
              textAlign: textAlign,
              style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
