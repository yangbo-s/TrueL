# 改写等待优化

## 范围与契约

- GOAL-R01：缩短当前 GPT 改写等待，保留完整正文、纠错与解释。
- REQ-R01 / AC-R01：模型完成 `output` 正文后、纠错元数据仍在生成时，界面已显示正文，不显示 JSON。
- REQ-R02 / AC-R02：仅当前已核实的 `gpt-6.1-terra` 改写使用 `reasoning_effort: low`；翻译策略与其他模型保持各自既有行为。
- REQ-R03 / AC-R03：完整响应通过 JSON 和原有纠错校验前，不得复制/替换；取消、修改输入/风格/模型或网络异常时拒绝旧数据并清除预览。
- IN-R01：沿用原文、原语言、解释语言、风格与已保存模型，UTF-8；空输入仍在提交前拒绝。
- OUT-R01：处理中发布完整 `output` 字符串；正常结束后返回完整 JSON 并按既有契约解析纠错。非法 JSON、截断、拒绝、空输出和网络异常不产生可用结果。
- CON-R01：复用 Swift 6、URLSession、固定端点与签名凭据组件；不增加依赖，不切换用户模型，不提升服务等级，不自动重试。
- ASM-R01 / OOS-R01：本次优化 OpenAI 改写；其他服务商沿用现有生成路径，不扩展为分段并行请求。

## 方案

ADR-R01：仅降推理不能解决等待解释的问题；直接展示流中的 JSON 会泄露实现结构。选择复用翻译的 SSE 传输，将 `output` 放在 JSON 首字段，只有其字符串完整且解码成功才预览正文。完整 JSON 仍走原解析器。相比解析未闭合字符串逐字预览，此方案更小，能够复用标准 JSON 解码处理 Unicode、转义和换行。

- MOD-R01 / IF-R01：AIClient 增加 `generateRewrite`，默认回退原 generate；OpenAI 走共享文本流，当前 Terra 改写设置 low。完成结果是原始 JSON，回调只含已解码的正文。
- MOD-R02：正文预览提取器只接受根对象首个 `output` 字符串；不同字段顺序或不完整值暂不预览，最终仍按原契约解析，不将嵌套同名字段当正文。
- MOD-R03：LanguageEngine 在每次预览及最终结果边界校验取消和任务 revision；DemoModel 复用已验证的处理中、错误清理和操作禁用逻辑。
- 网络沿用 120 秒请求、180 秒资源超时、10 MB 响应上限和禁止重定向；完整 stop / DONE 后才进入最终解析。

