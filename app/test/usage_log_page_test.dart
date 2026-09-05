import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/app/utils/usage_log_content.dart';

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

  test('token line includes the tokens unit and cache reads', () {
    final log = UsageLog(
      id: 'a',
      accountId: 'b',
      platformType: PlatformType.newapi,
      apiKeyId: '',
      apiKeyName: 'token',
      model: 'gpt-4o',
      time: '2026-09-05T06:12:33.000Z',
      quotaCost: 0.12,
      promptTokens: 1200,
      completionTokens: 34,
      success: true,
      other: const {'cache_tokens': 88, 'cache_creation_tokens': 12},
    );
    expect(formatTokenCount(1200), '1,200 tokens');
    expect(
      formatUsageTokenLine(log),
      '输入 1,200 tokens · 输出 34 tokens · 缓存 88 tokens',
    );
    expect(log.totalTokens, 1234);
    expect(log.cacheReadTokens, 88);
    expect(log.cacheWriteTokens, 12);
    expect(usageLogShowsTokens(log), isTrue);
  });

  test('parses NewAPI other json for cache tokens and request id', () {
    final parsed = NewApiUsageLog.fromJson({
      'id': 9,
      'type': 2,
      'token_name': 'api_token',
      'model_name': 'gpt-4o-mini',
      'quota': 500000,
      'prompt_tokens': 12,
      'completion_tokens': 34,
      'created_at': 1757055153,
      'request_id': 'req-1',
      'channel_name': 'OpenAI',
      'other': '{"cache_tokens": 8, "cache_creation_tokens_5m": 2, "cache_creation_tokens_1h": 3}',
    });
    expect(parsed.requestId, 'req-1');
    expect(parsed.channelName, 'OpenAI');
    expect(parsed.other['cache_tokens'], 8);
    expect(usageLogCacheReadTokens(parsed.other), 8);
    expect(usageLogCacheWriteTokens(parsed.other), 5);
  });

  test('parses NewAPI error content into a readable message', () {
    const raw =
        'status_code=400, {"error":{"message":"The \'gpt-5.4\' model is not supported when using Codex with a ChatGPT account.","type":"invalid_request_error"}} (traceid: 5367dabc)';
    final parsed = parseUsageLogContent(raw);
    expect(parsed.statusCode, 400);
    expect(parsed.type, 'invalid_request_error');
    expect(parsed.traceId, '5367dabc');
    expect(
      parsed.preview,
      "The 'gpt-5.4' model is not supported when using Codex with a ChatGPT account.",
    );
    expect(parsed.fields.map((item) => item.label).toList(), [
      '状态码',
      '错误类型',
      '说明',
      'Trace ID',
    ]);
  });

  test('flattens other json into labeled rows', () {
    final fields = usageLogOtherFields({
      'cache_tokens': 63,
      'frt': 210,
      'upstream_model_name': 'claude-haiku-4-5',
      'is_model_mapped': true,
      'model_ratio': 1.25,
      'admin_info': {
        'use_channel': ['12'],
        'local_count_tokens': false,
      },
    });
    expect(fields.map((item) => '${item.label}=${item.value}').toList(), [
      '首字耗时=210ms',
      '上游模型=claude-haiku-4-5',
      '模型已映射=是',
      '模型倍率=1.25',
      '实际渠道=12',
    ]);
  });
}
