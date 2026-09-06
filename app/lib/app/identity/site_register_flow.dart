import 'dart:math';

import 'package:vault/app/api/captcha_solver.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/sub2api.dart';
import 'package:vault/app/models/domain.dart';

enum SiteRegisterStage {
  checking,
  captcha,
  sendingCode,
  waitingMail,
  submitting,
  done,
}

class SiteRegisterOutcome {
  const SiteRegisterOutcome({
    required this.accessToken,
    required this.refreshToken,
    this.username = '',
    this.cookies = '',
    this.userId = '',
  });

  final String accessToken;
  final String refreshToken;
  final String username;
  final String cookies;
  final String userId;
}

typedef SiteRegisterCodePrompt = Future<String?> Function(String reason);

String mailboxSuffix(String email) {
  final at = email.lastIndexOf('@');
  return at < 0 ? '' : email.substring(at + 1).toLowerCase();
}

String mailboxLocalPart(String email) {
  final trimmed = email.trim();
  final at = trimmed.indexOf('@');
  if (at <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, at);
}

bool isMailboxLoginIdentity(String value) => value.trim().contains('@');

String preferMailboxLoginIdentity(String login, String? snapshotUsername) {
  final trimmed = login.trim();
  if (isMailboxLoginIdentity(trimmed)) {
    return trimmed;
  }
  final snapshot = snapshotUsername?.trim() ?? '';
  return snapshot.isNotEmpty ? snapshot : trimmed;
}

bool keepMailboxLoginIdentity(String current, String next) {
  return isMailboxLoginIdentity(current) && !isMailboxLoginIdentity(next);
}

bool emailAllowedByWhitelist(String email, List<String> whitelist) {
  if (whitelist.isEmpty) {
    return true;
  }
  final suffix = mailboxSuffix(email);
  if (suffix.isEmpty) {
    return false;
  }
  for (final raw in whitelist) {
    var item = raw.trim().toLowerCase();
    if (item.isEmpty) {
      continue;
    }
    if (item.startsWith('@')) {
      item = item.substring(1);
    }
    if (suffix == item) {
      return true;
    }
  }
  return false;
}

String deriveNewApiUsername(String email, [Random? random]) {
  final at = email.indexOf('@');
  var prefix = at > 0 ? email.substring(0, at) : email.trim();
  prefix = prefix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  if (prefix.isEmpty) {
    final rng = random ?? Random.secure();
    prefix = 'yucon${100000 + rng.nextInt(900000)}';
  }
  if (prefix.length > 20) {
    prefix = prefix.substring(0, 20);
  }
  return prefix;
}

String generateSiteRegisterPassword([Random? random]) {
  final rng = random ?? Random.secure();
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const pool = '$lower$upper$digits';
  final chars = <String>[
    lower[rng.nextInt(lower.length)],
    upper[rng.nextInt(upper.length)],
    digits[rng.nextInt(digits.length)],
  ];
  while (chars.length < 16) {
    chars.add(pool[rng.nextInt(pool.length)]);
  }
  chars.shuffle(rng);
  return chars.join();
}

String _retryNewApiUsername(String current, Random random) {
  final base = current.replaceAll(RegExp(r'\d+$'), '');
  final keep = base.length > 16
      ? base.substring(0, 16)
      : (base.isEmpty ? 'yucon' : base);
  var next = '$keep${100 + random.nextInt(900)}';
  if (next.length > 20) {
    next = next.substring(0, 20);
  }
  return next;
}

Future<String> _solveRegisterCaptcha({
  required String baseUrl,
  required String path,
  required String siteKey,
  required CaptchaSolverSettings solver,
  required void Function(SiteRegisterStage, String)? onProgress,
}) async {
  if (!solver.configured) {
    throw ApiError('该站点需要过人机验证。请到「我的 → 验证码服务」开启并填好 ClientKey');
  }
  return solveTurnstile(
    settings: solver,
    websiteUrl: joinUrl(baseUrl, path),
    websiteKey: siteKey,
    onWait: (detail) => onProgress?.call(SiteRegisterStage.captcha, detail),
  );
}

Future<String> _askVerifyCode(
  SiteRegisterCodePrompt? requestCode,
  String mailbox,
) async {
  final code =
      (await requestCode?.call('验证码已发到 $mailbox，请打开邮箱查看后填入'))?.trim() ?? '';
  if (code.isEmpty) {
    throw ApiError('已取消注册');
  }
  return code;
}

