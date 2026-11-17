# 0.5.5 翻译格式修复安装包验收

GOAL-110：交付包含翻译格式修复 `a628fda` 的 0.5.5 / build 19 安装包。

## 范围与契约

- REQ-110 / AC-110：源码与包内版本均为 0.5.5 / 19，保留已验收的翻译代码和固定凭据组件。
- REQ-111 / AC-111：生成可挂载的 arm64 DMG、发布说明、SHA256SUMS 和签名 appcast；安装包和更新源的签名通过验证。
- REQ-112 / AC-112：沿用仓库发布链路，核验旧 build 发现 19、19 无更新，以及篡改 feed 拒绝；交付状态分别记录本地产物和公开入口。
- REQ-113 / AC-113：正式 GitHub Release 提供 0.5.5 DMG 与摘要；签名更新源原样发布，公开下载和正式更新地址回读验证。
- IN-110：已验收并提交的修复、递增版本配置、固定代码签名和更新公钥。
- OUT-110：`build/releases/0.5.5/TrueL-0.5.5-arm64.dmg`、`SHA256SUMS`、发布说明和 `appcast.xml`；包内应用为 macOS 26+、arm64。
- CON-110：复用现有构建、签名、打包和更新工具，不改翻译实现或依赖；不覆盖历史版本产物，不重签固定凭据组件。

ADR-110：已发布的 0.5.4 / 18 不应被同版本新二进制替换；使用递增补丁版本与 build，沿用签名 DMG 和更新契约。先完成本地包验证，再处理外部发布步骤；公开下载与应用内更新分别回读。

## 验收矩阵

| 用例 | 关联 | 验证 | 状态 |
| --- | --- | --- | --- |
| TC-110 | REQ-110 | 复用修复阶段 187 项回归与实机翻译验收；核对新版本元数据和源码差异 | 通过：0.5.5 / 19；去除签名后的主程序与已验收修复版逐字节一致；浅深色关于页均显示 0.5.5 |
| TC-111 | REQ-111 | 打包/凭据打包测试，DMG 挂载、195 项内容比较、代码签名与更新签名校验 | 通过：打包 3 项、凭据打包 4 项；挂载内容一致，DMG 和 feed Ed25519 验签通过 |
| TC-112 | REQ-112 | 隔离 Sparkle 宿主检查旧版、当前版和篡改 feed；凭据跨升级回归 | 通过：18 发现 19、19 无更新、篡改 feed 被拒绝；两次实际安装及重启后测试凭据无需交互读取 |
| TC-113 | REQ-113 | GitHub Release 公开下载、签名 feed 与真实 Sparkle 检查 | 通过：正式 Release 下载逐字节一致；正式地址普通/压缩响应均为 19；真实 Sparkle 与日常应用更新窗口均发现 0.5.5 |

功能证据见 [翻译格式修复](TRANSLATION-OUTPUT.md)。本阶段只修改版本、更新记录和交付文档。日志与生成证据保存在 `artifacts/release-0.5.5/`，不纳入 Git。

## 交付与评分

本地安装包已完成：`build/releases/0.5.5/TrueL-0.5.5-arm64.dmg`，2,896,608 字节。SHA-256：`567a681bb2031ba7585f168dcf2825616adfeeb4b7b182884bb029bb8fc2be5a`。

`package-metadata.json` 核对包内版本及已验收二进制；`package.log` 记录构建、挂载、内容与签名检查。版本截图在 `about/`，两种外观的 0.5.5 版本清晰完整。`local-update-check.log` 和 `local-update-results.json` 记录真实 Sparkle 的三项本地检查；其中篡改 feed 返回签名错误为预期负向用例。

固定凭据组件保持 revision 3 / CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`。凭据回归通过，临时应用、测试密钥和测试条目已清理；证据见 `artifacts/credential-continuity/truel-credential-continuity-811txjca/`。hdiutil 出现现有子命令弃用提示，创建、挂载、验证和卸载均通过。

## 公开发布

用户明确授权推送 `main` 并完成发布后，源码提交 `4210afb4de4ab63ca351206329394097a91be180` 已正常快进推送至 `origin/main`，包含翻译修复 `a628fda`。正式标签 `v0.5.5` 指向同一提交，连接器回读验证通过。此前直接推送被自动审批拒绝，原因是缺少针对共享默认分支的明确授权；取得用户授权后使用原命令正常推送，未绕过审批或强推。

[TrueL 0.5.5](https://github.com/yangbo-s/TrueL/releases/tag/v0.5.5) 已正式发布，提供 [arm64 DMG](https://github.com/yangbo-s/TrueL/releases/download/v0.5.5/TrueL-0.5.5-arm64.dmg) 与 [SHA256SUMS](https://github.com/yangbo-s/TrueL/releases/download/v0.5.5/SHA256SUMS)。公开下载字节、摘要和 Ed25519 签名均验证通过，见 `public-release-check.log` 与 `public-release.json`。

签名 appcast 原样复制后提交为 `3821c89` 并推送 main。初次公开检查中普通响应已为 19、压缩响应仍为 18，实际 Sparkle 也未发现更新；保留 `appcast-compressed-headers-initial.txt`、`public-feed-results-initial.json`、旧压缩响应及 `public-update-initial.log`。响应头为 `Cache-Control: max-age=300` 和 `Vary: Authorization,Accept-Encoding`，确认发布后存在压缩 CDN 缓存传播延迟。

2026-11-16 23:39:27（America/New_York），正式原地址的普通与压缩响应均刷新为 19，并与本地签名 feed 逐字节一致。随后真实 Sparkle 验证 build 18 发现 19、19 显示最新，见 `public-update-check.log`、`public-update-results.json`。日常 `/Applications/TrueL.app` 的「检查更新…」窗口显示 “TrueL 0.5.5 is now available—you have 0.5.4”，展示本次翻译格式修复说明及 Install Update 按钮；已保留窗口供用户选择安装，未改变自动下载设置。

REQ-110～113 / AC-110～113 均通过。没有覆盖历史安装包或强推分支；未在第二台干净机器上安装本次正式包，日常应用未替换为 0.5.5，真实安装与重启回归使用隔离 fixture。翻译本身的模型与格式覆盖限制见功能验收记录。

## 证据评分：96 / 100

| 维度 | 得分 | 证据、扣分与后续验证 |
| --- | --- | --- |
| 需求与验收覆盖 | 25 / 25 | 版本、源码标签、正式下载、签名 feed 和真实更新入口均回读 |
| 正确性与边界 | 24 / 25 | 元数据、签名、篡改拒绝、旧/当前版更新及凭据延续通过；翻译结构识别边界沿用功能验收限制 |
| 测试充分性 | 17 / 20 | 复用 187 项功能回归并比对二进制，7 项打包测试、两种外观截图、两次真实升级及公开更新验证；未在第二台干净机器安装正式包 |
| 架构与接口 | 10 / 10 | 复用既有工具与固定凭据组件，无接口或依赖变化 |
| 代码与安全 | 10 / 10 | 不强推、不覆盖历史资产；签名与公钥保持，隔离测试资源清理；审批拒绝后取得明确授权 |
| 文档与交付 | 10 / 10 | 安装包、摘要、发布说明、签名更新源、失败与恢复证据完整，正式下载和应用内更新可用 |
