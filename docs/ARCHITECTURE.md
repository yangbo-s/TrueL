# 架构与数据契约

## 应用图标

`AppIconStyle` 定义六个稳定 ID。`Preferences.appIcon` 以 `TrueL.appIcon` 保存选择，首次启动或未知 ID 使用 3A；预览模式不读写持久化选择。`AppIconController` 同步载入已打包资源并通过 `NSApplication.applicationIconImage` 更新 Dock，重复选择不重复应用，资源异常回退 3A。默认样式使用 nil 恢复 bundle 图标，Finder 与签名内容保持不变。

## 模块

| 模块 | 职责 |
| --- | --- |
| App / PopupSession / NativeSurface | 主浮窗、设置窗口、原生窗口控制和失焦收起 |
| DemoModel / LanguageEngine / LanguageOptions | 编辑状态、取消、语言检测与互换、风格指令和结果解析 |
| ServiceConfiguration | 账号验证、模型目录、按任务保存选择及旧配置迁移 |
| AIClient / AIProvider | 固定服务端点、鉴权、分页目录、文本生成和安全错误信息 |
| CredentialStore / CredentialBrokerClient | 异步调用固定 XPC 凭据组件；测试用内存实现 |
| CredentialCore / TrueLCredentialBroker | 双向认证、串行钥匙串访问与旧条目迁移；普通更新原样保留组件 |
| ShortcutStore / ShortcutMonitor | 组合键与连续按键录制、冲突检查、全局匹配；原生复制/全选透传，其余前缀暂存与失配回放 |
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

OpenAI 翻译通过 `generateTranslation` 使用 SSE，首个正文片段立即显示，后续更新最多每 32 毫秒一次。仅已核实支持的 `gpt-6-luna` 翻译设置 `reasoning_effort: none`。推理字段不显示，完整 `stop` / `[DONE]` 后才允许复制和替换；流中错误或缺失结束标记清除部分译文。每次发布片段和最终结果都检查取消及配置 revision。网络仍复用禁止重定向的临时 URLSession，结束、取消或解析失败会关闭当前任务，且不自动重试。契约与证据见 [翻译等待优化](TRANSLATION-LATENCY.md)。

OpenAI 改写通过 `generateRewrite` 复用 `OpenAITextStream`，已验证的 `gpt-6.1-terra` 使用 `reasoning_effort: low`。提示词要求先生成 `output`，正文字符串完整后由 `RewriteOutputPreview` 解码并提前显示；不预览 JSON、不完整字符串或嵌套同名字段，字段顺序不同则等待最终解析。纠错与提示仍须完整响应通过 `parseGrammar` 后才发布，预览阶段禁止复制和替换，失败清除预览。其他模型和服务商的推理策略不变，非 OpenAI 改写保留完整响应路径。见 [改写等待优化](REWRITE-LATENCY.md)。

## 更新与凭据

生产凭据仅由 `TrueLCredentialBroker.xpc` 访问。主程序验证组件的证书、标识与 CDHash；组件通过 XPC 的调用方签名验证限制为同证书的 TrueL，且仅接受同一用户。组件加入调用方安全会话，并在串行队列设置文件钥匙串的交互策略。

启动、切换服务商及后台目录恢复均异步读取，禁止主动弹出系统授权框。需要授权时，AI 服务页提供「读取已存 Key」入口。旧 `com.truel.provider-api-key` 条目获准读取后，原子插入 `com.truel.credentials.v1` 并读回校验；保留旧条目供回退。新条目存在时不再访问旧条目；并发保存的新 Key 优先于迁移的旧值。取消、超时及 XPC 中断不会退回主程序直接读钥匙串。

组件的源码摘要、签名证书、CDHash 和完整产物摘要由 `Resources/CredentialBroker/manifest.json` 固定。正常构建只复制已有签名产物，绝不重签这个组件；变化必须显式封存新 revision 并重新验证授权迁移。详见 [凭据延续验收](CREDENTIAL-CONTINUITY.md)。

发布元数据集中在 `Config/release.json`。构建写入版本、HTTPS feed URL 和 Ed25519 公钥，保留应用 bundle identifier。Sparkle Framework 由 SwiftPM 固定版本，内层可执行文件先签名，再签 Framework 和应用。

更新源和安装包都使用 Ed25519 签名；私钥留在发布者本机钥匙串。`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 同时启用，安装包在解压前验证；签名失败的更新源始终拒绝。预览和测试启动不创建 Sparkle 控制器，也不读取用户 Key 或系统权限。

## 快速工作流

`PopupSession.presentation` 在同一个 NSPanel 内切换 `quick`（仅结果）与 `workspace`（左右对照）；窗口尺寸分别记忆，设置页仍与工作窗互斥。`returnAction` 是键盘派发与绿色按钮样式的共同来源。普通打开强制 workspace，只有快捷输入进入 quick；快速失焦、关闭及进入设置会结束临时会话并取消未完成请求。原生编辑控件自行处理 IME 与 Shift+Return。

`ShortcutBinding.passesThroughNativeEvents` 将 Command+C 和 Command+A 开头的自定义序列交给同一个非阻塞 matcher，所有原按键立即透传。Command+A,A 的第一下执行原生全选，第二下读取并改写当前全文选区；单次全选不暂存，也不在超时后回放。`startsWithNativeCopy` 仍独立限制剪贴板回退，Command+A 不读取剪贴板兜底。见 [Command+A 延迟验收](SHORTCUT-LATENCY.md)。

全选序列完成后异步给来源应用 50 ms 处理原生事件，再读取选区；该等待不作用于按键透传或单次全选。派发前再次核对来源 PID、暂停状态和 contextRevision；切应用、鼠标点击、配置变更或监听重启均使旧派发失效。

`ShortcutSequenceGate` 暂存其他配置序列的前缀，在匹配时丢弃原事件并触发动作，超时、失配、鼠标点击、切换应用或监听暂停时归还原事件至原进程。回放带内部标记防止再次匹配，不记录输入文本。非复制序列需辅助功能与输入监控权限。快捷键 ID 与 v2 存储保留，`TrueL.shortcuts.quickDefaults.v1` 标记一次性默认值迁移，自定义与禁用不被复原。

## 语言与风格

`TextLanguage` 定义八种语言；自动模式使用本地 NaturalLanguage，置信度不足或短内容保留自动状态。`sourceLanguage` 独立于偏好目标；`resolvedTargetLanguage` 在已知同语言时回退到另一语言。互换要求普通翻译已完成且源语言已知，交换语言并将译文写入原文后重新请求。

`TextStyle` 是设置和浮窗共用的稳定 ID、标题与提示词目录。`TrueL.translationStyle` 与原有 `TrueL.writingScene` 分别保存翻译和改写风格；改写始终保留原语言。重生成使用原文，不叠加处理上一版结果。旧追加指令接口移除。

语言、风格、模型与设置下拉框统一使用 `SettingsMenuButton`，由 `MenuMetrics` 提供对称外边距与箭头槽位。SwiftUI 图标共用 `PopupGlyph` 的 SF Symbols regular/monochrome 渲染，原生菜单使用同库同字重。
