import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/github_identity_screen.dart';
import 'package:vault/screens/google_identity_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/identity_brand_icon.dart';
import 'package:vault/screens/widgets/identity_login_sheet.dart';
import 'package:vault/screens/widgets/ui.dart';

class IdentityScreen extends StatelessWidget {
  const IdentityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    return SecureScope(
      child: Scaffold(
        appBar: const YuconAppBar(
          title: '身份',
          subtitle: '按 Google、GitHub 分组管理账号',
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
          children: [
            const TipBanner(
              text: '每个账号单独记住登录。系统同一时间只能挂一份 Google 或 GitHub Cookie，所以窗口要一个一个开。打开某个账号后，站点授权会用这一份。登录页只填入这个账号，点登录仍需手动完成。',
            ),
            const SectionTitle(text: '第三方登录'),
            _IdentityProviderGroup(
              store: store,
              provider: googleIdentityProvider,
            ),
            _IdentityProviderGroup(
              store: store,
              provider: githubIdentityProvider,
            ),
            const SectionTitle(text: '说明'),
            YuconCard(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              child: Text(
                '登录成功后会把这份会话记在本机。断开一个窗口不会删掉账号密码，也不会动其他账号的登录。\n'
                '站点授权会复用当前打开过的那份 Google / GitHub。验证码和两步验证都要在页面里手动完成。',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? ThemeDefine.kColorDarkText
                      : ThemeDefine.kColorText,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityProviderGroup extends StatelessWidget {
  const _IdentityProviderGroup({required this.store, required this.provider});

  final VaultStore store;
  final String provider;

  Widget get _leading => provider == githubIdentityProvider
      ? const IdentityBrandIcon.github(size: 22)
      : const IdentityBrandIcon.google(size: 22);

  @override
  Widget build(BuildContext context) {
    final items = store.identityLoginsFor(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(1, 8, 1, 8),
          child: Row(
            children: [
              _leading,
              const SizedBox(width: 8),
              Text(
                identityGroupTitle(provider),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        GroupCard(
          children: [
            if (items.isEmpty)
              GroupTile(
                title: identityProviderTitle(provider),
                subtitle: store.identityWindowConnected(provider)
                    ? '打开后使用这份已记住的登录'
                    : '打开窗口登录，验证码需手动完成',
                value: store.identityWindowLabel(provider),
                onTap: () => openIdentityWindow(context, provider, null),
              )
            else
              for (final account in items)
                GroupTile(
                  title: account.label,
                  subtitle:
                      store.identityWindowConnected(
                        provider,
                        accountId: account.id,
                      )
                      ? '已记住登录，点开进入窗口'
                      : '点开窗口登录，验证码需手动完成',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          store.identityWindowLabel(
                            provider,
                            accountId: account.id,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ThemeDefine.kColorText,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '编辑账号',
                        onPressed: () {
                          showIdentityLoginEditor(
                            context: context,
                            provider: provider,
                            account: account,
                          );
                        },
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: ThemeDefine.kColorText,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => openIdentityWindow(context, provider, account),
                ),
            GroupTile(
              title: '添加${identityLoginTitle(provider)}',
              subtitle: '保存用户名和密码，并打开独立窗口',
              onTap: () => _addIdentityAccount(context, provider),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _addIdentityAccount(BuildContext context, String provider) async {
  final account = await showIdentityLoginEditor(
    context: context,
    provider: provider,
  );
  if (account == null || !context.mounted) {
    return;
  }
  await openIdentityWindow(context, provider, account);
}

Future<void> openIdentityWindow(
  BuildContext context,
  String provider,
  IdentityLoginAccount? login,
) async {
  final store = context.read<VaultStore>();
  if (login != null) {
    await store.selectIdentityLogin(provider, login.id);
  }
  if (!context.mounted) {
    return;
  }
  final Widget screen = provider == githubIdentityProvider
      ? GitHubIdentityScreen(login: login)
      : GoogleIdentityScreen(login: login);
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

Future<bool> ensureFreshIdentitySession({
  required BuildContext context,
  required String provider,
  IdentityLoginAccount? login,
  String? accountId,
  NetworkProxy? proxy,
}) async {
  final store = context.read<VaultStore>();
  final id = (accountId ?? login?.id ?? '').trim();
  if (id.isNotEmpty) {
    await store.selectIdentityLogin(provider, id);
  }
  final fresh = await store.verifyIdentitySession(
    provider,
    accountId: id,
    proxy: proxy,
  );
  if (!context.mounted) {
    return false;
  }
  if (fresh == IdentitySessionFreshness.alive) {
    return true;
  }
  if (fresh == IdentitySessionFreshness.expired) {
    store.notify(
      '${identityLoginTitle(provider)}登录已过期，请重新登录',
      FeedbackType.warning,
    );
  }
  await openIdentityWindow(context, provider, login);
  if (!context.mounted) {
    return false;
  }
  return store.identityWindowConnected(provider, accountId: id);
}
