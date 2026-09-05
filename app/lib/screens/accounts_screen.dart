import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/account_form_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/ui.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const SizedBox.expand();
    }
    final store = context.watch<VaultStore>();
    final expired = store.expiredAccounts.length;
    final dns = store.dnsPollutedAccounts.length;
    final blocked = store.wafBlockedAccounts.length;
    final summaryParts = <String>[];
    if (expired > 0) {
      summaryParts.add('需重新登录 $expired 个');
    }
    if (dns > 0) {
      summaryParts.add('域名解析异常 $dns 个');
    }
    if (blocked > 0) {
      summaryParts.add('当前网络打不开 $blocked 个');
    }
    final summary = summaryParts.isNotEmpty
        ? '${summaryParts.join('，')}，共 ${store.accounts.length} 个账号'
        : '已正常 ${store.accounts.where((account) => account.status.name == 'active').length} 个，共 ${store.accounts.length} 个账号';
    const filters = [
      ('全部', 'all'),
      ('正常', 'active'),
      ('需登录', 'expired'),
      ('网络', 'blocked'),
      ('低额度', 'low'),
      ('无额度', 'exhausted'),
    ];

    Future<void> refresh() async {
      final ok = await store.refreshAllAccounts();
      if (ok) {
        store.notify('账号已更新');
      }
    }

    return YuconRefresh(
      onRefresh: refresh,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
      children: [
        YuconCard(
          padding: const EdgeInsets.all(13),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(Theme.of(context).cardColor, const Color(0xFF3178DF), 0.11)!,
              Theme.of(context).cardColor,
            ],
            stops: const [0, 0.65],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('已管理账号', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    '${store.accounts.length}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        TextField(
          decoration: InputDecoration(
            hintText: '搜索备注、站点或用户名',
            prefixIcon: const Icon(Icons.search, size: 18, color: ThemeDefine.kColorText),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: ThemeDefine.kColorPrimary),
            ),
          ),
          onChanged: store.setSearchTerm,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => store.setSelectedAccountStatus(filter.$2),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: store.selectedAccountStatus == filter.$2
                            ? ThemeDefine.kColorSoft
                            : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: store.selectedAccountStatus == filter.$2
                              ? const Color(0x29FA2C19)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        filter.$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.even,
                          color: store.selectedAccountStatus == filter.$2
                              ? ThemeDefine.kColorPrimary
                              : ThemeDefine.kColorText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(1, 14, 1, 9),
          child: Row(
            children: [
              Text(
                '共 ${store.filteredAccounts.length} 个账号',
                style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final ok = await store.refreshAllAccounts();
                  if (ok) {
                    store.notify('账号已更新');
                  }
                },
                child: const Text(
                  '刷新',
                  style: TextStyle(color: ThemeDefine.kColorPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (store.filteredAccounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('没有匹配的账号', style: TextStyle(color: ThemeDefine.kColorText))),
          )
        else
          ...store.filteredAccounts.map(
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
        const SizedBox(height: 14),
        PrimaryButton(
          label: '添加账号',
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountFormScreen()));
          },
        ),
      ],
    ),
    );
  }
}
