# 翻译等待优化

本记录对应翻译优化阶段（80484d0）。后续改写提速及共享流模块的更新见 [改写等待优化](REWRITE-LATENCY.md)。

## 目标与边界

- GOAL-001：缩短当前 GPT 翻译的首段可见等待，并减少 GPT-6 Luna 的额外推理。
- REQ-001 / AC-001：GPT 翻译收到首段正文后、完整响应结束前，界面已有可读译文。
- REQ-002 / AC-002：仅 GPT-6 Luna 翻译明确使用 `reasoning_effort: none`；其他模型、改写与账号验证不改变推理策略。
- REQ-003 / AC-003：取消、改动输入或切换翻译配置后，旧片段和结果不得出现；未完成或失败的片段不得复制或替换原文。
- IN-001：沿用原文、语言、风格与已保存模型配置；UTF-8 文本，空输入沿用既有校验。
- OUT-001：处理中回调累计译文；成功返回完整译文；中断、截断、拒绝或无正文沿用固定错误类型，清除部分结果。
- CON-001：Swift 6、Foundation URLSession；固定服务端点、鉴权及禁止重定向策略不变；不读取或记录真实 Key。
- ASM-001：以当前使用的 OpenAI 翻译为本次范围。其他服务商保留完整响应路径。
- OOS-001：不更换用户模型、不提高服务等级、不增加缓存、分段并发或自动重试。

## 方案与接口

ADR-001：仅降低推理无法解决长文等待；仅流式显示无法减少生成前的推理。选用两项独立改动：GPT 翻译增量显示，以及已核实支持的 GPT-6 Luna 翻译使用 none。保留现有生成接口作为其他任务与服务商的回退，避免扩展到未经验证的 API。

- MOD-001 / IF-001：AIClient 增加翻译生成入口，接收累计正文回调。OpenAI 请求 SSE，读取 `delta.content`，忽略推理；收到正常结束标记后才返回成功。
- MOD-002 / IF-002：LanguageEngine 转发片段前校验任务取消与配置 revision；既有引擎可沿用完整响应实现。
- MOD-003：DemoModel 在处理中显示片段，完成前保留操作禁用；失败清除片段。UI 复用已有处理中正文显示。
- 网络：保持 120 秒请求超时、180 秒资源超时、10 MB 响应限制；取消立即传到 URLSession，不自动重发。

## 基线与验证

2026-11-15，已安装 0.5.2 / build 16，翻译模型 gpt-6-luna。测试原文：`The meeting starts at nine tomorrow morning. Please bring the updated report.` 原生 UI 从提交到观察到完整结果约 3.75 秒，整段一次性出现。此为单次 UI 观测，包含工具采样开销，不能作为服务端延迟或统计基准。

