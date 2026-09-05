import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/screens/account_form_screen.dart';
import 'package:vault/screens/key_detail_screen.dart';
import 'package:vault/screens/key_form_screen.dart';
import 'package:vault/screens/model_compare_screen.dart';
import 'package:vault/screens/site_login_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/api_key_card.dart';
import 'package:vault/screens/widgets/quota_trend.dart';
import 'package:vault/screens/widgets/ui.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  bool _relogging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VaultStore>().loadTokenGroups(widget.accountId).catchError((_) => <TokenGroupOption>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final account = store.accountById(widget.accountId);
    if (account == null) {
      return SecureScope(
        child: Scaffold(
        appBar: const YuconAppBar(title: '账号详情'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('未找到该账号', style: TextStyle(color: ThemeDefine.kColorText))),
            ),
            PrimaryButton(label: '返回账号列表', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
      );
    }
    final preset = getPlatformPreset(account.platformType);
    final meta = accountDisplayMeta(account);
    final keys = store.apiKeysForAccount(account.id);
    final checkinText = !account.checkinEnabled
        ? '—'
        : store.isCheckedInToday(account)
        ? '今日已签到'
        : account.lastCheckin == null
        ? '尚未签到'
        : formatDateTime(account.lastCheckin);

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(
        title: '账号详情',
        subtitle: '${preset.label} 账号',
        actions: [
          HeaderTextAction(
            label: '编辑',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AccountFormScreen(accountId: account.id)),
              );
            },
          ),
        ],
      ),
      body: YuconRefresh(
        onRefresh: () async {
          try {
            await store.syncAccount(account.id);
            store.notify('账号已同步');
          } catch (error) {
            store.notify(userFacingError(error, '同步失败'), FeedbackType.error);
          }
        },
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(1, 4, 1, 13),
            child: Row(
              children: [
                SquareIcon(
                  size: 46,
                  radius: 14,
                  color: Color(preset.color),
                  child: Text(
                    preset.shortLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
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
                              store.displayAccountName(account),
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
                        '${account.siteName} · @${account.username.isEmpty ? '未填写用户名' : account.username}',
                        maxLines: 1,
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
                  const Text('登录已过期', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text(
                    '登录过期后无法同步额度和密钥。点下方会打开站点登录页，登录成功后即可继续使用。',
                    style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '重新登录',
                    busy: _relogging,
                    onPressed: () async {
                      setState(() => _relogging = true);
                      try {
                        final result = await store.reloginAccount(
                          account.id,
                          capture: () async {
                            final session = await captureSiteSession(
                              context,
                              baseUrl: account.baseUrl,
                              platformType: account.platformType,
                              email: account.email.isNotEmpty ? account.email : account.username,
                              proxy: store.resolvedProxy(account.proxy),
                            );
                            return (
                              accessToken: session.accessToken,
                              refreshToken: session.refreshToken,
                              cookies: session.cookies,
                            );
                          },
                        );
                        if (result == 'need-form' && context.mounted) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => AccountFormScreen(accountId: account.id)),
                          );
                          return;
                        }
                        store.notify('已重新登录并同步');
                      } catch (error) {
                        store.notify(userFacingError(error, '重新登录失败'), FeedbackType.error);
                      } finally {
                        if (mounted) {
                          setState(() => _relogging = false);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          if (account.dnsPolluted)
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('域名解析不正常', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text(
                    '不是登录过期。当前网络可能把这个域名解析到了错误地址。可到「我的」换一个可用代理后再同步。',
                    style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '换好代理后重新同步',
                    onPressed: () async {
                      try {
                        await store.syncAccount(account.id);
                        store.notify('账号已同步');
                      } catch (error) {
                        store.notify(userFacingError(error, '同步失败'), FeedbackType.error);
                      }
                    },
                  ),
                ],
              ),
            )
          else if (account.status == AccountStatus.blocked)
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('当前网络打不开这个网站', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text(
                    '不是没网，也不是登录过期。是这个网站当前打不开。可到「我的」换一个可用代理后再同步。',
                    style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: '换好代理后重新同步',
                    outlined: true,
                    onPressed: () async {
                      try {
                        await store.syncAccount(account.id);
                        store.notify('账号已同步');
                      } catch (error) {
                        store.notify(userFacingError(error, '同步失败'), FeedbackType.error);
                      }
                    },
                  ),
                ],
              ),
            ),
          YuconCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前可用额度', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  formatCurrency(account.quota),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
                ),
                const SizedBox(height: 8),
                Text(
                  '累计已用 ${formatCurrency(account.usedQuota)} · 累计调用 ${account.requestCount}',
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: '同步账号',
                  outlined: true,
                  onPressed: () async {
                    try {
                      await store.syncAccount(account.id);
                      store.notify('账号已同步');
                    } catch (error) {
                      store.notify(userFacingError(error, '同步失败'), FeedbackType.error);
                    }
                  },
                ),
              ),
              if (account.checkinEnabled) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: store.isCheckedInToday(account) ? '今日已签到' : '立即签到',
                    outlined: true,
                    onPressed: () async {
                      final result = await store.checkinAccount(account.id);
                      if (result != null) {
                        store.notify(result.message, result.success ? FeedbackType.success : FeedbackType.warning);
                      }
                    },
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: '添加密钥',
                  onPressed: account.needsRelogin || account.networkBlocked
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => KeyFormScreen(accountId: account.id)),
                          );
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          YuconCard(
            padding: const EdgeInsets.all(14),
            child: QuotaTrend(points: account.trend),
          ),
          const SectionTitle(text: '账号信息'),
          GroupCard(
            children: [
              GroupTile(title: '站点地址', value: account.baseUrl),
              if (account.apiUrls.isNotEmpty)
                for (final url in account.apiUrls)
                  GroupTile(title: '调用地址', value: url),
              GroupTile(title: '账号类型', value: preset.label),
              GroupTile(title: '站点名称', value: account.siteName),
              GroupTile(title: '代理', value: account.proxy.label),
              GroupTile(title: '用户名', value: account.username.isEmpty ? '未填写' : account.username),
              GroupTile(title: '用户 ID', value: account.userId.isEmpty ? '未填写' : account.userId),
              GroupTile(title: '邮箱', value: account.email.isEmpty ? '未填写' : account.email),
              GroupTile(title: '默认分组', value: account.group.isEmpty ? '默认' : account.group),
              GroupTile(
                title: '充值比例',
                value: formatTopupRatioExplain(account.topupRatio),
              ),
              if (preset.supportsModelCatalog)
                GroupTile(
                  title: '模型比价',
                  value: '查看报价',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ModelCompareScreen(accountId: account.id),
                      ),
                    );
                  },
                ),
              if (account.checkinEnabled) GroupTile(title: '最近签到', value: checkinText),
              GroupTile(
                title: '最近同步',
                value: account.lastSyncedAt == null ? '尚未同步' : formatDateTime(account.lastSyncedAt),
              ),
              if (account.lastError != null) GroupTile(title: '上次问题', value: account.lastError),
            ],
          ),
          SectionTitle(
            text: '密钥',
            action: '添加密钥',
            onAction: account.needsRelogin || account.networkBlocked
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => KeyFormScreen(accountId: account.id)),
                    );
                  },
          ),
          if (keys.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('这个账号还没有密钥', style: TextStyle(color: ThemeDefine.kColorText))),
            )
          else
            for (final apiKey in keys)
              ApiKeyCard(
                apiKey: apiKey,
                store: store,
                onOpen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => KeyDetailScreen(keyId: apiKey.id)),
                  );
                },
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
                          const Text('删除这个账号？', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text('这个账号下的密钥、签到和调用记录会一并删除。'),
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
                  await store.deleteAccount(account.id);
                  store.notify('账号已删除');
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5484D),
                side: const BorderSide(color: Color(0xFFE5484D)),
                shape: const StadiumBorder(),
              ),
              child: const Text('删除账号', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      ),
    ),
    );
  }
}
