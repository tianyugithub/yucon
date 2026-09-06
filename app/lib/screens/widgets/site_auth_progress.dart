import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vault/app/identity/site_register_flow.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class SiteAuthProgressScrim extends StatelessWidget {
  const SiteAuthProgressScrim({
    super.key,
    required this.title,
    required this.steps,
    required this.current,
    required this.detail,
    this.error,
    this.onRetry,
    this.onDismiss,
  });

  final String title;
  final List<(SiteRegisterStage, String, String)> steps;
  final SiteRegisterStage? current;
  final String detail;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    final currentIndex = steps.indexWhere((item) => item.$1 == current);
    final allDone = current == SiteRegisterStage.done && !failed;
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.82);

    return Positioned.fill(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && failed) {
            onDismiss?.call();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Material(
                          color: cardColor,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      failed
                                          ? Icons.error_outline
                                          : Icons.bolt_rounded,
                                      size: 18,
                                      color: failed
                                          ? const Color(0xFFBE2630)
                                          : ThemeDefine.kColorPrimary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        failed ? '$title中断' : title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (var i = 0; i < steps.length; i++)
                                  _stepRow(
                                    steps[i],
                                    i,
                                    currentIndex,
                                    allDone,
                                    failed,
                                  ),
                                if (failed && error!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0x14BE2630),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      error!.trim(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.45,
                                        color: Color(0xFFBE2630),
                                      ),
                                    ),
                                  ),
                                ],
                                if (failed) ...[
                                  const SizedBox(height: 14),
                                  PrimaryButton(
                                    label: '重试',
                                    onPressed: onRetry,
                                  ),
                                  const SizedBox(height: 8),
                                  PrimaryButton(
                                    label: '关闭',
                                    outlined: true,
                                    onPressed: onDismiss,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(
    (SiteRegisterStage, String, String) step,
    int index,
    int currentIndex,
    bool allDone,
    bool failed,
  ) {
    final title = step.$2;
    final subtitle = step.$3;
    final done = allDone || (currentIndex > index);
    final active = !allDone && currentIndex == index;
    final errorHere = failed && active;
    final line = errorHere ? '' : (active ? detail : '');
    final titleColor = errorHere
        ? const Color(0xFFBE2630)
        : (done || active ? null : ThemeDefine.kColorText);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: errorHere
                ? const Icon(Icons.cancel, size: 20, color: Color(0xFFBE2630))
                : done
                ? Icon(
                    Icons.check_circle,
                    size: 20,
                    color: ThemeDefine.kColorGreenBright,
                  )
                : active
                ? const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.radio_button_unchecked,
                    size: 18,
                    color: ThemeDefine.kColorText,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: done || active
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: titleColor,
                  ),
                ),
                if (line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeDefine.kColorPrimary,
                        height: 1.35,
                      ),
                    ),
                  )
                else if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeDefine.kColorText,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const siteLoginProgressSteps = <(SiteRegisterStage, String, String)>[
  (SiteRegisterStage.checking, '检查站点设置', '读取人机验证等公开配置'),
  (SiteRegisterStage.captcha, '过站点人机验证', '由验证码服务代解 Cloudflare Turnstile'),
  (SiteRegisterStage.submitting, '提交登录', '用账号和密码调用站点登录接口'),
];

const siteRegisterProgressSteps = <(SiteRegisterStage, String, String)>[
  (SiteRegisterStage.checking, '检查站点设置', '读取注册开关、邮箱后缀与人机验证配置'),
  (SiteRegisterStage.captcha, '过站点人机验证', '由验证码服务代解 Cloudflare Turnstile'),
  (SiteRegisterStage.sendingCode, '请求发送验证码', '调用站点接口向邮箱发送验证码'),
  (SiteRegisterStage.waitingMail, '填写邮箱验证码', '在邮箱里查看后填入，继续完成注册'),
  (SiteRegisterStage.submitting, '提交注册并登录', '带验证码调用注册接口，返回凭证即登录'),
];