官方依据：[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) 支持 none，默认 medium；[延迟优化](https://developers.openai.com/api/docs/guides/latency-optimization) 区分首字和完成时间；[Chat Completions 流式事件](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events) 定义增量正文和结束原因。

| 用例 | 关联 | 验证方法 | 状态 |
| --- | --- | --- | --- |
| TC-001 | REQ-001 / AC-001 | `firstTextIsVisibleWhileCompletionIsHeldAndActionsStayDisabled`：后半段仍被 gate 阻塞时，已有中文与 emoji；最终段落完整 | 通过 |
| TC-002 | REQ-002 / AC-002 | `lunaTranslationRequestsStreamingWithoutExtraReasoning`、`otherOpenAIModelsAndRewritingKeepTheirReasoningPolicy`、`otherProvidersKeepTheirExistingGenerationPath` | 通过 |
| TC-003 | REQ-003 / AC-003 | `staleStreamsCannotOverwriteCurrentSession`：取消、编辑、模型变化、模型切换后切回、另一任务模型变化；TC-001 断言复制/替换禁用 | 通过 |
| TC-004 | REQ-003 / AC-003 | `failureAfterFirstTextClearsThePartialResult`、`streamHTTPFailuresStaySanitized`、`malformedIncompleteAndRejectedStreamsCannotSucceed`、`streamTimeoutCancellationAndWrongContentTypeStayDistinct` | 通过 |
| TC-005 | REQ-001 / AC-001 | 同一句短句优化后约 1.462 秒观察到完整结果；三段英文长文约 3.816 秒完成；162 项回归、构建及 8 张截图检查 | 通过，性能统计限制见下 |

## 验证结果与交付

- 修改前执行 `./tools/test.sh --filter 'AIClientTests|LanguageEngineTests|TranslationLatencyTests'`，原有测试通过，新契约断言因 `stream: false` 与缺少 `reasoning_effort` 两项失败；修改后定向 31 项通过。
- `./tools/test.sh`：162 项测试、18 个 suite 通过，测试执行约 10.873 秒。首次运行受 SwiftPM 嵌套沙箱限制，获得执行权限后正常运行；测试编写时的嵌套宏编译问题已修正，最终构建无警告。
- `./build.sh`：release 构建与签名通过，固定凭据组件 revision 3 原样嵌入。
- `./tools/grid-lint.sh`、`git diff --check`：通过。
- `APP_SNAPSHOT_SCOPE=translation-streaming`：8 张浅深色截图通过 `tools/check-layout.py --translation-streaming`。快速浮窗和左右对照在处理中可读、无裁切，停止可用，复制/替换禁用；完成后恢复正常正文与操作。逐张审阅了 `quick-translation-{streaming,result}-{light,dark}.png` 和 `workspace-translation-{streaming,result}-{light,dark}.png`。
- `./tools/install-local.sh`：已安装至 `/Applications/TrueL.app`，原凭据可用；`tools/verify-bundle-copy.py` 验证安装内容与构建产物相同。测试文本已清空并恢复原有空白改写页面。此为本地优化构建，版本元数据仍为 0.5.2 / 16，未发布远程版本。

本地日志保存在 `artifacts/translation-latency/{baseline,focused,regression,build,install,snapshots}.log`，截图及元数据在 `artifacts/translation-latency/screenshots/`。这些生成证据不纳入 Git。

源码追踪：REQ-001 → `AIClient.swift` / `OpenAITranslationStream.swift` / `LanguageEngine.swift` / `DemoModel.swift` → TC-001、TC-005；REQ-002 → `AIClient.swift` → TC-002；REQ-003 → 流解析、engine revision 与 model generation → TC-003、TC-004。测试位于 `Tests/TrueLTests/TranslationLatencyTests.swift`。

## 证据边界

确定的是旧路径等待整个响应、现在能在响应结束前发布正文，以及 Luna 翻译请求明确关闭额外推理。短句从 3.750 秒到 1.462 秒仅为两次 UI 观测，包含采样开销，并受网络、缓存和服务负载影响；没有独立测量真实 API 首 token、p50/p95，不能声称固定提速比例，也不能把收益分别归因于两项改动。长文现场验证完成了真实流式 API 请求，UI 工具的该次快照已是完整结果；提前显示的时序由受控流测试验证。

未做复杂文本的翻译质量评测。短句样本在修改前后都曾返回 `source` JSON 包装，属于本次前已存在的格式问题，保持原提示词进行速度对比，未夹带修改。关闭推理的适用范围限定为当前已验证的 Luna 翻译；其他服务商没有进行实网测试，其原有路径由回归覆盖。

该包装问题的后续修复与独立回归见 [翻译正文格式修复](TRANSLATION-OUTPUT.md)。

## 证据评分：92 / 100

| 维度 | 分数 | 证据与扣分 |
| --- | --- | --- |
| 需求与验收覆盖 | 25 / 25 | 三项 AC 均有可复现断言及追踪关系 |
| 正确性与边界 | 23 / 25 | 取消、配置、失败与截断覆盖；未评估复杂文本质量，后续需人工样本集 |
| 测试充分性 | 17 / 20 | 162 项回归、8 张截图及真实请求；缺少重复实网延迟分布和首 token 测量 |
| 架构与接口 | 9 / 10 | 保留旧接口回退、复用连接；模型兼容白名单需随官方契约维护 |
| 代码与安全 | 9 / 10 | 隔离流状态、限制大小、清理取消、不泄露错误正文；未做协议模糊测试 |
| 文档与交付 | 9 / 10 | 本地安装、架构、开发命令、变更日志和证据齐全；现场计时依赖 UI 采样，尚无自动实网基准脚本 |
