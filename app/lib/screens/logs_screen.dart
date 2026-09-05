import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/model_brands.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

const _pageSizes = [10, 20, 50];

const _logTypes = [
  (2, '消费'),
  (5, '错误'),
  (1, '充值'),
  (0, '全部类型'),
];

const _ranges = [
  (UsageTimeRange.today, '今天'),
  (UsageTimeRange.days7, '近7天'),
  (UsageTimeRange.days30, '近30天'),
  (UsageTimeRange.all, '全部时间'),
];

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, this.active = true});

  final bool active;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _usage = true;
  String? _usageAccountId;
  String? _checkinSiteKey;
  int _page = 1;
  int _checkinPage = 1;
  int _pageSize = 20;
  int _logType = 0;
  UsageTimeRange _range = UsageTimeRange.all;
  String _tokenName = '';
  String _modelName = '';
  String _group = '';
  bool _loading = false;
  bool _bootstrapped = false;
  String? _error;
  UsageLogQueryResult? _result;
  String? _resultAccountId;
  int _loadSeq = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _allAccounts => _usageAccountId == '';

  Account? _usageAccount(VaultStore store) {
    if (store.accounts.isEmpty || _allAccounts) {
      return null;
    }
    return store.accountById(_usageAccountId ?? '') ??
        store.selectedKeysAccount ??
        store.accounts.first;
  }

  String _resultKey(VaultStore store) {
    if (_allAccounts) {
      return '';
    }
    return _usageAccount(store)?.id ?? '';
  }

  bool _isSub2(Account? account) =>
      account?.platformType == PlatformType.sub2api;

  String _rangeLabel(UsageTimeRange range) =>
      _ranges.firstWhere((item) => item.$1 == range).$2;

  String _typeLabel(int type) => type == 0
      ? '全部类型'
      : _logTypes.firstWhere((item) => item.$1 == type, orElse: () => (type, usageLogTypeLabel(type))).$2;

  UsageLogQuery _queryFor(Account? account) => UsageLogQuery(
    accountId: account?.id ?? '',
    page: _page,
    pageSize: _pageSize,
    type: _isSub2(account) ? 2 : _logType,
    range: _range,
    tokenName: _tokenName,
    modelName: _modelName,
    group: _group,
  );

  String _checkinKey(CheckinLog log, VaultStore store) {
    final host = log.siteHost.trim();
    if (host.isNotEmpty) {
      return host.toLowerCase();
    }
    final account = store.accountById(log.accountId);
    if (account != null) {
      final fromAccount = hostnameOf(account.baseUrl).trim();
      if (fromAccount.isNotEmpty) {
        return fromAccount.toLowerCase();
      }
    }
    return store.siteLabelForCheckin(log).toLowerCase();
  }

  List<CheckinLog> _filteredCheckins(VaultStore store) {
    final logs = [...store.checkinLogs]
      ..sort((a, b) => DateTime.parse(b.time).compareTo(DateTime.parse(a.time)));
    final key = _checkinSiteKey;
    if (key == null || key.isEmpty) {
      return logs;
    }
    return logs.where((log) => _checkinKey(log, store) == key).toList();
  }

  List<(String, String)> _checkinSites(VaultStore store) {
    final seen = <String>{};
    final sites = <(String, String)>[];
    for (final log in store.checkinLogs) {
      final key = _checkinKey(log, store);
      if (seen.add(key)) {
        sites.add((key, store.siteLabelForCheckin(log)));
      }
    }
    return sites;
  }

  Future<void> _reload({
    bool resetPage = false,
    bool notifyError = false,
  }) async {
    final store = context.read<VaultStore>();
    if (store.accounts.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final account = _allAccounts ? null : _usageAccount(store);
    if (!_allAccounts && account == null) {
      setState(() {
        _result = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    if (resetPage) {
      _page = 1;
    }
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await store.queryUsageLogs(_queryFor(account));
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _result = result;
        _resultAccountId = account?.id ?? '';
        _page = result.page;
        _loading = false;
        _error = null;
      });
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || seq != _loadSeq) {
        return;
      }
      final message = userFacingError(error, '获取日志失败');
      setState(() {
        _loading = false;
        _error = message;
      });
      if (notifyError) {
        store.notify(message, FeedbackType.error);
      }
    }
  }

  Future<void> _openUsageFilters(VaultStore store, Account? account) async {
    final selectedId = _usageAccountId ?? account?.id ?? '';
    final showTypeFilters = selectedId.isEmpty
        ? store.accounts.any(
            (item) => item.platformType != PlatformType.sub2api,
          )
        : !_isSub2(store.accountById(selectedId));
    final next = await showModalBottomSheet<_UsageFilterValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _UsageFilterSheet(
        accounts: store.accounts,
        selectedAccountId: selectedId,
        range: _range,
        type: showTypeFilters ? _logType : 2,
        tokenName: _tokenName,
        modelName: _modelName,
        group: _group,
        showTypeFilters: showTypeFilters,
        nameOf: store.displayAccountName,
      ),
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _usageAccountId = next.accountId;
      _range = next.range;
      _logType = next.type;
      _tokenName = next.tokenName;
      _modelName = next.modelName;
      _group = next.group;
    });
    await _reload(resetPage: true);
  }

  Future<void> _openCheckinFilters(VaultStore store) async {
    final sites = _checkinSites(store);
    final next = await showModalBottomSheet<_SitePick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CheckinFilterSheet(
        sites: sites,
        selectedKey: _checkinSiteKey,
      ),
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _checkinSiteKey = next.key;
      _checkinPage = 1;
    });
  }

  Future<void> _jumpPage(int current, int last) async {
    final controller = TextEditingController(text: '$current');
    final next = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('跳转到页码'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: '1 - $last'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, int.tryParse(controller.text.trim()));
              },
              child: const Text('前往'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || !mounted) {
      return;
    }
    final page = next.clamp(1, last);
    if (_usage) {
      if (page == _page) {
        return;
      }
      setState(() => _page = page);
      await _reload();
      return;
    }
    if (page == _checkinPage) {
      return;
    }
    setState(() => _checkinPage = page);
  }

  @override
  void didUpdateWidget(LogsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && context.read<VaultStore>().accounts.isNotEmpty) {
      _bootstrapped = true;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.expand();
    }
    final store = context.watch<VaultStore>();
    final usageAccount = _usageAccount(store);
    if (!_bootstrapped && store.accounts.isNotEmpty) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reload();
        }
      });
    }
    final result = _resultAccountId == _resultKey(store) ? _result : null;
    final usageCount = result == null
        ? (_allAccounts
              ? store.usageLogs.length
              : (usageAccount == null
                    ? 0
                    : store.usageLogsForAccount(usageAccount.id).length))
        : (result.totalKnown ? result.total : result.items.length);
    final checkins = _filteredCheckins(store);
    final checkinTotal = roundMoney(
      checkins
          .where((log) => log.success && log.reward != null)
          .fold<double>(0, (sum, log) => sum + log.reward!),
    );
    final checkinSuccess = checkins.where((log) => log.success).length;
    final checkinPages = checkins.isEmpty
        ? 1
        : ((checkins.length + _pageSize - 1) ~/ _pageSize);
    final checkinPage = _checkinPage.clamp(1, checkinPages);
    final checkinSlice = checkins.isEmpty
        ? const <CheckinLog>[]
        : checkins.sublist(
            (checkinPage - 1) * _pageSize,
            (checkinPage * _pageSize).clamp(0, checkins.length),
          );
    final selectedSiteLabel = _checkinSiteKey == null
        ? '全部站点'
        : _checkinSites(store)
            .where((item) => item.$1 == _checkinSiteKey)
            .map((item) => item.$2)
            .firstWhere((label) => label.isNotEmpty, orElse: () => '当前站点');
    final showUsagePager =
        _usage && result != null && (result.items.isNotEmpty || result.page > 1);
    final showCheckinPager = !_usage && checkins.length > _pageSize;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 0),
          child: YuconCard(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _switch('调用日志', formatCompactCount(usageCount), _usage, () {
                  setState(() => _usage = true);
                }),
                _switch(
                  '签到记录',
                  formatCompactCount(store.checkinLogs.length),
                  !_usage,
                  () {
                    setState(() => _usage = false);
                  },
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 2,
          child: _usage && _loading
              ? const LinearProgressIndicator(
                  minHeight: 2,
                  color: ThemeDefine.kColorPrimary,
                  backgroundColor: Colors.transparent,
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 0),
          child: _usage
              ? _UsageSummaryCard(
                  accountLabel: _allAccounts
                      ? '全部账号'
                      : usageAccount == null
                      ? '未选择账号'
                      : store.displayAccountName(usageAccount),
                  rangeLabel: _rangeLabel(_range),
                  typeLabel: _isSub2(usageAccount) ? '消费' : _typeLabel(_logType),
                  extraFilters:
                      _range != UsageTimeRange.all ||
                      (!_isSub2(usageAccount) && _logType != 0) ||
                      _tokenName.trim().isNotEmpty ||
                      _modelName.trim().isNotEmpty ||
                      _group.trim().isNotEmpty,
                  result: result,
                  logType: _isSub2(usageAccount) ? 2 : _logType,
                  loading: _loading && result == null,
                  onFilter: store.accounts.isEmpty
                      ? null
                      : () => _openUsageFilters(store, usageAccount),
                )
              : _CheckinSummaryCard(
                  siteLabel: selectedSiteLabel,
                  total: checkinTotal,
                  successCount: checkinSuccess,
                  totalCount: checkins.length,
                  onFilter: store.checkinLogs.isEmpty
                      ? null
                      : () => _openCheckinFilters(store),
                ),
        ),
        Expanded(
          child: YuconRefresh(
            onRefresh: () async {
              if (_usage && store.accounts.isNotEmpty) {
                await _reload(notifyError: true);
                if (!mounted || _error != null) {
                  return;
                }
                store.notify('记录已更新');
                return;
              }
              final ok = await store.refreshAllAccounts();
              if (ok) {
                store.notify('记录已更新');
              }
            },
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
              children: [
                if (_usage) ...[
                  if (store.accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          '还没有账号，添加后即可查看调用日志',
                          style: TextStyle(color: ThemeDefine.kColorText),
                        ),
                      ),
                    )
                  else ...[
                    if (_error != null) ...[
                      TipBanner(text: _error!),
                      PrimaryButton(
                        label: '重新加载',
                        outlined: true,
                        onPressed: () {
                          _reload();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (result == null && _loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (result != null && result.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            '这个筛选范围内没有调用日志',
                            style: TextStyle(color: ThemeDefine.kColorText),
                          ),
                        ),
                      )
                    else if (result != null)
                      for (final log in result.items)
                        _UsageLogCard(
                          log: log,
                          showIp: store.settings.recordIpLog,
                        ),
                  ],
                ] else ...[
                  if (checkins.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          '暂无签到记录',
                          style: TextStyle(color: ThemeDefine.kColorText),
                        ),
                      ),
                    )
                  else
                    for (final log in checkinSlice)
                      _CheckinLogCard(log: log, store: store),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 17),
                  child: Center(
                    child: Text(
                      _usage ? '下拉可刷新当前筛选的记录' : '以上是最近同步的签到记录',
                      style: const TextStyle(
                        color: ThemeDefine.kColorText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showUsagePager)
          _PaginationBar(
            page: result.page,
            pageCount: result.pageCount,
            pageSize: _pageSize,
            loading: _loading,
            totalKnown: result.totalKnown,
            onPrev: result.hasPrev && !_loading
                ? () {
                    setState(() => _page = _page - 1);
                    _reload();
                  }
                : null,
            onNext: result.hasNext && !_loading
                ? () {
                    setState(() => _page = _page + 1);
                    _reload();
                  }
                : null,
            onJump: _loading
                ? null
                : () => _jumpPage(result.page, result.pageCount),
            onPageSize: _loading
                ? null
                : (size) {
                    setState(() => _pageSize = size);
                    _reload(resetPage: true);
                  },
          )
        else if (showCheckinPager)
          _PaginationBar(
            page: checkinPage,
            pageCount: checkinPages,
            pageSize: _pageSize,
            loading: false,
            totalKnown: true,
            onPrev: checkinPage > 1
                ? () => setState(() => _checkinPage = checkinPage - 1)
                : null,
            onNext: checkinPage < checkinPages
                ? () => setState(() => _checkinPage = checkinPage + 1)
                : null,
            onJump: () => _jumpPage(checkinPage, checkinPages),
            onPageSize: (size) {
              setState(() {
                _pageSize = size;
                _checkinPage = 1;
              });
            },
          ),
      ],
    );
  }

  Widget _switch(String label, String count, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ThemeDefine.kColorSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: active
                      ? ThemeDefine.kColorPrimary
                      : ThemeDefine.kColorText,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0x1FFA2C19)
                      : const Color(0x247D8490),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  count,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: active
                        ? ThemeDefine.kColorPrimary
                        : ThemeDefine.kColorText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SitePick {
  const _SitePick(this.key);

  final String? key;
}

class _UsageFilterValue {
  const _UsageFilterValue({
    required this.accountId,
    required this.range,
    required this.type,
    required this.tokenName,
    required this.modelName,
    required this.group,
  });

  final String accountId;
  final UsageTimeRange range;
  final int type;
  final String tokenName;
  final String modelName;
  final String group;
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.maxWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 220),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? ThemeDefine.kColorSoft : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? const Color(0x29FA2C19) : ThemeDefine.kColorLine,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
                color: selected
                    ? ThemeDefine.kColorPrimary
                    : ThemeDefine.kColorText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageSummaryCard extends StatelessWidget {
  const _UsageSummaryCard({
    required this.accountLabel,
    required this.rangeLabel,
    required this.typeLabel,
    required this.extraFilters,
    required this.result,
    required this.logType,
    required this.loading,
    required this.onFilter,
  });

  final String accountLabel;
  final String rangeLabel;
  final String typeLabel;
  final bool extraFilters;
  final UsageLogQueryResult? result;
  final int logType;
  final bool loading;
  final VoidCallback? onFilter;

  @override
  Widget build(BuildContext context) {
    final amount = result?.quotaTotal;
    final amountColor = logType == 1 || logType == 6
        ? const Color(0xFF168553)
        : ThemeDefine.kColorPrimary;
    final allOnPage = result != null &&
        result!.totalKnown &&
        result!.items.length >= result!.total;
    final quotaLabel = switch (logType) {
      1 => allOnPage || result == null ? '充值额度总计' : '本页充值金额',
      5 => '涉及额度',
      6 => allOnPage || result == null ? '退还额度总计' : '本页退还金额',
      _ => '消耗额度总计',
    };
    final countText = result == null
        ? (loading ? '加载中' : '—')
        : (result!.totalKnown
              ? '共 ${formatGroupedInt(result!.total)} 条'
              : '本页 ${formatGroupedInt(result!.items.length)} 条');
    final rpmTpm = result == null || logType == 1 || logType == 6
        ? ''
        : 'RPM ${formatGroupedInt(result!.rpm)} · TPM ${formatGroupedInt(result!.tpm)} · ';
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quotaLabel,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                amount == null
                    ? (loading ? '…' : '—')
                    : (logType == 1 || logType == 6
                          ? '+${formatLogMoney(amount)}'
                          : formatLogMoney(amount)),
                style: TextStyle(
                  color: amountColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$rpmTpm$countText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                  ),
                ),
              ),
              _FilterButton(onTap: onFilter),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            extraFilters
                ? '$accountLabel · $rangeLabel · $typeLabel'
                : '$accountLabel · 全部记录',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA0A5AD),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckinSummaryCard extends StatelessWidget {
  const _CheckinSummaryCard({
    required this.siteLabel,
    required this.total,
    required this.successCount,
    required this.totalCount,
    required this.onFilter,
  });

  final String siteLabel;
  final double total;
  final int successCount;
  final int totalCount;
  final VoidCallback? onFilter;

  @override
  Widget build(BuildContext context) {
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '合计获得额度',
                  style: TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '+${formatLogMoney(total)}',
                  style: const TextStyle(
                    color: Color(0xFF168553),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              _FilterButton(onTap: onFilter),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$siteLabel · 成功 $successCount 次 · 共 $totalCount 条',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFA0A5AD),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: ThemeDefine.kColorPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('筛选'),
    );
  }
}

