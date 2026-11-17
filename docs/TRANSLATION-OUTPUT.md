# 翻译正文中的 source 包装修复

## 目标、契约与方案

- GOAL-001：普通文本翻译只显示、复制和替换译文，消除误带的 `{"source":"译文"}` 外壳。
- REQ-001 / AC-001：保留 JSON 输入封装，提示词明确只翻译 `source` 字符串；最终结果只拆除完整的单一 `source` 字符串外壳，兼容 JSON / 无标签代码围栏、转义与 Unicode。
- REQ-002 / AC-002：普通译文继续增量显示；疑似 JSON / 围栏响应在完整校验前不进入可见正文，失败时仍无可复制或替换的结果。
- REQ-003 / AC-003：原文自身以对象、数组或代码围栏开始时保留结构；不改写其他字段、额外字段、嵌套对象或重复字段，不递归剥离正文。
- IN-001：已有 `LanguageRequest.source` 与模型累计 UTF-8 正文；普通文本与结构化文本均可输入。
- OUT-001：普通片段原样回调；疑似包装片段暂缓；最终仅解码确认的包装字符串，空正文或破损包装走已有失败清理路径。
- CON-001：Swift 6 / Foundation；不改模型、Key、网络参数或持久化，不增加请求或依赖。
- OOS-001：不扩大为通用 JSON 修复，不更换翻译服务，不自动重新请求模型，不发布远程版本。
- ASM-001：将以 `{`、`[` 或代码围栏开始的原文视为需要保留结构的内容；这是一项保守保护，可能保留这类输入的多余包装。

ADR-001：只调整提示词无法兜底模型不遵循格式的情况；全局剥除 JSON 会损伤用户原文。选择提示词澄清与请求级保守解析。仅异常包装响应等待完整结果，普通翻译保持现有首段时序。

MOD-001 / IF-001：`TranslationOutput` 负责按原文判定保护范围、筛选预览与解码最终正文；无网络或持久化副作用。`ProviderLanguageEngine` 在每个回调前仍检查取消与配置 revision，然后使用该解析器；纠错路径不变。结构化原文另加明确指令：保留原文自己的外层结构和所有 JSON 键（包括内层 `source`），不得只抽取其中一个字段作为响应。

## 验收追踪

| 用例 | 需求 | 验证 | 状态 |
| --- | --- | --- | --- |
| TC-001 | REQ-001 | `reportedPackageTextLosesOnlyItsTransportWrapper`、`wrappedTextDecodesEscapesAndUnicode`、`surrogatePairsAndPrettyPrintedEnvelopeUseJSONDecoding` | 通过 |
| TC-002 | REQ-002 | `noFragmentOfAnAccidentalEnvelopeEntersThePreview`；`sourceEnvelopeNeverReachesTheVisibleOrCopiedResult` 用模拟传输驱动实际 SSE→engine→model，检查显示、复制、替换与网络失败 | 通过 |
| TC-003 | REQ-003 | `structuredSourceKeepsItsOwnStructureInPreviewAndFinalResult`、`ordinaryTextAndOtherStructuresAreNotRewritten`、`onlyOneEnvelopeIsRemoved` | 通过 |
| TC-004 | REQ-001/002 | `emptyOrMalformedEnvelopesCannotBecomeSuccessfulTranslations`、`ordinaryTranslationStillStreamsImmediately`，既有 `TranslationLatencyTests` 取消/配置/失败回归 | 通过 |
| TC-005 | REQ-001/003 | 已安装最终版本上，GPT-6 Luna 分别翻译封装段落和含内层 source 的 JSON；原生替换按钮仅写回正文 | 通过 |

## 验证与交付

2026-11-16（America/New_York）：

