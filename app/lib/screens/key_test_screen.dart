import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/key_probe.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

enum _ModelFilter { all, ok, fail, pending }

class KeyTestScreen extends StatefulWidget {
  const KeyTestScreen({super.key, required this.keyId});

  final String keyId;

  @override
  State<KeyTestScreen> createState() => _KeyTestScreenState();
}

class _KeyTestScreenState extends State<KeyTestScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _running = false;
  int _runId = 0;
  String? _error;
  String _secret = '';
  String _baseUrl = '';
  List<String> _urls = [];
  List<String> _models = [];
  final Map<String, ModelProbeResult> _results = {};
  String? _current;
  _ModelFilter _filter = _ModelFilter.all;
  String _query = '';
  ModelProbeKind? _protocol;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _runId++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _prepare({String? baseUrl}) async {
    setState(() {
      _loading = true;
      _error = null;
      _running = false;
      _runId++;
      _current = null;
    });
    final store = context.read<VaultStore>();
    try {
      final prep = await store.prepareKeyTest(widget.keyId, baseUrl: baseUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        _secret = prep.secret;
        _urls = prep.urls;
        _baseUrl = prep.baseUrl;
        _models = prep.models;
        _results.clear();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = userFacingError(error, '打不开测试');
      });
    }
  }

  List<String> get _visible {
    final keyword = _query.trim().toLowerCase();
    return _models.where((model) {
      if (keyword.isNotEmpty && !model.toLowerCase().contains(keyword)) {
        return false;
      }
      final result = _results[model];
      switch (_filter) {
        case _ModelFilter.all:
          return true;
        case _ModelFilter.ok:
          return result?.status == ModelProbeStatus.ok;
        case _ModelFilter.fail:
          return result?.status == ModelProbeStatus.fail;
        case _ModelFilter.pending:
          return result == null ||
              result.status == ModelProbeStatus.pending ||
              result.status == ModelProbeStatus.skipped;
      }
    }).toList();
  }

  Future<void> _runAll() async {
    if (_running || _secret.isEmpty) {
      return;
    }
    final id = ++_runId;
    setState(() => _running = true);
    for (final model in _models) {
      if (!mounted || id != _runId) {
        return;
      }
      final existing = _results[model];
      if (existing != null &&
          (existing.status == ModelProbeStatus.ok || existing.status == ModelProbeStatus.fail)) {
        continue;
      }
      await _testOne(model, runId: id, allowExpensive: false);
    }
    if (mounted && id == _runId) {
      setState(() {
        _running = false;
        _current = null;
      });
    }
  }

  void _stop() {
    setState(() {
      _runId++;
      _running = false;
      _current = null;
    });
  }

  ModelProbeKind _displayKind(String model) {
    final auto = classifyModelProbe(model);
    if (_protocol != null && isTextProbeKind(auto)) {
      return _protocol!;
    }
    return auto;
  }

  Future<void> _testOne(
    String model, {
    int? runId,
    required bool allowExpensive,
  }) async {
    final store = context.read<VaultStore>();
    final apiKey = store.apiKeyById(widget.keyId);
    if (apiKey == null) {
      return;
    }
    setState(() {
      _current = model;
      _results[model] = ModelProbeResult(
        model: model,
        kind: _displayKind(model),
        status: ModelProbeStatus.running,
        message: '测试中',
      );
    });
    final result = await store.testKeyModel(
      accountId: apiKey.accountId,
      secret: _secret,
      baseUrl: _baseUrl,
      model: model,
      allowExpensive: allowExpensive,
      protocol: _protocol,
    );
    if (!mounted || (runId != null && runId != _runId)) {
      return;
    }
    setState(() => _results[model] = result);
  }

  Future<void> _tapModel(String model) async {
    if (_running) {
      return;
    }
    final kind = classifyModelProbe(model);
    if (kind == ModelProbeKind.video || kind == ModelProbeKind.image) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  kind == ModelProbeKind.video ? '测试这个视频模型？' : '测试这个图像模型？',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text('会向站点发一次真实调用，可能消耗较多额度。'),
                const SizedBox(height: 16),
                PrimaryButton(label: '开始测试', onPressed: () => Navigator.pop(context, true)),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: '取消',
                  outlined: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          );
        },
      );
      if (ok != true || !mounted) {
        return;
      }
    }
    setState(() => _running = true);
    final id = ++_runId;
    await _testOne(model, runId: id, allowExpensive: true);
    if (mounted && id == _runId) {
      setState(() {
        _running = false;
        _current = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final apiKey = store.apiKeyById(widget.keyId);
    final account = apiKey == null ? null : store.accountById(apiKey.accountId);
    final visible = _visible;
    final okCount = _results.values.where((item) => item.status == ModelProbeStatus.ok).length;
    final failCount = _results.values.where((item) => item.status == ModelProbeStatus.fail).length;
    final done = okCount + failCount;

    return SecureScope(
      child: Scaffold(
        appBar: YuconAppBar(
          title: '测试模型',
          subtitle: apiKey == null
              ? '密钥'
              : (account == null
                    ? apiKey.name
                    : '${apiKey.name} · ${store.displayAccountName(account)}'),
          actions: [
            if (!_loading && !_running && _models.isNotEmpty)
              HeaderTextAction(
                label: '清空结果',
                onPressed: () => setState(() => _results.clear()),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
                children: [
                  const TipBanner(
                    text: '对话、Claude、Codex 都会发同一句测试话，并显示模型的回答。默认按模型名自动选探测点，失败会自动换端点重试；在「探测点」里手动指定后，只用选中的端点直测。Claude 会伪装成 Claude Code 客户端、Codex 会伪装成 Codex CLI 客户端，兼容只认官方客户端的站点。图像模型会真正出图并显示在结果里。全部测试时会跳过图像和视频，点某一行可单独测。',
                  ),
                  const YuconCard(
                    padding: EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('测试内容', style: TextStyle(fontSize: 12, color: ThemeDefine.kColorText)),
                        SizedBox(height: 4),
                        Text(
                          '问：$kModelProbePrompt',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '图：$kModelProbeImagePrompt',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TipBanner(text: _error!),
                    ),
                  if (_urls.length > 1) ...[
                    const SectionTitle(text: 'API 地址'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final url in _urls)
                          GestureDetector(
                            onTap: _running ? null : () => _prepare(baseUrl: url),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: url == _baseUrl
                                    ? ThemeDefine.kColorSoft
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: url == _baseUrl
                                      ? const Color(0x29FA2C19)
                                      : ThemeDefine.kColorLine,
                                ),
                              ),
                              child: Text(
                                url,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: url == _baseUrl
                                      ? ThemeDefine.kColorPrimary
                                      : ThemeDefine.kColorText,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ] else if (_baseUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _baseUrl,
                        style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const SectionTitle(text: '探测点'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _protocolChip(null, '自动'),
                        _protocolChip(ModelProbeKind.chat, '对话'),
                        _protocolChip(ModelProbeKind.claude, 'Claude'),
                        _protocolChip(ModelProbeKind.codex, 'Codex'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: _running ? '测试中' : '测试全部',
                          busy: _running && _current != null,
                          onPressed: _running || _models.isEmpty ? null : _runAll,
                        ),
                      ),
                      if (_running) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: PrimaryButton(
                            label: '停止',
                            outlined: true,
                            onPressed: _stop,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(1, 12, 1, 8),
                    child: Text(
                      _models.isEmpty
                          ? '这把密钥暂时没有可测的模型'
                          : '共 ${_models.length} 个模型 · 已测 $done · 可用 $okCount · 失败 $failCount',
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                  ),
                  if (_models.length > 8)
                    YuconCard(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                      child: TextField(
                        controller: _search,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: inCardInput(hint: '筛选模型名称'),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(_ModelFilter.all, '全部'),
                        _filterChip(_ModelFilter.pending, '未测'),
                        _filterChip(_ModelFilter.ok, '可用'),
                        _filterChip(_ModelFilter.fail, '失败'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text('没有符合筛选的模型', style: TextStyle(color: ThemeDefine.kColorText)),
                      ),
                    )
                  else
                    for (final model in visible)
                      _modelTile(model),
                ],
              ),
      ),
    );
  }

  Widget _protocolChip(ModelProbeKind? value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _pill(
        label: label,
        selected: _protocol == value,
        onTap: _running
            ? null
            : () => setState(() {
                  _protocol = value;
                  _results.clear();
                }),
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ThemeDefine.kColorSoft : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? const Color(0x29FA2C19) : Colors.transparent,
          ),
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

  Widget _filterChip(_ModelFilter value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: _pill(
        label: label,
        selected: _filter == value,
        onTap: () => setState(() => _filter = value),
      ),
    );
  }

  Widget _modelTile(String model) {
    final result = _results[model];
    final kind = result?.kind ?? _displayKind(model);
    final status = result?.status ?? ModelProbeStatus.pending;
    final color = switch (status) {
      ModelProbeStatus.ok => ThemeDefine.kColorGreenBright,
      ModelProbeStatus.fail => const Color(0xFFBE2630),
      ModelProbeStatus.running => ThemeDefine.kColorPrimary,
      ModelProbeStatus.skipped => ThemeDefine.kColorWarning,
      ModelProbeStatus.pending => ThemeDefine.kColorText,
    };
    final label = switch (status) {
      ModelProbeStatus.ok => result?.message ?? '可用',
      ModelProbeStatus.fail => result?.message ?? '失败',
      ModelProbeStatus.running => '测试中',
      ModelProbeStatus.skipped => result?.message ?? '已跳过',
      ModelProbeStatus.pending => '未测 · ${modelProbeKindLabel(kind)}',
    };
    final reply = result?.reply?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final showReply = status == ModelProbeStatus.ok && reply != null && reply.isNotEmpty;
    final imageBytes = result?.imageBytes;

    return YuconCard(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _running ? null : () => _tapModel(model),
              child: Row(
                children: [
                  ModelBrandIcon(model: model, size: ModelBrandIconSize.md),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color, fontSize: 12, height: 1.35),
                        ),
                        if (showReply) ...[
                          const SizedBox(height: 3),
                          Text(
                            '答：$reply',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (status == ModelProbeStatus.running)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (imageBytes != null && imageBytes.isNotEmpty) ...[
            const SizedBox(width: 8),
            _imageThumb(imageBytes),
          ]
          else
            Text(
              modelProbeKindLabel(kind),
              style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 11, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _imageThumb(Uint8List bytes) {
    return GestureDetector(
      onTap: () => _previewImage(bytes),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 72,
            height: 72,
            child: Icon(Icons.broken_image_outlined, color: ThemeDefine.kColorText),
          ),
        ),
      ),
    );
  }

  void _previewImage(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('图像无法显示', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
