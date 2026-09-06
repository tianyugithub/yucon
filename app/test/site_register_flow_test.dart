import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/sub2api.dart';
import 'package:vault/app/identity/site_register_flow.dart';
import 'package:vault/app/models/domain.dart';

void main() {
  test('parses newapi register settings from /api/status', () {
    final settings = NewApiRegisterSettings.fromJson({
      'register_enabled': true,
      'password_register_enabled': true,
      'email_verification': true,
      'turnstile_check': true,
      'turnstile_site_key': '0x4AAAAAA',
      'system_name': 'New API',
    });
    expect(settings.registrationEnabled, isTrue);
    expect(settings.passwordRegisterEnabled, isTrue);
    expect(settings.emailVerifyEnabled, isTrue);
    expect(settings.turnstileEnabled, isTrue);
    expect(settings.turnstileSiteKey, '0x4AAAAAA');
    expect(
      NewApiRegisterSettings.fromJson({'register_enabled': false})
          .registrationEnabled,
      isFalse,
    );
  });

  test('maps newapi register errors', () {
    expect(describeNewApiRegisterError('该用户名已被注册'), contains('用户名'));
    expect(describeNewApiRegisterError('该邮箱地址已被注册'), contains('已经注册'));
    expect(
      describeNewApiRegisterError('Turnstile 校验失败，请刷新重试！'),
      contains('人机验证'),
    );
    expect(describeNewApiRegisterError(''), '注册失败，请稍后重试');
    expect(looksLikeNewApiUsernameTaken('该用户名已被注册'), isTrue);
    expect(looksLikeNewApiUsernameTaken('该邮箱地址已被注册'), isFalse);
  });

  test('parses registration fields from public settings', () {
    final settings = Sub2PublicSettings.fromJson({
      'data': {
        'site_name': 'Mi-API',
        'registration_enabled': true,
        'email_verify_enabled': true,
        'registration_email_suffix_whitelist': ['@qq.com', '@gmail.com'],
        'turnstile_enabled': true,
        'turnstile_site_key': '0x4AAAAAA',
      },
    });
    expect(settings.registrationEnabled, isTrue);
    expect(settings.emailVerifyEnabled, isTrue);
    expect(settings.emailSuffixWhitelist, ['@qq.com', '@gmail.com']);
    expect(settings.turnstileEnabled, isTrue);
  });

  test('defaults registration to open and verification to off', () {
    final settings = Sub2PublicSettings.fromJson({'site_name': 'X'});
    expect(settings.registrationEnabled, isTrue);
    expect(settings.emailVerifyEnabled, isFalse);
    expect(settings.emailSuffixWhitelist, isEmpty);
  });

  test('maps register errors to friendly messages', () {
    expect(describeSub2RegisterError('Email already exists'), contains('已经注册'));
    expect(describeSub2RegisterError('验证码错误'), contains('验证码'));
    expect(
      describeSub2RegisterError('Invalid request: Email validation failed', ''),
      contains('邮箱'),
    );
    expect(describeSub2RegisterError(''), '注册失败，请稍后重试');
  });

  test('register errors keep ApiError type', () {
    expect(ApiError('x', 400).status, 400);
  });

  test('derives safe newapi usernames from mailbox', () {
    expect(deriveNewApiUsername('hkmialiming@gmail.com'), 'hkmialiming');
    expect(deriveNewApiUsername('q q+tag@qq.com'), 'qqtag');
    expect(deriveNewApiUsername('no-mailbox'), 'no-mailbox');
    expect(
      deriveNewApiUsername('aaaaaaaaaaaaaaaaaaaaaaaaaa@qq.com').length,
      lessThanOrEqualTo(20),
    );
    expect(deriveNewApiUsername('中文邮箱@qq.com'), startsWith('yucon'));
    expect(deriveNewApiUsername('中文@qq.com').startsWith('yucon'), isTrue);
  });

  test('checks mailbox suffix against site whitelist', () {
    expect(emailAllowedByWhitelist('a@qq.com', const []), isTrue);
    expect(
      emailAllowedByWhitelist('a@qq.com', const ['@qq.com', '@163.com']),
      isTrue,
    );
    expect(emailAllowedByWhitelist('a@qq.com', const ['qq.com']), isTrue);
    expect(emailAllowedByWhitelist('a@gmail.com', const ['@qq.com']), isFalse);
    expect(emailAllowedByWhitelist('no-suffix', const ['@qq.com']), isFalse);
  });

  test('splits mailbox suffix', () {
    expect(mailboxSuffix('a@qq.com'), 'qq.com');
    expect(mailboxSuffix('no-suffix'), '');
  });

  test('uses mailbox local part as remark', () {
    expect(mailboxLocalPart('hkmialiming@gmail.com'), 'hkmialiming');
    expect(mailboxLocalPart('  a.b+tag@qq.com '), 'a.b+tag');
    expect(mailboxLocalPart('no-suffix'), 'no-suffix');
    expect(mailboxLocalPart('@qq.com'), '@qq.com');
  });

  test('keeps mailbox as login identity after site username snapshot', () {
    expect(
      preferMailboxLoginIdentity('user@qq.com', 'derivedname'),
      'user@qq.com',
    );
    expect(preferMailboxLoginIdentity('siteuser', 'siteuser'), 'siteuser');
    expect(keepMailboxLoginIdentity('user@qq.com', 'derivedname'), isTrue);
    expect(keepMailboxLoginIdentity('siteuser', 'siteuser'), isFalse);
    expect(keepMailboxLoginIdentity('user@qq.com', 'other@qq.com'), isFalse);
  });

  test('generates mixed passwords long enough for site rules', () {
    final first = generateSiteRegisterPassword();
    final second = generateSiteRegisterPassword();
    expect(first.length, 16);
    expect(second.length, 16);
    expect(first, isNot(second));
    expect(RegExp(r'[a-z]').hasMatch(first), isTrue);
    expect(RegExp(r'[A-Z]').hasMatch(first), isTrue);
    expect(RegExp(r'\d').hasMatch(first), isTrue);
  });

  test(
    'native login rejects empty credentials before contacting the site',
    () async {
      expect(
        () => loginSub2SiteNatively(
          baseUrl: 'https://example.com',
          email: 'not-an-email',
          password: 'secret',
          solver: CaptchaSolverSettings(),
        ),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => loginNewApiSiteNatively(
          baseUrl: 'https://example.com',
          username: '',
          password: 'secret',
          solver: CaptchaSolverSettings(),
        ),
        throwsA(isA<ApiError>()),
      );
    },
  );
}
