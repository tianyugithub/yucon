import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';

const _kSolverPollLimit = 40;

String captchaSolverApiBase(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
      return 'https://api.yescaptcha.com';
    case CaptchaSolverType.twoCaptcha:
      return 'https://api.2captcha.com';
    case CaptchaSolverType.capMonsterCloud:
      return 'https://api.capmonster.cloud';
    case CaptchaSolverType.capSolver:
      return 'https://api.capsolver.com';
  }
}

String captchaSolverKeyHint(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
      return '在 yescaptcha.com 个人中心首页复制 ClientKey';
    case CaptchaSolverType.twoCaptcha:
      return '在 2captcha.com → Settings 复制 API key';
    case CaptchaSolverType.capMonsterCloud:
      return '在 capmonster.cloud 控制台复制 API key';
    case CaptchaSolverType.capSolver:
      return '在 capsolver.com Dashboard 复制 API Key（CAP- 开头）';
  }
}

String captchaSolverIconAsset(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
      return 'assets/solvers/yescaptcha.png';
    case CaptchaSolverType.twoCaptcha:
      return 'assets/solvers/twocaptcha.png';
    case CaptchaSolverType.capMonsterCloud:
      return 'assets/solvers/capmonster.png';
    case CaptchaSolverType.capSolver:
      return 'assets/solvers/capsolver.png';
  }
}

String captchaSolverHomeHost(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
      return 'yescaptcha.com';
    case CaptchaSolverType.twoCaptcha:
      return '2captcha.com';
    case CaptchaSolverType.capMonsterCloud:
      return 'capmonster.cloud';
    case CaptchaSolverType.capSolver:
      return 'capsolver.com';
  }
}

String captchaSolverTurnstileTaskType(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
    case CaptchaSolverType.twoCaptcha:
      return 'TurnstileTaskProxyless';
    case CaptchaSolverType.capMonsterCloud:
      return 'TurnstileTask';
    case CaptchaSolverType.capSolver:
      return 'AntiTurnstileTaskProxyLess';
  }
}

Duration captchaSolverPollInterval(CaptchaSolverType type) {
  switch (type) {
    case CaptchaSolverType.twoCaptcha:
      return const Duration(seconds: 5);
    case CaptchaSolverType.capSolver:
      return const Duration(seconds: 2);
    case CaptchaSolverType.yesCaptcha:
    case CaptchaSolverType.capMonsterCloud:
      return const Duration(seconds: 3);
  }
}

String formatCaptchaSolverBalance(CaptchaSolverType type, double balance) {
  switch (type) {
    case CaptchaSolverType.yesCaptcha:
      if (balance == balance.roundToDouble()) {
        return '${balance.toStringAsFixed(0)} 点';
      }
      return '${balance.toStringAsFixed(2)} 点';
    case CaptchaSolverType.twoCaptcha:
    case CaptchaSolverType.capMonsterCloud:
    case CaptchaSolverType.capSolver:
      return '\$${balance.toStringAsFixed(2)}';
  }
}

Object captchaSolverTaskIdPayload(Object? taskId) {
  final text = taskId?.toString().trim() ?? '';
  final asInt = int.tryParse(text);
  if (asInt != null && asInt.toString() == text) {
    return asInt;
  }
  return text;
}

Map<String, Object?> captchaSolverTurnstileTask({
  required CaptchaSolverType type,
  required String websiteUrl,
  required String websiteKey,
}) {
  return {
    'type': captchaSolverTurnstileTaskType(type),
    'websiteURL': websiteUrl,
    'websiteKey': websiteKey,
  };
}

Future<Object> _captchaPost(
  CaptchaSolverSettings settings,
  String path,
  Map<String, Object?> data,
) async {
  final result = await requestJsonDetailed<Object>(
    method: 'POST',
    path: path,
    baseUrl: captchaSolverApiBase(settings.type),
    data: data,
    timeout: const Duration(seconds: 25),
    throwOnHttpError: false,
  );
  final record = asRecord(result.data);
  final errorId = readNumber(record['errorId']).round();
  if (result.status >= 400 || errorId != 0) {
    throw ApiError(describeCaptchaSolverError(record));
  }
  return result.data;
}

