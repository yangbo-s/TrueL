# 0.3.0 发布验收

GOAL-047：让提交、任务模型选择和应用更新形成清晰可靠的日常工作流。

| 需求 / 验收 | 模块与契约 | 验证 |
| --- | --- | --- |
| REQ-047 / AC-047：Return 提交，Shift+Return 换行，输入法确认候选不提交 | EditorView；本地键盘事件，不注册全局 Return | TC-047：原文、换行、空输入、输入法、数字键盘 Enter |
| REQ-048 / AC-048：浮窗选择实际模型，立即保存当前任务选择 | ModelSelection / ModelMenu；仅列已验证账号目录 | TC-048：同系列、多系列、长名称、空目录 |
| REQ-049 / AC-049：翻译与改写分别保存 provider + modelID | ServiceConfiguration → LanguageEngine；旧单模型迁移至两项 | TC-049：迁移、重启、独立请求、失效凭据、过期响应 |
| REQ-050 / AC-050：检查更新、自动检查开关、Ed25519 签名安装包 | Sparkle 官方 SPM 依赖；HTTPS appcast | TC-050：依赖嵌入、代码签名、包签名、更新检查 |
| REQ-051 / AC-051：文档与当前行为一致，README 聚焦产品 | README、使用、开发、发布与验收文档 | TC-051：命令、链接、版本、公开文件审阅 |
| REQ-052 / AC-052：GitHub 源码、版本标签、安装包和更新源可访问 | GitHub main + Releases + updates/appcast.xml | TC-052：发布后读回并校验安装包 SHA-256 |

## 边界与接口

IN-047：AppKit keyDown，Return 36 / Enter 76；Shift 表示换行，marked text 交由输入法处理。OUT-047：提交回调或编辑器换行。

IN-048：模型选择为 `{provider: AIProvider, modelID: String}`；modelID 必须在已验证目录中。例如 `{"provider":"openAI","modelID":"api-returned-id"}`；空串或未返回的 ID 拒绝保存。OUT-048：任务独立持久化，错误保留上次有效配置。Key 仅保存在钥匙串和进程内存。

IF-049：`configuration(for: WorkMode)` 在提交时解析已保存配置。每个任务独立 revision；当前任务变更拒绝旧成功/失败回调，另一个任务及未保存表单编辑不影响当前请求。

IF-050：`SUFeedURL` 指向公开 HTTPS XML，版本号采用单调递增 CFBundleVersion；更新包 URL、Ed25519 签名、字节长度必须一致。私钥保留本机钥匙串。无效签名拒绝安装。

CON-047：Swift 6 / macOS 26 / Apple silicon；保留现有样式、权限身份、单浮窗和用户数据。OOS-047：新服务商、模型名称猜测、权限重置。ASM-047：以 API 目录实际返回为可选模型，服务不可用时保持上次已保存选择。

## 方案

ADR-047：选择共享账号目录 + 按任务保存模型；相比复制两份完整服务设置，避免两套 Key 和验证逻辑。设置草稿与实际请求配置隔离；付出少量目录缓存和迁移状态的复杂度。

ADR-050：使用官方 Sparkle，替代手写下载/替换逻辑。固定依赖版本并嵌入 Framework；保留既有本机代码签名，更新包另用 Ed25519 验证。公开仓库当前为空，发布当前清理后的源码快照，保留本地开发历史。

顺序：键盘 → 配置契约/迁移 → 模型菜单与设置 → Sparkle/打包 → 回归与逐页截图 → 文档与公开文件 → GitHub 发布 → 远程读回。

## 结果