Future<SiteRegisterOutcome> registerSub2SiteNatively({
  required String baseUrl,
  required String email,
  required String password,
  required CaptchaSolverSettings solver,
  SiteRegisterCodePrompt? requestCode,
  void Function(SiteRegisterStage stage, String detail)? onProgress,
}) async {
  final mailbox = email.trim();
  if (mailbox.isEmpty || !mailbox.contains('@')) {
    throw ApiError('请填写用于注册的邮箱');
  }
  void stage(SiteRegisterStage value, [String detail = '']) =>
      onProgress?.call(value, detail);
  final normalized = normalizeBaseUrl(baseUrl);
  stage(SiteRegisterStage.checking, '读取站点公开设置');
  final settings = await fetchPublicSettings(normalized);
  if (!settings.registrationEnabled) {
    throw ApiError('该站点已关闭注册');
  }
  if (!emailAllowedByWhitelist(mailbox, settings.emailSuffixWhitelist)) {
    throw ApiError('站点不允许这个邮箱后缀注册');
  }
  var turnstile = '';
  final siteKey = settings.turnstileSiteKey?.trim() ?? '';
  if (settings.turnstileEnabled && siteKey.isNotEmpty) {
    stage(SiteRegisterStage.captcha, '由验证码服务代解 Cloudflare Turnstile');
    turnstile = await _solveRegisterCaptcha(
      baseUrl: normalized,
      path: '/login',
      siteKey: siteKey,
      solver: solver,
      onProgress: onProgress,
    );
  } else {
    stage(SiteRegisterStage.captcha, '该站点无需人机验证');
  }
  var code = '';
  if (settings.emailVerifyEnabled) {
    stage(SiteRegisterStage.sendingCode, '请求站点发送验证码邮件');
    await sendSub2VerifyCode(
      baseUrl: normalized,
      email: mailbox,
      turnstileToken: turnstile,
    );
    stage(SiteRegisterStage.waitingMail, '请填写邮箱里收到的验证码');
    code = await _askVerifyCode(requestCode, mailbox);
  }
  stage(SiteRegisterStage.submitting, '提交注册并获取登录凭证');
  final outcome = await registerSub2Account(
    baseUrl: normalized,
    email: mailbox,
    password: password,
    verifyCode: code,
    turnstileToken: turnstile,
  );
  stage(SiteRegisterStage.done, '注册成功');
  return SiteRegisterOutcome(
    accessToken: outcome.accessToken,
    refreshToken: outcome.refreshToken,
    username: mailbox,
  );
}

Future<SiteRegisterOutcome> loginSub2SiteNatively({
  required String baseUrl,
  required String email,
  required String password,
  required CaptchaSolverSettings solver,
  void Function(SiteRegisterStage stage, String detail)? onProgress,
}) async {
  final mailbox = email.trim();
  if (mailbox.isEmpty || !mailbox.contains('@')) {
    throw ApiError('请填写登录邮箱');
  }
  if (password.trim().isEmpty) {
    throw ApiError('请填写密码');
  }
  void stage(SiteRegisterStage value, [String detail = '']) =>
      onProgress?.call(value, detail);
  final normalized = normalizeBaseUrl(baseUrl);
  stage(SiteRegisterStage.checking, '读取站点公开设置');
  final settings = await fetchPublicSettings(normalized);
  var turnstile = '';
  final siteKey = settings.turnstileSiteKey?.trim() ?? '';
  if (settings.turnstileEnabled && siteKey.isNotEmpty) {
    stage(SiteRegisterStage.captcha, '由验证码服务代解 Cloudflare Turnstile');
    turnstile = await _solveRegisterCaptcha(
      baseUrl: normalized,
      path: '/login',
      siteKey: siteKey,
      solver: solver,
      onProgress: onProgress,
    );
  } else {
    stage(SiteRegisterStage.captcha, '该站点无需人机验证');
  }
  stage(SiteRegisterStage.submitting, '提交登录并获取凭证');
  final outcome = await connectSub2Account(
    baseUrl: normalized,
    email: mailbox,
    password: password,
    turnstileToken: turnstile,
  );
  stage(SiteRegisterStage.done, '登录成功');
  return SiteRegisterOutcome(
    accessToken: outcome.accessToken,
    refreshToken: outcome.refreshToken,
    username: mailbox,
  );
}

