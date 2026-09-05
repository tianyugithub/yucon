const kAppDisplayName = 'Yucon 钥仓';
const kAppVersion = '0.1.0';
const kAppSourceUrl = 'https://github.com/tianyugithub/yucon';

class OpenSourceProject {
  const OpenSourceProject({
    required this.name,
    required this.owner,
    required this.license,
    required this.summary,
    required this.url,
    required this.mark,
    required this.color,
  });

  final String name;
  final String owner;
  final String license;
  final String summary;
  final String url;
  final String mark;
  final int color;

  String get displayUrl => url.replaceFirst(RegExp(r'^https://'), '');
}

const kThisProject = OpenSourceProject(
  name: kAppDisplayName,
  owner: 'tianyugithub',
  license: 'MIT',
  summary: '本应用的源代码。独立客户端，用于在手机上管理多个中转站点账号。',
  url: kAppSourceUrl,
  mark: '钥',
  color: 0xFFFA2C19,
);

const kCompatibleGateways = <OpenSourceProject>[
  OpenSourceProject(
    name: 'New API',
    owner: 'QuantumNous',
    license: 'AGPL-3.0',
    summary: '基于 One API 的模型聚合网关。钥仓按其余量、密钥与日志接口进行同步。',
    url: 'https://github.com/QuantumNous/new-api',
    mark: 'N',
    color: 0xFFFA2C19,
  ),
  OpenSourceProject(
    name: 'One API',
    owner: 'songquanpeng',
    license: 'MIT',
    summary: 'New API 的上游项目，提供统一的 OpenAI 兼容接口与令牌管理。',
    url: 'https://github.com/songquanpeng/one-api',
    mark: 'O',
    color: 0xFF3178DF,
  ),
  OpenSourceProject(
    name: 'Sub2API',
    owner: 'Wei-Shaw',
    license: 'LGPL-3.0',
    summary: '将订阅额度转为可调用 API 的开源网关。钥仓按邮箱登录与其余额接口对接。',
    url: 'https://github.com/Wei-Shaw/sub2api',
    mark: 'S',
    color: 0xFF0D9488,
  ),
];

const kBuildFoundation = <OpenSourceProject>[
  OpenSourceProject(
    name: 'Flutter',
    owner: 'flutter',
    license: 'BSD-3-Clause',
    summary: '本应用的跨平台界面框架。',
    url: 'https://github.com/flutter/flutter',
    mark: 'F',
    color: 0xFF0175C2,
  ),
];

const kOpenSourceDisclaimer =
    '钥仓是独立开源客户端，与下列项目及其运营站点均无隶属、合作、投资或担保关系。连接站点时请自行核对其来源，并遵守对应项目的许可证与服务条款。';
