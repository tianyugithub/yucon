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
    List<String>? enableGroups,
  }) : enableGroups = enableGroups ?? [];

  final String modelName;
  final double modelRatio;
  final double completionRatio;
  final double modelPrice;
  final int quotaType;
  final List<String> enableGroups;

  bool get isPerCall => quotaType == 1 || (modelPrice > 0 && modelRatio <= 0);
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
}

class ModelPriceBreakdown {
  const ModelPriceBreakdown({
    required this.perCall,
    required this.siteInput,
    required this.siteOutput,
    required this.group,
    required this.groupRatio,
  });

  final bool perCall;
  final double siteInput;
  final double siteOutput;
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
    required this.effectiveInput,
    required this.effectiveOutput,
  });

  final String accountId;
  final String modelName;
  final String group;
  final double groupRatio;
  final double topupRatio;
  final bool perCall;
  final double siteInput;
  final double siteOutput;
  final double effectiveInput;
  final double effectiveOutput;

  double get sortPrice => effectiveInput;
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
  return quote.enableGroups.contains(group);
}

double groupRatioFor(SitePricingCatalog catalog, String group) {
  return catalog.groupRatio[group] ?? catalog.groupRatio['default'] ?? 1;
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
      group: group,
      groupRatio: ratio,
    );
  }
  final input = quote.modelRatio * ratio * millionTokens / unit;
  final output = quote.modelRatio * quote.completionRatio * ratio * millionTokens / unit;
  return ModelPriceBreakdown(
    perCall: false,
    siteInput: input,
    siteOutput: output,
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
    effectiveInput: price.siteInput * topup,
    effectiveOutput: price.siteOutput * topup,
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
  return [
    for (final group in billingGroupsForQuote(catalog, quote))
      offerForQuote(account: account, quote: quote, catalog: catalog, group: group),
  ];
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
      quotes.add(
        SiteModelQuote(
          modelName: name,
          modelRatio: modelRatio,
          completionRatio: readNumber(record['completion_ratio'], 1),
          modelPrice: modelPrice,
          quotaType: quotaType == 1 || (modelPrice > 0 && modelRatio <= 0) ? 1 : quotaType,
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
        quotaType: price > 0 ? 1 : 0,
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
