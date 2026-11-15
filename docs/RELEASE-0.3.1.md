# 0.3.1 发布验收

GOAL-056：将六款图标选择发布为可下载、可由 Sparkle 检查更新的正式版本。

| 需求 / 验收 | 输入、输出与约束 | 验证 |
| --- | --- | --- |
| REQ-056 / AC-056：已验收源码进入 GitHub main | 基于 f96ba07；只快进推送，不覆盖其他提交 | TC-056：远程 main 读回 |
| REQ-057 / AC-057：v0.3.1 正式 Release 提供安装包及校验文件 | version 0.3.1、build 9、macOS 26+、arm64；复用固定签名身份与既有更新公钥 | TC-057：DMG 挂载、签名、175 项 bundle 内容、公开下载 SHA-256 |
| REQ-058 / AC-058：0.3.0 可发现 0.3.1，当前版显示最新，篡改签名被拒绝 | 签名 appcast 指向可下载的版本资产；先发布资产，再更新 feed | TC-058：公钥验证与真实 Sparkle 检查 |

沿用当前发布脚本、GitHub Releases 和 Sparkle；仅发布已经验收的图标功能，不调整代码签名身份、权限和用户数据。安装流程保持由用户发起，不替换正在使用的应用。

## 已有功能证据

图标功能与视觉验收见 [ICON-CHOICE.md](ICON-CHOICE.md)：115 项应用测试通过，62 张完整状态矩阵与 14 张图标专项截图已检查，六款图标默认 3A，选择保存与恢复通过。

## 发布验证

- TC-056：图标功能提交 `f96ba07d7ed9734fb860d763dba3179b9fc19868` 已快进推送到 main，远程 SHA 读回一致。`v0.3.1` 指向该提交；更新源在 `f8cff60` 发布。
- TC-057：3 项打包回归通过；DMG 校验、挂载后的固定签名、175 项 bundle 内容一致性均通过。GitHub Release 为正式版并设为 latest；公开下载的 DMG 和 SHA256SUMS 与本地发布文件逐字节一致，Ed25519 签名通过。
- TC-058：签名 feed 保留 build 8，新增 build 9。公开 HTTPS 地址读回内容与签名原文逐字节一致。真实 Sparkle 对公开 feed 检查：旧 build 8 发现 build 9，当前 build 9 显示已是最新。隔离本地篡改 feed 被拒绝。

发布证据保存在 `artifacts/release-0.3.1/`。最终产物位于 `build/releases/0.3.1/`。

## 交付

- [源码](https://github.com/yangbo-s/TrueL)与 [v0.3.1 Release](https://github.com/yangbo-s/TrueL/releases/tag/v0.3.1)。
- [TrueL-0.3.1-arm64.dmg](https://github.com/yangbo-s/TrueL/releases/download/v0.3.1/TrueL-0.3.1-arm64.dmg)，2,781,254 字节。
- [SHA256SUMS](https://github.com/yangbo-s/TrueL/releases/download/v0.3.1/SHA256SUMS)。
- [Sparkle 更新源](https://raw.githubusercontent.com/yangbo-s/TrueL/main/updates/appcast.xml)。

安装包 SHA-256：

```text
5ca2e7eddc95f39637dd9a6548f816f40c4773b5baaf8ebc9f5278fadbbcc112
```

本地日志：`prepare-release.log`、`release-tests.log`、`local-update-results.json`、`public-release-check.log`、`public-update-check.log`。准备发布复用了本机已有 Sparkle 签名密钥，未调整其访问权限或应用签名身份。

## 边界与证据评分：97 / 100

本轮验证了更新发现、包校验与 feed 验证，没有执行 Sparkle 对日常使用应用的实际替换和重启。图标本身的视觉与交互验收边界沿用 [ICON-CHOICE.md](ICON-CHOICE.md)；本评分针对发布链路。

| 项目 | 分数 | 证据 |
| --- | --- | --- |
| 需求与验收覆盖 | 25 / 25 | main、正式 Release、公开安装包与更新源全部读回 |
| 功能正确性与边界 | 25 / 25 | 版本递增、两个版本共存、当前版与旧版检查、篡改拒绝 |
| 测试充分性 | 17 / 20 | 3 项打包测试与真实更新器检查通过；未做安装替换/重启，扣 3 分 |
| 架构与接口 | 10 / 10 | 沿用现有 GitHub/Sparkle 发布契约与固定公钥 |
| 代码与安全 | 10 / 10 | 固定身份、先发布资产再启用 feed、公开下载签名与哈希一致 |
| 文档与交付 | 10 / 10 | 发布说明、使用文档、校验文件与验收日志齐全 |
