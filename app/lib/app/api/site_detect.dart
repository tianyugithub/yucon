import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/sub2api.dart';
import 'package:vault/app/models/domain.dart';

class DetectedSite {
  const DetectedSite({
    required this.type,
    required this.status,
    this.score = 0,
  });

  final PlatformType type;
  final SiteStatus status;
  final int score;
}

Map<String, dynamic> _payloadData(Map<String, dynamic> payload) {
  final nested = payload['data'];
  if (nested is Map) {
    return asRecord(nested);
  }
  return payload;
}

int newApiStatusScore(Map<String, dynamic> payload) {
  final data = _payloadData(payload);
  if (data.isEmpty) {
    return 0;
  }
  var score = 0;
  if (data.containsKey('system_name') || data.containsKey('SystemName')) {
    score += 2;
  }
  if (data.containsKey('quota_per_unit') || data.containsKey('QuotaPerUnit')) {
    score += 2;
  }
  if (data.containsKey('email_verification') ||
      data.containsKey('EmailVerification')) {
    score += 1;
  }
  if (data.containsKey('turnstile_check') || data.containsKey('TurnstileCheck')) {
    score += 1;
  }
  if (data.containsKey('github_oauth') || data.containsKey('GitHubOAuth')) {
    score += 1;
  }
  if (data.containsKey('google_oauth') || data.containsKey('GoogleOAuth')) {
    score += 1;
  }
  if (data.containsKey('version') &&
      (data.containsKey('start_time') || data.containsKey('StartTime'))) {
    score += 2;
  }
  if (payload['success'] == true &&
      (data.containsKey('version') ||
          data.containsKey('system_name') ||
          data.containsKey('SystemName'))) {
    score += 1;
  }
  return score;
}

int sub2SettingsScore(Map<String, dynamic> payload) {
  final nested = payload['data'];
  final data =
      nested is Map &&
          (nested.containsKey('site_name') ||
              nested.containsKey('turnstile_enabled') ||
              nested.containsKey('turnstile_site_key'))
      ? asRecord(nested)
      : payload;
  if (data.isEmpty) {
    return 0;
  }
  var score = 0;
  if (data.containsKey('site_name')) {
    score += 2;
  }
  if (data.containsKey('site_logo') || data.containsKey('site_subtitle')) {
    score += 1;
  }
  if (data.containsKey('turnstile_enabled') ||
      data.containsKey('turnstile_site_key')) {
    score += 2;
  }
  if (data.containsKey('github_oauth_enabled') ||
      data.containsKey('google_oauth_enabled')) {
    score += 2;
  }
  if (data.containsKey('email_verification_enabled')) {
    score += 1;
  }
  if (data.containsKey('oidc_enabled')) {
    score += 1;
  }
  return score;
}

bool looksLikeNewApiStatus(Map<String, dynamic> payload) =>
    newApiStatusScore(payload) >= 2;

bool looksLikeSub2Site(Map<String, dynamic> payload) =>
    sub2SettingsScore(payload) >= 2;

DetectedSite? chooseDetectedSite(DetectedSite? newApi, DetectedSite? sub2) {
  if (newApi == null) {
    return sub2;
  }
  if (sub2 == null) {
    return newApi;
  }
  return sub2.score > newApi.score ? sub2 : newApi;
}

Future<DetectedSite?> _detectNewApi(String baseUrl) async {
  try {
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/status',
    );
    final score = newApiStatusScore(payload);
    if (score < 2) {
      return null;
    }
    final data = asRecord(payload['data']);
    return DetectedSite(
      type: PlatformType.newapi,
      status: siteStatusFromData(data.isEmpty ? payload : data),
      score: score,
    );
  } catch (_) {
    return null;
  }
}

Future<DetectedSite?> _detectSub2(String baseUrl) async {
  for (final path in const [
    '/api/v1/settings/public',
    '/api/v1/public/settings',
  ]) {
    try {
      final payload = await requestJson<Map<String, dynamic>>(
        baseUrl: baseUrl,
        path: path,
      );
      final score = sub2SettingsScore(payload);
      if (score < 2) {
        continue;
      }
      return DetectedSite(
        type: PlatformType.sub2api,
        status: siteStatusFromSub2Settings(
          Sub2PublicSettings.fromJson(payload),
        ),
        score: score,
      );
    } catch (_) {}
  }
  return null;
}

Future<DetectedSite?> detectSitePlatform(String baseUrl) async {
  final results = await Future.wait([
    _detectNewApi(baseUrl),
    _detectSub2(baseUrl),
  ]);
  return chooseDetectedSite(results[0], results[1]);
}