官方依据：[Terra 模型契约](https://developers.openai.com/api/docs/models/gpt-6.1-terra) 支持 low、默认 medium；[推理强度建议](https://developers.openai.com/api/docs/guides/deployment-checklist#set-up-reasoningeffort) 建议日常改写使用 low。

## 基线与验收矩阵

2026-11-15，本机 0.5.2 / 16，gpt-6.1-terra，标准风格。输入：`I has an idea for our project. It help people write more clearly, and we should discuss it at tomorrow's meeting.`

| 版本 | 提交至 UI 观测到完整结果 | 内容 |
| --- | --- | --- |
| 优化前，提交 `80484d0` | 4.587 秒 | `I has` → `I have`，`It help` → `It helps`，含解释与提示 |
| 本次安装后 | 3.784 秒 | 同样两处纠错，保留完整原意与提示 |

计时来自原生 UI 的提交与结果观测，包含工具采样开销；只有一组前后样本，没有测量首字延迟、p50 或 p95，也不能分别归因于推理强度、流式传输和提示词。该观测支持本次方向，但不代表稳定提速比例。

| 用例 | 关联 | 断言 | 状态 |
| --- | --- | --- | --- |
| TC-R01 | REQ-R01 | 阻塞纠错尾段时正文已可见；完成后正文、纠错、提示一致 | 通过：`completedBodyAppearsBeforeCorrectionsAndCannotBeAppliedEarly` |
| TC-R02 | REQ-R02 | Terra 改写请求 stream + low，翻译和其他模型参数不变 | 通过：`terraRewriteRequestsStreamingWithLowReasoning`、`effortRemainsSpecificToModelAndTask` 的 6 个组合、其他服务商 12 个回退组合 |
| TC-R03 | REQ-R01/03 | 引号、反斜杠、换行、Unicode 和嵌套 output 不泄露 JSON；不完整值不预览 | 通过：`RewriteOutputPreviewTests` 的完整字符串、代理对、代码围栏及 13 个非法/嵌套输入 |
| TC-R04 | REQ-R03 | 中断、非法最终 JSON、取消、编辑、风格和模型变化清除正文；无变化文本正常完成 | 通过：5 类元数据失败、6 类会话变化、无变化/字段重排响应；其他任务的模型修改不影响当前请求 |
| TC-R05 | 全部 | 定向/完整回归、构建、浅深快照、相同真实样本复测和安装 | 通过：171 项测试、16 张快照、真实样本与已安装应用核对，详见下文 |

实现追踪：REQ-R01 对应 [OpenAITextStream](../Sources/TrueL/OpenAITextStream.swift)、[RewriteOutputPreview](../Sources/TrueL/RewriteOutputPreview.swift)；REQ-R02 对应 [AIClient](../Sources/TrueL/AIClient.swift)；REQ-R03 对应 [LanguageEngine](../Sources/TrueL/LanguageEngine.swift) 与 [DemoModel](../Sources/TrueL/DemoModel.swift)。主要契约测试为 [RewriteLatencyTests](../Tests/TrueLTests/RewriteLatencyTests.swift)、[RewriteOutputPreviewTests](../Tests/TrueLTests/RewriteOutputPreviewTests.swift) 和 [TranslationLatencyTests](../Tests/TrueLTests/TranslationLatencyTests.swift)。

## 验证证据

- 修改前新增请求契约用例：22 项测试中仅新增用例产生两处预期失败，确认改写未开启流式且未设置 low；原翻译与 engine 用例通过。
- 定向检查：`./tools/test.sh --filter 'RewriteLatencyTests|RewriteOutputPreviewTests|TranslationLatencyTests|LanguageEngineTests|AIClientTests'`，5 个 suite、40 项测试全部通过，测试阶段 0.258 秒。
- 完整回归：`./tools/test.sh`，20 个 suite、171 项测试全部通过，测试阶段 10.802 秒。
- 发布配置构建：`./build.sh` 通过，编译 8.31 秒。定向测试、完整测试及构建日志中无编译 warning/error；`./tools/grid-lint.sh` 与 `git diff --check` 通过。
- `APP_SNAPSHOT_SCOPE=rewrite-streaming` 与 `translation-streaming` 各生成 8 张快照；两个 `tools/check-layout.py` 对应检查均通过。逐张检查了快速浮窗/左右对照、浅色/深色、处理中/完成状态：无裁切和重叠，处理中操作禁用，改写完成后三处纠错恢复。快照使用模拟内容；真实流式时序由受控传输测试验证。
- 安装后真实内容检查输入：`Please don't change the deadline from June 12 to June 21. Neither of the two proposals are ready, and the budget remains $1,250. If Mia approves it tomorrow, we can start; otherwise, we must wait.` 仅将 `Neither of the two proposals are ready` 修正为 `Neither of the two proposals is ready`，保留否定、两个日期、金额、姓名及条件关系；最终提示说明 neither 的主谓一致。该样例是人工构造的验收文本。
- `./tools/install-local.sh` 已更新 `/Applications/TrueL.app`；`python3 tools/verify-bundle-copy.py build/TrueL.app /Applications/TrueL.app` 确认 195 个条目一致。签名检查通过，凭据组件保持 revision 3 / CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`。启动后已有服务配置可用，测试文本已清空。版本仍为 0.5.2 / 16，仅本地安装，未发布远程版本。

本地证据位于 `artifacts/rewrite-latency/`：`baseline.log`、`focused.log`、`regression.log`、`build.log`、`install.log`，以及 `screenshots/` 和 `translation-screenshots/` 内的 PNG / `captures.json`。该目录按仓库约定忽略，不随源码提交。

## 限制与质量评分

改写预览是在完整正文字符串闭合后显示一次，并非逐字显示；若模型未把 `output` 放在首字段，仍可正常解析最终结果，但没有提前预览。网络和服务端负载仍影响等待时间。本次未做多语言长文质量基准或统计延迟测试；非 OpenAI 路径通过契约回归，未逐一调用真实服务。低推理强度的内容检查仅覆盖上述两个英文样例，不能据此保证所有复杂改写的质量不变。

| 维度 | 得分 | 证据、扣分与后续改进 |
| --- | --- | --- |
| 需求与验收覆盖 | 25/25 | REQ-R01～03、AC-R01～03 均有对应通过用例，无遗留范围内验收项 |
| 功能正确性与边界处理 | 23/25 | 最终校验、取消、配置变化和转义边界通过；扣 2 分：复杂长文的语义保持尚未广泛验证，可补多语言固定语料 |
| 测试充分性与结果 | 16/20 | 171 项测试、16 张快照及真实请求通过；扣 4 分：仅一组延迟对比，尚无延迟分布和其他服务商实测，可按固定语料重复测量 |
| 架构、接口与可扩展性 | 9/10 | 复用传输与最终解析，默认实现保留服务商兼容；扣 1 分：预览依赖字段顺序，必要时可扩展为增量根对象解析 |
| 代码质量、安全性与可维护性 | 9/10 | 无新依赖，保留限额、取消、端点和凭据边界，构建无警告；扣 1 分：推理参数采用精确模型名单，新模型须核实后扩展 |
| 文档与交付完整性 | 10/10 | 契约、追踪、证据、限制、架构、开发指引和变更日志齐全；本地安装并验证 |
| 合计 | **92/100** | 可交付；评分反映当前证据覆盖程度，不是模型质量或提速比例 |
