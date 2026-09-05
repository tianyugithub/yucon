import 'package:flutter/material.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.store,
    required this.onOpen,
  });

  final Account account;
  final VaultStore store;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final preset = getPlatformPreset(account.platformType);
    final meta = accountDisplayMeta(account);
    final showsCheckin = account.checkinEnabled;
    final metaLabel = showsCheckin ? '最近签到' : '最近同步';
    String metaValue;
    if (!showsCheckin) {
      metaValue = account.lastSyncedAt == null ? '尚未同步' : formatDateTime(account.lastSyncedAt);
    } else if (store.isCheckedInToday(account)) {
      metaValue = '今日已签到';
    } else {
      metaValue = account.lastCheckin == null ? '尚未签到' : formatDateTime(account.lastCheckin);
    }
    final borderColor = account.status == AccountStatus.expired
        ? const Color(0x33BE2630)
        : account.status == AccountStatus.blocked
        ? const Color(0x339A3412)
        : account.status == AccountStatus.exhausted
        ? const Color(0x339A3412)
        : account.status == AccountStatus.low
        ? const Color(0x38ED8A19)
        : const Color(0x0A16191F);

    return YuconCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(13),
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(
                color: Color(preset.color),
                child: Text(
                  preset.shortLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.displayAccountName(account),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${account.siteName} · ${preset.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              StatusChip(label: meta.label, color: meta.color, background: meta.background),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前可用额度', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      formatCurrency(account.quota),
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.7, height: 1.12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ThemeDefine.kColorText, size: 18),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ThemeDefine.kColorLine)),
            ),
            child: Row(
              children: [
                _meta('用户名', account.username.isEmpty ? '未填写' : account.username, CrossAxisAlignment.start),
                _meta('密钥', '${store.keyCountForAccount(account.id)} 个', CrossAxisAlignment.center),
                _meta(metaLabel, metaValue, CrossAxisAlignment.end),
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

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return YuconCard(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

class GroupTile extends StatelessWidget {
  const GroupTile({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.leading,
    this.icon,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final Widget? leading;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget? end = trailing;
    if (end == null && value != null) {
      end = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
        child: Text(
          value!,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13),
        ),
      );
    }
    if (end == null && onTap != null) {
      end = const Icon(Icons.chevron_right, color: ThemeDefine.kColorText);
    } else if (onTap != null && value != null) {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
            child: Text(
              value!,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13),
            ),
          ),
          const Icon(Icons.chevron_right, color: ThemeDefine.kColorText, size: 18),
        ],
      );
    }
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: leading ??
          (icon == null
              ? null
              : SquareIcon(
                  size: 28,
                  radius: 8,
                  color: ThemeDefine.kColorSoft,
                  child: Icon(icon, color: ThemeDefine.kColorPrimary, size: 16),
                )),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13)),
      trailing: end,
    );
  }
}
