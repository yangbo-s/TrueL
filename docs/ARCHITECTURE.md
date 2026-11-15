# 架构与数据契约

## 应用图标

`AppIconStyle` 定义六个稳定 ID。`Preferences.appIcon` 以 `TrueL.appIcon` 保存选择，首次启动或未知 ID 使用 3A；预览模式不读写持久化选择。`AppIconController` 同步载入已打包资源并通过 `NSApplication.applicationIconImage` 更新 Dock，重复选择不重复应用，资源异常回退 3A。默认样式使用 nil 恢复 bundle 图标，Finder 与签名内容保持不变。

## 模块

| 模块 | 职责 |
| --- | --- |
| App / NativeSurface | 主浮窗、设置窗口、原生窗口控制和失焦收起 |
| DemoModel / LanguageEngine | 编辑状态、取消、翻译和改写请求、结果解析 |
| ServiceConfiguration | 账号验证、模型目录、按任务保存选择及旧配置迁移 |
| AIClient / AIProvider | 固定服务端点、鉴权、分页目录、文本生成和安全错误信息 |
| CredentialStore | macOS 钥匙串 API Key；测试用内存实现 |
| ShortcutStore / ShortcutMonitor | 组合键与连续按键录制、冲突检查、全局匹配 |
| SelectionBridge / SelectionReplacementContext | 获取选区、来源有效性和安全替换 |
| AppUpdater | Sparkle 控制器、更新菜单与自动检查偏好 |
| Snapshot / PreviewAIClient | 内存配置、模拟响应和逐页窗口截图 |

## 模型选择

`ModelSelection` 为 `{provider, modelID}`。`provider` 是内置七种系列的稳定 rawValue，`modelID` 为目录中的实际 ID。偏好 `TrueL.ai.taskModels.v1` 按 `translation` / `grammar` 保存 JSON；Key 不进入偏好文件。

旧 `TrueL.ai.selectedProvider` + `TrueL.ai.savedModels` 在首次迁移时复制到两项任务。之后即使任务留空，也不会重复恢复旧值。已配置账号记录在 `TrueL.ai.configuredProviders`，启动时载入其目录；GLM 恢复时复用保存验证，避免后台推理请求。

`configuration(for:)` 在提交时返回 provider、modelID、内存中的已验证 Key。无有效选择时抛出 `ServiceConfigurationError.notReady`。设置中的 Key/模型草稿不会改变已保存请求；成功替换 Key 后，需要重新确认受影响任务的模型。

每项任务独立维护配置 revision。模型选择变化后，旧请求的结果与错误都被拒绝；切换另一项任务的模型不影响当前请求。界面取消是即时反馈，LanguageEngine 在响应边界再次检查 revision 和取消状态。

## 网络边界

端点固定在 `AIProvider`。模型 ID 限定 200 个字符以内，允许字母、数字、连字符、下划线、点和冒号。目录请求超时 30 秒，生成请求 120 秒。失败通过 `AIClientError` 转换成固定消息，服务商响应正文不进入用户错误提示。

目录可分页，最多 50 页；重复页 token 和无效响应被拒绝。服务端 401、403、429、超时、内容拦截、截断及空响应均有独立错误。

## 更新与凭据

发布元数据集中在 `Config/release.json`。构建写入版本、HTTPS feed URL 和 Ed25519 公钥，保留应用 bundle identifier。Sparkle Framework 由 SwiftPM 固定版本，内层可执行文件先签名，再签 Framework 和应用。

更新源和安装包都使用 Ed25519 签名；私钥留在发布者本机钥匙串。`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 同时启用，安装包在解压前验证；签名失败的更新源始终拒绝。预览和测试启动不创建 Sparkle 控制器，也不读取用户 Key 或系统权限。
