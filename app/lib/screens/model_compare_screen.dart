import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/model_brands.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
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
  String? _selectedModel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final store = context.read<VaultStore>();
    try {
      await store.loadAllPricingCatalogs();
    } catch (error) {
      store.notify(userFacingError(error, '读取模型价格失败'), FeedbackType.warning);
    }
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final brands = store.comparableBrands(query: _query);
    final brandKey = _brandKey != null && brands.any((brand) => brand.key == _brandKey)
        ? _brandKey
        : null;
    final summaries = store.comparableModelSummaries(query: _query, brandKey: brandKey);
    final selected = _selectedModel != null &&
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
        ],
      ),
      body: YuconRefresh(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索模型名称',
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
              onChanged: (value) => setState(() {
                _query = value;
                if (_selectedModel != null &&
                    !_selectedModel!.toLowerCase().contains(value.trim().toLowerCase())) {
                  _selectedModel = null;
                }
              }),
            ),
            if (brands.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _brandChip(label: '全部', selected: brandKey == null, onTap: () {
                      setState(() => _brandKey = null);
                    }),
                    for (final brand in brands)
                      _brandChip(
                        label: brand.label,
                        selected: brandKey == brand.key,
                        brand: brand,
                        onTap: () => setState(() {
                          _brandKey = brand.key;
                          if (_selectedModel != null &&
                              detectModelBrand(_selectedModel!).key != brand.key) {
                            _selectedModel = null;
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (summaries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    store.accounts.isEmpty
                        ? '先添加账号，再来对比模型价格'
                        : '没有匹配的模型',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, height: 1.5),
                  ),
                ),
              )
            else if (selected == null)
              ...summaries.map((item) => _modelCard(item.$1, item.$2, item.$3))
            else
              ..._siteCards(store, selected),
          ],
        ),
      ),
    );
  }

  Widget _brandChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    ModelBrand? brand,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.fromLTRB(10, 0, 11, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ThemeDefine.kColorSoft : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? const Color(0x29FA2C19) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (brand != null) ...[
                ModelBrandIcon(model: brand.key, size: ModelBrandIconSize.sm),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: selected ? ThemeDefine.kColorPrimary : ThemeDefine.kColorText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelCard(String name, ModelCompareOffer lowest, int siteCount) {
    final priceText = lowest.perCall
        ? '最低 ${formatYuanPrice(lowest.effectiveInput)} / 次 · $siteCount 个站点'
        : '最低 ${formatYuanPrice(lowest.effectiveInput)} / 1M · $siteCount 个站点';
    return YuconCard(
      onTap: () => setState(() => _selectedModel = name),
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
      child: Row(
        children: [
          ModelBrandIcon(model: name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  priceText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: ThemeDefine.kColorText),
        ],
      ),
    );
  }

  List<Widget> _siteCards(VaultStore store, String model) {
    final sites = store.sitesForModel(model);
    if (sites.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: Text('这个模型暂时没有可用报价', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13)),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < sites.length; i++)
        _siteCard(store, sites[i].$1, sites[i].$2, rank: i + 1, cheapest: i == 0),
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
    final lowest = groups.first;
    final priceLine = lowest.perCall
        ? '每次 ${formatYuanPrice(lowest.effectiveInput)}'
        : '输入 ${formatYuanPrice(lowest.effectiveInput)} / 1M · 输出 ${formatYuanPrice(lowest.effectiveOutput)} / 1M';
    return YuconCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: account.id)),
        );
      },
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      borderColor: highlight
          ? Color(preset.color)
          : cheapest
          ? const Color(0x33168553)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cheapest ? const Color(0xFFE7F7EF) : ThemeDefine.kColorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cheapest ? '低' : '$rank',
                  style: TextStyle(
                    color: cheapest ? const Color(0xFF168553) : ThemeDefine.kColorPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            store.displayAccountName(account),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (cheapest)
                          const StatusChip(
                            label: '最低',
                            color: Color(0xFF168553),
                            background: Color(0xFFE7F7EF),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      priceLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${store.siteLabelForAccount(account)} · ${formatTopupRatioExplain(lowest.topupRatio)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (var i = 0; i < groups.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _groupRow(groups[i], lowest: i == 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupRow(ModelCompareOffer offer, {required bool lowest}) {
    final price = offer.perCall
        ? '${formatYuanPrice(offer.effectiveInput)} / 次'
        : '${formatYuanPrice(offer.effectiveInput)} / 1M';
    return Row(
      children: [
        Expanded(
          child: Text(
            offer.group,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          formatGroupRatio(offer.groupRatio),
          style: TextStyle(
            color: lowest ? const Color(0xFF168553) : ThemeDefine.kColorText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          price,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: lowest ? const Color(0xFF168553) : null,
          ),
        ),
        if (lowest) ...[
          const SizedBox(width: 6),
          const Text(
            '最低倍率',
            style: TextStyle(color: Color(0xFF168553), fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}
