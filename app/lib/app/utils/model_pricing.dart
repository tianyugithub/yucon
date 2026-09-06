import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/quota.dart';

const millionTokens = 1000000.0;

class SiteModelQuote {
  SiteModelQuote({
    required this.modelName,
    this.modelRatio = 0,
    this.completionRatio = 1,
    this.modelPrice = 0,
    this.quotaType = 0,
    this.cacheRatio,
    this.createCacheRatio,
    List<String>? enableGroups,
  }) : enableGroups = enableGroups ?? [];

  final String modelName;
  final double modelRatio;
  final double completionRatio;
  final double modelPrice;
  final int quotaType;
  final double? cacheRatio;
  final double? createCacheRatio;
  final List<String> enableGroups;

  bool get isPerCall => quotaType == 1 || (modelPrice > 0 && modelRatio <= 0);

  Map<String, dynamic> toJson() => {
        'modelName': modelName,
        'modelRatio': modelRatio,
        'completionRatio': completionRatio,
        'modelPrice': modelPrice,
        'quotaType': quotaType,
        'cacheRatio': cacheRatio,
        'createCacheRatio': createCacheRatio,
        'enableGroups': enableGroups,
      };

  factory SiteModelQuote.fromJson(Map<String, dynamic> json) => SiteModelQuote(
        modelName: (json['modelName'] ?? json['model_name'] ?? '').toString(),
        modelRatio: readNumber(json['modelRatio'] ?? json['model_ratio']),
        completionRatio: readNumber(json['completionRatio'] ?? json['completion_ratio'], 1),
        modelPrice: readNumber(json['modelPrice'] ?? json['model_price']),
        quotaType: readNumber(json['quotaType'] ?? json['quota_type']).toInt(),
        cacheRatio: readOptionalNumber(json['cacheRatio'] ?? json['cache_ratio']),
        createCacheRatio: readOptionalNumber(
          json['createCacheRatio'] ?? json['create_cache_ratio'] ?? json['cache_creation_ratio'],
        ),
        enableGroups: parseEnableGroups(json['enableGroups'] ?? json['enable_groups']),
      );
}

class SitePricingCatalog {
  SitePricingCatalog({
    Map<String, double>? groupRatio,
    List<SiteModelQuote>? quotes,
  }) : groupRatio = groupRatio ?? {},
       quotes = quotes ?? [];

  final Map<String, double> groupRatio;
  final List<SiteModelQuote> quotes;

  bool get isEmpty => quotes.isEmpty;

