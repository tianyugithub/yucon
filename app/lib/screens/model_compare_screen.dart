import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/model_brands.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class ModelCompareScreen extends StatefulWidget {
  const ModelCompareScreen({super.key, this.accountId});

  final String? accountId;

  @override
  State<ModelCompareScreen> createState() => _ModelCompareScreenState();
}

class _ModelCompareScreenState extends State<ModelCompareScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _brandKey;
  String? _siteHost;
  String? _selectedModel;
  bool _useMine = false;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<VaultStore>();
    final account = widget.accountId == null
        ? null
        : store.accountById(widget.accountId!);
    if (account != null) {
      _siteHost = store.siteHostForAccount(account);
      _useMine = true;
    }
    _loading = !store.hasPricingCatalogs;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final store = context.read<VaultStore>();
    if (store.hasPricingCatalogs) {
      if (mounted) {
        setState(() => _loading = false);
      }
      await store.loadAllPricingCatalogs();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await _reload(notifySuccess: false);
  }

  Future<void> _reload({bool notifySuccess = true}) async {
    final store = context.read<VaultStore>();
    final showPageSpinner = !store.hasPricingCatalogs;
    setState(() {
      _refreshing = true;
      _loading = showPageSpinner;
    });
    try {
      await store.loadAllPricingCatalogs(force: true);
      if (notifySuccess && store.hasPricingCatalogs) {
        store.notify('模型价格已更新');
      }
    } catch (error) {
      store.notify(userFacingError(error, '读取模型价格失败'), FeedbackType.warning);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshing = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final sites = store.comparableSites();
    final siteHost =
        _siteHost != null && sites.any((item) => item.$1 == _siteHost)
        ? _siteHost
        : null;
    final brands = store.comparableBrands(
      query: _query,
      siteHost: siteHost,
      useAccountGroup: _useMine,
    );
    final brandKey =
        _brandKey != null && brands.any((brand) => brand.key == _brandKey)
        ? _brandKey
        : null;
    final summaries = store.comparableModelSummaries(
      query: _query,
      brandKey: brandKey,
      siteHost: siteHost,
      useAccountGroup: _useMine,
    );
    final selected =
        _selectedModel != null &&
            summaries.any((item) => item.$1 == _selectedModel)
        ? _selectedModel
        : null;

    return Scaffold(
      appBar: YuconAppBar(
        title: selected ?? '模型比价',
        actions: [
          if (selected != null)
            HeaderTextAction(
              label: '全部模型',
              onPressed: () => setState(() => _selectedModel = null),
            ),
          HeaderIconAction(
            icon: Icons.refresh,
            tooltip: '刷新报价',
            busy: _refreshing,
            onPressed: () {
              _reload();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _stickyFilters(
            sites: sites,
            siteHost: siteHost,
            brands: brands,
            brandKey: brandKey,
            selected: selected,
            modelCount: summaries.length,
          ),
          if (_refreshing && !_loading)
            const LinearProgressIndicator(
              minHeight: 2,
              color: ThemeDefine.kColorPrimary,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: YuconRefresh(
              onRefresh: () => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 24),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (summaries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          store.accounts.isEmpty
                              ? '先添加账号，再来对比模型价格'
                              : _useMine
                              ? '当前账号分组下没有匹配的模型'
                              : '没有匹配的模型',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ThemeDefine.kColorText,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  else if (selected == null)
                    ...summaries.map(
                      (item) => _modelCard(store, item.$1, item.$2, item.$3),
                    )
                  else
                    ..._siteCards(store, selected, siteHost),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stickyFilters({
    required List<(String, String)> sites,
    required String? siteHost,
    required List<ModelBrand> brands,
    required String? brandKey,
    required String? selected,
    required int modelCount,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine;
    final field = dark ? const Color(0xFF232323) : const Color(0xFFEEEEF0);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(15, 2, 15, 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: line, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索模型',
                isDense: true,
                filled: true,
                fillColor: field,
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: ThemeDefine.kColorText,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除',
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: ThemeDefine.kColorText,
                        ),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: ThemeDefine.kColorPrimary,
                  ),
                ),
              ),
              onChanged: (value) => setState(() {
                _query = value;
                if (_selectedModel != null &&
                    !_selectedModel!.toLowerCase().contains(
                      value.trim().toLowerCase(),
                    )) {
                  _selectedModel = null;
                }
              }),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: dark
                    ? ThemeDefine.kColorDarkCard
                    : ThemeDefine.kColorCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _modeTab(
                    '最低价',
                    !_useMine,
                    () => setState(() => _useMine = false),
                  ),
                  _modeTab(
                    '我的分组',
                    _useMine,
                    () => setState(() => _useMine = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _caption(modelCount, selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeDefine.kColorText,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            if (sites.length > 1) ...[
              const SizedBox(height: 8),
              _filterLane(
                label: '站点',
                chips: [
                  _filterChip(
                    label: '全部',
                    selected: siteHost == null,
                    onTap: () => setState(() => _siteHost = null),
                  ),
                  for (final site in sites)
                    _filterChip(
                      label: site.$2,
                      selected: siteHost == site.$1,
                      onTap: () => setState(() => _siteHost = site.$1),
                    ),
                ],
              ),
            ],
            if (brands.isNotEmpty) ...[
              const SizedBox(height: 8),
              _filterLane(
                label: '厂商',
                chips: [
                  _filterChip(
                    label: '全部',
                    selected: brandKey == null,
                    onTap: () => setState(() => _brandKey = null),
                  ),
                  for (final brand in brands)
                    _filterChip(
                      label: brand.label,
                      selected: brandKey == brand.key,
                      brand: brand,
                      onTap: () => setState(() {
                        _brandKey = brand.key;
                        if (_selectedModel != null &&
                            detectModelBrand(_selectedModel!).key !=
                                brand.key) {
                          _selectedModel = null;
                        }
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _caption(int modelCount, String? selected) {
    if (selected != null) {
      return _useMine ? '按各站当前账号分组排序 · 人民币 / 1M' : '按各站最低输出价排序 · 人民币 / 1M';
    }
    if (_loading) {
      return '人民币 / 1M · 含分组和充值比例';
    }
    return '$modelCount 个模型 · 人民币 / 1M';
  }

  Widget _modeTab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ThemeDefine.kColorSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              color: selected
                  ? ThemeDefine.kColorPrimary
                  : ThemeDefine.kColorText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterLane({required String label, required List<Widget> chips}) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ThemeDefine.kColorText,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    ModelBrand? brand,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = dark ? const Color(0xFF232323) : const Color(0xFFEEEEF0);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 30,
          padding: const EdgeInsets.fromLTRB(9, 0, 10, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ThemeDefine.kColorSoft : idle,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? const Color(0x40FA2C19) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (brand != null) ...[
                ModelBrandIcon(model: brand.key, size: ModelBrandIconSize.sm),
                const SizedBox(width: 5),
              ],
              Text(
                label,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelCard(
    VaultStore store,
    String name,
    ModelCompareOffer offer,
    int siteCount,
  ) {
    final account = store.accountById(offer.accountId);
    final siteName = account == null
        ? offer.group
        : store.displayAccountName(account);
    return YuconCard(
      onTap: () => setState(() => _selectedModel = name),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          ModelBrandIcon(model: name, size: ModelBrandIconSize.md),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$siteName · ${offer.group} · $siteCount 站',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ioPrices(offer),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: ThemeDefine.kColorText,
          ),
        ],
      ),
    );
  }

  List<Widget> _siteCards(VaultStore store, String model, String? siteHost) {
    final sites = store.sitesForModel(
      model,
      siteHost: siteHost,
      useAccountGroup: _useMine,
    );
    if (sites.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: Text(
              '这个模型暂时没有可用报价',
              style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13),
            ),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < sites.length; i++)
        _siteCard(
          store,
          sites[i].$1,
          sites[i].$2,
          rank: i + 1,
          cheapest: i == 0,
        ),
    ];
  }

  Widget _siteCard(
    VaultStore store,
    Account account,
    List<ModelCompareOffer> groups, {
    required int rank,
    required bool cheapest,
  }) {
    final preset = getPlatformPreset(account.platformType);
    final highlight = widget.accountId == account.id;
    final view =
        pickOfferForAccount(
          account: account,
          offers: groups,
          useAccountGroup: _useMine,
        ) ??
        groups.first;
    final cacheLine = formatCachePriceLine(view);
    return YuconCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: account.id),
          ),
        );
      },
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      borderColor: highlight
          ? Color(preset.color)
          : cheapest
          ? const Color(0x33168553)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cheapest
                      ? const Color(0xFFE7F7EF)
                      : ThemeDefine.kColorSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  cheapest ? '低' : '$rank',
                  style: TextStyle(
                    color: cheapest
                        ? const Color(0xFF168553)
                        : ThemeDefine.kColorPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.displayAccountName(account),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ioPrices(
                view,
                color: cheapest ? const Color(0xFF168553) : null,
                emphasize: true,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${hostnameOf(account.baseUrl)} · ${formatTopupRatioExplain(view.topupRatio)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ThemeDefine.kColorText,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          if (cacheLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              cacheLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeDefine.kColorText,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _groupRow(
              account,
              groups[i],
              cheapest: i == 0,
              current: groups[i].group == view.group,
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupRow(
    Account account,
    ModelCompareOffer offer, {
    required bool cheapest,
    required bool current,
  }) {
    final mine = isAccountBillingGroup(account, offer.group);
    final color = cheapest ? const Color(0xFF168553) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: current
            ? ThemeDefine.kColorSoft
            : Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        offer.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    if (cheapest) _miniTag('最低', const Color(0xFF168553)),
                    if (mine) _miniTag('当前', ThemeDefine.kColorPrimary),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatGroupRatio(offer.groupRatio),
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ioPrices(offer, color: color),
        ],
      ),
    );
  }

  Widget _ioPrices(
    ModelCompareOffer offer, {
    Color? color,
    bool emphasize = false,
  }) {
    final unit = offer.perCall ? '/次' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '出 ${formatYuanPrice(offer.effectiveOutput)}$unit',
          style: TextStyle(
            fontSize: emphasize ? 13 : 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        if (!offer.perCall)
          Text(
            '入 ${formatYuanPrice(offer.effectiveInput)}',
            style: TextStyle(
              color: color ?? ThemeDefine.kColorText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _miniTag(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
