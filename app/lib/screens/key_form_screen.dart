import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/api_address_copy.dart';
import 'package:vault/screens/widgets/model_brand_icon.dart';
import 'package:vault/screens/widgets/tab_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class KeyFormScreen extends StatefulWidget {
  const KeyFormScreen({super.key, this.keyId, this.accountId});

  final String? keyId;
  final String? accountId;

  @override
  State<KeyFormScreen> createState() => _KeyFormScreenState();
}

class _KeyFormScreenState extends State<KeyFormScreen> {
  late ApiKeyDraft _form;
  late final TextEditingController _name;
  late final TextEditingController _quota;
  late final TextEditingController _ips;
  late final TextEditingController _modelQuery;
  bool _saving = false;
  ApiKey? _created;

  @override
  void initState() {
    super.initState();
    final store = context.read<VaultStore>();
    final existing = widget.keyId == null ? null : store.apiKeyById(widget.keyId!);
    _form = store.toApiKeyDraft(apiKey: existing, accountId: widget.accountId ?? existing?.accountId ?? '');
    _name = TextEditingController(text: _form.name);
    _quota = TextEditingController(text: _form.remainQuota);
    _ips = TextEditingController(text: _form.allowIpsText);
    _modelQuery = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _name.dispose();
    _quota.dispose();
    _ips.dispose();
    _modelQuery.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final store = context.read<VaultStore>();
    if (_form.accountId.isEmpty) {
      return;
    }
    try {
      await store.loadTokenGroups(_form.accountId);
      final account = store.accountById(_form.accountId);
      if (_form.id == null) {
        _form.group = store.defaultGroupForAccount(account);
      }
      final preset = account == null ? null : getPlatformPreset(account.platformType);
      if (preset?.supportsKeyModelLimits == true) {
        await store.loadGroupModels(_form.accountId, _form.group);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      store.notify(userFacingError(error, '无法读取分组，请稍后重试'), FeedbackType.warning);
    }
  }

  Future<void> _save() async {
    final store = context.read<VaultStore>();
    _form.name = _name.text;
    _form.remainQuota = _quota.text;
    _form.allowIpsText = _ips.text;
    if (_form.name.trim().isEmpty) {
      store.notify('请填写密钥名称', FeedbackType.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await store.saveApiKey(_form);
      if (_form.id != null) {
        store.notify('密钥已更新');
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      store.notify('密钥已创建');
      setState(() => _created = created);
    } catch (error) {
      store.notify(userFacingError(error, '保存失败'), FeedbackType.error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _toggleModel(String model, List<String> selectedModels) {
    final next = [...selectedModels];
    if (next.contains(model)) {
      next.remove(model);
    } else {
      next.add(model);
    }
    setState(() => _form.modelLimitsText = next.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final account = store.accountById(_form.accountId);
    final preset = account == null ? null : getPlatformPreset(account.platformType);
    final groups = store.groupsForAccount(account);
    final models = store.modelsForGroup(_form.accountId, _form.group);
    final selectedModels = _form.modelLimitsText
        .split(RegExp(r'[\n,，]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (_created != null) {
      return SecureScope(
        child: Scaffold(
        appBar: const YuconAppBar(title: '密钥已创建', subtitle: '请马上复制完整密钥'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
          children: [
            const TipBanner(text: '请马上复制完整密钥。离开后可能只会显示部分字符。'),
            YuconCard(
              padding: const EdgeInsets.all(14),
              child: SelectableText(_created!.key, style: const TextStyle(fontSize: 13, letterSpacing: 0.2)),
            ),
            PrimaryButton(
              label: '复制密钥',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _created!.key));
                store.notify('复制成功');
              },
            ),
            if (account != null) ApiAddressCopy(account: account, store: store),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
        ),
      );
    }

    final expired = account?.status == AccountStatus.expired;
    final blocked = account?.status == AccountStatus.blocked;
    final canSave = account != null && !expired && !blocked && !_saving;
    final saveLabel = _form.id == null ? '添加' : '保存';
    final fabLabel = _form.id == null ? '添加密钥' : '保存修改';
    final visibleModels = models
        .where((model) => model.toLowerCase().contains(_modelQuery.text.trim().toLowerCase()))
        .toList();
    final tip = expired
        ? '该账号登录已过期，无法创建或修改密钥。请先回到账号详情重新登录。'
        : blocked
        ? (account?.dnsPolluted == true
              ? '不是登录过期。当前网络的域名解析不正常，请到「我的」换代理后再同步。'
              : '不是登录过期。当前网络打不开这个网站，请到「我的」换代理后再同步。')
        : (preset?.supportsKeyModelLimits == true
              ? '分组和可用模型来自当前站点。创建后通常只会完整显示一次密钥，请及时复制。'
              : '这把密钥不单独限制模型，能用哪些模型由分组决定。创建后通常只会完整显示一次密钥，请及时复制。');

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(
        title: _form.id == null ? '添加密钥' : '编辑密钥',
        subtitle: account == null ? '请从账号页进入' : '${store.displayAccountName(account)} 的密钥',
        actions: [
          HeaderPill(
            label: _saving ? '保存中' : saveLabel,
            onPressed: canSave ? _save : null,
          ),
        ],
      ),
      floatingActionButton: _created != null
          ? null
          : FloatingActionButton.extended(
              onPressed: canSave ? _save : null,
              backgroundColor: ThemeDefine.kColorPrimary,
              foregroundColor: Colors.white,
              disabledElevation: 0,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(
                fabLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 96),
        children: [
          TipBanner(text: tip),
          YuconCard(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                const SquareIcon(
                  size: 33,
                  radius: 10,
                  color: Color(0xFFEDF4FF),
                  child: TabIcon(name: YuconTabIcon.keys, size: 16, color: Color(0xFF3178DF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.trim().isEmpty ? '未命名密钥' : _name.text.trim(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${account?.siteName ?? ''} · ${store.tokenGroupLabel(_form.accountId, _form.group)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle(text: '基本设置'),
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 4),
            child: Column(
              children: [
                LabeledField(
                  label: '密钥名称',
                  requiredMark: true,
                  child: TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    decoration: inCardInput(hint: '例如：生产环境、开发测试'),
                  ),
                ),
                LabeledField(
                  label: '分组',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: groups.any((group) => group.name == _form.group) ? _form.group : null,
                      hint: const Text('选择分组'),
                      items: [
                        for (final group in groups)
                          DropdownMenuItem(
                            value: group.name,
                            child: Text('${group.name} · ${group.ratioLabel}'),
                          ),
                      ],
                      onChanged: (value) async {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _form.group = value;
                          if (value != 'auto') {
                            _form.crossGroupRetry = false;
                          }
                        });
                        if (preset?.supportsKeyModelLimits == true) {
                          await store.loadGroupModels(_form.accountId, value);
                        }
                      },
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('无限额度', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  value: _form.unlimitedQuota,
                  onChanged: (value) => setState(() => _form.unlimitedQuota = value),
                ),
                if (!_form.unlimitedQuota)
                  LabeledField(
                    label: '剩余额度（美元）',
                    child: TextField(
                      controller: _quota,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: inCardInput(hint: '10.00'),
                    ),
                  ),
                LabeledField(
                  label: '允许使用的 IP',
                  last: true,
                  hint: '多个地址用逗号分开，留空表示不限制',
                  child: TextField(
                    controller: _ips,
                    decoration: inCardInput(hint: '不限制则留空'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('过期时间', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(_form.expiresAt.isEmpty ? '永不过期' : _form.expiresAt),
                  trailing: const Icon(Icons.event, color: ThemeDefine.kColorText),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked == null) {
                      return;
                    }
                    setState(() {
                      _form.expiresAt =
                          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    });
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _form.expiresAt = ''),
                    child: const Text('设为永不过期'),
                  ),
                ),
              ],
            ),
          ),
          if (preset?.supportsKeyModelLimits == true && models.isNotEmpty) ...[
            SectionTitle(
              text: selectedModels.isEmpty ? '模型限制' : '模型限制 · 已选 ${selectedModels.length}',
              action: selectedModels.length == models.length ? '清空' : '全选',
              onAction: () {
                setState(() {
                  _form.modelLimitsText = selectedModels.length == models.length
                      ? ''
                      : models.join(', ');
                });
              },
            ),
            YuconCard(
              padding: const EdgeInsets.fromLTRB(13, 4, 13, 4),
              child: Column(
                children: [
                  TextField(
                    controller: _modelQuery,
                    onChanged: (_) => setState(() {}),
                    decoration: inCardInput(hint: '搜索模型'),
                  ),
                  if (visibleModels.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('没有匹配的模型', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13)),
                    )
                  else
                    for (final model in visibleModels)
                      InkWell(
                        onTap: () => _toggleModel(model, selectedModels),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: ThemeDefine.kColorLine)),
                          ),
                          child: Row(
                            children: [
                              ModelBrandIcon(model: model),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selectedModels.contains(model)
                                        ? ThemeDefine.kColorPrimary
                                        : null,
                                  ),
                                ),
                              ),
                              Icon(
                                selectedModels.contains(model)
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 20,
                                color: selectedModels.contains(model)
                                    ? ThemeDefine.kColorPrimary
                                    : ThemeDefine.kColorText,
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
          if (preset?.supportsCrossGroupRetry == true && _form.group == 'auto')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('失败后自动换分组'),
              value: _form.crossGroupRetry,
              onChanged: (value) => setState(() => _form.crossGroupRetry = value),
            ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }
}