  SitePricingCatalog filteredToModels(Iterable<String> models) {
    final allowed = models.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
    if (allowed.isEmpty) {
      return this;
    }
    return SitePricingCatalog(
      groupRatio: groupRatio,
      quotes: quotes.where((quote) => allowed.contains(quote.modelName)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupRatio': groupRatio,
        'quotes': quotes.map((quote) => quote.toJson()).toList(),
      };

  factory SitePricingCatalog.fromJson(Map<String, dynamic> json) {
    final quotesRaw = json['quotes'];
    return SitePricingCatalog(
      groupRatio: parseGroupRatios(json['groupRatio'] ?? json['group_ratio']),
      quotes: quotesRaw is List
          ? quotesRaw
              .whereType<Map>()
              .map((item) => SiteModelQuote.fromJson(Map<String, dynamic>.from(item)))
              .where((quote) => quote.modelName.trim().isNotEmpty)
              .toList()
          : const [],
    );
  }
}

class ModelPriceBreakdown {
  const ModelPriceBreakdown({
    required this.perCall,
    required this.siteInput,
    required this.siteOutput,
    required this.siteCacheRead,
    required this.siteCacheWrite,
    required this.hasCacheRead,
    required this.hasCacheWrite,
    required this.group,
    required this.groupRatio,
  });

  final bool perCall;
  final double siteInput;
  final double siteOutput;
  final double siteCacheRead;
  final double siteCacheWrite;
  final bool hasCacheRead;
  final bool hasCacheWrite;
  final String group;
  final double groupRatio;
}

class ModelCompareOffer {
  const ModelCompareOffer({
    required this.accountId,
    required this.modelName,
    required this.group,
    required this.groupRatio,
    required this.topupRatio,
    required this.perCall,
    required this.siteInput,
    required this.siteOutput,
    required this.siteCacheRead,
    required this.siteCacheWrite,
    required this.effectiveInput,
    required this.effectiveOutput,
    required this.effectiveCacheRead,
    required this.effectiveCacheWrite,
    required this.hasCacheRead,
    required this.hasCacheWrite,
  });

  final String accountId;
  final String modelName;
  final String group;
  final double groupRatio;
  final double topupRatio;
  final bool perCall;
  final double siteInput;
  final double siteOutput;
  final double siteCacheRead;
  final double siteCacheWrite;
  final double effectiveInput;
  final double effectiveOutput;
  final double effectiveCacheRead;
  final double effectiveCacheWrite;
  final bool hasCacheRead;
  final bool hasCacheWrite;

  double get sortPrice => effectiveOutput;
}

String compareGroupForAccount(Account account) {
  final group = account.group.trim();
  if (group.isEmpty || group == 'auto') {
    return 'default';
  }
  return group;
}

Map<String, double> parseGroupRatios(Object? value) {
  final record = asRecord(value);
  return {
    for (final entry in record.entries)
      if (entry.key.trim().isNotEmpty) entry.key.trim(): readNumber(entry.value, 1),
  };
}

List<String> parseEnableGroups(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return splitList(value?.toString() ?? '');
}

bool quoteAvailableForGroup(SiteModelQuote quote, String group) {
  if (quote.enableGroups.isEmpty) {
    return true;
  }
  for (final item in quote.enableGroups) {
    final name = item.trim();
    if (name == 'all' || name == group) {
      return true;
    }
  }
  return false;
}

double? readOptionalNumber(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return double.tryParse(text);
}

double groupRatioFor(SitePricingCatalog catalog, String group) {
  return catalog.groupRatio[group] ?? catalog.groupRatio['default'] ?? 1;
}

double _tokenUsdPerMillion({
  required double modelRatio,
  required double extraRatio,
  required double groupRatio,
  required double quotaPerUnit,
}) {
  final unit = quotaPerUnit > 0 ? quotaPerUnit : defaultQuotaPerUnit;
  return modelRatio * extraRatio * groupRatio * millionTokens / unit;
}

ModelPriceBreakdown priceForQuote({
  required SiteModelQuote quote,
  required SitePricingCatalog catalog,
  required String group,
  required double quotaPerUnit,
}) {
  final ratio = groupRatioFor(catalog, group);
  final unit = quotaPerUnit > 0 ? quotaPerUnit : defaultQuotaPerUnit;
  if (quote.isPerCall) {
    final site = quote.modelPrice * ratio;
    return ModelPriceBreakdown(
      perCall: true,
      siteInput: site,
      siteOutput: site,
      siteCacheRead: 0,
      siteCacheWrite: 0,
      hasCacheRead: false,
      hasCacheWrite: false,
      group: group,
      groupRatio: ratio,
    );
  }
  final input = _tokenUsdPerMillion(
    modelRatio: quote.modelRatio,
    extraRatio: 1,
    groupRatio: ratio,
    quotaPerUnit: unit,
  );
  final output = _tokenUsdPerMillion(
    modelRatio: quote.modelRatio,
    extraRatio: quote.completionRatio <= 0 ? 1 : quote.completionRatio,
    groupRatio: ratio,
    quotaPerUnit: unit,
  );
  final cacheRead = quote.cacheRatio == null
      ? 0.0
      : _tokenUsdPerMillion(
          modelRatio: quote.modelRatio,
          extraRatio: quote.cacheRatio!,
          groupRatio: ratio,
          quotaPerUnit: unit,
        );
  final cacheWrite = quote.createCacheRatio == null
      ? 0.0
      : _tokenUsdPerMillion(
          modelRatio: quote.modelRatio,
          extraRatio: quote.createCacheRatio!,
          groupRatio: ratio,
          quotaPerUnit: unit,
        );
  return ModelPriceBreakdown(
    perCall: false,
    siteInput: input,
    siteOutput: output,
    siteCacheRead: cacheRead,
    siteCacheWrite: cacheWrite,
    hasCacheRead: quote.cacheRatio != null,
    hasCacheWrite: quote.createCacheRatio != null,
    group: group,
    groupRatio: ratio,
  );
}

ModelCompareOffer offerForQuote({
  required Account account,
  required SiteModelQuote quote,
  required SitePricingCatalog catalog,
  String? group,
}) {
  final resolved = (group ?? compareGroupForAccount(account)).trim();
  final price = priceForQuote(
    quote: quote,
    catalog: catalog,
    group: resolved.isEmpty ? 'default' : resolved,
    quotaPerUnit: account.quotaPerUnit,
  );
  final topup = sanitizeTopupRatio(account.topupRatio);
  return ModelCompareOffer(
    accountId: account.id,
    modelName: quote.modelName,
    group: price.group,
    groupRatio: price.groupRatio,
    topupRatio: topup,
    perCall: price.perCall,
    siteInput: price.siteInput,
    siteOutput: price.siteOutput,
    siteCacheRead: price.siteCacheRead,
    siteCacheWrite: price.siteCacheWrite,
    effectiveInput: price.siteInput * topup,
    effectiveOutput: price.siteOutput * topup,
    effectiveCacheRead: price.siteCacheRead * topup,
    effectiveCacheWrite: price.siteCacheWrite * topup,
    hasCacheRead: price.hasCacheRead,
    hasCacheWrite: price.hasCacheWrite,
  );
}

bool _isBillingGroup(String group) {
  final name = group.trim();
  return name.isNotEmpty && name != 'auto';
}

List<String> billingGroupsForQuote(SitePricingCatalog catalog, SiteModelQuote quote) {
  var groups = catalog.groupRatio.keys.where(_isBillingGroup).toList();
  if (groups.isEmpty) {
    groups = quote.enableGroups.where(_isBillingGroup).toList();
  }
  if (groups.isEmpty) {
    groups = ['default'];
  }
  final available = groups.where((name) => quoteAvailableForGroup(quote, name)).toList();
  available.sort((left, right) {
    final cmp = groupRatioFor(catalog, left).compareTo(groupRatioFor(catalog, right));
    return cmp != 0 ? cmp : left.toLowerCase().compareTo(right.toLowerCase());
  });
  return available;
}

SitePricingCatalog enrichCatalogGroups(
  SitePricingCatalog catalog,
  Iterable<TokenGroupOption> groups,
) {
  final ratios = {...catalog.groupRatio};
  for (final group in groups) {
    if (!_isBillingGroup(group.name) || group.ratio == null) {
      continue;
    }
    ratios.putIfAbsent(group.name.trim(), () => group.ratio!);
  }
  return SitePricingCatalog(groupRatio: ratios, quotes: catalog.quotes);
}

List<ModelCompareOffer> offersForAccountModel({
  required Account account,
  required SiteModelQuote quote,
  required SitePricingCatalog catalog,
}) {
  final offers = [
    for (final group in billingGroupsForQuote(catalog, quote))
      offerForQuote(account: account, quote: quote, catalog: catalog, group: group),
  ];
  sortModelCompareOffers(offers);
  return offers;
}

int compareModelOffers(ModelCompareOffer left, ModelCompareOffer right) {
  final priceCmp = left.sortPrice.compareTo(right.sortPrice);
  if (priceCmp != 0) {
    return priceCmp;
  }
  final inputCmp = left.effectiveInput.compareTo(right.effectiveInput);
  if (inputCmp != 0) {
    return inputCmp;
  }
  final ratioCmp = left.groupRatio.compareTo(right.groupRatio);
  if (ratioCmp != 0) {
    return ratioCmp;
  }
  return left.group.compareTo(right.group);
}

void sortModelCompareOffers(List<ModelCompareOffer> offers) {
  offers.sort(compareModelOffers);
}

bool isAccountBillingGroup(Account account, String group) =>
    compareGroupForAccount(account) == group.trim();

ModelCompareOffer? pickOfferForAccount({
  required Account account,
  required List<ModelCompareOffer> offers,
  required bool useAccountGroup,
}) {
  if (offers.isEmpty) {
    return null;
  }
  if (useAccountGroup) {
    final group = compareGroupForAccount(account);
    return offers.where((offer) => offer.group == group).firstOrNull;
  }
  return offers.first;
}

SitePricingCatalog parseSitePricing(Object? payload) {
  final root = asRecord(payload);
  var data = root['data'];
  var groupRatio = parseGroupRatios(root['group_ratio']);
  if (data is Map) {
    final nested = asRecord(data);
    if (groupRatio.isEmpty) {
      groupRatio = parseGroupRatios(nested['group_ratio']);
    }
    if (nested['data'] is List) {
      data = nested['data'];
    }
  }

  if (data is List) {
    final quotes = <SiteModelQuote>[];
    for (final item in data) {
      final record = asRecord(item);
      final name = (record['model_name'] ??
              record['modelName'] ??
              record['model'] ??
              record['name'] ??
              '')
          .toString()
          .trim();
      if (name.isEmpty) {
        continue;
      }
      final modelPrice = readNumber(record['model_price']);
      final modelRatio = readNumber(record['model_ratio']);
      final quotaType = readNumber(record['quota_type']).toInt();
      final perCall = quotaType == 1 || (modelPrice > 0 && modelRatio <= 0);
      quotes.add(
        SiteModelQuote(
          modelName: name,
          modelRatio: modelRatio,
          completionRatio: readNumber(record['completion_ratio'], 1),
          modelPrice: modelPrice,
          quotaType: perCall ? 1 : 0,
          cacheRatio: readOptionalNumber(record['cache_ratio']),
          createCacheRatio: readOptionalNumber(
            record['create_cache_ratio'] ?? record['cache_creation_ratio'],
          ),
          enableGroups: parseEnableGroups(record['enable_groups'] ?? record['enable_group']),
        ),
      );
    }
    return SitePricingCatalog(groupRatio: groupRatio, quotes: quotes);
  }

  final record = asRecord(data);
  if (groupRatio.isEmpty) {
    groupRatio = parseGroupRatios(record['group_ratio']);
  }
  final modelRatio = asRecord(record['model_ratio']);
  final completionRatio = asRecord(record['completion_ratio']);
  final modelPrice = asRecord(record['model_price']);
  final cacheRatio = asRecord(record['cache_ratio'] ?? root['cache_ratio']);
  final createCacheRatio = asRecord(
    record['create_cache_ratio'] ??
        record['cache_creation_ratio'] ??
        root['create_cache_ratio'] ??
        root['cache_creation_ratio'],
  );
  final names = <String>{...modelRatio.keys, ...modelPrice.keys};
  final quotes = <SiteModelQuote>[];
  for (final name in names) {
    final modelName = name.trim();
    if (modelName.isEmpty) {
      continue;
    }
    final price = readNumber(modelPrice[name]);
    final ratio = readNumber(modelRatio[name]);
    quotes.add(
      SiteModelQuote(
        modelName: modelName,
        modelRatio: ratio,
        completionRatio: readNumber(completionRatio[name], 1),
        modelPrice: price,
        quotaType: price > 0 && ratio <= 0 ? 1 : 0,
        cacheRatio: readOptionalNumber(cacheRatio[name]),
        createCacheRatio: readOptionalNumber(createCacheRatio[name]),
      ),
    );
  }
  return SitePricingCatalog(groupRatio: groupRatio, quotes: quotes);
}

String _formatPriceDigits(num value) {
  final abs = value.abs();
  if (abs >= 1) {
    return value.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }
  if (abs >= 0.01) {
    return value.toStringAsFixed(4);
  }
  return value.toStringAsFixed(6);
}

String formatModelPrice(num value) => value == 0 ? '\$0' : '\$${_formatPriceDigits(value)}';

String formatYuanPrice(num value) => value == 0 ? '¥0' : '¥${_formatPriceDigits(value)}';

String formatCachePriceLine(ModelCompareOffer offer) {
  if (offer.perCall) {
    return '';
  }
  final parts = <String>[];
  if (offer.hasCacheRead) {
    parts.add('缓存读 ${formatYuanPrice(offer.effectiveCacheRead)}');
  }
  if (offer.hasCacheWrite) {
    parts.add('缓存写 ${formatYuanPrice(offer.effectiveCacheWrite)}');
  }
  return parts.join(' · ');
}

String formatTopupRatio(num value) {
  final ratio = sanitizeTopupRatio(value);
  final text = ratio == ratio.roundToDouble() ? ratio.toInt().toString() : '$ratio';
  return '×$text';
}

String formatTopupRatioExplain(num value) {
  final ratio = sanitizeTopupRatio(value);
  final text = ratio == ratio.roundToDouble() ? ratio.toInt().toString() : '$ratio';
  return '$text 元人民币 = 1 美元';
}

String topupRatioInputText(num value) {
  final ratio = sanitizeTopupRatio(value);
  return ratio == ratio.roundToDouble() ? ratio.toInt().toString() : '$ratio';
}
