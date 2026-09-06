import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/captcha_solver.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/captcha_solver_brand_icon.dart';
import 'package:vault/screens/widgets/ui.dart';

class CaptchaSolverScreen extends StatefulWidget {
  const CaptchaSolverScreen({super.key});

  @override
  State<CaptchaSolverScreen> createState() => _CaptchaSolverScreenState();
}

class _CaptchaSolverScreenState extends State<CaptchaSolverScreen> {
  late final VaultStore _store;
  late CaptchaSolverSettings _draft;
  late final Map<CaptchaSolverType, TextEditingController> _keyControllers;
  late final Map<CaptchaSolverType, FocusNode> _keyFocus;
  final _keyVisible = <CaptchaSolverType>{};
  final _balanceText = <CaptchaSolverType, String>{};
  final _balanceError = <CaptchaSolverType, String>{};
  CaptchaSolverType? _testingType;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _store = context.read<VaultStore>();
    _draft = _store.settings.captchaSolver.copy();
    _keyControllers = {
      for (final type in CaptchaSolverType.values)
        type: TextEditingController(text: _draft.clientKeys[type] ?? ''),
    };
    _keyFocus = {
      for (final type in CaptchaSolverType.values)
        type: FocusNode()
          ..addListener(() {
            if (!_keyFocus[type]!.hasFocus) {
              unawaited(_persist());
            }
            if (mounted) {
              setState(() {});
            }
          }),
    };
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _syncDraftKeys();
    unawaited(_store.saveCaptchaSolver(_draft));
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    for (final focus in _keyFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _syncDraftKeys() {
    for (final type in CaptchaSolverType.values) {
      _draft.setKey(type, _keyControllers[type]!.text.trim());
    }
  }

  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _syncDraftKeys();
    await _store.saveCaptchaSolver(_draft);
  }

  Future<void> _testBalance(CaptchaSolverType type) async {
    if (_testingType != null) {
      return;
    }
    _syncDraftKeys();
    final draft = _draft.copy()..type = type;
    if (draft.clientKey.isEmpty) {
      setState(() {
        _balanceError[type] = '请先填写 Key';
        _balanceText.remove(type);
      });
      return;
    }
    setState(() {
      _testingType = type;
      _balanceError.remove(type);
      _balanceText.remove(type);
    });
    try {
      final balance = await fetchCaptchaSolverBalance(draft);
      if (!mounted) {
        return;
      }
      setState(
        () => _balanceText[type] =
            '余额 ${formatCaptchaSolverBalance(type, balance)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _balanceError[type] = userFacingError(error, '查询失败'));
    } finally {
      if (mounted) {
        setState(() => _testingType = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      child: Scaffold(
        appBar: const YuconAppBar(title: '验证码服务', subtitle: '自动过人机验证'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
          children: [
            const TipBanner(
              text: '站点开了 Cloudflare Turnstile 时，自动登录和注册会用下方勾选的服务商过盾。每个服务商的 Key 分开保存。',
            ),
            GroupCard(
              children: [
                GroupTile(
                  title: '启用自动过盾',
                  subtitle: '关闭后，开启验证的站点无法自动登录或注册',
                  trailing: Switch(
                    value: _draft.enabled,
                    onChanged: (value) {
                      setState(() => _draft.enabled = value);
                      unawaited(_persist());
                      _store.notify(
                        value ? '已开启自动过盾' : '已关闭自动过盾',
                        FeedbackType.text,
                      );
                    },
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(1, 18, 1, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务商',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '点右侧选择过盾用的平台，每个平台单独保存 Key。',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeDefine.kColorText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            for (final type in CaptchaSolverType.values) _providerCard(type),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(CaptchaSolverType type) {
    final selected = _draft.type == type;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focus = _keyFocus[type]!;
    final hidden = !_keyVisible.contains(type);
    final testing = _testingType == type;
    final balance = _balanceText[type];
    final balanceError = _balanceError[type];
    final line = dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine;
    return YuconCard(
      borderColor: selected
          ? const Color(0x40FA2C19)
          : (dark ? ThemeDefine.kColorDarkLine : const Color(0x0A16191F)),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CaptchaSolverBrandIcon(type: type, size: 22, radius: 6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  captchaSolverTypeLabel(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _useButton(type, selected),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyControllers[type],
            focusNode: focus,
            obscureText: hidden && !focus.hasFocus,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: '密钥',
              hintText: 'ClientKey / API Key',
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: ThemeDefine.kColorPrimary),
              ),
              suffixIcon: secretVisibilityButton(
                visible: !hidden,
                onPressed: () => setState(() {
                  if (hidden) {
                    _keyVisible.add(type);
                  } else {
                    _keyVisible.remove(type);
                  }
                }),
              ),
            ),
            onChanged: (_) {
              setState(() => _balanceError.remove(type));
              _schedulePersist();
            },
          ),
          const SizedBox(height: 8),
          Text(
            captchaSolverKeyHint(type),
            style: const TextStyle(
              fontSize: 12,
              color: ThemeDefine.kColorText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: testing ? null : () => _testBalance(type),
                child: Text(
                  testing ? '查询中…' : '查询余额',
                  style: TextStyle(
                    color: testing
                        ? ThemeDefine.kColorText
                        : ThemeDefine.kColorPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (testing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (balanceError != null)
                Expanded(
                  child: Text(
                    balanceError,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFFC54638),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                )
              else if (balance != null)
                Expanded(
                  child: Text(
                    balance,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: ThemeDefine.kColorText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _useButton(CaptchaSolverType type, bool selected) {
    if (selected) {
      return const StatusChip(
        label: '使用中',
        color: ThemeDefine.kColorPrimary,
        background: ThemeDefine.kColorSoft,
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() => _draft.type = type);
        unawaited(_persist());
      },
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          '用于过盾',
          style: TextStyle(
            color: ThemeDefine.kColorPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
