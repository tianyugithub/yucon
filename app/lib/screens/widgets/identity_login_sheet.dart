import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/ui.dart';

Future<bool> showIdentityLoginSheet({
  required BuildContext context,
  required String provider,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _IdentityLoginListSheet(provider: provider),
  );
  return saved == true;
}

Future<IdentityLoginAccount?> showIdentityLoginEditor({
  required BuildContext context,
  required String provider,
  IdentityLoginAccount? account,
}) {
  return showModalBottomSheet<IdentityLoginAccount>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _IdentityLoginEditorSheet(
      provider: provider,
      account: account,
    ),
  );
}

class _IdentityLoginListSheet extends StatelessWidget {
  const _IdentityLoginListSheet({required this.provider});

  final String provider;

  Future<void> _edit(BuildContext context, IdentityLoginAccount? account) async {
    await showIdentityLoginEditor(
      context: context,
      provider: provider,
      account: account,
    );
  }

  Future<void> _select(BuildContext context, IdentityLoginAccount account) async {
    await context.read<VaultStore>().selectIdentityLogin(provider, account.id);
    if (context.mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final items = store.identityLoginsFor(provider);
    final selected = store.identityLoginFor(provider);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            identityLoginTitle(provider),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '可以保存多个账号。登录页会填入当前选中的那一个，点登录仍需手动完成。',
            style: TextStyle(color: ThemeDefine.kColorText, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Text(
              '还没有保存账号。',
              style: TextStyle(color: ThemeDefine.kColorText),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
              child: SingleChildScrollView(
                child: GroupCard(
                  children: [
                    for (final account in items)
                      GroupTile(
                        title: account.label,
                        subtitle: account.id == selected?.id ? '当前填入' : '点选后在登录页填入',
                        trailing: IconButton(
                          tooltip: '编辑',
                          onPressed: () => _edit(context, account),
                          icon: const Icon(Icons.edit_outlined, size: 18, color: ThemeDefine.kColorText),
                        ),
                        onTap: () => _select(context, account),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: '添加账号',
            onPressed: () => _edit(context, null),
          ),
        ],
      ),
    );
  }
}

class _IdentityLoginEditorSheet extends StatefulWidget {
  const _IdentityLoginEditorSheet({
    required this.provider,
    this.account,
  });

  final String provider;
  final IdentityLoginAccount? account;

  @override
  State<_IdentityLoginEditorSheet> createState() => _IdentityLoginEditorSheetState();
}

class _IdentityLoginEditorSheetState extends State<_IdentityLoginEditorSheet> {
  late final TextEditingController _username;
  late final TextEditingController _password;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.account?.username ?? '');
    _password = TextEditingController(text: widget.account?.password ?? '');
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<VaultStore>();
    final account = IdentityLoginAccount(
      id: widget.account?.id ?? '',
      provider: widget.provider,
      username: _username.text.trim(),
      password: _password.text,
    );
    if (account.isEmpty) {
      if (account.id.isNotEmpty) {
        await store.forgetIdentityLogin(account.id);
      }
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      store.notify('已删除账号', FeedbackType.text);
      return;
    }
    await store.rememberIdentityLogin(account);
    if (!mounted) {
      return;
    }
    Navigator.pop(context, store.identityLoginFor(widget.provider));
    store.notify('已保存账号，打开窗口后会填入这份用户名和密码', FeedbackType.text);
  }

  Future<void> _delete() async {
    final id = widget.account?.id ?? '';
    if (id.isEmpty) {
      return;
    }
    final store = context.read<VaultStore>();
    await store.forgetIdentityLogin(id);
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    store.notify('已删除账号', FeedbackType.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.account == null ? '添加账号' : '编辑账号',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            identityLoginTitle(widget.provider),
            style: const TextStyle(color: ThemeDefine.kColorText, height: 1.5),
          ),
          const SizedBox(height: 16),
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Column(
              children: [
                LabeledField(
                  label: identityLoginUsernameLabel(widget.provider),
                  child: TextField(
                    controller: _username,
                    keyboardType: widget.provider == githubIdentityProvider
                        ? TextInputType.text
                        : TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: inCardInput(
                      hint: identityLoginUsernameLabel(widget.provider),
                    ),
                  ),
                ),
                LabeledField(
                  label: '密码',
                  last: true,
                  child: TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: inCardInput(
                      hint: '加密保存在本机',
                      suffix: secretVisibilityButton(
                        visible: _showPassword,
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: '保存账号', onPressed: _save),
          if (widget.account != null) ...[
            const SizedBox(height: 8),
            PrimaryButton(label: '删除账号', outlined: true, onPressed: _delete),
          ],
        ],
      ),
    );
  }
}
