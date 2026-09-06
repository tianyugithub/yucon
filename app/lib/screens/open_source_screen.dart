import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vault/app/constants/open_source.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class OpenSourceScreen extends StatelessWidget {
  const OpenSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      child: Scaffold(
        appBar: const YuconAppBar(
          title: '开源与致谢',
          subtitle: '本软件、兼容网关与许可证',
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 28),
          children: [
            const TipBanner(text: kOpenSourceDisclaimer),
            const SectionTitle(text: '本软件'),
            _ProjectCard(project: kThisProject, badge: 'v$kAppVersion'),
            const SectionTitle(text: '兼容的开源网关'),
            const Padding(
              padding: EdgeInsets.fromLTRB(1, 0, 1, 10),
              child: Text(
                '钥仓按下列项目公开的 HTTP 接口同步额度、密钥与日志。站点由你自行填写，不代表官方实例。',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.5),
              ),
            ),
            for (final project in kCompatibleGateways) _ProjectCard(project: project),
            const SectionTitle(text: '构建基础'),
            for (final project in kBuildFoundation) _ProjectCard(project: project),
            const Padding(
              padding: EdgeInsets.fromLTRB(1, 8, 1, 0),
              child: Text(
                '许可证全文以各仓库为准。钥仓只分发本客户端，不重新分发上述网关的源代码。点按条目可打开对应仓库。',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, this.badge});

  final OpenSourceProject project;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return YuconCard(
      onTap: () => openOpenSourceProject(context, project),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: project.iconAsset == null
                    ? SquareIcon(
                        size: 32,
                        radius: 9,
                        color: Color(project.color),
                        child: Text(
                          project.mark,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Image.asset(
                        project.iconAsset!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      project.owner,
                      style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: project.license,
                color: const Color(0xFF69707C),
                background: const Color(0xFFF1F3F6),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            project.summary,
            style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (badge != null) ...[
                Text(
                  badge!,
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('·', style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  project.displayUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ThemeDefine.kColorPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new, size: 14, color: ThemeDefine.kColorPrimary),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openOpenSourceProject(BuildContext context, OpenSourceProject project) async {
  final store = context.read<VaultStore>();
  final uri = Uri.parse(project.url);
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened) {
      return;
    }
  } catch (_) {}
  await Clipboard.setData(ClipboardData(text: project.url));
  store.notify('无法打开浏览器，已复制项目地址', FeedbackType.text);
}
