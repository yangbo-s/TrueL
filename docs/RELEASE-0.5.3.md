# 0.5.3 翻译与改写提速发布验收

GOAL-089：将已验收的翻译和改写等待优化发布为补丁版本，使现有用户可下载或通过应用内更新获取。

## 范围、契约与阶段门禁

- REQ-089 / AC-089：源码、标签和安装包均为 0.5.3 / build 17，包含 `80484d0` 与 `b407455`，正常推送至 `origin/main`。
- REQ-090 / AC-090：正式 GitHub Release 包含 arm64 DMG 与 SHA256SUMS；公开下载的字节、摘要及包签名与本地准备产物一致。
- REQ-091 / AC-091：签名 appcast 原样发布；旧 build 能发现 17、build 17 无新版本，篡改 feed 被拒绝。固定凭据组件在两次真实 Sparkle 安装和重启后继续非交互读取隔离测试凭据。
- IN-089：已提交源码、`Config/release.json`、更新记录、既有固定代码签名身份和更新签名配置。版本为 `0.5.3` 字符串，build 为递增数字字符串 `17`；重复已发布 build 会被准备脚本拒绝。
- OUT-089：`build/releases/0.5.3/` 内 DMG、发布说明、SHA256SUMS 与签名 appcast；远端正式标签 `v0.5.3`、Release 及 `main/updates/appcast.xml`。
- CON-089：复用发布脚本、Sparkle、公钥、凭据组件与端点；不调整依赖、权限或用户数据。签名 XML 不手工编辑。
- ASM-089：依照补丁更新惯例，将最新正式版 0.5.2 / 16 递增为 0.5.3 / 17。远端已核实无新提交冲突，初始工作区干净。
- OOS-089：不增加功能，不承诺统计意义上的提速比例，不更换签名方式或执行公证迁移。

ADR-089：直接复用已有正式发布流程。仅上传二进制会遗漏应用内更新，因此依次执行版本验收、源码推送、Release 上传、公开包验证、更新源发布、公开更新验证。任何阶段失败均停止依赖该结果的后续阶段，保留可诊断日志；不覆盖已有版本资产，不强推分支。

MOD-089：版本与更新记录 → `tools/prepare-release.py` → 签名 DMG / appcast；MOD-090：Git / GitHub Release → 公开下载核对；MOD-091：`tools/check-update.swift`、`tools/test-credential-continuity.py` → 更新和凭据回归。均复用现有接口，不新增产品 API。

## 验收矩阵

| 用例 | 需求、层级、优先级 | 输入 / 步骤与预期 | 结果与证据 |
| --- | --- | --- | --- |
| TC-089a | REQ-089，回归，P1 | 运行完整测试、网格与打包契约；复核翻译/改写已验收快照及新版本信息 | 通过：171 项 / 20 套件，10.773 秒；网格通过，打包 3 项、凭据打包 4 项通过；2 张新版本关于页快照通过 |
| TC-089b | REQ-089/090，集成，P1 | 准备发布；挂载 DMG，与构建逐项比较，核对版本和签名 | 通过：0.5.3 / 17；挂载后 195 项一致，代码签名、DMG 与 feed Ed25519 验签通过；`package.log`、`package-metadata.json` |
| TC-090a | REQ-090，验收，P1 | 正常推送源码并建立正式 Release；匿名下载资产，核对摘要和签名 | 通过：正式最新 Release 含 DMG 与 SHA256SUMS，公开下载逐字节一致，摘要与 Ed25519 验签通过，标签指向源码提交；`public-release-check.log`、`public-release.json` |
| TC-091a | REQ-091，集成，P1 | 隔离宿主检查旧版、当前版及被篡改 feed | 通过：build 15、16 均发现 17，17 显示最新，篡改签名被拒绝；`local-update-check.log`、`local-update-results.json` |
| TC-091b | REQ-091，集成，P1 | 固定组件跨两次真实 Sparkle 安装/重启保持可读，拒绝错误调用身份，清理测试凭据 | 通过：`credential-continuity.log`；`artifacts/credential-continuity/truel-credential-continuity-f7t0ky4p/result.json` |
| TC-091c | REQ-091，验收，P1 | 下载公开 feed，检查字节与签名；真实 Sparkle 从公开地址发现 build 17 | 通过：公开 feed 逐字节一致且验签通过；build 15、16 均发现 17，17 显示最新；`public-update-check.log`、`public-update-results.json` |