- 修复前，`./tools/test.sh --filter 'TranslationOutputTests|sourceEnvelopeNeverReachesTheVisibleOrCopiedResult'` 记录 19 个失败断言，准确覆盖用户段落、包装预览和复制泄漏；普通文本与结构化原文保护用例原本已通过。见 `artifacts/translation-output/baseline.log`。
- 修复后，`./tools/test.sh --filter 'TranslationOutputTests|TranslationLatencyTests|LanguageEngineTests|RewriteLatencyTests|AIClientTests'`：47 项测试全部通过。补充的最终正文替换断言也已通过，最终完整回归包含这些断言。
- 首次实机测试发现，原文本身是 `{"source":"The small pad connects to the large pad."}` 时，模型自行省略原文 JSON。补充结构化原文指令及契约断言（`structured-baseline.log` 中 4 项先失败），重新构建后，同一原文实际返回 `{"source":"小焊盘与大焊盘相连。"}`。
- `./tools/test.sh`：最终 187 项、21 个 suite 全部通过，测试执行约 10.814 秒，见 `regression-final.log`。早期锁屏时 `childPopoverCanTakeFocusWithoutDismissingPanel` 的 `child.isKeyWindow` 断言失败；用户解锁后完整回归通过，未修改或放宽该断言。
- `./tools/grid-lint.sh`、`git diff --check` 通过；`./build.sh` 完成 release 构建与签名，无编译警告，固定凭据组件 revision 3 原样嵌入。
- `./tools/install-local.sh` 初次因 TrueL 仍运行而拒绝安装；解锁后确认原文为空，正常退出应用再安装。最终安装至 `/Applications/TrueL.app`，`tools/verify-bundle-copy.py` 核对 195 项 bundle 内容一致；版本元数据保持 0.5.4，本次未发布远程版本。
- 最终安装版实机翻译普通封装段落得到纯正文，保留空行、`1.3 mm`、`0.5 × 0.58 mm` 和待办段落；JSON 原文保留内层字段。替换按钮仅将译文写回原文。已检查正文排版，并清空验收样例、恢复原来的空白改写页面。

实现追踪：REQ-001/002/003 → [TranslationOutput.swift](../Sources/TrueL/TranslationOutput.swift) / [LanguageEngine.swift](../Sources/TrueL/LanguageEngine.swift) → [TranslationOutputTests.swift](../Tests/TrueLTests/TranslationOutputTests.swift) / [TranslationLatencyTests.swift](../Tests/TrueLTests/TranslationLatencyTests.swift)。变更说明见 [CHANGELOG.md](../CHANGELOG.md)。完整日志位于 `artifacts/translation-output/`，生成证据不纳入 Git。

后续已将该修复发布为 0.5.5 / build 19；正式安装包、签名更新源与公开验收见 [0.5.5 发布记录](RELEASE-0.5.5.md)。

## 证据边界与评分：95 / 100

实网检查仅覆盖当前 GPT-6 Luna 的普通段落和 JSON 样例，不能据此承诺所有模型始终遵循格式。解析器只处理已确认的单一 `source` 字符串外壳；其他包装字段与结构化原文的额外包装保持原样。疑似包装响应会等待完整结果，普通文本的首段时序由回归测试保证，未做新的延迟统计。

| 维度 | 分数 | 证据与扣分 |
| --- | --- | --- |
| 需求与验收覆盖 | 25 / 25 | 三项需求均有调用链回归；原生界面与实际翻译补充验收 |
| 正确性与边界 | 24 / 25 | 转义、Unicode、空值、破损包装、重复/嵌套字段、失败清理通过；结构化原文保守分支可能保留额外包装 |
| 测试充分性 | 17 / 20 | 187 项全量回归、真实 SSE 解析链的模拟传输测试、两类最终实网样例；未覆盖多服务商实网与大样本格式遵循率 |
| 架构与接口 | 10 / 10 | 请求级纯逻辑复用，网络接口、取消与改写路径保留，无新增依赖 |
| 代码质量与维护 | 9 / 10 | 标准 JSON 解码、严格单字段识别、无凭据日志；包装种类与原文前缀采用明确的有限规则，扩展时需同步测试 |
| 文档与交付 | 10 / 10 | 契约、追踪、失败与修复证据、构建签名、本地安装与读回校验齐全 |
