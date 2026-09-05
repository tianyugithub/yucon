import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/open_source.dart';

const kGithubApiBase = 'https://api.github.com';
const kGithubLatestReleasePath = '/repos/tianyugithub/yucon/releases/latest';

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    this.androidDownloadUrl,
    this.iosDownloadUrl,
  });

  final String version;
  final String tag;
  final String title;
  final String notes;
  final String htmlUrl;
  final String? androidDownloadUrl;
  final String? iosDownloadUrl;
}

String normalizeAppVersion(String value) {
  return value.trim().replaceFirst(RegExp(r'^[vV]'), '');
}

List<int> appVersionParts(String version) {
  final core = normalizeAppVersion(version).split(RegExp(r'[-+]')).first;
  if (core.isEmpty) {
    return const [0];
  }
  return core.split('.').map((part) {
    final digits = part.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }).toList();
}

int compareAppVersions(String left, String right) {
  final a = appVersionParts(left);
  final b = appVersionParts(right);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final l = i < a.length ? a[i] : 0;
    final r = i < b.length ? b[i] : 0;
    if (l != r) {
      return l.compareTo(r);
    }
  }
  return 0;
}

bool isAppVersionNewer(String remote, String current) {
  return compareAppVersions(remote, current) > 0;
}

AppReleaseInfo? parseGithubRelease(Map<String, dynamic> json) {
  if (json['draft'] == true) {
    return null;
  }
  final tag = json['tag_name']?.toString().trim() ?? '';
  if (tag.isEmpty) {
    return null;
  }
  final version = normalizeAppVersion(tag);
  String? androidUrl;
  String? iosUrl;
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) {
        continue;
      }
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final url = asset['browser_download_url']?.toString();
      if (url == null || url.isEmpty) {
        continue;
      }
      if (name.endsWith('.apk')) {
        androidUrl = url;
      } else if (name.endsWith('.ipa')) {
        iosUrl = url;
      }
    }
  }
  final notes = (json['body'] ?? '').toString().trim();
  final htmlUrl = (json['html_url'] ?? '$kAppSourceUrl/releases/tag/$tag').toString();
  final title = (json['name'] ?? 'v$version').toString().trim();
  return AppReleaseInfo(
    version: version,
    tag: tag,
    title: title.isEmpty ? 'v$version' : title,
    notes: notes,
    htmlUrl: htmlUrl,
    androidDownloadUrl: androidUrl,
    iosDownloadUrl: iosUrl,
  );
}

String preferredUpdateUrl(AppReleaseInfo release, {required bool android}) {
  if (android && (release.androidDownloadUrl ?? '').isNotEmpty) {
    return release.androidDownloadUrl!;
  }
  return release.htmlUrl;
}

Future<AppReleaseInfo> fetchLatestGithubRelease() async {
  final data = await requestJson<Map<String, dynamic>>(
    path: kGithubLatestReleasePath,
    baseUrl: kGithubApiBase,
    timeout: const Duration(seconds: 12),
    headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'YuconVault/$kAppVersion',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  );
  final parsed = parseGithubRelease(data);
  if (parsed == null) {
    throw ApiError('未找到可用的发布版本');
  }
  return parsed;
}