String describeCaptchaSolverError(Object? payload) {
  final record = asRecord(payload);
  final code = record['errorCode']?.toString().trim() ?? '';
  final description = record['errorDescription']?.toString().trim() ?? '';
  final lower = '$code $description'.toLowerCase();
  if (lower.contains('key_does_not_exist') ||
      lower.contains('wrong_user_key') ||
      lower.contains('invalid_key') ||
      lower.contains('invalid api key') ||
      lower.contains('clientkey is invalid')) {
    return '打码平台密钥无效，请到「我的 → 验证码服务」检查 ClientKey';
  }
  if (lower.contains('zero_balance') ||
      lower.contains('zero balance') ||
      lower.contains('insufficient')) {
    return '打码平台余额不足，请先充值';
  }
  if (lower.contains('ip_blocked') ||
      lower.contains('ip block') ||
      lower.contains('ip_banned')) {
    return '请求太频繁，打码平台暂时限制了当前 IP，请稍后再试';
  }
  if (lower.contains('no_slot') || lower.contains('busy')) {
    return '打码平台当前较忙，请稍后重试';
  }
  if (lower.contains('type_not_supported') ||
      lower.contains('task_not_supported') ||
      lower.contains('unsupported captcha type')) {
    return '这个打码平台不支持当前验证类型';
  }
  if (lower.contains('invalid_task_data') ||
      lower.contains('invalid websitekey')) {
    return '验证码参数不正确，请重试';
  }
  if (lower.contains('unsolvable') ||
      lower.contains('captcha_fail') ||
      record['status']?.toString() == 'failed') {
    return '这次验证码没能解出来，请重试';
  }
  if (lower.contains('timeout')) {
    return '打码平台识别超时，请重试';
  }
  final text = description.isNotEmpty ? description : code;
  if (text.isEmpty) {
    return '打码平台调用失败';
  }
  return '打码平台调用失败：$text';
}

Future<double> fetchCaptchaSolverBalance(CaptchaSolverSettings settings) async {
  if (settings.clientKey.trim().isEmpty) {
    throw ApiError('请先填写打码平台的 ClientKey');
  }
  final payload = await _captchaPost(settings, '/getBalance', {
    'clientKey': settings.clientKey.trim(),
  });
  return readNumber(asRecord(payload)['balance']);
}

class _SolverTaskTimeout implements Exception {}

String? _readyTurnstileToken(Object payload) {
  final record = asRecord(payload);
  if (record['status']?.toString() != 'ready') {
    return null;
  }
  final solution = asRecord(record['solution']);
  final token =
      (solution['token'] ?? solution['gRecaptchaResponse'])
          ?.toString()
          .trim() ??
      '';
  return token.isEmpty ? null : token;
}

Future<String> solveTurnstile({
  required CaptchaSolverSettings settings,
  required String websiteUrl,
  required String websiteKey,
  void Function(String detail)? onWait,
  int retries = 1,
}) async {
  if (!settings.configured) {
    throw ApiError('请先到「我的 → 验证码服务」开启并填好 ClientKey');
  }
  for (var round = 0; ; round++) {
    try {
      return await _solveTurnstileOnce(
        settings,
        websiteUrl,
        websiteKey,
        onWait,
      );
    } on _SolverTaskTimeout {
      if (round >= retries) {
        final seconds =
            _kSolverPollLimit *
            captchaSolverPollInterval(settings.type).inSeconds;
        throw ApiError('打码平台 $seconds 秒没解出验证码，可能正忙，请稍后重试');
      }
      onWait?.call('上一次解题排队超时，正在重试…');
    }
  }
}

Future<String> _solveTurnstileOnce(
  CaptchaSolverSettings settings,
  String websiteUrl,
  String websiteKey,
  void Function(String detail)? onWait,
) async {
  final created = await _captchaPost(settings, '/createTask', {
    'clientKey': settings.clientKey.trim(),
    'task': captchaSolverTurnstileTask(
      type: settings.type,
      websiteUrl: websiteUrl,
      websiteKey: websiteKey,
    ),
  });
  final createdToken = _readyTurnstileToken(created);
  if (createdToken != null) {
    return createdToken;
  }
  if (asRecord(created)['status']?.toString() == 'failed') {
    throw ApiError(describeCaptchaSolverError(created));
  }
  final taskId = asRecord(created)['taskId']?.toString().trim() ?? '';
  if (taskId.isEmpty) {
    throw ApiError('打码平台没有返回任务编号');
  }
  final started = DateTime.now();
  final interval = captchaSolverPollInterval(settings.type);
  final waitLabel = captchaSolverTypeLabel(settings.type);
  for (var attempt = 0; attempt < _kSolverPollLimit; attempt++) {
    await Future<void>.delayed(interval);
    final result = await _captchaPost(settings, '/getTaskResult', {
      'clientKey': settings.clientKey.trim(),
      'taskId': captchaSolverTaskIdPayload(taskId),
    });
    final record = asRecord(result);
    if (record['status']?.toString() == 'failed') {
      throw ApiError(describeCaptchaSolverError(record));
    }
    final token = _readyTurnstileToken(result);
    if (token != null) {
      return token;
    }
    if (record['status']?.toString() == 'ready') {
      throw ApiError('打码平台没有返回验证码 token');
    }
    onWait?.call(
      '$waitLabel 正在解题… 已等待 '
      '${DateTime.now().difference(started).inSeconds} 秒',
    );
  }
  throw _SolverTaskTimeout();
}