- TC-047：原文 Return / 数字键盘 Enter 提交、Shift 换行、输入法候选、空原文测试通过；隔离应用内实际按键通过。
- TC-048/049：109 项 Swift Testing 回归通过（10 个测试集）。两任务跨系列持久化、旧配置一次迁移、未保存草稿独立、旧响应丢弃及未使用账号目录恢复均有覆盖。实际下拉选择、切换任务及设置显示通过。
- UI：主浮窗全部状态及四页设置的 60 张浅深截图已审阅；长模型 ID、错误和缩放正常。关于页收紧布局后另补拍浅深两张，活动窗口与布局检查通过。网格检查通过。
- TC-050：正式构建与嵌套代码签名通过；安装包挂载后，160 个目录/文件/链接条目完全一致。3 项打包校验回归通过。最终安装包与 appcast 的 Ed25519 签名通过公钥验证。实际 Sparkle 检查能从 build 7 发现 build 8，同版本显示已是最新，篡改更新源被拒绝。
- TC-051：README、使用、架构、开发、发布、产品与设计文档已更新，本地文档链接与差异检查通过。
- TC-052：[GitHub 源码](https://github.com/yangbo-s/TrueL)与 [v0.3.0 安装包](https://github.com/yangbo-s/TrueL/releases/tag/v0.3.0)已发布。公开地址下载的 DMG、SHA256SUMS 与本地产物一致，Ed25519 验证通过；公开 HTTPS feed 与签名原文完全一致，真实 Sparkle 检查的“发现新版”和“已是最新”路径均通过。

首次回归中，一个原有悬停测试受主线程调度影响偶发失败；改为在有界时间内等待关闭状态，保留原最终断言后通过。首次打包的目录 diff 跟随 Framework 链接产生重复遍历提示，已替换为不跟随链接的内容、可执行位与链接目标校验。

Sparkle 首次集成检查发现：启用签名 feed 但缺少 `SUVerifyUpdateBeforeExtraction` 会导致启动失败。补齐解压前验证配置后，使用最终构建的 Info.plist 重新运行更新检查通过；最终 DMG 在此修正之后重新生成并签名。

## 界面证据

下列为本次本地验收截图，`*-light.png` 和 `*-dark.png` 均已检查。截图目录保留在本机 `artifacts/release-0.3.0/`。

| 页面 | 观察与文件 |
| --- | --- |
| 主浮窗输入 | 模型名称与动作位于同一工具栏，空输入与处理中保持对齐。`screenshots/popup-input-*`、`popup-empty-*`、`popup-processing-*` |
| 翻译与改写结果 | 译文、修改标记和后续输入正常；长内容及调整尺寸没有遮挡。`screenshots/popup-translation-*`、`popup-result-*`、`popup-long-*`、`popup-resized-*` |
| 通用 | 权限行与开关对齐，浅深外观可读。`screenshots/settings-general-*` |
| AI 服务 | Key 与模型区域分离，两任务的模型、保存按钮对齐；长 ID 截断而不挤压按钮。`screenshots/settings-service-*`、`settings-long-model-*`、`settings-service-error-*` |
| 快捷键 | 录制、错误提示与正常行保持紧凑布局。`screenshots/settings-shortcuts-*`、`settings-recording-*`、`settings-shortcut-error-*` |
| 关于 | 品牌、版本、更新开关与隐私内容完整显示，无底部裁切或多余滚动条。最终采用 `about-approved/settings-about-*` |

## 交付与限制

安装包为 `TrueL-0.3.0-arm64.dmg`，大小 1,650,768 字节，SHA-256：

```text
68b95f62a1bbafa01419c5abcff1a289b8fcd82793b9176f338a1b9d2ad09e5c
```

更新源为 `https://raw.githubusercontent.com/yangbo-s/TrueL/main/updates/appcast.xml`。本地证据包括 `tests.log`、`release-tests.log`、`final-build.log`、`final-package.log`、`signature-tests.log`、`local-update-check.log`、`tampered-update-check.log`、`public-release-check.log` 和 `public-update-check.log`，均位于 `artifacts/release-0.3.0/`。

实测使用模拟服务端响应验证真实请求构造和路由；本轮未使用用户的七家真实 Key 逐一付费调用。更新检查、包验证和安装包挂载通过，未执行 Sparkle 替换正在使用的应用并重启的完整安装流程。自签版本的钥匙串授权延续不作保证。现有 0.2.x 版本需要先手动安装本次 DMG，此后的版本可以通过应用内检查更新。

## 证据评分：95 / 100

| 项目 | 分数 | 依据与改进 |
| --- | --- | --- |
| 需求与验收覆盖 | 25 / 25 | REQ-047 至 REQ-052 均有实现、验证与交付 |
| 功能正确性与边界 | 25 / 25 | 输入法、空输入、两任务配置隔离、迁移、旧响应及更新签名失败路径通过 |
| 测试充分性 | 15 / 20 | 109 项应用测试、3 项打包测试、界面与实际更新检查通过；未实测七家付费 API 扣 2 分，未实测完整自动安装重启扣 3 分，可在独立测试账号和安装环境补测 |
| 架构与接口 | 10 / 10 | 任务模型契约独立，账号目录共享，使用官方固定版 Sparkle |
| 代码与安全 | 10 / 10 | 固定代码签名、公钥验证、篡改拒绝、私钥和 API Key 不进入公开仓库 |
| 文档与交付 | 10 / 10 | 使用、开发、发布与验收文档齐全，公开下载和更新源已读回校验 |
