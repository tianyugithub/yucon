import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:vault/app/storage/vault_backup.dart';
import 'package:vault/app/storage/vault_backup_crypto.dart';

const _maxLocalBackups = 20;

class VaultBackupFiles {
  static Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/yucon-backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _legacyDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/yucon-backups');
  }

  static Future<File> saveLocal(VaultSnapshot snapshot, String password) async {
    final dir = await directory();
    final file = File(
      '${dir.path}/${backupFileStem(snapshot.exportedAt)}.$vaultBackupExtension',
    );
    await file.writeAsString(await VaultBackupCrypto.seal(snapshot, password), flush: true);
    await _trimOld(dir, keep: file.path);
    return file;
  }

  static Future<File> writeTemp(VaultSnapshot snapshot, String password) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${backupFileStem(snapshot.exportedAt)}.$vaultBackupExtension',
    );
    await file.writeAsString(await VaultBackupCrypto.seal(snapshot, password), flush: true);
    return file;
  }

  static Future<List<BackupFileInfo>> listLocal() async {
    final dirs = <Directory>[await directory(), await _legacyDirectory()];
    final seen = <String>{};
    final items = <BackupFileInfo>[];
    for (final dir in dirs) {
      if (!await dir.exists()) {
        continue;
      }
      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.$vaultBackupExtension'))
          .cast<File>()
          .toList();
      for (final file in files) {
        if (!seen.add(file.path)) {
          continue;
        }
        items.add(await inspect(file));
      }
    }
    items.sort((left, right) {
      final leftTime = left.exportedAt ?? left.modifiedAt;
      final rightTime = right.exportedAt ?? right.modifiedAt;
      return rightTime.compareTo(leftTime);
    });
    return items;
  }

  static Future<BackupFileInfo> inspect(File file) async {
    final stat = await file.stat();
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    try {
      final peek = peekBackup(await file.readAsString());
      return BackupFileInfo(
        path: file.path,
        name: name,
        modifiedAt: stat.modified,
        exportedAt: peek.exportedAt,
        accountCount: peek.accountCount,
        keyCount: peek.keyCount,
        encrypted: peek.encrypted,
      );
    } catch (_) {
      return BackupFileInfo(
        path: file.path,
        name: name,
        modifiedAt: stat.modified,
        readable: false,
      );
    }
  }

  static Future<VaultSnapshot> readFile(File file, {String? password}) async {
    return VaultBackupCrypto.open(await file.readAsString(), password: password);
  }

  static Future<VaultSnapshot> readBytes(Uint8List bytes, {String? password}) {
    return VaultBackupCrypto.open(utf8.decode(bytes), password: password);
  }

  static Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> _trimOld(Directory dir, {required String keep}) async {
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.$vaultBackupExtension'))
        .cast<File>()
        .toList();
    files.sort((left, right) => right.statSync().modified.compareTo(left.statSync().modified));
    for (var i = _maxLocalBackups; i < files.length; i++) {
      if (files[i].path == keep) {
        continue;
      }
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }
}
