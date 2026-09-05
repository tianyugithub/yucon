import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:vault/app/api/http.dart';

enum SiteAccessIssue { none, dnsPolluted, networkBlocked }

class SiteAccessDiagnosis {
  const SiteAccessDiagnosis(this.issue, this.message);

  final SiteAccessIssue issue;
  final String message;
}

bool looksLikeHostLookupFailure(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('failed host lookup') ||
      text.contains('name or service not known') ||
      text.contains('nodename nor servname') ||
      text.contains('no address associated') ||
      text.contains('找不到这个站点');
}

bool looksLikeCertificateMismatch(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('certificate_verify_failed') ||
      text.contains('hostname mismatch') ||
      text.contains('certificateverifyfailed') ||
      (text.contains('handshakeexception') && text.contains('certificate'));
}

bool looksLikeTransportFailure(Object error) {
  final text = '${error is ApiError ? error.message : error}'.toLowerCase();
  return text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('超时') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable') ||
      text.contains('software caused connection abort') ||
      text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('handshake') ||
      text.contains('broken pipe') ||
      text.contains('连不上') ||
      text.contains('打不开') ||
      text.contains('网络连接失败') ||
      text.contains('proxy failed') ||
      text.contains('proxy tunnel failed');
}

bool shouldDiagnoseSiteAccess(Object error) {
  if (isDnsPollutedError(error) || isNetworkBlockedError(error)) {
    return true;
  }
  if (isAuthExpiredError(error)) {
    return false;
  }
  return looksLikeHostLookupFailure(error) ||
      looksLikeCertificateMismatch(error) ||
      looksLikeTransportFailure(error);
}

final Map<String, _DnsSnapshot> _dnsCache = {};

class _DnsSnapshot {
  const _DnsSnapshot({
    required this.system,
    required this.trusted,
    required this.chinaView,
    required this.at,
  });

  final List<InternetAddress> system;
  final List<InternetAddress> trusted;
  final List<InternetAddress> chinaView;
  final DateTime at;

  List<InternetAddress> get chinaPoison => chinaView.where(isKnownPoisonAddress).toList();
}

Future<SiteAccessDiagnosis> diagnoseSiteAccess(String baseUrl, Object error) async {
  if (isDnsPollutedError(error)) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }

  String host = '';
  try {
    host = Uri.parse(normalizeBaseUrl(baseUrl)).host.trim().toLowerCase();
  } catch (_) {}
  if (host.isEmpty || InternetAddress.tryParse(host) != null) {
    return _fallbackDiagnosis(error);
  }

  final snapshot = await _lookupHost(host);
  final system = snapshot.system;
  final trusted = snapshot.trusted;
  final systemPoison = system.where(isKnownPoisonAddress).toList();
  final systemPublic = system.where((address) => !isKnownPoisonAddress(address)).toList();
  final trustedPublic = trusted.where((address) => !isKnownPoisonAddress(address)).toList();
  final overlap = _hasOverlap(systemPublic, trustedPublic);

  debugPrint(
    '[YUCON_DNS] $host system=${_fmt(system)} trusted=${_fmt(trusted)} china=${_fmt(snapshot.chinaView)} poison=${_fmt(systemPoison)} overlap=$overlap',
  );

  if (systemPoison.isNotEmpty) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (trustedPublic.isNotEmpty && systemPublic.isNotEmpty && !overlap) {
    if (isNetworkBlockedError(error) && systemPoison.isEmpty) {
      return SiteAccessDiagnosis(
        SiteAccessIssue.networkBlocked,
        userFacingError(error, kSiteNetworkBlockedMessage),
      );
    }
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (looksLikeCertificateMismatch(error) && currentRequestProxy() == null) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (looksLikeHostLookupFailure(error) && trustedPublic.isNotEmpty) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (trustedPublic.isEmpty && snapshot.chinaPoison.isNotEmpty) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (isNetworkBlockedError(error) || looksLikeTransportFailure(error)) {
    return SiteAccessDiagnosis(
      SiteAccessIssue.networkBlocked,
      _unreachableMessage(error),
    );
  }
  return _fallbackDiagnosis(error);
}

SiteAccessDiagnosis _fallbackDiagnosis(Object error) {
  if (looksLikeHostLookupFailure(error) || looksLikeCertificateMismatch(error)) {
    return const SiteAccessDiagnosis(SiteAccessIssue.dnsPolluted, kDnsPollutedMessage);
  }
  if (isNetworkBlockedError(error) || looksLikeTransportFailure(error)) {
    return SiteAccessDiagnosis(
      SiteAccessIssue.networkBlocked,
      _unreachableMessage(error),
    );
  }
  return SiteAccessDiagnosis(SiteAccessIssue.none, userFacingError(error, '同步失败'));
}

String _unreachableMessage(Object error) {
  if (isNetworkBlockedError(error) && !looksLikeTransportFailure(error)) {
    return userFacingError(error, kSiteNetworkBlockedMessage);
  }
  return kSiteUnreachableMessage;
}

String _fmt(List<InternetAddress> addresses) =>
    addresses.map((address) => address.address).join(',');

