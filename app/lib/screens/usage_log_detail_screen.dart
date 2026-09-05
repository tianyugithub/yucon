import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/app/utils/usage_log_content.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class UsageLogDetailScreen extends StatelessWidget {
  const UsageLogDetailScreen({
    super.key,
    required this.log,
    required this.showIp,
  });

  final UsageLog log;
  final bool showIp;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final account = store.accountById(log.accountId);
    final accountName = account == null ? '已删除账号' : store.displayAccountName(account);
    final topup = isUsageTopup(log.type);
    final duration = formatUseTime(log.useTime);
    final amount = formatUsageQuota(log.quotaCost, log.type);
    final quotaColor = topup
        ? const Color(0xFF168553)
        : (log.type == 5 ? const Color(0xFFC54638) : ThemeDefine.kColorPrimary);
    final extraFields = usageLogOtherFields(log.other);
    final contentInfo = parseUsageLogContent(log.content);
    final showParsedContent = log.content.trim().isNotEmpty &&
        (contentInfo.statusCode != null ||
            contentInfo.message != null ||
            contentInfo.traceId != null);

    return SecureScope(
      child: Scaffold(
        appBar: YuconAppBar(
          title: '调用详情',
          subtitle: usageLogTypeLabel(log.type),
          actions: [
            HeaderTextAction(
              label: '复制',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: formatUsageLogDump(log, accountName: accountName, showIp: showIp),
                  ),
                );
                store.notify('已复制这条记录');
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 28),
          children: [
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      topup
                          ? SquareIcon(
                              size: 36,
                              radius: 11,
                              color: const Color(0xFFE7F7EF),
                              child: Text(
                                log.type == 6 ? '↩' : '+',
                                style: const TextStyle(
                                  color: Color(0xFF168553),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            )
                          : Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: ThemeDefine.kColorSoft,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: ModelBrandIcon(model: log.model),
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          usageLogTitle(log),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    amount,
                    style: TextStyle(
                      color: quotaColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${getPlatformPreset(log.platformType).label} · ${formatDateTimeFull(log.time)}',
                    style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!topup) ...[
              const SectionTitle(text: 'Tokens'),
              YuconCard(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  children: [
                    _TokenMetric(label: '输入', value: log.promptTokens),
                    _TokenMetric(label: '输出', value: log.completionTokens),
                    _TokenMetric(label: '合计', value: log.totalTokens, last: true),
                  ],
                ),
              ),
              if (log.cacheReadTokens > 0 || log.cacheWriteTokens > 0)
                GroupCard(
                  children: [
                    if (log.cacheReadTokens > 0)
                      GroupTile(title: '缓存读取', value: formatTokenCount(log.cacheReadTokens)),
                    if (log.cacheWriteTokens > 0)
                      GroupTile(title: '缓存写入', value: formatTokenCount(log.cacheWriteTokens)),
                  ],
                ),
            ],
            const SectionTitle(text: '记录信息'),
            GroupCard(
              children: [
                GroupTile(title: '类型', value: usageLogTypeLabel(log.type)),
                GroupTile(title: '结果', value: log.success ? '成功' : '失败'),
                GroupTile(title: '账号', value: accountName),
                GroupTile(title: '密钥', value: log.apiKeyName.trim().isEmpty ? '未命名密钥' : log.apiKeyName),
                if (log.group.trim().isNotEmpty) GroupTile(title: '分组', value: log.group.trim()),
                GroupTile(title: '平台', value: getPlatformPreset(log.platformType).label),
                GroupTile(title: '流式', value: log.isStream ? '是' : '否'),
                if (duration.isNotEmpty) GroupTile(title: '耗时', value: duration),
                GroupTile(title: '时间', value: formatDateTimeFull(log.time)),
                if (showIp && log.ip.trim().isNotEmpty) GroupTile(title: 'IP', value: log.ip.trim()),
                if (log.requestId.trim().isNotEmpty) GroupTile(title: '请求 ID', value: log.requestId.trim()),
                if (log.upstreamRequestId.trim().isNotEmpty)
                  GroupTile(title: '上游请求 ID', value: log.upstreamRequestId.trim()),
                if (log.channelName.trim().isNotEmpty) GroupTile(title: '渠道', value: log.channelName.trim()),
                if (log.username.trim().isNotEmpty) GroupTile(title: '站点用户', value: log.username.trim()),
              ],
            ),
            if (showParsedContent) ...[
              const SectionTitle(text: '错误信息'),
              _FieldCard(
                fields: contentInfo.fields,
                danger: true,
              ),
            ] else if (log.content.trim().isNotEmpty) ...[
              const SectionTitle(text: '内容'),
              YuconCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: SelectableText(
                  log.content.trim(),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
            if (extraFields.isNotEmpty) ...[
              const SectionTitle(text: '附加数据'),
              _FieldCard(fields: extraFields),
            ],
          ],
        ),
      ),
    );
  }
}

class _TokenMetric extends StatelessWidget {
  const _TokenMetric({required this.label, required this.value, this.last = false});

  final String label;
  final int value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: last ? 0 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              formatGroupedInt(value),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.1),
            ),
            const SizedBox(height: 2),
            const Text('tokens', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.fields, this.danger = false});

  final List<UsageLogField> fields;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      borderColor: danger ? const Color(0x33FA2C19) : null,
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) Divider(height: 1, color: dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      fields[i].label,
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      fields[i].value,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: danger && fields[i].label == '说明'
                            ? const Color(0xFFC54638)
                            : (dark ? Colors.white : ThemeDefine.kColorTitle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