功能实现与内容限制见[翻译等待优化](TRANSLATION-LATENCY.md)和[改写等待优化](REWRITE-LATENCY.md)。本次仅改变发布元数据，沿用相同功能实现的 16 张浅深色界面验收证据；发布包另行验证版本信息。

主程序的签名之外内容与上一轮已验收的本机版本逐字节一致；版本元数据变化后签名随之改变。新构建的 `about/settings-about-light.png` 与 `about/settings-about-dark.png` 均显示 0.5.3，文字完整、布局无重叠、红绿灯处于激活状态。关于页截图使用独立预览，不调用真实 API。

凭据组件保持 revision 3 / CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`。连续更新验收仅使用隔离测试凭据，测试条目和临时应用已清理。日志中的错误身份拒绝与篡改 feed 失败是预期负向用例。

安装包：`build/releases/0.5.3/TrueL-0.5.3-arm64.dmg`，2,889,887 字节。SHA-256：`4f74493d590b1be270ae6a9684cd4ad25d630a52787ec27c1cff7491b477a7d9`。

本轮证据存放于 `artifacts/release-0.5.3/`，该目录按仓库约定不提交。打包工具出现既有 `hdiutil` 子命令弃用提示，实际创建、挂载、内容检查和卸载均成功。

## 公开交付

源码提交 `40cbc52375e71ec5d287ca58542206622fa9ef89` 已正常推送至 `origin/main`，正式标签 `v0.5.3` 指向该提交。[TrueL 0.5.3](https://github.com/yangbo-s/TrueL/releases/tag/v0.5.3) 为最新正式版，包含 [DMG](https://github.com/yangbo-s/TrueL/releases/download/v0.5.3/TrueL-0.5.3-arm64.dmg) 和 [SHA256SUMS](https://github.com/yangbo-s/TrueL/releases/download/v0.5.3/SHA256SUMS)。公开资产内容、摘要与本地安装包一致。

签名更新源提交 `2a1760d921a1302b3ea52b306a3a5d35a372ce52` 已推送。公开 HTTPS feed 与本地签名文件一致，真实 Sparkle 检查通过。REQ-089～091 / AC-089～091 均通过，无未解决的发布阻塞；没有覆盖、删除历史 Release 或强推分支。

本次未改变日常安装的应用或偏好；它可通过检查更新获取 0.5.3。包仍采用既有固定自签证书和 Sparkle 更新签名。未在第二台干净机器上复核首次安装/系统确认，也未用日常应用执行实际替换；实际安装与重启验证使用隔离 fixture。翻译与改写的速度观测和内容质量限制仍以各自验收文档为准。

## 证据评分

| 项目 | 得分 | 依据、扣分与改进建议 |
| --- | --- | --- |
| 需求与验收覆盖 | 25/25 | 三项发布需求逐项通过，代码、标签、资产、更新源均回读验证 |
| 功能正确性与边界 | 25/25 | 旧版与当前版检测、篡改拒绝、两次实际更新及错误身份拒绝通过 |
| 测试充分性与结果 | 17/20 | 171 项测试、7 项打包测试、16 张既有功能快照及 2 张新版本快照、公开下载和更新检查；扣 3 分：未在独立干净机器上完成正式包升级，可补第二台机器的安装验证 |
| 架构、接口与扩展性 | 10/10 | 完全复用已验收实现和既有发布流程，仅更新版本与发布文档，无新产品接口 |
| 代码质量、安全与维护 | 10/10 | 固定组件不变，源码正常快进推送，签名与完整性验证通过，隔离测试数据已清理 |
| 文档与交付完整性 | 10/10 | 版本、更新记录、追踪矩阵、证据与限制齐全，正式发布、包与更新源已公开 |
| 合计 | **97/100** | 发布验收通过；该评分不代表模型改写质量或速度基准 |
