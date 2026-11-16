# 0.3.2 发布验收

GOAL-064：将固定凭据组件修复发布到 GitHub main、正式 Release 和 Sparkle 更新源。

| 需求 / 验收 | 输入、输出与约束 | 验证 |
| --- | --- | --- |
| REQ-064 / AC-064：已验收修复进入 main | 基于 a7b637b；只快进推送，保留其他提交 | TC-064：远程提交 SHA 读回 |
| REQ-065 / AC-065：正式 v0.3.2 提供安装包与校验文件 | 0.3.2、build 10、arm64；复用已验收的 DMG、固定组件及既有公钥 | TC-065：公开下载字节、SHA-256、Ed25519 与 Release 状态 |
| REQ-066 / AC-066：0.3.1 可发现新版，当前版显示最新，篡改 feed 拒绝 | 先发布可下载附件，再发布签名更新源 | TC-066：实际 Sparkle 检查与公开 feed 读回 |

功能验收沿用 [CREDENTIAL-CONTINUITY.md](CREDENTIAL-CONTINUITY.md)：128 项 Swift 测试、7 项打包检查、四张迁移状态截图，以及隔离应用连续两次真实 Sparkle 安装/重启后的非交互凭据读取均通过。不重新编译或重签固定凭据组件，不修改用户 Key 和系统权限。

发布顺序：核对远程版本 → 签名已验收安装包的更新源 → 提交并推送源码 → 创建正式 Release 与上传附件 → 下载验证 → 推送签名更新源 → 从公开源验证真实更新检查。

## 发布证据

验收日期：2026-11-15（America/New_York）。证据目录：`artifacts/release-0.3.2/`。

| 用例 | 结果与证据 |
| --- | --- |
| TC-064 / AC-064 | 通过。源码提交 `c9635e859fb32e1e9f84c9452501f74e0a5a31c8` 已快进推送到 `main`，`v0.3.2` 指向该提交。签名更新源提交为 `47f7cbca2f392275d96a26cab053283e170fcc27`；远程分支和标签均已读回核对。 |
| TC-065 / AC-065 | 通过。[正式 Release](https://github.com/yangbo-s/TrueL/releases/tag/v0.3.2) 为 latest，非草稿、非预发布，包含 DMG 和 `SHA256SUMS`。匿名下载的两个附件与本地产物逐字节一致，DMG Ed25519 公钥验签通过。见 `github-release.json` 与 `public-release-check.log`。 |
| TC-066 / AC-066 | 通过。[公开更新源](https://raw.githubusercontent.com/yangbo-s/TrueL/main/updates/appcast.xml) 与已签名源文件逐字节一致，公钥验签通过。真实 Sparkle 读取到 build 10、9、8：build 9 找到 10，build 10 显示当前已是最新；本地篡改 feed 被拒绝。见 `public-update-check.log`、`public-update-results.json` 和 `local-update-check.log`。 |

公开 feed 刚发布时曾返回缓存中的 build 9、8；等待缓存刷新后，使用未修改的正式 feed URL 再次检查，两项真实 Sparkle 检查均通过。未通过修改客户端地址或放宽签名校验规避该检查。

安装包：[TrueL-0.3.2-arm64.dmg](https://github.com/yangbo-s/TrueL/releases/download/v0.3.2/TrueL-0.3.2-arm64.dmg)，2,843,343 字节，SHA-256：

```text
72d65f7c4225259e3c63ad156cd6e803782ab74857f26625af0c960df32c9ff4
```

本轮复用已通过两次真实隔离更新验收的安装包，没有重签固定凭据组件，也没有替换用户日常使用的应用或读取真实 API Key。公开源验证覆盖更新发现和签名检查；安装与重启连续性证据见凭据验收报告。旧 Key 首次迁移仍可能需要用户在「AI 服务 → 读取已存 Key」确认一次；最低支持系统 macOS 26 未另行上机测试。

## 证据评分：96 / 100

沿用 [凭据修复验收的六维评分](CREDENTIAL-CONTINUITY.md#证据评分96--100)：需求与验收覆盖 24/25、功能正确性与边界 25/25、测试充分性 18/20、架构与接口 10/10、代码安全与维护 9/10、文档与交付 10/10。本次三个发布验收项均已通过；保留首次真实用户条目迁移、macOS 26 上机验证及自签钥匙串 API 维护边界的扣分。
