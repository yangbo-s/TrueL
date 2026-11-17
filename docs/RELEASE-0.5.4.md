# 0.5.4 Command+A 即时全选发布验收

GOAL-095：将已验收的 Command+A 延迟修复直接推送至 main，并发布可下载、可通过应用内更新获取的新安装包。

## 范围、契约与阶段门禁

- REQ-095 / AC-095：源码、标签和安装包均为 0.5.4 / build 18，包含修复提交 `1404f9b`，正常快进推送至 `origin/main`。
- REQ-096 / AC-096：正式 GitHub Release 含 arm64 DMG 与 SHA256SUMS；公开下载字节、摘要和更新签名与本地准备产物一致。
- REQ-097 / AC-097：签名 appcast 原样发布；旧 build 发现 18、18 无新版本，篡改 feed 被拒绝；固定凭据组件通过两次实际 Sparkle 安装及重启回归。
- IN-095：已提交修复、`Config/release.json`、更新记录、现有代码签名身份和更新签名配置。版本为字符串 `0.5.4`，build 为递增数字字符串 `18`；重复已发布 build 被准备脚本拒绝。
- OUT-095：`build/releases/0.5.4/` 中 DMG、发布说明、SHA256SUMS 和签名 appcast；远端标签 `v0.5.4`、正式 Release 及 `main/updates/appcast.xml`。
- CON-095：复用发布脚本、Sparkle、公钥、固定凭据组件与端点；不改变用户数据、权限或依赖，不手工修改签名 XML。
- ASM-095：用户明确要求直推 main 并发布新包；已核实最新正式版为 0.5.3 / 17，远端 main 与本地修复无分叉。
- OOS-095：不添加功能、不更换签名方式或执行公证迁移；Jump 网络和来源应用自身卡顿不属于本次修复范围。

ADR-095：复用既有发布流程，依次完成版本验收、源码直推、Release 上传、公开安装包核对、更新源发布及公开更新检查。仅上传安装包会遗漏应用内更新；覆盖旧版本会破坏版本与签名追踪，因此采用递增补丁版本。阶段失败时停止依赖该结果的步骤，保留日志；不强推或覆盖历史发布资产。

MOD-095：版本与更新记录 → `tools/prepare-release.py` → 签名 DMG / appcast。MOD-096：Git / GitHub Release → 公开下载核对。MOD-097：`tools/check-update.swift`、`tools/test-credential-continuity.py` → 真实更新与凭据回归。输入输出契约复用既有实现，不新增产品接口。

## 验收矩阵

| 用例 | 需求、层级、优先级 | 输入 / 步骤与预期 | 结果与证据 |
| --- | --- | --- | --- |
| TC-095a | REQ-095 / 回归 / P1 | 完整测试、网格、打包契约；核对版本及浅深色关于页 | 通过：177 项 / 20 套件，10.679 秒；网格通过，打包 3 项及凭据打包 4 项通过；关于页浅深色快照通过 |
| TC-095b | REQ-095、096 / 集成 / P1 | 构建签名安装包、挂载检查内容及签名，DMG 与 feed 验签 | 通过：0.5.4 / 18；挂载后 195 项一致，固定代码签名、DMG 与 feed Ed25519 验签通过；`package.log`、`package-metadata.json` |
| TC-096 | REQ-096 / 发布验收 / P1 | 正常直推 main，建立正式 Release，公开下载并比较字节与摘要，核对标签 | 通过：正式最新 Release 含 DMG 与 SHA256SUMS；公开下载逐字节一致，摘要及 Ed25519 验签通过；标签与源码提交一致；`public-release-check.log`、`public-release.json` |
| TC-097a | REQ-097 / 集成 / P1 | 隔离宿主检测旧 build、当前 build 及被篡改的本地 feed | 通过：build 16、17 发现 18，18 显示最新，篡改 feed 被拒绝；`local-update-check.log`、`local-update-results.json` |
| TC-097b | REQ-097 / 集成 / P1 | 固定组件跨两次实际 Sparkle 安装、重启读取隔离测试凭据；拒绝错误身份 | 通过：`credential-continuity.log`；`artifacts/credential-continuity/truel-credential-continuity-hc4kvcv4/result.json` |
| TC-097c | REQ-097 / 发布验收 / P1 | 公开 feed 字节与签名核对；真实 Sparkle 从公开地址发现 build 18 | 待执行 |

功能验收见 [Command+A 延迟修复](SHORTCUT-LATENCY.md)：177 项测试、10 轮双 A 捕获与完整替换、本机安装后 3 次单次全选已通过。本轮只调整发布元数据，复用其功能证据；补测新版本关于页和发布链路。

新构建主程序的签名之外内容与上一阶段已验收的本机修复逐字节一致，只有版本元数据及相应签名改变。`about/settings-about-light.png` 和 `about/settings-about-dark.png` 均显示 0.5.4，文字清晰完整、无重叠或裁切，窗口处于激活状态；快照仅使用内存设置和模拟 API。

凭据组件保持 revision 3 / CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`。凭据回归的临时应用、签名测试密钥和测试条目已清理；日志中的错误身份拒绝和篡改 feed 失败是预期负向用例。

安装包：`build/releases/0.5.4/TrueL-0.5.4-arm64.dmg`，2,890,214 字节。SHA-256：`92fac7fb892c6a67b856b4dd571719a95ded673620d802216daba1e16963cc72`。

本轮证据目录为 `artifacts/release-0.5.4/`（不提交）。打包工具出现既有 hdiutil 子命令弃用提示，实际创建、挂载、内容检查及卸载均通过。公开交付记录、限制与最终 100 分制证据评分在实际验证后补齐。

## 公开交付

源码提交 `8e5a1a615abcf3421c01e3d1f131c0c0a21f9373` 已正常直推 `origin/main`，正式标签 `v0.5.4` 指向同一提交。[TrueL 0.5.4](https://github.com/yangbo-s/TrueL/releases/tag/v0.5.4) 为最新正式版，包含 [DMG](https://github.com/yangbo-s/TrueL/releases/download/v0.5.4/TrueL-0.5.4-arm64.dmg) 与 [SHA256SUMS](https://github.com/yangbo-s/TrueL/releases/download/v0.5.4/SHA256SUMS)。公开下载的字节、摘要和更新签名已验证。

签名 appcast 已原样复制到 `updates/appcast.xml`，待推送后验证公开更新链路。