Future<SiteRegisterOutcome> registerNewApiSiteNatively({
  required String baseUrl,
  required String email,
  required String password,
  required CaptchaSolverSettings solver,
  SiteRegisterCodePrompt? requestCode,
  void Function(SiteRegisterStage stage, String detail)? onProgress,
}) async {
  final mailbox = email.trim();
  if (mailbox.isEmpty || !mailbox.contains('@')) {
    throw ApiError('请填写用于注册的邮箱');
  }
  void stage(SiteRegisterStage value, [String detail = '']) =>
      onProgress?.call(value, detail);
  final normalized = normalizeBaseUrl(baseUrl);
  stage(SiteRegisterStage.checking, '读取站点公开设置');
  final settings = await fetchNewApiRegisterSettings(normalized);
  if (!settings.registrationEnabled || !settings.passwordRegisterEnabled) {
    throw ApiError('该站点已关闭注册');
  }
  var turnstile = '';
  if (settings.turnstileEnabled &&
      settings.turnstileSiteKey.trim().isNotEmpty) {
    stage(SiteRegisterStage.captcha, '由验证码服务代解 Cloudflare Turnstile');
    turnstile = await _solveRegisterCaptcha(
      baseUrl: normalized,
      path: '/register',
      siteKey: settings.turnstileSiteKey,
      solver: solver,
      onProgress: onProgress,
    );
  } else {
    stage(SiteRegisterStage.captcha, '该站点无需人机验证');
  }
  var code = '';
  if (settings.emailVerifyEnabled) {
    stage(SiteRegisterStage.sendingCode, '请求站点发送验证码邮件');
    await sendNewApiVerifyCode(
      baseUrl: normalized,
      email: mailbox,
      turnstileToken: turnstile,
    );
    stage(SiteRegisterStage.waitingMail, '请填写邮箱里收到的验证码');
    code = await _askVerifyCode(requestCode, mailbox);
  }
  final rng = Random.secure();
  var username = deriveNewApiUsername(mailbox, rng);
  for (var attempt = 0; ; attempt++) {
    stage(
      SiteRegisterStage.submitting,
      attempt == 0 ? '提交注册（用户名 $username）' : '用户名被占用，改用 $username 重试',
    );
    try {
      await registerNewApiAccount(
        baseUrl: normalized,
        username: username,
        password: password,
        email: mailbox,
        verifyCode: code,
        turnstileToken: turnstile,
      );
      break;
    } on ApiError catch (error) {
      if (attempt >= 3 || !looksLikeNewApiUsernameTaken(error.message)) {
        rethrow;
      }
      username = _retryNewApiUsername(username, rng);
    }
  }
  stage(SiteRegisterStage.done, '注册成功，正在登录…');
  var loginTurnstile = turnstile;
  if (settings.turnstileEnabled &&
      settings.turnstileSiteKey.trim().isNotEmpty) {
    loginTurnstile = await _solveRegisterCaptcha(
      baseUrl: normalized,
      path: '/login',
      siteKey: settings.turnstileSiteKey,
      solver: solver,
      onProgress: onProgress,
    );
  }
  final connected = await connectAccount(
    baseUrl: normalized,
    username: username,
    password: password,
    turnstileToken: loginTurnstile,
  );
  return SiteRegisterOutcome(
    accessToken: connected.accessToken,
    refreshToken: connected.refreshToken,
    username: username,
    cookies: connected.cookies,
    userId: '${connected.user.id}',
  );
}

Future<SiteRegisterOutcome> loginNewApiSiteNatively({
  required String baseUrl,
  required String username,
  required String password,
  required CaptchaSolverSettings solver,
  void Function(SiteRegisterStage stage, String detail)? onProgress,
}) async {
  final loginName = username.trim();
  if (loginName.isEmpty) {
    throw ApiError('请填写用户名');
  }
  if (password.trim().isEmpty) {
    throw ApiError('请填写密码');
  }
  void stage(SiteRegisterStage value, [String detail = '']) =>
      onProgress?.call(value, detail);
  final normalized = normalizeBaseUrl(baseUrl);
  stage(SiteRegisterStage.checking, '读取站点公开设置');
  final settings = await fetchNewApiRegisterSettings(normalized);
  var turnstile = '';
  if (settings.turnstileEnabled &&
      settings.turnstileSiteKey.trim().isNotEmpty) {
    stage(SiteRegisterStage.captcha, '由验证码服务代解 Cloudflare Turnstile');
    turnstile = await _solveRegisterCaptcha(
      baseUrl: normalized,
      path: '/login',
      siteKey: settings.turnstileSiteKey,
      solver: solver,
      onProgress: onProgress,
    );
  } else {
    stage(SiteRegisterStage.captcha, '该站点无需人机验证');
  }
  stage(SiteRegisterStage.submitting, '提交登录并获取凭证');
  final connected = await connectAccount(
    baseUrl: normalized,
    username: loginName,
    password: password,
    turnstileToken: turnstile,
  );
  stage(SiteRegisterStage.done, '登录成功');
  return SiteRegisterOutcome(
    accessToken: connected.accessToken,
    refreshToken: connected.refreshToken,
    username: loginName,
    cookies: connected.cookies,
    userId: '${connected.user.id}',
  );
}
