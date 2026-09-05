import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';

void main() {
  test('parses NewAPI log page with totals', () {
    final page = parsePagedItemsFromPayload(
      {
        'success': true,
        'data': {
          'items': [
            {
              'id': 9,
              'type': 2,
              'token_name': 'api_token',
              'model_name': 'gpt-4o-mini',
              'quota': 500000,
              'prompt_tokens': 12,
              'completion_tokens': 34,
              'created_at': 1757055153,
              'use_time': 2,
              'is_stream': true,
              'ip': '1.2.3.4',
              'group': 'default',
            },
          ],
          'total': 87,
          'page': 2,
          'page_size': 20,
        },
      },
      NewApiUsageLog.fromJson,
      page: 2,
      pageSize: 20,
    );

    expect(page.total, 87);
    expect(page.page, 2);
    expect(page.pageSize, 20);
    expect(page.totalKnown, isTrue);
    expect(page.items.single.modelName, 'gpt-4o-mini');
    expect(page.items.single.isStream, isTrue);
    expect(page.items.single.ip, '1.2.3.4');
    expect(page.items.single.timeIso, isNotNull);
  });

  test('parses legacy list payload without total as unknown length', () {
    final page = parsePagedItemsFromPayload(
      {
        'success': true,
        'data': [
          {'id': 1, 'model_name': 'gpt-4', 'created_at': 1757055153},
        ],
      },
      NewApiUsageLog.fromJson,
    );
    expect(page.items, hasLength(1));
    expect(page.totalKnown, isFalse);
  });

  test('created_at accepts unix seconds and iso strings', () {
    expect(createdAtToIso(1757055153), isNotNull);
    expect(createdAtToIso('2026-09-05T06:12:33Z'), '2026-09-05T06:12:33.000Z');
  });

  test('today window covers local calendar day', () {
    final now = DateTime(2026, 9, 5, 14, 12, 33);
    final window = dateWindowFor(UsageTimeRange.today, now);
    expect(window.startDate, '2026-09-05');
    expect(window.endDate, '2026-09-05');
    expect(window.startUnix, DateTime(2026, 9, 5).millisecondsSinceEpoch ~/ 1000);
    expect(
      window.endUnix,
      DateTime(2026, 9, 5, 23, 59, 59).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('query result page count and full datetime', () {
    const result = UsageLogQueryResult(total: 87, page: 2, pageSize: 20);
    expect(result.pageCount, 5);
    expect(result.hasPrev, isTrue);
    expect(result.hasNext, isTrue);
    expect(
      formatDateTimeFull('2026-09-05T06:12:33.000Z'),
      matches(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')),
    );
    expect(formatUseTime(2), '2s');
    expect(usageLogTypeLabel(2), '消费');
    expect(formatLogMoney(0.001234), '\$0.001234');
    expect(formatUsageQuota(10, 1), '+\$10.00');
    expect(
      parseTopupAmountFromContent(
        '使用在线充值成功，充值金额：\$ 20.000000 额度，支付金额：20.000000',
      ),
      20,
    );
    expect(
      parseTopupAmountFromContent('使用在线充值成功，充值金额: \$10.000000 额度'),
      10,
    );
    expect(
      resolveUsageQuotaCost(
        type: 1,
        quota: 0,
        content: '使用在线充值成功，充值金额：\$ 20.000000 额度，支付金额：20.000000',
      ),
      20,
    );
    expect(
      resolveUsageQuotaCost(type: 1, quota: 10000000, content: '', quotaPerUnit: 500000),
      20,
    );
    expect(
      resolveUsageQuotaCost(type: 2, quota: 500000, content: '充值金额: \$20'),
      1,
    );
  });

  test('old usage log json still loads', () {
    final log = UsageLog.fromJson({
      'id': 'a',
      'accountId': 'b',
      'platformType': 'newapi',
      'apiKeyId': '',
      'apiKeyName': 'token',
      'model': 'gpt-4',
      'time': '2026-09-05T06:12:33.000Z',
      'quotaCost': 0.12,
      'promptTokens': 1,
      'completionTokens': 2,
      'success': true,
    });
    expect(log.type, 2);
    expect(log.ip, isEmpty);
    expect(log.quotaCost, 0.12);
  });
}
