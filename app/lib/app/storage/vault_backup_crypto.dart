import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:vault/app/storage/vault.dart';
import 'package:vault/app/storage/vault_backup.dart';

const vaultBackupKdf = 'pbkdf2-sha256';
const vaultBackupCipher = 'aes-256-gcm';
const vaultBackupKdfIterations = 150000;
const minBackupPasswordLength = 10;

final _aes = AesGcm.with256bits();

Future<List<int>> _deriveKeyBytes(Map<String, Object> request) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: request['iterations'] as int,
    bits: 256,
  );
  final key = await kdf.deriveKeyFromPassword(
    password: request['password'] as String,
    nonce: List<int>.from(request['salt'] as List),
  );
  return key.extractBytes();
}

class VaultBackupCrypto {
  static Future<List<int>> _deriveKey({
    required String password,
    required List<int> salt,
    required int iterations,
  }) {
    return Isolate.run(
      () => _deriveKeyBytes({
        'password': password,
        'salt': List<int>.from(salt),
        'iterations': iterations,
      }),
    );
  }

  static Future<String> seal(VaultSnapshot snapshot, String password) async {
    final secret = password;
    if (secret.length < minBackupPasswordLength) {
      throw VaultBackupException('备份密码至少 $minBackupPasswordLength 位');
    }
    final salt = _randomBytes(16);
    final nonce = _randomBytes(_aes.nonceLength);
    final keyBytes = await _deriveKey(
      password: secret,
      salt: salt,
      iterations: vaultBackupKdfIterations,
    );
    final key = SecretKey(keyBytes);
    final box = await _aes.encrypt(
      utf8.encode(snapshot.encode()),
      secretKey: key,
      nonce: nonce,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': vaultBackupFormat,
      'version': vaultBackupVersion,
      'encrypted': true,
      'kdf': vaultBackupKdf,
      'cipher': vaultBackupCipher,
      'iterations': vaultBackupKdfIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
      'exportedAt': snapshot.exportedAt.toUtc().toIso8601String(),
      'summary': {
        'accounts': snapshot.accounts.length,
        'keys': snapshot.apiKeys.length,
        'sessions': snapshot.sessionCount,
        'passwords': snapshot.accountPasswords.length,
        'identityLogins': snapshot.identityLogins.length,
        'identitySessions': snapshot.identitySessionCount,
      },
    });
  }

  static Future<VaultSnapshot> open(String raw, {String? password}) async {
    final peek = peekBackup(raw);
    if (!peek.encrypted) {
      return VaultSnapshot.decode(raw);
    }
    if (password == null || password.isEmpty) {
      throw VaultBackupException('这份备份已加密，需要密码');
    }
    final record = VaultStorage.asMap(jsonDecode(raw.trim()));
    final iterations =
        (record['iterations'] as num?)?.toInt() ?? vaultBackupKdfIterations;
    if (iterations < 10000 || iterations > 2000000) {
      throw VaultBackupException('备份文件已损坏，打不开');
    }
    final salt = _b64(record['salt']);
    final nonce = _b64(record['nonce']);
    final mac = _b64(record['mac']);
    final cipher = _b64(record['ciphertext']);
    final keyBytes = await _deriveKey(
      password: password,
      salt: salt,
      iterations: iterations,
    );
    final key = SecretKey(keyBytes);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return VaultSnapshot.decode(utf8.decode(clear));
    } on SecretBoxAuthenticationError {
      throw VaultBackupException('密码不对，解不开这份备份');
    } catch (error) {
      if (error is VaultBackupException) {
        rethrow;
      }
      throw VaultBackupException('密码不对，解不开这份备份');
    }
  }

  static Uint8List _b64(Object? value) {
    try {
      return Uint8List.fromList(base64Decode(value?.toString() ?? ''));
    } catch (_) {
      throw VaultBackupException('备份文件已损坏，打不开');
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
