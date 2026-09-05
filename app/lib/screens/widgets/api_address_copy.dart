import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class ApiAddressCopy extends StatelessWidget {
  const ApiAddressCopy({super.key, required this.account, required this.store});

  final Account account;
  final VaultStore store;

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    store.notify('已复制 API 地址');
  }

  @override
  Widget build(BuildContext context) {
    final urls = apiCopyUrlsFor(account);
    if (urls.isEmpty) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF1C1C1C) : const Color(0xFFF6F7F9);

    return YuconCard(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      child: Column(
        children: [
          for (var i = 0; i < urls.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _row(
              fill: fill,
              url: urls[i],
              label: i == 0 ? 'API 地址' : '其他地址',
            ),
          ],
        ],
      ),
    );
  }

  Widget _row({
    required Color fill,
    required String url,
    required String label,
  }) {
    return GestureDetector(
      onTap: () => _copy(url),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Text(
              '复制',
              style: TextStyle(
                color: ThemeDefine.kColorPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
