import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/model_pricing.dart';

Account _account({
  String id = 'a1',
  String group = 'default',
  double topupRatio = 1,
  double quotaPerUnit = 500000,
}) {
  return Account(
    id: id,
    alias: '主账号',
    siteName: '测试站',
    baseUrl: 'https://api.example.com',
    platformType: PlatformType.newapi,
    authMode: AuthMode.password,
    userId: '1',
    username: 'demo',
    displayName: 'demo',
    email: '',
    group: group,
    quota: 10,
    usedQuota: 0,
    requestCount: 0,
    quotaPerUnit: quotaPerUnit,
    status: AccountStatus.active,
    checkedInToday: false,
    checkinEnabled: false,
    tags: const [],
    trend: const [],
    createdAt: '',
    updatedAt: '',
    topupRatio: topupRatio,
  );
}

void main() {
  test('parses classic NewAPI map pricing', () {
    final catalog = parseSitePricing({
      'success': true,
      'data': {
        'model_ratio': {'gpt-4': 15, 'gpt-3.5-turbo': 0.75},
        'completion_ratio': {'gpt-4': 2},
        'model_price': {'dall-e-3': 0.04},
        'group_ratio': {'default': 1, 'vip': 0.5},
      },
    });
    expect(catalog.quotes.map((item) => item.modelName), containsAll(['gpt-4', 'gpt-3.5-turbo', 'dall-e-3']));

    final gpt4 = catalog.quotes.firstWhere((item) => item.modelName == 'gpt-4');
    final price = priceForQuote(
      quote: gpt4,
      catalog: catalog,
      group: 'default',
      quotaPerUnit: 500000,
    );
    expect(price.perCall, isFalse);
    expect(price.siteInput, 30);
    expect(price.siteOutput, 60);

    final dalle = catalog.quotes.firstWhere((item) => item.modelName == 'dall-e-3');
    final callPrice = priceForQuote(
      quote: dalle,
      catalog: catalog,
      group: 'vip',
      quotaPerUnit: 500000,
    );
    expect(callPrice.perCall, isTrue);
    expect(callPrice.siteInput, closeTo(0.02, 0.000001));
  });

  test('parses array pricing and respects enable_groups plus topup ratio', () {
    final catalog = parseSitePricing({
      'success': true,
      'data': [
        {
          'model_name': 'gpt-4o',
          'quota_type': 0,
          'model_ratio': 1.25,
          'completion_ratio': 4,
          'model_price': 0,
          'enable_groups': ['default', 'vip'],
        },
        {
          'model_name': 'sora',
          'quota_type': 1,
          'model_ratio': 0,
          'completion_ratio': 1,
          'model_price': 0.1,
          'enable_groups': ['vip'],
        },
      ],
      'group_ratio': {'default': 1, 'vip': 0.8, 'auto': 1},
    });

    final gpt4o = catalog.quotes.firstWhere((item) => item.modelName == 'gpt-4o');
    expect(billingGroupsForQuote(catalog, gpt4o), ['vip', 'default']);
    final vip = offerForQuote(
      account: _account(topupRatio: 2.5),
      quote: gpt4o,
      catalog: catalog,
      group: 'vip',
    );
    expect(vip.groupRatio, 0.8);
    expect(vip.effectiveInput, closeTo(5.0, 0.000001));
    final offer = offerForQuote(
      account: _account(topupRatio: 2.5),
      quote: gpt4o,
      catalog: catalog,
    );
    expect(offer.siteInput, 2.5);
    expect(offer.siteOutput, 10);
    expect(offer.effectiveInput, 6.25);
    expect(offer.effectiveOutput, 25);
    expect(offer.sortPrice, 25);
    expect(formatYuanPrice(offer.effectiveInput), '¥6.25');
    expect(formatTopupRatioExplain(2.5), '2.5 元人民币 = 1 美元');
    expect(formatTopupRatioExplain(1), '1 元人民币 = 1 美元');

    final sora = catalog.quotes.firstWhere((item) => item.modelName == 'sora');
    expect(quoteAvailableForGroup(sora, 'default'), isFalse);
    expect(quoteAvailableForGroup(sora, 'vip'), isTrue);
    expect(billingGroupsForQuote(catalog, sora), ['vip']);
    final soraOffer = offerForQuote(
      account: _account(group: 'vip'),
      quote: sora,
      catalog: catalog,
    );
    expect(soraOffer.perCall, isTrue);
    expect(soraOffer.effectiveInput, closeTo(0.08, 0.000001));
  });

  test('auto group falls back to default and invalid topup becomes 1', () {
    expect(compareGroupForAccount(_account(group: 'auto')), 'default');
    expect(compareGroupForAccount(_account(group: '')), 'default');
    expect(sanitizeTopupRatio(0), 1);
    expect(sanitizeTopupRatio(-2), 1);
    expect(formatTopupRatio(2.5), '×2.5');
    expect(Account.fromJson(_account(topupRatio: 2.5).toJson()).topupRatio, 2.5);
  });

  test('filters pricing to models the account can actually use', () {
    final catalog = parseSitePricing({
      'data': {
        'model_ratio': {'kept': 1, 'hidden': 2},
        'group_ratio': {'default': 1},
      },
    });
    final filtered = catalog.filteredToModels(['kept']);
    expect(filtered.quotes.map((item) => item.modelName), ['kept']);
    expect(catalog.filteredToModels([]).quotes.length, 2);
  });

  test('parses cache ratios and enable_groups all', () {
    final catalog = parseSitePricing({
      'success': true,
      'data': [
        {
          'model_name': 'claude-sonnet',
          'quota_type': 0,
          'model_ratio': 1.5,
          'completion_ratio': 5,
          'cache_ratio': 0.1,
          'create_cache_ratio': 1.25,
          'enable_groups': ['all'],
        },
      ],
      'group_ratio': {'default': 1, 'vip': 0.8},
    });
    final quote = catalog.quotes.first;
    expect(quoteAvailableForGroup(quote, 'default'), isTrue);
    expect(quoteAvailableForGroup(quote, 'vip'), isTrue);
    expect(billingGroupsForQuote(catalog, quote), ['vip', 'default']);

    final price = priceForQuote(
      quote: quote,
      catalog: catalog,
      group: 'default',
      quotaPerUnit: 500000,
    );
    expect(price.siteInput, 3);
    expect(price.siteOutput, 15);
    expect(price.hasCacheRead, isTrue);
    expect(price.hasCacheWrite, isTrue);
    expect(price.siteCacheRead, closeTo(0.3, 0.000001));
    expect(price.siteCacheWrite, closeTo(3.75, 0.000001));

    final roundtrip = SitePricingCatalog.fromJson(catalog.toJson());
    expect(roundtrip.quotes.first.cacheRatio, 0.1);
    expect(roundtrip.quotes.first.createCacheRatio, 1.25);
    expect(formatCachePriceLine(offerForQuote(
      account: _account(),
      quote: quote,
      catalog: catalog,
    )), '缓存读 ¥0.3000 · 缓存写 ¥3.75');
  });

  test('map pricing keeps token billing when both ratio and price exist', () {
    final catalog = parseSitePricing({
      'data': {
        'model_ratio': {'gpt-4': 15},
        'model_price': {'gpt-4': 0.06},
        'completion_ratio': {'gpt-4': 2},
        'cache_ratio': {'gpt-4': 0.5},
        'group_ratio': {'default': 1},
      },
    });
    final quote = catalog.quotes.first;
    expect(quote.isPerCall, isFalse);
    expect(quote.cacheRatio, 0.5);
    final price = priceForQuote(
      quote: quote,
      catalog: catalog,
      group: 'default',
      quotaPerUnit: 500000,
    );
    expect(price.siteInput, 30);
    expect(price.siteCacheRead, 15);
  });

  test('picks account group or cheapest offer', () {
    final catalog = parseSitePricing({
      'data': [
        {
          'model_name': 'gpt-4o',
          'quota_type': 0,
          'model_ratio': 1.25,
          'completion_ratio': 4,
          'enable_groups': ['default', 'vip'],
        },
      ],
      'group_ratio': {'default': 1, 'vip': 0.8},
    });
    final quote = catalog.quotes.first;
    final offers = offersForAccountModel(
      account: _account(group: 'default'),
      quote: quote,
      catalog: catalog,
    );
    expect(offers.first.group, 'vip');
    expect(
      pickOfferForAccount(
        account: _account(group: 'default'),
        offers: offers,
        useAccountGroup: false,
      )?.group,
      'vip',
    );
    expect(
      pickOfferForAccount(
        account: _account(group: 'default'),
        offers: offers,
        useAccountGroup: true,
      )?.group,
      'default',
    );
    expect(isAccountBillingGroup(_account(group: 'auto'), 'default'), isTrue);
  });
}
