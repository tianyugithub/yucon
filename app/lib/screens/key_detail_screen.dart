import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/key_form_screen.dart';
import 'package:vault/screens/key_test_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/api_address_copy.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class KeyDetailScreen extends StatefulWidget {
  const KeyDetailScreen({super.key, required this.keyId});

  final String keyId;

  @override
  State<KeyDetailScreen> createState() => _KeyDetailScreenState();
}

class _KeyDetailScreenState extends State<KeyDetailScreen> {
  bool _showValue = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final apiKey = store.apiKeyById(widget.keyId);
    final account = apiKey == null ? null : store.accountById(apiKey.accountId);
    if (apiKey == null || account == null) {
      return const Scaffold(
        appBar: YuconAppBar(title: '密钥详情'),
        body: Center(child: Text('找不到这把密钥')),
      );
    }
    final preset = getPlatformPreset(account.platformType);
    final meta = apiKeyStatusMeta(apiKey.status);
    final quotaText = apiKey.unlimitedQuota ? '无限额度' : formatCurrency(apiKey.remainQuota);
    final expiryText = apiKey.expiresAt == null ? '永不过期' : formatShortDate(apiKey.expiresAt!);
    final accessedText = apiKey.accessedAt == null ? '从未使用' : formatDateTime(apiKey.accessedAt);

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(
        title: '密钥详情',
        subtitle: '${store.displayAccountName(account)} 的密钥',
        actions: [
          HeaderTextAction(
            label: '编辑',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => KeyFormScreen(keyId: apiKey.id)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(1, 4, 1, 13),
            child: Row(
              children: [
                const SquareIcon(
                  size: 46,
                  radius: 14,
                  color: Color(0xFFEDF4FF),
                  child: TabIcon(name: YuconTabIcon.keys, size: 20, color: Color(0xFF3178DF)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              apiKey.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(label: meta.label, color: meta.color, background: meta.background),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${account.siteName} · ${store.tokenGroupLabel(account.id, apiKey.group)} · 最近使用：$accessedText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (account.status == AccountStatus.expired)
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '所属账号登录已过期，显示或修改密钥前请先重新登录。',
                    style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '去重新登录',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: account.id)),
                      );
                    },
                  ),
                ],
              ),
            ),
          if (account.status == AccountStatus.blocked)
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    account.dnsPolluted
                        ? '不是登录过期。当前网络的域名解析不正常，请到「我的」换代理后再回来操作。'
                        : '不是登录过期。当前网络打不开这个网站，请到「我的」换代理后再回来操作。',
                    style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '去账号详情处理',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: account.id)),
                      );
                    },
                  ),
                ],
              ),
            ),
          YuconCard(
            padding: const EdgeInsets.all(13),
            child: Column(
              children: [
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
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('密钥', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          _showValue ? apiKey.key : maskSecret(apiKey.key),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          if (_showValue) {
                            setState(() => _showValue = false);
                            return;
                          }
                          try {
                            await store.revealApiKey(apiKey.id);
                            setState(() => _showValue = true);
                          } catch (error) {
                            store.notify(userFacingError(error, '无法显示完整密钥'), FeedbackType.error);
                          }
                        },
                        child: Text(_showValue ? '隐藏' : '显示'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          try {
                            final value = await store.revealApiKey(apiKey.id);
                            await Clipboard.setData(ClipboardData(text: value));
                            store.notify('复制成功');
                          } catch (error) {
                            store.notify(userFacingError(error, '复制失败'), FeedbackType.error);
                          }
                        },
                        child: const Text('复制'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ApiAddressCopy(account: account, store: store),
          YuconCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('剩余额度', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  quotaText,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                ),
                const SizedBox(height: 8),
                Text(
                  '已使用 ${formatCurrency(apiKey.usedQuota)} · 有效期 $expiryText',
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                ),
              ],
            ),
          ),
          PrimaryButton(
            label: '测试模型',
            outlined: true,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => KeyTestScreen(keyId: apiKey.id)),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: apiKey.status == ApiKeyStatus.enabled ? '停用密钥' : '启用密钥',
                  outlined: true,
                  onPressed: () async {
                    try {
                      final updated = await store.toggleApiKeyStatus(apiKey.id);
                      if (updated == null) {
                        return;
                      }
                      if (updated.status == ApiKeyStatus.expired || updated.status == ApiKeyStatus.exhausted) {
                        store.notify('已过期或额度用完的密钥无法直接启用', FeedbackType.warning);
                        return;
                      }
                      store.notify(updated.status == ApiKeyStatus.enabled ? '密钥已启用' : '密钥已停用');
                    } catch (error) {
                      store.notify(userFacingError(error, '更新失败'), FeedbackType.error);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: '修改设置',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => KeyFormScreen(keyId: apiKey.id)),
                    );
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(1, 22, 1, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text('使用范围', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Flexible(
                  child: Text(
                    preset.supportsKeyModelLimits ? '来自站点当前设置' : '该站点不单独限制模型',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          GroupCard(
            children: [
              GroupTile(title: '分组', value: store.tokenGroupLabel(account.id, apiKey.group)),
              GroupTile(title: '允许使用的 IP', value: apiKey.allowIps.isEmpty ? '不限制' : apiKey.allowIps.join('、')),
              if (preset.supportsCrossGroupRetry)
                GroupTile(title: '失败后自动换分组', value: apiKey.crossGroupRetry ? '已开启' : '未开启'),
              if (!preset.supportsKeyModelLimits)
                const GroupTile(title: '模型限制', value: '不限制，分组内模型都能用')
              else if (apiKey.modelLimits.isEmpty)
                const GroupTile(title: '模型限制', value: '不限制'),
            ],
          ),
          if (preset.supportsKeyModelLimits && apiKey.modelLimits.isNotEmpty)
            YuconCard(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('模型限制', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  for (final name in apiKey.modelLimits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          ModelBrandIcon(model: name, size: ModelBrandIconSize.sm),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 41,
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final ok = await showModalBottomSheet<bool>(
                  context: context,
                  builder: (context) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('删除这把密钥？', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text('会同时从站点上删除，删除后无法恢复。'),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 41,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
                              child: const Text('确认删除'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          PrimaryButton(label: '取消', outlined: true, onPressed: () => Navigator.pop(context, false)),
                        ],
                      ),
                    );
                  },
                );
                if (ok == true) {
                  try {
                    await store.deleteApiKey(apiKey.id);
                    store.notify('密钥已删除');
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  } catch (error) {
                    store.notify(userFacingError(error, '删除失败'), FeedbackType.error);
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5484D),
                side: const BorderSide(color: Color(0xFFE5484D)),
                shape: const StadiumBorder(),
              ),
              child: const Text('删除密钥', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
