import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';
import 'package:vault/app/utils/usage_log_content.dart';
import 'package:vault/screens/theme_define.dart';
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
    final failed = !log.success || log.type == 5;
    final duration = formatUseTime(log.useTime);
    final amount = formatUsageQuota(log.quotaCost, log.type);
    final quotaColor = topup
        ? const Color(0xFF168553)
        : (failed ? const Color(0xFFC54638) : ThemeDefine.kColorPrimary);
    final extraFields = usageLogOtherFields(log.other);
    final contentInfo = parseUsageLogContent(log.content);
    final showParsedContent = log.content.trim().isNotEmpty &&
        (contentInfo.statusCode != null ||
            contentInfo.message != null ||
            contentInfo.traceId != null);
    final billingFields = extraFields.where(_isBillingField).toList();
    final otherFields = extraFields.where((field) => !_isBillingField(field)).toList();
    final sourceRows = [
      (label: '账号', value: accountName),
      (label: '密钥', value: log.apiKeyName.trim().isEmpty ? '未命名密钥' : log.apiKeyName.trim()),
      if (log.group.trim().isNotEmpty) (label: '分组', value: log.group.trim()),
      if (log.channelName.trim().isNotEmpty) (label: '渠道', value: log.channelName.trim()),
      if (log.username.trim().isNotEmpty) (label: '站点用户', value: log.username.trim()),
    ];
    final requestRows = [
      if (duration.isNotEmpty) (label: '耗时', value: duration),
      (label: '流式', value: log.isStream ? '是' : '否'),
      if (showIp && log.ip.trim().isNotEmpty) (label: 'IP', value: log.ip.trim()),
      if (log.requestId.trim().isNotEmpty) (label: '请求 ID', value: log.requestId.trim()),
      if (log.upstreamRequestId.trim().isNotEmpty)
        (label: '上游请求 ID', value: log.upstreamRequestId.trim()),
    ];

    return SecureScope(
      child: Scaffold(
        appBar: YuconAppBar(
          title: '调用详情',
          subtitle: accountName,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              borderColor: failed ? const Color(0x33FA2C19) : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _leadIcon(topup: topup, failed: failed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usageLogTitle(log),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.25),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${usageLogTypeLabel(log.type)} · ${formatDateTimeFull(log.time)}',
                          style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 11, height: 1.3),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            StatusChip(
                              label: failed ? '失败' : '成功',
                              color: failed ? const Color(0xFFC54638) : const Color(0xFF168553),
                              background: failed ? const Color(0xFFFFEFEF) : const Color(0xFFE7F7EF),
                            ),
                            if (log.isStream) const _MetaChip(label: '流式'),
                            if (duration.isNotEmpty) _MetaChip(label: duration),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    amount,
                    style: TextStyle(
                      color: quotaColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (showParsedContent) ...[
              const SizedBox(height: 8),
              _ErrorCard(info: contentInfo, onCopy: (label, value) => _copy(store, label, value)),
            ] else if (log.content.trim().isNotEmpty) ...[
              _blockTitle('内容'),
              YuconCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: SelectableText(
                  log.content.trim(),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
            if (!topup && usageLogShowsTokens(log)) ...[
              _blockTitle('Tokens'),
              YuconCard(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _TokenMetric(label: '输入', value: formatGroupedInt(log.promptTokens)),
                        _TokenMetric(label: '输出', value: formatGroupedInt(log.completionTokens)),
                        _TokenMetric(label: '合计', value: formatGroupedInt(log.totalTokens), last: true),
                      ],
                    ),
                    if (log.cacheReadTokens > 0 || log.cacheWriteTokens > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (log.cacheReadTokens > 0)
                            _TokenMetric(
                              label: '缓存读',
                              value: formatGroupedInt(log.cacheReadTokens),
                              last: log.cacheWriteTokens <= 0,
                            ),
                          if (log.cacheWriteTokens > 0)
                            _TokenMetric(
                              label: '缓存写',
                              value: formatGroupedInt(log.cacheWriteTokens),
                              last: true,
                            ),
                          if (log.cacheReadTokens <= 0 || log.cacheWriteTokens <= 0)
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (sourceRows.isNotEmpty) ...[
              _blockTitle('来源'),
              _RowsCard(
                rows: sourceRows,
                onCopy: (label, value) => _copy(store, label, value),
              ),
            ],
            if (requestRows.isNotEmpty) ...[
              _blockTitle('请求'),
              _RowsCard(
                rows: requestRows,
                onCopy: (label, value) => _copy(store, label, value),
              ),
            ],
            if (billingFields.isNotEmpty) ...[
              _blockTitle('计费'),
              _RowsCard(
                rows: [
                  for (final field in billingFields) (label: field.label, value: field.value),
                ],
                onCopy: (label, value) => _copy(store, label, value),
              ),
            ],
            if (otherFields.isNotEmpty) ...[
              _blockTitle('其它'),
              _RowsCard(
                rows: [
                  for (final field in otherFields) (label: field.label, value: field.value),
                ],
                onCopy: (label, value) => _copy(store, label, value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leadIcon({required bool topup, required bool failed}) {
    if (topup) {
      return SquareIcon(
        size: 36,
        radius: 11,
        color: const Color(0xFFE7F7EF),
        child: Text(
          log.type == 6 ? '↩' : '+',
          style: const TextStyle(color: Color(0xFF168553), fontWeight: FontWeight.w800, fontSize: 18),
        ),
      );
    }
    if (failed && (log.model.trim().isEmpty || log.model == '未知模型')) {
      return SquareIcon(
        size: 36,
        radius: 11,
        color: ThemeDefine.kColorSoft,
        child: const Text(
          '!',
          style: TextStyle(color: ThemeDefine.kColorPrimary, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ThemeDefine.kColorSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: ModelBrandIcon(model: log.model),
    );
  }

  static Widget _blockTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: ThemeDefine.kColorText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static bool _isBillingField(UsageLogField field) {
    final label = field.label;
    return label.contains('倍率') ||
        label.contains('价格') ||
        label.contains('计费') ||
        label.contains('档位') ||
        label.contains('tokens') ||
        label == '上游模型' ||
        label == '模型已映射' ||
        label == '本地计费' ||
        label == '推理力度';
  }

  static Future<void> _copy(VaultStore store, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    store.notify('已复制$label');
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: ThemeDefine.kColorText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}

class _TokenMetric extends StatelessWidget {
  const _TokenMetric({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: last ? 0 : 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.rows, required this.onCopy});

  final List<({String label, String value})> rows;
  final Future<void> Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine),
            _InfoRow(label: rows[i].label, value: rows[i].value, onCopy: onCopy),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.onCopy});

  final String label;
  final String value;
  final Future<void> Function(String label, String value) onCopy;

  bool get _copyable {
    final lower = label.toLowerCase();
    return value.length > 16 ||
        lower.contains('id') ||
        label == 'IP' ||
        label.contains('路径') ||
        label.contains('User-Agent');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 8, _copyable ? 0 : 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : ThemeDefine.kColorTitle,
              ),
            ),
          ),
          if (_copyable)
            IconButton(
              onPressed: () => onCopy(label, value),
              tooltip: '复制$label',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.copy_outlined, size: 14, color: ThemeDefine.kColorText),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.info, required this.onCopy});

  final UsageLogContentInfo info;
  final Future<void> Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final message = info.message?.trim().isNotEmpty == true ? info.message!.trim() : info.preview.trim();
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      borderColor: const Color(0x33FA2C19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '错误信息',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFC54638)),
              ),
              const Spacer(),
              if (info.statusCode != null)
                StatusChip(
                  label: '${info.statusCode}',
                  color: const Color(0xFFC54638),
                  background: const Color(0xFFFFEFEF),
                ),
            ],
          ),
          if (info.type != null && info.type!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(info.type!, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              message,
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: Color(0xFFC54638)),
            ),
          ],
          if (info.traceId != null && info.traceId!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Trace ID', value: info.traceId!, onCopy: onCopy),
          ],
        ],
      ),
    );
  }
}
