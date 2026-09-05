import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/storage/vault_backup.dart';
import 'package:vault/app/storage/vault_backup_crypto.dart';
import 'package:vault/app/storage/vault_backup_files.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/themes.dart';
import 'package:vault/screens/widgets/account_card.dart';
import 'package:vault/screens/widgets/ui.dart';

class DataBackupScreen extends StatefulWidget {
  const DataBackupScreen({super.key});

  @override
  State<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends State<DataBackupScreen> {
  List<BackupFileInfo> _backups = [];
  bool _loadingList = true;
  bool _actionsReady = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() => _actionsReady = true);
        }
      });
    });
  }

  Future<void> _reload() async {
    setState(() => _loadingList = true);
    try {
      final items = await VaultBackupFiles.listLocal();
      if (!mounted) {
        return;
      }
      setState(() {
        _backups = items;
        _loadingList = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingList = false);
      context.read<VaultStore>().notify('读不了本机备份列表', FeedbackType.error);
    }
  }

  Future<void> _run(String token, Future<void> Function() action) async {
    if (_busy != null || !_actionsReady) {
      return;
    }
    setState(() => _busy = token);
    try {
      await action();
    } on _BackupCancelled {
      return;
    } on VaultBackupException catch (error) {
      if (mounted) {
        context.read<VaultStore>().notify(error.message, FeedbackType.error);
      }
    } catch (error) {
      if (mounted) {
        context.read<VaultStore>().notify(
          userFacingBackupError(error),
          FeedbackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
    }
  }

  Future<void> _backup() async {
    final password = await _askSetPassword();
    if (password == null) {
      return;
    }
    await _run('backup', () async {
      final store = context.read<VaultStore>();
      final file = await VaultBackupFiles.saveLocal(
        store.captureSnapshot(),
        password,
      );
      await _reload();
      if (!mounted) {
        return;
      }
      store.notify('已加密备份到本机 · ${_fileName(file.path)}');
    });
  }

  Future<void> _export() async {
    final password = await _askSetPassword();
    if (password == null) {
      return;
    }
    await _run('export', () async {
      final store = context.read<VaultStore>();
      final snapshot = store.captureSnapshot();
      final file = await VaultBackupFiles.writeTemp(snapshot, password);
      final box = mounted ? context.findRenderObject() as RenderBox? : null;
      final result = await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/json',
            name: _fileName(file.path),
          ),
        ],
        subject: '钥仓备份',
        text: snapshot.summaryLabel,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
      if (!mounted || result.status == ShareResultStatus.dismissed) {
        return;
      }
      store.notify('加密备份已送出');
    });
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'yuconbak'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    await _run('import', () async {
      final file = picked.files.first;
      final VaultSnapshot snapshot;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        snapshot = await _openBytes(file.bytes!);
      } else if (file.path != null && file.path!.isNotEmpty) {
        snapshot = await _openFile(File(file.path!));
      } else {
        throw VaultBackupException('打不开这份文件');
      }
      if (!mounted) {
        return;
      }
      final mode = await _chooseImportMode(snapshot);
      if (mode == null || !mounted) {
        return;
      }
      await _apply(snapshot, mode);
    });
  }

  Future<void> _restore(BackupFileInfo info) async {
    if (!info.readable) {
      context.read<VaultStore>().notify('这份备份无法识别', FeedbackType.error);
      return;
    }
    final ok = await _confirm(
      title: '用这份备份覆盖当前数据？',
      body: '${info.name}\n${info.detailLabel}\n覆盖后，现在这台手机上的账号、登录状态和密码会被换成备份里的内容。',
      action: '覆盖并恢复',
      destructive: true,
    );
    if (ok != true) {
      return;
    }
    await _run('restore:${info.path}', () async {
      final snapshot = await _openFile(File(info.path));
      await _apply(snapshot, VaultBackupApplyMode.replace);
    });
  }

  Future<VaultSnapshot> _openFile(File file) async {
    final raw = await file.readAsString();
    return _openRaw(raw);
  }

  Future<VaultSnapshot> _openBytes(List<int> bytes) {
    return _openRaw(utf8.decode(bytes));
  }

  Future<VaultSnapshot> _openRaw(String raw) async {
    final peek = peekBackup(raw);
    String? password;
    if (peek.encrypted) {
      password = await _askUnlockPassword();
      if (password == null) {
        throw _BackupCancelled();
      }
    }
    return VaultBackupCrypto.open(raw, password: password);
  }

  Future<void> _delete(BackupFileInfo info) async {
    final ok = await _confirm(
      title: '删除这份本机备份？',
      body: info.name,
      action: '删除',
      destructive: true,
    );
    if (ok != true) {
      return;
    }
    await VaultBackupFiles.delete(info.path);
    await _reload();
    if (mounted) {
      context.read<VaultStore>().notify('已删除本机备份');
    }
  }

  Future<void> _apply(VaultSnapshot snapshot, VaultBackupApplyMode mode) async {
    final store = context.read<VaultStore>();
    final applied = await store.applySnapshot(snapshot, mode: mode);
    if (!mounted) {
      return;
    }
    context.read<Themes>().setTheme(
      store.settings.darkMode ? ThemeDefine.kThemeDark : ThemeDefine.kThemeLight,
    );
    store.notify(
      mode == VaultBackupApplyMode.replace
          ? '已覆盖为备份数据 · ${applied.summaryLabel}'
          : '已合并备份数据 · 现在共 ${store.accounts.length} 个账号',
    );
  }

  Future<VaultBackupApplyMode?> _chooseImportMode(VaultSnapshot snapshot) {
    return showModalBottomSheet<VaultBackupApplyMode>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('导入这份备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                snapshot.summaryLabel,
                style: const TextStyle(color: ThemeDefine.kColorText, height: 1.45),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: '合并到现有数据',
                onPressed: () => Navigator.pop(context, VaultBackupApplyMode.merge),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: '覆盖当前数据',
                outlined: true,
                onPressed: () => Navigator.pop(context, VaultBackupApplyMode.replace),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askSetPassword() {
    return _askPassword(
      title: '设置备份密码',
          body: '文件会加密保存，含登录密码、登录状态和密钥。密码至少 $minBackupPasswordLength 位，导入时要输入同一组密码。',
      confirm: true,
    );
  }

  Future<String?> _askUnlockPassword() {
    return _askPassword(
      title: '输入备份密码',
      body: '这份备份已加密，输入当时设置的密码才能打开。',
      confirm: false,
    );
  }

  Future<String?> _askPassword({
    required String title,
    required String body,
    required bool confirm,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _BackupPasswordSheet(
          title: title,
          body: body,
          confirm: confirm,
        );
      },
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(height: 1.5)),
              const SizedBox(height: 16),
              SizedBox(
                height: 41,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: destructive
                        ? const Color(0xFFE5484D)
                        : ThemeDefine.kColorPrimary,
                  ),
                  child: Text(action),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? ThemeDefine.kColorDarkText : ThemeDefine.kColorText;
    final snapshot = VaultSnapshot(
      exportedAt: DateTime.now().toUtc(),
      accounts: store.accounts,
      sessions: store.sessions,
      apiKeys: store.apiKeys,
      revealedKeys: store.revealedKeys,
      accountPasswords: store.accountPasswords,
      checkinLogs: store.checkinLogs,
      usageLogs: store.usageLogs,
      settings: store.settings,
    );

    return SecureScope(
      child: Scaffold(
      appBar: const YuconAppBar(title: '数据备份', subtitle: '导入、备份和导出本机数据'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
        children: [
          YuconCard(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.summaryLabel,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '含账号、登录密码、登录状态、密钥和偏好设置。备份时会加密，导入时再解密。',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
          YuconCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _ActionCell(
                  icon: Icons.archive_outlined,
                  label: '备份',
                  caption: '存到本机',
                  busy: _busy == 'backup',
                  onTap: _backup,
                ),
                _ActionCell(
                  icon: Icons.ios_share_outlined,
                  label: '导出',
                  caption: '分享文件',
                  busy: _busy == 'export',
                  onTap: _export,
                ),
                _ActionCell(
                  icon: Icons.file_download_outlined,
                  label: '导入',
                  caption: '从文件恢复',
                  busy: _busy == 'import',
                  onTap: _import,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
            child: Text(
              '备份文件已加密，但仍请只放到你自己能控制的地方。',
              style: TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
          ),
          const SectionTitle(text: '本机备份'),
          if (_loadingList)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_backups.isEmpty)
            YuconCard(
              padding: const EdgeInsets.fromLTRB(15, 22, 15, 22),
              child: Text(
                '还没有本机备份。点上面的「备份」会加密存一份，换机前建议再导出一份。',
                style: TextStyle(color: muted, fontSize: 13, height: 1.5),
              ),
            )
          else
            GroupCard(
              children: [
                for (final item in _backups)
                  _BackupTile(
                    info: item,
                    busy: _busy == 'restore:${item.path}',
                    onRestore: () => _restore(item),
                    onDelete: () => _delete(item),
                  ),
              ],
            ),
        ],
      ),
      ),
    );
  }

  String _fileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}

class _ActionCell extends StatelessWidget {
  const _ActionCell({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    required this.busy,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              SquareIcon(
                size: 36,
                radius: 11,
                color: ThemeDefine.kColorPrimary,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                caption,
                style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.info,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final BackupFileInfo info;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final time = info.exportedAt ?? info.modifiedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          SquareIcon(
            size: 28,
            radius: 8,
            color: const Color(0xFF25272B),
            child: Icon(
              info.readable ? Icons.folder_outlined : Icons.error_outline,
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(time.toIso8601String()),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  info.detailLabel,
                  style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: info.readable && !busy ? onRestore : null,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('恢复'),
          ),
          IconButton(
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: ThemeDefine.kColorText,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

String userFacingBackupError(Object error) {
  final text = error.toString();
  if (text.contains('MissingPluginException')) {
    return '当前环境还不能选文件';
  }
  if (text.contains('Permission')) {
    return '没有文件访问权限';
  }
  return '操作失败，请再试一次';
}

class _BackupPasswordSheet extends StatefulWidget {
  const _BackupPasswordSheet({
    required this.title,
    required this.body,
    required this.confirm,
  });

  final String title;
  final String body;
  final bool confirm;

  @override
  State<_BackupPasswordSheet> createState() => _BackupPasswordSheetState();
}

class _BackupPasswordSheetState extends State<_BackupPasswordSheet> {
  late final TextEditingController _first;
  late final TextEditingController _second;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _first = TextEditingController();
    _second = TextEditingController();
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _first.text;
    final store = context.read<VaultStore>();
    if (password.length < minBackupPasswordLength) {
      store.notify('备份密码至少 $minBackupPasswordLength 位', FeedbackType.error);
      return;
    }
    if (widget.confirm && password != _second.text) {
      store.notify('两次密码不一致', FeedbackType.error);
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(widget.body, style: const TextStyle(height: 1.45, color: ThemeDefine.kColorText)),
          const SizedBox(height: 16),
          TextField(
            controller: _first,
            obscureText: !_showPassword,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '备份密码（至少 $minBackupPasswordLength 位）',
              suffixIcon: secretVisibilityButton(
                visible: _showPassword,
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _second,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: '再输入一次',
                suffixIcon: secretVisibilityButton(
                  visible: _showPassword,
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: widget.confirm ? '加密并继续' : '解锁备份',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _BackupCancelled implements Exception {}
