import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/debug/json_view.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class HttpRequestLogDetailScreen extends StatefulWidget {
  const HttpRequestLogDetailScreen({super.key, required this.logId});

  final String logId;

  @override
  State<HttpRequestLogDetailScreen> createState() => _HttpRequestLogDetailScreenState();
}

class _HttpRequestLogDetailScreenState extends State<HttpRequestLogDetailScreen> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final log = context.watch<HttpRequestLogger>().byId(widget.logId);
    if (log == null) {
      return const Scaffold(
        appBar: YuconAppBar(title: '请求详情'),
        body: Center(child: Text('这条记录已经不在了', style: TextStyle(color: ThemeDefine.kColorText))),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = log.isTransportError
        ? const Color(0xFFBE2630)
        : log.is2xx
        ? ThemeDefine.kColorGreenBright
        : log.is4xx
        ? ThemeDefine.kColorWarning
        : const Color(0xFFBE2630);

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(
        title: '请求详情',
        subtitle: log.statusLabel,
        actions: [
          HeaderTextAction(
            label: '复制全文',
            onPressed: () => _copy(store, log.dump(reveal: _reveal), '已复制全部内容'),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'http-reveal',
            tooltip: _reveal ? '隐藏敏感内容' : '显示原文',
            backgroundColor: dark ? const Color(0xFF2A2424) : Colors.white,
            foregroundColor: ThemeDefine.kColorPrimary,
            onPressed: () => setState(() => _reveal = !_reveal),
            child: Icon(_reveal ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'http-curl',
            backgroundColor: ThemeDefine.kColorPrimary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制为 curl', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => _copy(store, log.toCurl(reveal: _reveal), '已复制 curl'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 108),
        children: [
          _OverviewCard(log: log, dark: dark, statusColor: statusColor),
          _PayloadCard(
            icon: Icons.north_east_rounded,
            title: 'REQUEST',
            headersLabel: '请求头',
            bodyLabel: '请求体',
            emptyBodyLabel: '<无请求体>',
            dark: dark,
            query: log.queryParameters,
            headers: log.displayRequestHeaders(reveal: _reveal),
            body: log.displayRequestBody(reveal: _reveal),
            contentType: log.requestContentType,
            onCopyHeaders: () => _copy(store, formatHeaderBlock(log.displayRequestHeaders(reveal: _reveal)), '已复制请求头'),
            onCopyBody: () => _copy(store, log.displayRequestBody(reveal: _reveal) ?? '', '已复制请求体'),
          ),
          _PayloadCard(
            icon: Icons.south_west_rounded,
            title: 'RESPONSE',
            headersLabel: '响应头',
            bodyLabel: '响应体',
            emptyBodyLabel: log.isTransportError ? '<无响应>' : '<无响应体>',
            dark: dark,
            headers: log.displayResponseHeaders(reveal: _reveal),
            body: log.displayResponseBody(reveal: _reveal),
            contentType: log.responseContentType,
            onCopyHeaders: () => _copy(store, formatHeaderBlock(log.displayResponseHeaders(reveal: _reveal)), '已复制响应头'),
            onCopyBody: () => _copy(store, log.displayResponseBody(reveal: _reveal) ?? '', '已复制响应体'),
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _copy(VaultStore store, String text, String ok) async {
    if (text.trim().isEmpty) {
      store.notify('没有可复制的内容', FeedbackType.text);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    store.notify(ok);
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.log, required this.dark, required this.statusColor});

  final HttpRequestLog log;
  final bool dark;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final bar = (log.duration.inMilliseconds / 3000).clamp(0.08, 1.0);
    return _SectionCard(
      icon: Icons.info_outline_rounded,
      title: '概览',
      dark: dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MethodBadge(method: log.method),
              _Pill(text: log.statusLabel, color: statusColor, dark: dark),
              _Pill(text: log.durationLabel, color: ThemeDefine.kColorText, dark: dark),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            log.url,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: dark ? Colors.white : ThemeDefine.kColorTitle,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 4,
              color: statusColor,
              backgroundColor: dark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F3F6),
            ),
          ),
          const SizedBox(height: 14),
          _MetaTable(
            dark: dark,
            rows: [
              ('状态', log.statusLabel, statusColor),
              ('耗时', log.durationLabel, null),
              ('开始', log.startedClock, null),
              ('结束', log.endedClock, null),
              ('主机', log.host, null),
              ('路径', log.pathOnly, null),
              ('请求体', log.requestSizeLabel, null),
              ('响应体', log.responseSizeLabel, null),
            ],
          ),
          if (log.error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0x14BE2630),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                log.error!,
                style: const TextStyle(color: Color(0xFFBE2630), fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayloadCard extends StatelessWidget {
  const _PayloadCard({
    required this.icon,
    required this.title,
    required this.headersLabel,
    required this.bodyLabel,
    required this.dark,
    required this.headers,
    required this.body,
    required this.onCopyHeaders,
    required this.onCopyBody,
    this.query = const {},
    this.contentType,
    this.emptyBodyLabel = '<无内容>',
  });

  final IconData icon;
  final String title;
  final String headersLabel;
  final String bodyLabel;
  final bool dark;
  final Map<String, String> query;
  final Map<String, String> headers;
  final String? body;
  final String? contentType;
  final String emptyBodyLabel;
  final VoidCallback onCopyHeaders;
  final VoidCallback onCopyBody;

  @override
  Widget build(BuildContext context) {
    final kind = bodyKind(body);
    return _SectionCard(
      icon: icon,
      title: title,
      dark: dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (query.isNotEmpty) ...[
            _SubHead(label: '查询参数', count: query.length, onCopy: null, dark: dark),
            _PairList(pairs: query.entries.toList(), dark: dark),
            const SizedBox(height: 14),
          ],
          _SubHead(label: headersLabel, count: headers.length, onCopy: onCopyHeaders, dark: dark),
          if (headers.isEmpty)
            const Text('<无>', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13, fontStyle: FontStyle.italic))
          else
            _PairList(pairs: sortedHeaders(headers), dark: dark, keyTint: true),
          const SizedBox(height: 14),
          _SubHead(
            label: bodyLabel,
            chip: kind == HttpBodyKind.json
                ? 'JSON'
                : kind == HttpBodyKind.html
                ? 'HTML'
                : (contentType?.split(';').first.trim().isNotEmpty == true ? contentType!.split(';').first.trim() : null),
            onCopy: kind == HttpBodyKind.empty ? null : onCopyBody,
            dark: dark,
          ),
          if (kind == HttpBodyKind.empty)
            Text(
              emptyBodyLabel,
              style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, fontStyle: FontStyle.italic),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF141414) : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine),
              ),
              child: CodeBodyView(text: body, dark: dark),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.dark,
    required this.child,
  });

  final IconData icon;
  final String title;
  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF2A1C1A) : ThemeDefine.kColorSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: ThemeDefine.kColorPrimary),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SubHead extends StatelessWidget {
  const _SubHead({required this.label, required this.dark, this.count, this.chip, this.onCopy});

  final String label;
  final bool dark;
  final int? count;
  final String? chip;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          if (chip != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2A1C1A) : ThemeDefine.kColorSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                chip!,
                style: const TextStyle(color: ThemeDefine.kColorPrimary, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const Spacer(),
          if (onCopy != null)
            GestureDetector(
              onTap: onCopy,
              child: const Text('复制', style: TextStyle(color: ThemeDefine.kColorPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _MetaTable extends StatelessWidget {
  const _MetaTable({required this.rows, required this.dark});

  final List<(String, String, Color?)> rows;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 16, color: dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine),
          _KvRow(label: rows[i].$1, value: rows[i].$2, valueColor: rows[i].$3, dark: dark),
        ],
      ],
    );
  }
}

class _PairList extends StatelessWidget {
  const _PairList({required this.pairs, required this.dark, this.keyTint = false});

  final List<MapEntry<String, String>> pairs;
  final bool dark;
  final bool keyTint;

  @override
  Widget build(BuildContext context) {
    final keyColor = keyTint
        ? (dark ? const Color(0xFFFF9B8A) : const Color(0xFFC54638))
        : ThemeDefine.kColorText;
    return Column(
      children: [
        for (var i = 0; i < pairs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: SelectableText(
                  pairs[i].key,
                  style: TextStyle(
                    color: keyColor,
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  pairs[i].value,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: dark ? const Color(0xFFE8E6E3) : ThemeDefine.kColorTitle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value, required this.dark, this.valueColor});

  final String label;
  final String value;
  final bool dark;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: valueColor ?? (dark ? Colors.white : ThemeDefine.kColorTitle),
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      'GET' => ThemeDefine.kColorGreenBright,
      'POST' => ThemeDefine.kColorWarning,
      'PUT' || 'PATCH' => const Color(0xFF3178DF),
      'DELETE' => const Color(0xFFBE2630),
      _ => ThemeDefine.kColorText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
      child: Text(method, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.dark});

  final String text;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}
