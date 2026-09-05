# Yucon 钥仓

钥仓是运行在手机上的开源客户端，用来集中管理多个 AI 中转站点账号。

每一个账号对应你自己填写的站点。登录状态保存在本机，额度、密钥和调用记录直接向该站点同步，不经过钥仓的服务器。

兼容 [New API](https://github.com/QuantumNous/new-api)、[One API](https://github.com/songquanpeng/one-api)、[Sub2API](https://github.com/Wei-Shaw/sub2api) 以及与之接口一致的自建或第三方站点。钥仓是独立客户端，与上述项目及其运营方无隶属、合作或担保关系。

当前版本 **0.1.2**。[下载安装包](https://github.com/tianyugithub/yucon/releases/latest)

## 功能

**看板**
- 汇总全部账号余额、今日用量和签到进度
- 额度偏低、用尽或需要重新登录时给出状态提醒

**账号**
- 同时管理多个站点，支持用户名密码或系统访问令牌登录
- 同步余额、分组与签到
- 可选 HTTP、HTTPS 或 SOCKS 代理
- 可将个别账号排除出总额度统计

**密钥**
- 查看、创建、停用和删除密钥
- 设置额度、分组和可用模型
- 复制完整 API 调用地址
- 在独立窗口测试对话、Claude、Codex 与图像模型
- 可手动指定探测点，并伪装成 Claude Code / Codex CLI 客户端

**日志**
- 按账号、分组、密钥、模型筛选调用记录
- 查看用量与耗时，可选择显示调用方 IP
- 查看单条调用的请求 ID、渠道与用户名等详情

**数据**
- 登录密码和会话写入系统安全存储
- 加密备份，可在设备之间迁移
- 启动时检查 GitHub 发布，可在「我的」下载新版本

## 使用

1. 打开「账号」，添加站点。
2. 选择 New API、One API 或 Sub2API，填写 `https://` 站点地址。
3. 使用该站点的用户名和密码登录；或粘贴「个人设置 → 安全设置」中的系统访问令牌，并填写同一页上的数字用户 ID。
4. 不要把 `sk-` 开头的模型调用密钥当作登录令牌。
5. 若站点开启了两步验证，请改用系统访问令牌。

密钥的创建、停用和删除会写回对应站点。卸载应用或清除本机数据后，需要重新登录。

## 隐私

账号列表、登录状态和最近一次同步结果只保存在本机。备份文件使用你设定的密码加密。请自行确认所连接站点的来源，并遵守该站点的服务条款。

## 开源与致谢

源码许可证为 [MIT](LICENSE)。应用按下列项目公开的 HTTP 接口工作，不重新分发其源代码。

| 项目 | 许可证 | 说明 |
| --- | --- | --- |
| [Yucon 钥仓](https://github.com/tianyugithub/yucon) | MIT | 本客户端 |
| [New API](https://github.com/QuantumNous/new-api) | AGPL-3.0 | 模型聚合网关 |
| [One API](https://github.com/songquanpeng/one-api) | MIT | New API 的上游项目 |
| [Sub2API](https://github.com/Wei-Shaw/sub2api) | LGPL-3.0 | 订阅转 API 网关 |
| [Flutter](https://github.com/flutter/flutter) | BSD-3-Clause | 跨平台界面框架 |

许可证全文以各仓库为准。

## 许可

[MIT](LICENSE)
