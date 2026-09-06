import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/account_form_screen.dart';
import 'package:vault/screens/key_detail_screen.dart';
import 'package:vault/screens/key_form_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_connect_menu.dart';
import 'package:vault/screens/widgets/api_address_copy.dart';
import 'package:vault/screens/widgets/api_key_card.dart';
import 'package:vault/screens/widgets/platform_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key, this.active = true});

  final bool active;

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void didUpdateWidget(KeysScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _prepare();
    }
  }

  void _prepare() {
    if (!widget.active || !mounted) {
      return;
    }
    final store = context.read<VaultStore>();
    final account = store.selectedKeysAccount;
    if (account != null) {
      store.setSelectedKeysAccountId(account.id);
    }
  }

  Future<void> _refresh(VaultStore store) async {
    final account = store.selectedKeysAccount;
    if (account == null) {
      return;
    }
    try {
      await store.syncAccount(account.id);
      store.notify('密钥已更新');
    } catch (error) {
      store.notify(userFacingError(error, '同步失败'), FeedbackType.error);
    }
  }

  void _openCreate(Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KeyFormScreen(accountId: account.id)),
    );
  }

  Future<void> _pickAccount(VaultStore store) async {
    final selected = store.selectedKeysAccount;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择账号',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '查看该账号下的密钥',
                    style: TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final account in store.accounts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: YuconCard(
                              margin: EdgeInsets.zero,
                              padding: const EdgeInsets.all(12),
                              borderColor: selected?.id == account.id
                                  ? const Color(0x29FA2C19)
                                  : null,
                              onTap: () {
                                store.setSelectedKeysAccountId(account.id);
                                Navigator.pop(context);
                              },
                              child: Row(
                                children: [
                                  PlatformBrandIcon(
                                    type: account.platformType,
                                    size: 32,
                                    radius: 10,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          store.displayAccountName(account),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${getPlatformPreset(account.platformType).label} · ${store.keyCountForAccount(account.id)} 个密钥',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: ThemeDefine.kColorText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected?.id == account.id)
                                    const Text(
                                      '当前',
                                      style: TextStyle(
                                        color: ThemeDefine.kColorPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openAccountDetail(Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountDetailScreen(accountId: account.id),
      ),
    );
  }

  String _accountMeta(Account account) {
    final preset = getPlatformPreset(account.platformType).label;
    final alias = context.read<VaultStore>().displayAccountName(account).trim();
    final user = account.username.trim();
    if (user.isNotEmpty && user.toLowerCase() != alias.toLowerCase()) {
      return '$preset · @$user';
    }
    return preset;
  }

  Widget _accountSwitcher(VaultStore store, Account selected) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in store.accounts)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => store.setSelectedKeysAccountId(item.id),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.fromLTRB(5, 0, 10, 0),
                        decoration: BoxDecoration(
                          color: item.id == selected.id
                              ? ThemeDefine.kColorSoft
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: item.id == selected.id
                                ? const Color(0x29FA2C19)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlatformBrandIcon(
                              type: item.platformType,
                              size: 22,
                              radius: 7,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 118),
                              child: Text(
                                store.displayAccountName(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                  color: item.id == selected.id
                                      ? ThemeDefine.kColorPrimary
                                      : ThemeDefine.kColorText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (store.accounts.length > 4) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _pickAccount(store),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: ThemeDefine.kColorText,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _accountContextCard(VaultStore store, Account account) {
    return YuconCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _openAccountDetail(account),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                PlatformBrandIcon(
                  type: account.platformType,
                  size: 36,
                  radius: 11,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.displayAccountName(account),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _accountMeta(account),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: ThemeDefine.kColorText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ApiAddressCopy(account: account, store: store, embedded: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.expand();
    }
    final store = context.watch<VaultStore>();
    final account = store.selectedKeysAccount;
    final keys = account == null
        ? <ApiKey>[]
        : store.apiKeysForAccount(account.id);
    final expired = account?.status == AccountStatus.expired;
    final blocked = account?.status == AccountStatus.blocked;
    final canAdd = account != null && !expired && !blocked;

    final pageColor = Theme.of(context).scaffoldBackgroundColor;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(15, account == null ? 4 : 0, 15, 24),
      children: [
        if (store.accounts.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                '还没有账号，添加后即可管理密钥',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13),
              ),
            ),
          ),
          PrimaryButton(
            label: '添加账号',
            onPressed: () => showAccountConnectMenu(context),
          ),
        ] else if (account == null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                '选择一个账号后即可管理密钥',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13),
              ),
            ),
          ),
        ] else if (keys.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                expired
                    ? '登录过期，暂时不能同步密钥'
                    : blocked
                    ? (account.dnsPolluted
                          ? '域名解析不正常，暂时不能同步密钥'
                          : '当前网络打不开这个网站，暂时不能同步密钥')
                    : '这个账号还没有密钥',
                style: const TextStyle(color: ThemeDefine.kColorText),
              ),
            ),
          )
        else
          for (final apiKey in keys)
            ApiKeyCard(
              apiKey: apiKey,
              store: store,
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => KeyDetailScreen(keyId: apiKey.id),
                  ),
                );
              },
            ),
        if (account != null) ...[
          const SizedBox(height: 8),
          if (canAdd)
            PrimaryButton(label: '添加密钥', onPressed: () => _openCreate(account))
          else if (expired)
            PrimaryButton(
              label: '重新登录',
              outlined: true,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AccountFormScreen(accountId: account.id),
                  ),
                );
              },
            )
          else if (blocked)
            PrimaryButton(
              label: '去账号详情处理',
              outlined: true,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AccountDetailScreen(accountId: account.id),
                  ),
                );
              },
            ),
        ],
      ],
    );

    return SecureScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null)
            ColoredBox(
              color: pageColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (store.accounts.length > 1) ...[
                      _accountSwitcher(store, account),
                      const SizedBox(height: 10),
                    ],
                    _accountContextCard(store, account),
                    if (expired)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: TipBanner(text: '这个账号需要重新登录后，才能添加或同步密钥。'),
                      ),
                    if (blocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TipBanner(
                          text: account.dnsPolluted
                              ? '不是登录过期。当前网络的域名解析不正常，请到「我的」换代理后再同步密钥。'
                              : '不是登录过期。当前网络打不开这个网站，请到「我的」换代理后再同步密钥。',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(1, 14, 1, 9),
                      child: Text(
                        '共 ${keys.length} 个密钥',
                        style: const TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: YuconRefresh(onRefresh: () => _refresh(store), child: list),
          ),
        ],
      ),
    );
  }
}
