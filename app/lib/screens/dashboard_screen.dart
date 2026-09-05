import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/account_form_screen.dart';
import 'package:vault/screens/model_compare_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/balance_card.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    this.active = true,
    this.onOpenAccounts,
    this.onOpenKeys,
    this.onOpenLogs,
  });

  final bool active;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenKeys;
  final VoidCallback? onOpenLogs;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const SizedBox.expand();
    }
    final store = context.watch<VaultStore>();
    final recent = store.accounts.take(3).toList();
    final expired = store.expiredAccounts.length;
    final dns = store.dnsPollutedAccounts.length;
    final blocked = store.wafBlockedAccounts.length;
    final exhausted = store.exhaustedAccounts.length;
    final low = store.lowQuotaAccounts.length;
    final parts = <String>[];
    if (expired > 0) {
      parts.add('$expired 个需重新登录');
    }
    if (dns > 0) {
      parts.add('$dns 个域名解析异常');
    }
    if (blocked > 0) {
      parts.add('$blocked 个当前网络打不开');
    }
    final statusMessage = store.accounts.isEmpty
        ? '还没有连接账号'
        : parts.isNotEmpty
        ? parts.join('，')
        : exhausted > 0
        ? '$exhausted 个账号没有额度'
        : low > 0
        ? '$low 个账号额度偏低'
        : '全部账号额度状态正常';
    final healthDescription = store.accounts.isEmpty
        ? '添加账号后即可同步额度和密钥'
        : expired > 0
        ? '打开账号详情重新登录即可'
        : dns > 0
        ? '当前网络的域名解析不正常，到「我的」换代理后再同步'
        : blocked > 0
        ? '不是没网。这个网站当前打不开，到「我的」换代理后再同步'
        : exhausted > 0
        ? '可以在账号页筛选无额度查看'
        : low > 0
        ? '提醒额度：${store.settings.lowQuotaThreshold.toStringAsFixed(2)} 美元'
        : '${store.activeApiKeyCount} 个密钥可正常使用';
    final warning = expired > 0 || dns > 0 || blocked > 0 || exhausted > 0 || low > 0;

    Future<void> refresh() async {
      final ok = await store.refreshAllAccounts();
      if (ok && !store.feedback.visible) {
        store.notify('额度已更新');
      }
    }

    Future<void> checkin() async {
      final summary = store.summarizeCheckin(await store.checkinAll());
      store.notify(summary.message, summary.type);
    }

    final quickItems = <(Color, Widget, String, VoidCallback)>[
      if (store.todayCheckinStatus.total > 0)
        (const Color(0xFFFA2C19), const Icon(Icons.check, color: Colors.white, size: 15), '快速签到', checkin),
      (
        const Color(0xFF25272B),
        const TabIcon(name: YuconTabIcon.keys, size: 15, color: Colors.white),
        '密钥管理',
        onOpenKeys ?? () {},
      ),
      (
        const Color(0xFF3178DF),
        const Icon(Icons.add, color: Colors.white, size: 18),
        '添加账号',
        () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountFormScreen())),
      ),
      (
        const Color(0xFF8257E6),
        const TabIcon(name: YuconTabIcon.logs, size: 15, color: Colors.white),
        '调用日志',
        onOpenLogs ?? () {},
      ),
    ];

    return YuconRefresh(
      onRefresh: refresh,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(1, 4, 1, 12),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('账号额度总览', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text('同步各站点余额、密钥与用量', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                  ],
                ),
              ),
              StatusChip(
                label: '${store.accounts.length} 个账号',
                color: const Color(0xFFD91D0D),
                background: ThemeDefine.kColorSoft,
              ),
            ],
          ),
        ),
        BalanceOverviewCard(
          totalQuota: store.totalQuota,
          todayUsage: store.todayUsage,
          accountCount: store.accounts.length,
          checkinDone: store.todayCheckinStatus.done,
          checkinTotal: store.todayCheckinStatus.total,
          loading: store.isRefreshing,
          onRefresh: refresh,
          onCheckin: checkin,
          excludedCount: store.excludedFromTotalCount,
        ),
        YuconCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              SquareIcon(
                size: 24,
                radius: 8,
                color: warning ? ThemeDefine.kColorSoft : const Color(0xFFE7F7EF),
                child: Text(
                  warning ? '!' : '✓',
                  style: TextStyle(
                    color: warning ? ThemeDefine.kColorPrimary : const Color(0xFF168553),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      healthDescription,
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
        const SectionTitle(text: '快捷操作'),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: i < quickItems.length
                    ? _quick(quickItems[i].$1, quickItems[i].$2, quickItems[i].$3, quickItems[i].$4)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
        YuconCard(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ModelCompareScreen()),
            );
          },
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              const SquareIcon(
                size: 28,
                radius: 9,
                color: Color(0xFF0F766E),
                child: Icon(Icons.stacked_bar_chart, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('模型比价', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      '按人民币对比实际花费',
                      style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ThemeDefine.kColorText),
            ],
          ),
        ),
        SectionTitle(text: '最近账号', action: '查看全部', onAction: onOpenAccounts),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text('还没有添加账号', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13)),
            ),
          )
        else
          ...recent.map(
            (account) => AccountCard(
              account: account,
              store: store,
              onOpen: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: account.id)),
                );
              },
            ),
          ),
        const SizedBox(height: 11),
        PrimaryButton(label: '管理账号', outlined: true, onPressed: onOpenAccounts),
      ],
    ),
    );
  }

  Widget _quick(Color color, Widget icon, String label, VoidCallback onTap) {
    return YuconCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SquareIcon(size: 28, radius: 9, color: color, child: icon),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}