class _UsageLogCard extends StatelessWidget {
  const _UsageLogCard({required this.log, required this.showIp});

  final UsageLog log;
  final bool showIp;

  bool get _isTopup => log.type == 1 || log.type == 6;
  bool get _isError => log.type == 5;

  String get _title {
    if (_isTopup) {
      return log.type == 6 ? '额度退还' : '额度充值';
    }
    if (_isError) {
      final model = log.model.trim();
      if (model.isNotEmpty && model != '未知模型') {
        return model;
      }
      return '调用错误';
    }
    final model = log.model.trim();
    return model.isEmpty || model == '未知模型' ? '调用记录' : model;
  }

  bool get _showTokens =>
      !_isTopup &&
      (log.type == 2 ||
          log.promptTokens > 0 ||
          log.completionTokens > 0);

  @override
  Widget build(BuildContext context) {
    final duration = formatUseTime(log.useTime);
    final details = <String>[
      if (!_isTopup && log.apiKeyName.trim().isNotEmpty && log.apiKeyName != '未命名密钥')
        log.apiKeyName,
      if (log.group.trim().isNotEmpty) '分组 ${log.group.trim()}',
      if (log.isStream) '流式',
      if (duration.isNotEmpty) duration,
      if (showIp && log.ip.trim().isNotEmpty) log.ip.trim(),
    ];
    final quotaColor = _isTopup
        ? const Color(0xFF168553)
        : (_isError ? const Color(0xFFC54638) : ThemeDefine.kColorPrimary);
    final amount = formatUsageQuota(log.quotaCost, log.type);
    return YuconCard(
      padding: const EdgeInsets.all(12),
      borderColor: _isError ? const Color(0x33FA2C19) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _isTopup
                ? SquareIcon(
                    size: 27,
                    radius: 9,
                    color: const Color(0xFFE7F7EF),
                    child: Text(
                      log.type == 6 ? '↩' : '+',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF168553),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : _isError &&
                      (log.model.trim().isEmpty || log.model == '未知模型')
                ? SquareIcon(
                    size: 27,
                    radius: 9,
                    color: ThemeDefine.kColorSoft,
                    child: const Text(
                      '!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ThemeDefine.kColorPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ModelBrandIcon(model: log.model),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_isTopup)
                          const Text(
                            '充值金额',
                            style: TextStyle(
                              color: ThemeDefine.kColorText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          amount,
                          style: TextStyle(
                            color: quotaColor,
                            fontSize: _isTopup ? 15 : 12,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_isTopup) ...[
                  const SizedBox(height: 3),
                  Text(
                    log.content.trim().isEmpty
                        ? '余额到账 ${formatLogMoney(log.quotaCost)}'
                        : log.content.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_showTokens) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${log.apiKeyName} · 输入 ${formatGroupedInt(log.promptTokens)} / 输出 ${formatGroupedInt(log.completionTokens)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_isError && log.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    log.content.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC54638),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (!_isTopup &&
                    !_isError &&
                    log.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    log.content.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${getPlatformPreset(log.platformType).label} · ${usageLogTypeLabel(log.type)}${log.success ? '' : ' · 失败'}',
                        style: const TextStyle(
                          color: Color(0xFFA0A5AD),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      formatDateTimeFull(log.time),
                      style: const TextStyle(
                        color: Color(0xFFA0A5AD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckinLogCard extends StatelessWidget {
  const _CheckinLogCard({required this.log, required this.store});

  final CheckinLog log;
  final VaultStore store;

  @override
  Widget build(BuildContext context) {
    final account = store.accountById(log.accountId);
    final name = account == null ? '已删除账号' : store.displayAccountName(account);
    return YuconCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SquareIcon(
            size: 27,
            radius: 9,
            color: log.success
                ? const Color(0xFFE7F7EF)
                : ThemeDefine.kColorSoft,
            child: Text(
              log.success ? '✓' : '!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: log.success
                    ? const Color(0xFF168553)
                    : ThemeDefine.kColorPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      log.success
                          ? (log.reward == null
                                ? '已完成'
                                : '+${formatLogMoney(log.reward!)}')
                          : '未到账',
                      style: TextStyle(
                        color: log.success
                            ? const Color(0xFF168553)
                            : ThemeDefine.kColorText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  store.siteLabelForCheckin(log),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  log.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        getPlatformPreset(log.platformType).label,
                        style: const TextStyle(
                          color: Color(0xFFA0A5AD),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      formatDateTimeFull(log.time),
                      style: const TextStyle(
                        color: Color(0xFFA0A5AD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.pageSize,
    required this.loading,
    required this.totalKnown,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
    required this.onPageSize,
  });

  final int page;
  final int pageCount;
  final int pageSize;
  final bool loading;
  final bool totalKnown;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onJump;
  final ValueChanged<int>? onPageSize;

  @override
  Widget build(BuildContext context) {
    final pageText = totalKnown ? '$page / $pageCount' : '$page';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(
          top: BorderSide(color: ThemeDefine.kColorLine),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Column(
        children: [
          Row(
            children: [
              TextButton(
                onPressed: onPrev,
                style: TextButton.styleFrom(
                  foregroundColor: ThemeDefine.kColorPrimary,
                ),
                child: const Text('上一页'),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onJump,
                  child: Text(
                    loading ? '加载中…' : pageText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: onNext,
                style: TextButton.styleFrom(
                  foregroundColor: ThemeDefine.kColorPrimary,
                ),
                child: const Text('下一页'),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '每页',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
              ),
              const SizedBox(width: 8),
              for (final size in _pageSizes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _SelectChip(
                    label: '$size',
                    selected: pageSize == size,
                    onTap: onPageSize == null ? () {} : () => onPageSize!(size),
                  ),
                ),
              const Text(
                '条',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageFilterSheet extends StatefulWidget {
  const _UsageFilterSheet({
    required this.accounts,
    required this.selectedAccountId,
    required this.range,
    required this.type,
    required this.tokenName,
    required this.modelName,
    required this.group,
    required this.showTypeFilters,
    required this.nameOf,
  });

  final List<Account> accounts;
  final String selectedAccountId;
  final UsageTimeRange range;
  final int type;
  final String tokenName;
  final String modelName;
  final String group;
  final bool showTypeFilters;
  final String Function(Account account) nameOf;

  @override
  State<_UsageFilterSheet> createState() => _UsageFilterSheetState();
}

class _UsageFilterSheetState extends State<_UsageFilterSheet> {
  late String _accountId;
  late UsageTimeRange _range;
  late int _type;
  late String _tokenName;
  late String _modelName;
  late String _group;
  bool _loadingOptions = false;
  int _optionSeq = 0;

  @override
  void initState() {
    super.initState();
    _accountId = widget.selectedAccountId;
    _range = widget.range;
    _type = widget.type;
    _tokenName = widget.tokenName;
    _modelName = widget.modelName;
    _group = widget.group;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLinkedOptions());
  }

  List<String> _optionAccountIds() {
    if (_accountId.isNotEmpty) {
      return [_accountId];
    }
    return widget.accounts.map((account) => account.id).toList();
  }

  Future<void> _loadLinkedOptions() async {
    if (!mounted) {
      return;
    }
    final ids = _optionAccountIds();
    if (ids.isEmpty) {
      return;
    }
    final seq = ++_optionSeq;
    setState(() => _loadingOptions = true);
    final store = context.read<VaultStore>();
    try {
      await Future.wait(
        ids.map((id) async {
          await store.loadTokenGroups(id);
          await store.loadGroupModels(id, _group);
        }),
      );
    } catch (_) {}
    if (!mounted || seq != _optionSeq) {
      return;
    }
    _syncLinkedValues(store);
    setState(() => _loadingOptions = false);
  }

  void _syncLinkedValues(VaultStore store) {
    final tokenNames = _tokenNamesFor(store, includeCurrent: false);
    if (_tokenName.isNotEmpty &&
        tokenNames.isNotEmpty &&
        !tokenNames.contains(_tokenName)) {
      _tokenName = '';
    }
    if (_tokenName.isEmpty) {
      return;
    }
    final key = _keyNamed(store, _tokenName);
    if (key != null &&
        key.modelLimits.isNotEmpty &&
        _modelName.isNotEmpty &&
        !key.modelLimits.contains(_modelName)) {
      _modelName = '';
    }
  }

  List<ApiKey> _keysFor(VaultStore store) {
    final keys = [
      for (final id in _optionAccountIds()) ...store.apiKeysForAccount(id),
    ];
    if (_group.isEmpty) {
      return keys;
    }
    return keys.where((key) => key.group == _group).toList();
  }

  ApiKey? _keyNamed(VaultStore store, String name) {
    final scoped = [
      for (final id in _optionAccountIds()) ...store.apiKeysForAccount(id),
    ].where((item) => item.name == name);
    final inGroup = _group.isEmpty
        ? scoped
        : scoped.where((item) => item.group == _group);
    return inGroup.firstOrNull ?? scoped.firstOrNull;
  }

  Iterable<UsageLog> _logsFor(VaultStore store, {bool byToken = false}) {
    return [
      for (final id in _optionAccountIds()) ...store.usageLogsForAccount(id),
    ].where((log) {
      if (_group.isNotEmpty && log.group != _group) {
        return false;
      }
      if (byToken && _tokenName.isNotEmpty && log.apiKeyName != _tokenName) {
        return false;
      }
      return true;
    });
  }

  List<String> _tokenNamesFor(VaultStore store, {bool includeCurrent = true}) {
    final names = <String>{};
    for (final key in _keysFor(store)) {
      final name = key.name.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    for (final log in _logsFor(store)) {
      final name = log.apiKeyName.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    if (includeCurrent && _tokenName.trim().isNotEmpty) {
      names.add(_tokenName.trim());
    }
    return names.toList()..sort();
  }

  List<TokenGroupOption> _groupsFor(VaultStore store) {
    final groups = <TokenGroupOption>[];
    final seen = <String>{};
    void addName(String raw, {TokenGroupOption? option}) {
      final name = raw.trim();
      if (name.isEmpty || !seen.add(name)) {
        return;
      }
      groups.add(
        option ?? TokenGroupOption(name: name, desc: name, ratioLabel: name),
      );
    }

    for (final id in _optionAccountIds()) {
      for (final group in store.groupsForAccount(store.accountById(id))) {
        addName(group.name, option: group);
      }
      for (final key in store.apiKeysForAccount(id)) {
        addName(key.group);
      }
      for (final log in store.usageLogsForAccount(id)) {
        addName(log.group);
      }
    }
    if (_group.trim().isNotEmpty) {
      addName(_group);
    }
    groups.sort((left, right) => left.name.compareTo(right.name));
    return groups;
  }

  List<String> _modelsFor(VaultStore store) {
    final models = <String>{};
    final key = _tokenName.isEmpty ? null : _keyNamed(store, _tokenName);
    if (key != null && key.modelLimits.isNotEmpty) {
      models.addAll(key.modelLimits);
    } else {
      for (final id in _optionAccountIds()) {
        models.addAll(store.modelsForGroup(id, _group));
      }
      for (final item in _keysFor(store)) {
        models.addAll(item.modelLimits);
      }
    }
    for (final log in _logsFor(store, byToken: true)) {
      final name = log.model.trim();
      if (name.isNotEmpty) {
        models.add(name);
      }
    }
    if (_modelName.trim().isNotEmpty) {
      models.add(_modelName.trim());
    }
    return models.toList()..sort();
  }

  String _groupValueLabel(VaultStore store) {
    if (_group.isEmpty) {
      return '全部';
    }
    for (final id in _optionAccountIds()) {
      final label = store.tokenGroupLabel(id, _group);
      if (label.isNotEmpty && label != _group) {
        return label;
      }
    }
    return _group;
  }

  Future<void> _selectAccount(String accountId) async {
    if (_accountId == accountId) {
      return;
    }
    setState(() {
      _accountId = accountId;
      _tokenName = '';
      _modelName = '';
      _group = '';
    });
    await _loadLinkedOptions();
  }

  Future<void> _selectGroup(String group) async {
    setState(() => _group = group);
    final store = context.read<VaultStore>();
    final valid = _tokenNamesFor(store, includeCurrent: false);
    if (_tokenName.isNotEmpty &&
        valid.isNotEmpty &&
        !valid.contains(_tokenName)) {
      setState(() => _tokenName = '');
    }
    await _loadLinkedOptions();
  }

  Future<void> _selectToken(String name) async {
    final store = context.read<VaultStore>();
    setState(() => _tokenName = name);
    if (name.isEmpty) {
      await _loadLinkedOptions();
      return;
    }
    final key = _keyNamed(store, name);
    if (key != null && key.group.trim().isNotEmpty && key.group != _group) {
      setState(() => _group = key.group);
      await _loadLinkedOptions();
      return;
    }
    _syncLinkedValues(store);
    setState(() {});
  }

  void _selectModel(String model) {
    final store = context.read<VaultStore>();
    setState(() => _modelName = model);
    if (model.isEmpty || _tokenName.isEmpty) {
      return;
    }
    final key = _keyNamed(store, _tokenName);
    if (key != null &&
        key.modelLimits.isNotEmpty &&
        !key.modelLimits.contains(model)) {
      setState(() => _tokenName = '');
    }
  }

  Future<void> _pickOption({
    required String title,
    required List<_FilterOption> options,
    required String selected,
    required ValueChanged<String> onPicked,
  }) async {
    final next = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _LinkedOptionSheet(
        title: title,
        options: options,
        selected: selected,
      ),
    );
    if (next == null || !mounted) {
      return;
    }
    onPicked(next);
  }

  void _apply() {
    Navigator.pop(
      context,
      _UsageFilterValue(
        accountId: _accountId,
        range: _range,
        type: _type,
        tokenName: _tokenName.trim(),
        modelName: _modelName.trim(),
        group: _group.trim(),
      ),
    );
  }

  Widget _chips(List<Widget> children) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final groups = _groupsFor(store);
    final tokenNames = _tokenNamesFor(store);
    final models = _modelsFor(store);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: ThemeDefine.kColorLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Text(
                '筛选日志',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (widget.accounts.length > 1) ...[
                const SizedBox(height: 12),
                const Text('账号', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                _chips([
                  _SelectChip(
                    label: '全部',
                    selected: _accountId.isEmpty,
                    onTap: () => _selectAccount(''),
                  ),
                  for (final account in widget.accounts)
                    _SelectChip(
                      label: widget.nameOf(account),
                      selected: account.id == _accountId,
                      maxWidth: 140,
                      onTap: () => _selectAccount(account.id),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              const Text('时间', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              _chips([
                for (final item in _ranges)
                  _SelectChip(
                    label: item.$2,
                    selected: _range == item.$1,
                    onTap: () => setState(() => _range = item.$1),
                  ),
              ]),
              if (widget.showTypeFilters) ...[
                const SizedBox(height: 12),
                const Text('类型', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                _chips([
                  for (final item in _logTypes)
                    _SelectChip(
                      label: item.$2,
                      selected: _type == item.$1,
                      onTap: () => setState(() => _type = item.$1),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              LabeledField(
                label: '分组',
                child: _LinkedSelectField(
                  valueLabel: _groupValueLabel(store),
                  empty: _group.isEmpty,
                  loading: _loadingOptions,
                  iconModel: _group,
                  iconKind: _OptionIconKind.brand,
                  onTap: () => _pickOption(
                    title: '选择分组',
                    selected: _group,
                    options: [
                      const _FilterOption(value: '', label: '全部'),
                      for (final group in groups)
                        _FilterOption(
                          value: group.name,
                          label: group.name,
                          subtitle: group.ratioLabel == group.name
                              ? null
                              : group.ratioLabel,
                          iconKind: _OptionIconKind.brand,
                        ),
                    ],
                    onPicked: _selectGroup,
                  ),
                ),
              ),
              LabeledField(
                label: '密钥名称',
                child: _LinkedSelectField(
                  valueLabel: _tokenName.isEmpty ? '全部' : _tokenName,
                  empty: _tokenName.isEmpty,
                  onTap: () => _pickOption(
                    title: '选择密钥',
                    selected: _tokenName,
                    options: [
                      const _FilterOption(value: '', label: '全部'),
                      for (final name in tokenNames)
                        _FilterOption(
                          value: name,
                          label: name,
                          subtitle: _keyNamed(store, name)?.group,
                        ),
                    ],
                    onPicked: _selectToken,
                  ),
                ),
              ),
              LabeledField(
                label: '模型',
                last: true,
                child: _LinkedSelectField(
                  valueLabel: _modelName.isEmpty ? '全部' : _modelName,
                  empty: _modelName.isEmpty,
                  loading: _loadingOptions,
                  iconModel: _modelName,
                  iconKind: _OptionIconKind.model,
                  onTap: () => _pickOption(
                    title: '选择模型',
                    selected: _modelName,
                    options: [
                      const _FilterOption(value: '', label: '全部'),
                      for (final model in models)
                        _FilterOption(
                          value: model,
                          label: model,
                          iconKind: _OptionIconKind.model,
                        ),
                    ],
                    onPicked: _selectModel,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: '重置为全部',
                      outlined: true,
                      onPressed: () {
                        setState(() {
                          _range = UsageTimeRange.all;
                          _type = 0;
                          _tokenName = '';
                          _modelName = '';
                          _group = '';
                        });
                        _loadLinkedOptions();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(label: '查看结果', onPressed: _apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.iconKind = _OptionIconKind.none,
  });

  final String value;
  final String label;
  final String? subtitle;
  final _OptionIconKind iconKind;
}

enum _OptionIconKind { none, model, brand }

Widget? _optionBrandIcon(String name, _OptionIconKind kind) {
  if (name.isEmpty || kind == _OptionIconKind.none) {
    return null;
  }
  if (kind == _OptionIconKind.brand &&
      detectModelBrand(name).key == 'unknown') {
    return null;
  }
  return ModelBrandIcon(model: name);
}

class _LinkedSelectField extends StatelessWidget {
  const _LinkedSelectField({
    required this.valueLabel,
    required this.empty,
    required this.onTap,
    this.loading = false,
    this.iconModel = '',
    this.iconKind = _OptionIconKind.none,
  });

  final String valueLabel;
  final bool empty;
  final VoidCallback onTap;
  final bool loading;
  final String iconModel;
  final _OptionIconKind iconKind;

  @override
  Widget build(BuildContext context) {
    final icon = empty ? null : _optionBrandIcon(iconModel, iconKind);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              icon,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: empty
                      ? ThemeDefine.kColorDisable
                      : ThemeDefine.kColorTitle,
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: ThemeDefine.kColorText,
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkedOptionSheet extends StatefulWidget {
  const _LinkedOptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<_FilterOption> options;
  final String selected;

  @override
  State<_LinkedOptionSheet> createState() => _LinkedOptionSheetState();
}

class _LinkedOptionSheetState extends State<_LinkedOptionSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? widget.options
        : widget.options
            .where((item) {
              if (item.value.isEmpty) {
                return true;
              }
              return item.label.toLowerCase().contains(keyword) ||
                  (item.subtitle?.toLowerCase().contains(keyword) ?? false);
            })
            .toList();
    final searchable = widget.options.length > 9;
    final maxListHeight = (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            168)
        .clamp(120.0, MediaQuery.sizeOf(context).height * 0.42);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ThemeDefine.kColorLine,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (searchable) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _query,
                autofocus: widget.options.length > 30,
                decoration: const InputDecoration(
                  hintText: '搜索',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: filtered.isEmpty
                  ? const SizedBox(
                      height: 56,
                      child: Center(
                        child: Text(
                          '没有匹配项',
                          style: TextStyle(color: ThemeDefine.kColorText),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final selected = item.value == widget.selected;
                        final icon = _optionBrandIcon(item.value, item.iconKind);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          minLeadingWidth: 24,
                          leading: icon,
                          title: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? ThemeDefine.kColorPrimary
                                  : ThemeDefine.kColorTitle,
                            ),
                          ),
                          subtitle: item.subtitle == null ||
                                  item.subtitle!.isEmpty
                              ? null
                              : Text(
                                  item.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: ThemeDefine.kColorPrimary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, item.value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckinFilterSheet extends StatelessWidget {
  const _CheckinFilterSheet({
    required this.sites,
    required this.selectedKey,
  });

  final List<(String, String)> sites;
  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ThemeDefine.kColorLine,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Text(
              '按站点筛选签到',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SelectChip(
                label: '全部站点',
                selected: selectedKey == null,
                onTap: () => Navigator.pop(context, const _SitePick(null)),
              ),
              for (final site in sites)
                _SelectChip(
                  label: site.$2,
                  selected: selectedKey == site.$1,
                  maxWidth: 180,
                  onTap: () => Navigator.pop(context, _SitePick(site.$1)),
                ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}
