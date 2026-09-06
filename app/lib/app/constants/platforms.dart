import 'package:flutter/material.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/screens/theme_define.dart';

const platformPresets = <PlatformType, PlatformPreset>{
  PlatformType.newapi: PlatformPreset(
    type: PlatformType.newapi,
    label: 'NewAPI',
    shortLabel: 'N',
    description: 'NewAPI 站点账号',
    color: 0xFFFA2C19,
    lightColor: 0xFFFFF0ED,
    supportsAccessToken: true,
    supportsKeyModelLimits: true,
    supportsCrossGroupRetry: true,
    identityLabel: '用户名',
    identityPlaceholder: '站点用户名',
    iconAsset: 'assets/platforms/newapi.png',
  ),
  PlatformType.sub2api: PlatformPreset(
    type: PlatformType.sub2api,
    label: 'Sub2API',
    shortLabel: 'S',
    description: 'Sub2API 站点账号，使用邮箱登录',
    color: 0xFF0D9488,
    lightColor: 0xFFE7F7F4,
    supportsAccessToken: false,
    supportsKeyModelLimits: false,
    supportsCrossGroupRetry: false,
    identityLabel: '邮箱',
    identityPlaceholder: '登录邮箱',
    iconAsset: 'assets/platforms/sub2api.png',
  ),
};

PlatformPreset getPlatformPreset(PlatformType type) =>
    platformPresets[type] ?? platformPresets[PlatformType.newapi]!;

String platformLabelSlash() =>
    platformPresets.values.map((preset) => preset.label).join(' / ');

String summarizePlatformTypes(List<Account> accounts) {
  final parts = platformPresets.values
      .map((preset) {
        final count = accounts
            .where((account) => account.platformType == preset.type)
            .length;
        return count > 0 ? '${preset.label} $count 个' : '';
      })
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? '暂无账号' : parts.join(' · ');
}

class StatusMeta {
  const StatusMeta({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;
}

StatusMeta accountDisplayMeta(Account account) {
  if (account.dnsPolluted) {
    return const StatusMeta(
      label: '域名解析异常',
      color: Color(0xFF9A3412),
      background: Color(0xFFFBE7E0),
    );
  }
  return accountStatusMeta(account.status);
}

StatusMeta accountStatusMeta(AccountStatus status) {
  switch (status) {
    case AccountStatus.active:
      return const StatusMeta(
        label: '正常',
        color: Color(0xFF168553),
        background: Color(0xFFE7F7EF),
      );
    case AccountStatus.low:
      return const StatusMeta(
        label: '低额度',
        color: Color(0xFFB05F00),
        background: Color(0xFFFFF2DC),
      );
    case AccountStatus.exhausted:
      return const StatusMeta(
        label: '无额度',
        color: Color(0xFF9A3412),
        background: Color(0xFFFBE7E0),
      );
    case AccountStatus.disabled:
      return const StatusMeta(
        label: '已停用',
        color: Color(0xFF69707C),
        background: Color(0xFFEEF0F3),
      );
    case AccountStatus.pending:
      return const StatusMeta(
        label: '待同步',
        color: Color(0xFF3178DF),
        background: Color(0xFFEDF4FF),
      );
    case AccountStatus.expired:
      return const StatusMeta(
        label: '需重新登录',
        color: Color(0xFFBE2630),
        background: Color(0xFFFDE8E6),
      );
    case AccountStatus.blocked:
      return const StatusMeta(
        label: '此站打不开',
        color: Color(0xFF9A3412),
        background: Color(0xFFFBE7E0),
      );
  }
}

StatusMeta apiKeyStatusMeta(ApiKeyStatus status) {
  switch (status) {
    case ApiKeyStatus.enabled:
      return const StatusMeta(
        label: '启用',
        color: Color(0xFF168553),
        background: Color(0xFFE7F7EF),
      );
    case ApiKeyStatus.disabled:
      return const StatusMeta(
        label: '停用',
        color: Color(0xFF69707C),
        background: Color(0xFFEEF0F3),
      );
    case ApiKeyStatus.expired:
      return const StatusMeta(
        label: '过期',
        color: Color(0xFFBE2630),
        background: Color(0xFFFDE8E6),
      );
    case ApiKeyStatus.exhausted:
      return const StatusMeta(
        label: '已用完',
        color: Color(0xFFB05F00),
        background: Color(0xFFFFF2DC),
      );
  }
}

Color platformColor(PlatformType type) =>
    Color(getPlatformPreset(type).color);

Color yuconPrimary = ThemeDefine.kColorPrimary;
