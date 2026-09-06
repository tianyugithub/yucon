import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/captcha_solver.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/storage/vault.dart';

void main() {
  test('captcha solver settings round-trips and detects configured state', () {
    final settings = CaptchaSolverSettings()
      ..enabled = true
      ..clientKey = 'sk-test';
    expect(settings.configured, isTrue);

    final restored = CaptchaSolverSettings.fromJson(settings.toJson());
    expect(restored.enabled, isTrue);
    expect(restored.type, CaptchaSolverType.yesCaptcha);
    expect(restored.clientKey, 'sk-test');

    expect(CaptchaSolverSettings.fromJson(null).configured, isFalse);
    expect(
      CaptchaSolverSettings.fromJson({'enabled': true}).configured,
      isFalse,
    );
    expect(
      CaptchaSolverSettings.fromJson({'type': 'unknown'}).type,
      CaptchaSolverType.yesCaptcha,
    );
  });

  test(
    'keeps a client key per provider and configured follows the selected type',
    () {
      final settings = CaptchaSolverSettings(
        enabled: true,
        type: CaptchaSolverType.yesCaptcha,
        clientKeys: {
          CaptchaSolverType.yesCaptcha: 'yes-key',
          CaptchaSolverType.capSolver: 'cap-key',
        },
      );
      expect(settings.clientKey, 'yes-key');
      expect(settings.configured, isTrue);
      expect(settings.keyFor(CaptchaSolverType.capSolver), 'cap-key');
      expect(settings.keyFor(CaptchaSolverType.twoCaptcha), isEmpty);

      settings.type = CaptchaSolverType.twoCaptcha;
      expect(settings.clientKey, isEmpty);
      expect(settings.configured, isFalse);

      settings.type = CaptchaSolverType.capSolver;
      expect(settings.clientKey, 'cap-key');
      expect(settings.configured, isTrue);

      final restored = CaptchaSolverSettings.fromJson(settings.toJson());
      expect(restored.type, CaptchaSolverType.capSolver);
      expect(restored.clientKey, 'cap-key');
      expect(restored.keyFor(CaptchaSolverType.yesCaptcha), 'yes-key');
      expect(restored.keyFor(CaptchaSolverType.capSolver), 'cap-key');
      expect(restored.keyFor(CaptchaSolverType.twoCaptcha), isEmpty);
      expect(restored.toJson()['clientKeys'], {
        'yesCaptcha': 'yes-key',
        'capSolver': 'cap-key',
      });

      final copy = settings.copy();
      copy.setKey(CaptchaSolverType.yesCaptcha, 'changed');
      expect(settings.keyFor(CaptchaSolverType.yesCaptcha), 'yes-key');
    },
  );

  test('legacy clientKey json migrates into the selected provider slot', () {
    final restored = CaptchaSolverSettings.fromJson({
      'enabled': true,
      'type': 'twoCaptcha',
      'clientKey': 'legacy-key',
    });
    expect(restored.type, CaptchaSolverType.twoCaptcha);
    expect(restored.clientKey, 'legacy-key');
    expect(restored.keyFor(CaptchaSolverType.twoCaptcha), 'legacy-key');
    expect(restored.keyFor(CaptchaSolverType.yesCaptcha), isEmpty);
    expect(restored.toJson()['clientKeys'], {'twoCaptcha': 'legacy-key'});
  });

  test('stores each solver provider through json round-trip', () {
    for (final type in CaptchaSolverType.values) {
      final restored = CaptchaSolverSettings.fromJson({
        'enabled': true,
        'type': type.name,
        'clientKey': 'key-${type.name}',
      });
      expect(restored.type, type);
      expect(restored.clientKey, 'key-${type.name}');
    }
  });

  test('proxy secrets keep a key per captcha provider', () {
    final secrets = ProxySecrets(
      captcha: 'active',
      captchaKeys: {'yesCaptcha': 'yes', 'capSolver': 'cap'},
    );
    final restored = ProxySecrets.fromJson(secrets.toJson());
    expect(restored.captcha, 'active');
    expect(restored.captchaKeys['yesCaptcha'], 'yes');
    expect(restored.captchaKeys['capSolver'], 'cap');
    expect(restored.captchaKeys.containsKey('twoCaptcha'), isFalse);
  });

  test('prototype settings keep captcha solver through json round-trip', () {
    final settings = PrototypeSettings();
    settings.captchaSolver
      ..enabled = true
      ..type = CaptchaSolverType.capSolver
      ..clientKey = 'key-123'
      ..setKey(CaptchaSolverType.yesCaptcha, 'yes-key');
    final restored = PrototypeSettings.fromJson(settings.toJson());
    expect(restored.captchaSolver.enabled, isTrue);
    expect(restored.captchaSolver.type, CaptchaSolverType.capSolver);
    expect(restored.captchaSolver.clientKey, 'key-123');
    expect(
      restored.captchaSolver.keyFor(CaptchaSolverType.yesCaptcha),
      'yes-key',
    );
    expect(PrototypeSettings.fromJson({}).captchaSolver.enabled, isFalse);
  });

  test('exposes provider api hosts, task types and copy', () {
    expect(
      captchaSolverApiBase(CaptchaSolverType.yesCaptcha),
      'https://api.yescaptcha.com',
    );
    expect(
      captchaSolverApiBase(CaptchaSolverType.twoCaptcha),
      'https://api.2captcha.com',
    );
    expect(
      captchaSolverApiBase(CaptchaSolverType.capMonsterCloud),
      'https://api.capmonster.cloud',
    );
    expect(
      captchaSolverApiBase(CaptchaSolverType.capSolver),
      'https://api.capsolver.com',
    );

    expect(
      captchaSolverTurnstileTaskType(CaptchaSolverType.yesCaptcha),
      'TurnstileTaskProxyless',
    );
    expect(
      captchaSolverTurnstileTaskType(CaptchaSolverType.twoCaptcha),
      'TurnstileTaskProxyless',
    );
    expect(
      captchaSolverTurnstileTaskType(CaptchaSolverType.capMonsterCloud),
      'TurnstileTask',
    );
    expect(
      captchaSolverTurnstileTaskType(CaptchaSolverType.capSolver),
      'AntiTurnstileTaskProxyLess',
    );

    expect(captchaSolverTypeLabel(CaptchaSolverType.twoCaptcha), '2Captcha');
    expect(
      captchaSolverTypeLabel(CaptchaSolverType.capMonsterCloud),
      'CapMonster Cloud',
    );
    expect(captchaSolverKeyHint(CaptchaSolverType.capSolver), contains('CAP-'));
    expect(
      captchaSolverPollInterval(CaptchaSolverType.twoCaptcha).inSeconds,
      5,
    );
    expect(captchaSolverPollInterval(CaptchaSolverType.capSolver).inSeconds, 2);
    expect(captchaSolverHomeHost(CaptchaSolverType.twoCaptcha), '2captcha.com');
    expect(
      captchaSolverHomeHost(CaptchaSolverType.capMonsterCloud),
      'capmonster.cloud',
    );
    for (final type in CaptchaSolverType.values) {
      expect(captchaSolverIconAsset(type), startsWith('assets/solvers/'));
      expect(captchaSolverIconAsset(type), endsWith('.png'));
    }
  });

  test('ships official solver brand icon files', () {
    for (final type in CaptchaSolverType.values) {
      expect(
        File(captchaSolverIconAsset(type)).existsSync(),
        isTrue,
        reason: captchaSolverIconAsset(type),
      );
    }
  });

  test('sends numeric task ids as ints and keeps uuid task ids as strings', () {
    expect(captchaSolverTaskIdPayload(83776035437), 83776035437);
    expect(captchaSolverTaskIdPayload('83776035437'), 83776035437);
    expect(
      captchaSolverTaskIdPayload('abd4a863-adaf-4edd-979b-063de12216e6'),
      'abd4a863-adaf-4edd-979b-063de12216e6',
    );
  });

  test('formats yesCaptcha points and usd balances separately', () {
    expect(
      formatCaptchaSolverBalance(CaptchaSolverType.yesCaptcha, 120),
      '120 点',
    );
    expect(
      formatCaptchaSolverBalance(CaptchaSolverType.twoCaptcha, 4.87536),
      '\$4.88',
    );
    expect(
      formatCaptchaSolverBalance(CaptchaSolverType.capMonsterCloud, 0),
      '\$0.00',
    );
    expect(
      formatCaptchaSolverBalance(CaptchaSolverType.capSolver, 6),
      '\$6.00',
    );
  });

  test('builds the turnstile task body expected by each provider', () {
    expect(
      captchaSolverTurnstileTask(
        type: CaptchaSolverType.capSolver,
        websiteUrl: 'https://example.com/login',
        websiteKey: '0x4AAAAAA',
      ),
      {
        'type': 'AntiTurnstileTaskProxyLess',
        'websiteURL': 'https://example.com/login',
        'websiteKey': '0x4AAAAAA',
      },
    );
    expect(
      captchaSolverTurnstileTask(
        type: CaptchaSolverType.capMonsterCloud,
        websiteUrl: 'https://example.com/login',
        websiteKey: '0x4AAAAAA',
      )['type'],
      'TurnstileTask',
    );
  });

  test('maps solver errors to friendly messages', () {
    expect(
      describeCaptchaSolverError({
        'errorId': 1,
        'errorCode': 'ERROR_KEY_DOES_NOT_EXIST',
        'errorDescription': 'wrong key',
      }),
      contains('密钥无效'),
    );
    expect(
      describeCaptchaSolverError({
        'errorId': 1,
        'errorCode': 'ERROR_ZERO_BALANCE',
        'errorDescription': 'Account has zero balance',
      }),
      contains('余额不足'),
    );
    expect(
      describeCaptchaSolverError({
        'errorId': 1,
        'errorCode': 'ERROR_IP_BLOCKED_1MIN',
        'errorDescription': 'ip blocked',
      }),
      contains('IP'),
    );
    expect(
      describeCaptchaSolverError({
        'errorId': 1,
        'errorCode': 'ERROR_TYPE_NOT_SUPPORTED',
        'errorDescription': 'unsupported captcha type, please check if the type is correct: TurnstileTaskProxyless',
      }),
      contains('不支持'),
    );
    expect(
      describeCaptchaSolverError({
        'errorId': 1,
        'errorCode': 'ERROR_CUSTOM',
        'errorDescription': 'site not supported',
      }),
      contains('site not supported'),
    );
    expect(
      describeCaptchaSolverError({'errorId': 1, 'errorCode': 'ERROR_CUSTOM'}),
      '打码平台调用失败：ERROR_CUSTOM',
    );
  });
}
