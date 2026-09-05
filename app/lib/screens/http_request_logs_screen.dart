import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/http_request_log_detail_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class HttpRequestLogsScreen extends StatefulWidget {
  const HttpRequestLogsScreen({super.key});

  @override
  State<HttpRequestLogsScreen> createState() => _HttpRequestLogsScreenState();
}

class _HttpRequestLogsScreenState extends State<HttpRequestLogsScreen> {
  HttpLogFilter _filter = HttpLogFilter.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final logger = context.watch<HttpRequestLogger>();
    final logs = logger.query(filter: _filter, search: _search);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(
        title: '请求记录',
        subtitle: logger.enabled ? '正在记录' : '记录已暂停',
        actions: [
          Switch(
            value: logger.enabled,
            onChanged: (value) {
              store.updateSettings(store.settings.copyWith(developerLogEnabled: value));
            },
          ),
          IconButton(
            tooltip: '清空',
            onPressed: logger.records.isEmpty ? null : () => _confirmClear(context, store, logger),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 4, 15, 0),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: '搜索 URL（包含即匹配）',
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
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                for (final item in HttpLogFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: '${_filterLabel(item)} (${logger.count(item, search: _search)})',
                      selected: _filter == item,
                      onTap: () => setState(() => _filter = item),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        logger.records.isEmpty
                            ? (logger.enabled ? '还没有请求。去同步账号或连接站点后就会出现。' : '还没开始记录。打开右上角开关后再操作即可看到请求。')
                            : '没有符合条件的记录',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ThemeDefine.kColorText, height: 1.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: YuconCard(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => HttpRequestLogDetailScreen(logId: log.id)),
                            );
                          },
                          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                          child: Row(
                            children: [
                              _MethodBadge(method: log.method),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  log.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusBadge(log: log, dark: dark),
                              const SizedBox(width: 8),
                              Text(
                                log.durationLabel,
                                style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                              ),
                              const Icon(Icons.chevron_right, size: 18, color: ThemeDefine.kColorText),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    );
  }

  String _filterLabel(HttpLogFilter filter) {
    switch (filter) {
      case HttpLogFilter.all:
        return '全部';
      case HttpLogFilter.ok:
        return '2xx';
      case HttpLogFilter.client:
        return '4xx';
      case HttpLogFilter.server:
        return '5xx';
      case HttpLogFilter.error:
        return '错误';
    }
  }

  Future<void> _confirmClear(BuildContext context, VaultStore store, HttpRequestLogger logger) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空请求记录'),
          content: const Text('将删除内存里的全部请求记录，无法恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
          ],
        );
      },
    );
    if (ok == true) {
      logger.clear();
      store.notify('记录已清空', FeedbackType.text);
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ThemeDefine.kColorSoft : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? const Color(0x29FA2C19) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? ThemeDefine.kColorPrimary : ThemeDefine.kColorText,
          ),
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      'GET' => const Color(0xFF21A366),
      'POST' => const Color(0xFFED8A19),
      'PUT' || 'PATCH' => const Color(0xFF3178DF),
      'DELETE' => const Color(0xFFBE2630),
      _ => ThemeDefine.kColorText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.log, required this.dark});

  final HttpRequestLog log;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (log.isTransportError) {
      color = const Color(0xFFBE2630);
      label = '错误';
    } else if (log.is2xx) {
      color = const Color(0xFF21A366);
      label = '${log.status}';
    } else if (log.is4xx) {
      color = const Color(0xFFED8A19);
      label = '${log.status}';
    } else {
      color = const Color(0xFFBE2630);
      label = '${log.status}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