Future<_DnsSnapshot> _lookupHost(String host) async {
  final cached = _dnsCache[host];
  if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 30)) {
    return cached;
  }
  final encoded = Uri.encodeQueryComponent(host);
  final results = await Future.wait([
    _systemLookup(host),
    _dohCollect([
      'https://1.1.1.1/dns-query?name=$encoded&type=A',
      'https://8.8.8.8/resolve?name=$encoded&type=A',
    ], skipPoison: true),
    _dohCollect([
      'https://223.5.5.5/resolve?name=$encoded&type=A',
      'https://223.6.6.6/resolve?name=$encoded&type=A',
    ], skipPoison: false),
  ]);
  final snapshot = _DnsSnapshot(
    system: results[0],
    trusted: results[1],
    chinaView: results[2],
    at: DateTime.now(),
  );
  _dnsCache[host] = snapshot;
  return snapshot;
}

Future<List<InternetAddress>> _systemLookup(String host) async {
  try {
    return await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
  } catch (_) {
    return const [];
  }
}

Future<List<InternetAddress>> _dohCollect(List<String> urls, {required bool skipPoison}) async {
  final collected = <InternetAddress>[];
  final seen = <String>{};
  final batches = await Future.wait(urls.map(_dohLookup));
  for (final addresses in batches) {
    for (final address in addresses) {
      if (skipPoison && isKnownPoisonAddress(address)) {
        continue;
      }
      if (seen.add(address.address)) {
        collected.add(address);
      }
    }
  }
  return collected;
}

Future<List<InternetAddress>> _dohLookup(String url) async {
  IOClient? client;
  try {
    final io = HttpClient();
    io.userAgent = kHttpUserAgent;
    io.connectionTimeout = const Duration(seconds: 2);
    client = IOClient(io);
    final response = await client
        .get(Uri.parse(url), headers: {'Accept': 'application/dns-json'})
        .timeout(const Duration(seconds: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    if (!response.body.trimLeft().startsWith('{')) {
      return const [];
    }
    return _addressesFromDoh(response.body);
  } catch (_) {
    return const [];
  } finally {
    client?.close();
  }
}

List<InternetAddress> _addressesFromDoh(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const [];
    }
    final answers = decoded['Answer'];
    if (answers is! List) {
      return const [];
    }
    final addresses = <InternetAddress>[];
    for (final item in answers) {
      if (item is! Map) {
        continue;
      }
      final type = item['type'];
      if (type != 1 && type != '1') {
        continue;
      }
      final parsed = InternetAddress.tryParse(item['data']?.toString().trim() ?? '');
      if (parsed != null) {
        addresses.add(parsed);
      }
    }
    return addresses;
  } catch (_) {
    return const [];
  }
}

const _knownPoisonIpv4 = {
  '159.106.121.75',
  '169.132.13.103',
  '4.36.66.178',
  '64.33.88.161',
  '8.7.198.45',
};

bool isKnownPoisonAddress(InternetAddress address) {
  if (isSuspiciousResolvedAddress(address)) {
    return true;
  }
  if (address.type != InternetAddressType.IPv4) {
    return false;
  }
  if (_knownPoisonIpv4.contains(address.address)) {
    return true;
  }
  return _ipv4InCidr(address, [199, 16, 156, 0], 22) ||
      _ipv4InCidr(address, [199, 59, 148, 0], 22) ||
      _ipv4InCidr(address, [104, 244, 42, 0], 24) ||
      _ipv4InCidr(address, [243, 185, 187, 0], 24) ||
      _ipv4InCidr(address, [46, 82, 174, 0], 24) ||
      _ipv4InCidr(address, [203, 98, 7, 0], 24) ||
      _ipv4InCidr(address, [128, 242, 240, 0], 24) ||
      _ipv4InCidr(address, [128, 242, 245, 0], 24) ||
      _ipv4InCidr(address, [128, 242, 250, 0], 24) ||
      _ipv4InCidr(address, [128, 121, 146, 0], 24) ||
      _ipv4InCidr(address, [128, 121, 243, 0], 24);
}

bool isSuspiciousResolvedAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (bytes.length != 4) {
      return true;
    }
    if (bytes[0] == 0 || bytes[0] == 10 || bytes[0] == 127) {
      return true;
    }
    if (bytes[0] == 169 && bytes[1] == 254) {
      return true;
    }
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) {
      return true;
    }
    if (bytes[0] == 192 && bytes[1] == 168) {
      return true;
    }
    if (bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)) {
      return true;
    }
    if (bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 2) {
      return true;
    }
    if (bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100) {
      return true;
    }
    if (bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113) {
      return true;
    }
    return false;
  }
  if (bytes.isEmpty || bytes.every((byte) => byte == 0)) {
    return true;
  }
  if (bytes[0] == 0xfc || bytes[0] == 0xfd) {
    return true;
  }
  if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
    return true;
  }
  if (bytes.length >= 4 && bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) {
    return true;
  }
  return false;
}

bool _ipv4InCidr(InternetAddress address, List<int> network, int prefix) {
  final bytes = address.rawAddress;
  if (bytes.length != 4 || network.length != 4) {
    return false;
  }
  final ip = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  final net = (network[0] << 24) | (network[1] << 16) | (network[2] << 8) | network[3];
  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return (ip & mask) == (net & mask);
}

bool _hasOverlap(List<InternetAddress> left, List<InternetAddress> right) {
  final wanted = right.map((address) => address.address).toSet();
  return left.any((address) => wanted.contains(address.address));
}
