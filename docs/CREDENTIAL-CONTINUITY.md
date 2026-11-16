# 凭据跨版本延续

## 目标与验收

GOAL-059：在继续使用固定自签身份的前提下，让普通 TrueL 更新不再因主程序 CDHash 变化而要求重新授权 API Key。

| 需求 / 验收 | 实现边界 | 测试 |
| --- | --- | --- |
| REQ-059 / AC-059：连续两次主程序更新后无交互读取已存凭据 | 固定 XPC 组件，普通构建原样嵌入 | TC-059：登录钥匙串测试条目、三个不同主程序指纹、两次真实 Sparkle 安装及重启 |
| REQ-060 / AC-060：保留旧 Key，授权后迁移一次，失败不丢失数据 | 新服务名优先；旧条目只读；复制并读回校验 | TC-060：迁移、拒绝、写入失败、重复迁移、更新新 Key |
| REQ-061 / AC-061：只有同一证书签名的 TrueL 可调用固定组件 | XPC 双向签名验证、固定 bundle ID、同一用户 | TC-061：错误标识、错误签名、错误组件、非法账号均被拒绝 |
| REQ-062 / AC-062：启动不主动弹钥匙串密码框，用户可在设置重试 | 异步非交互读取；显式授权入口 | TC-062：启动、取消、超时、切换服务商及编辑草稿时的过期响应 |
| REQ-063 / AC-063：构建不能悄悄更换组件身份 | 已签名产物、源码摘要和 CDHash 固定，校验失败停止构建 | TC-063：篡改、源码漂移、证书漂移、重复构建及 DMG 内容验证 |

CON-059：macOS 26、Swift 6、现有自签证书和 Sparkle 2.10.1；不读取或记录用户真实 Key 来做测试，不修改系统权限、钥匙串全局 ACL 或搜索列表。辅助组件将来升级时可能需要再次迁移。OOS-059：Apple 证书切换、图标和页面重新设计。

## 设计决策 ADR-059

登录钥匙串同时校验访问控制与 partition list。最小回归在相同证书及 designated requirement 下得到：构建一写入/读取成功；构建二读取返回 -25293；测试条目随后删除。临时创建的独立钥匙串未复现这一行为，因此跨版本验收必须使用登录钥匙串中的唯一测试条目。

主程序直接读钥匙串不能满足 AC-059；更换 Developer ID 与用户的自签选择不符。采用固定、受认证的内嵌 XPC 服务：每个普通版本复制已签名的原始产物，主程序不再直接读写生产凭据。组件升级必须显式生成新版本并重新验收，构建脚本不能自动重签。

MOD-059：CredentialProtocol/Core 定义固定账号、XPC 契约、错误和可测试迁移逻辑。MOD-060：TrueLCredentialBroker 在串行队列访问文件钥匙串。MOD-061：主程序异步客户端与 ServiceConfiguration 恢复流程。MOD-062：构建工具保存并验证组件身份及源码摘要。

## 契约 IF-059

- UTF-8 账号仅允许现有七个 provider ID；Key 必须非空、至多 16 KiB。读无数据返回 nil；失败仅返回 OSStatus，不包含 Key 或服务商响应。
- read(account, allowInteraction) / save(account, key) 经 XPC 调用；调用方使用固定组件 CDHash 和证书要求，组件验证 TrueL 的 bundle ID、证书与用户身份。默认读取禁止系统交互；显式重试才允许交互。
- 先读取 `com.truel.credentials.v1`；不存在时读 `com.truel.provider-api-key`，复制到新条目并读回校验。保留旧条目；新条目存在时不再访问旧条目。保存只更新新条目。
- XPC 失败、取消或超时均为失败，不退回主程序直接访问钥匙串。恢复响应必须匹配发起时的服务商和草稿 revision。
- 健康检查仅允许 UUID 票据和 create/read/delete 操作，使用独立的 `com.truel.credential-broker.validation` 服务名及虚构值；不接触生产账号，不返回凭据内容。用于真实发布包的跨版本验收。
- 合法示例：read("gemini", false)；非法示例：read("../other-service", true)，返回参数错误。重复保存同值与重复删除测试条目为幂等；无分页或排序。

## 实施门禁与证据

1. 已复现直接访问的跨构建失败，再实施固定组件。
2. 先验证存储和双向认证，再接主程序异步恢复与迁移入口。
3. 模块回归、实际 Sparkle 两次安装/重启、最终包验证均通过后才判定修复有效。

## 验收结果 · 2026-11-15

| 用例 | 结果与证据 |
| --- | --- |
| TC-059 / AC-059 | 通过。`python3 tools/test-credential-continuity.py` 在登录钥匙串复现旧代码跨构建 -25293；三个新客户端分别成功非交互读取；隔离应用 build 9001 → 9002 → 9003 经真实 Sparkle 下载、签名验证、安装、自动重启后分别读取成功。辅助组件 CDHash 始终为 `47fd00ec57231d9685aede03ea335e1eecc405d8`。 |
| TC-060 / AC-060 | 通过模块回归。`CredentialVaultTests` 覆盖复制并读回、仅迁移一次、保留旧值、拒绝读取、写入失败、读回不一致、并发保存优先、非法账号与超长 Key。未读取用户真实 API Key，也未代替用户进行首次系统授权。 |
| TC-061 / AC-061 | 通过。真实 XPC 错误应用标识、临时签名及错误辅助组件三条路径均返回连接拒绝 -10002，无凭据返回且不崩溃；未降低认证条件。 |
| TC-062 / AC-062 | 通过。`CredentialRecoveryTests` 验证默认无交互、显式授权、取消可重试、过期读取不能覆盖输入或其他服务商、缺失组件失败关闭。`BrokerReplyTests` 验证提前回复、并发完成仅恢复一次、超时与迟到回复。128 项 Swift 测试全部通过。 |
| TC-063 / AC-063 | 通过。4 项固定组件打包测试与 3 项既有发布测试通过。两次正式构建的组件指纹一致；最终 DMG 挂载后签名验证通过，183 个 bundle 条目与原构建一致。`git diff --check`、`grid-lint.sh` 通过。 |

UI 验收：`artifacts/credential-screenshots` 中四张截图均实际查看，覆盖待授权与已恢复的浅深外观；按钮完整、未裁切，仍保持一个可见内容窗口和三个原生窗口按钮。截图使用模拟凭据。

真实更新证据：`artifacts/credential-continuity/truel-credential-continuity-xhorewy_/result.json` 与 `sparkle-events.jsonl`。测试应用复用正式 `CredentialBrokerClient.swift` 和已封存的组件，使用独立 Sparkle 偏好域、一次性更新密钥和 UUID 测试条目；没有替换 `/Applications/TrueL.app`。主程序与辅助组件均由既有自签证书签名。

其余日志位于 `artifacts/debug/credential-continuity`：`final-tests.log`、`final-build.log`、`integration-apfs.log`、`screenshots.log`、`package.log`。

### 本轮发现并解决的问题

- XPC 初次未加入调用方安全会话，创建测试条目失败；按 Apple 的 `JoinExistingSession` 契约修正后，创建、读取和删除均通过。
- Swift 6 推断错误回调具有 MainActor 隔离，认证拒绝时崩溃；显式标注回调 `@Sendable` 后，三条真实拒绝路径均正常返回错误。
- 给无 Team ID 的主程序额外启用库验证会阻止加载自签 Sparkle；保持主程序既有签名选项，只有独立凭据组件启用 hardened runtime。
- 工作区卷的原子文件交换阻塞安装验收；测试移至本机临时目录后，两次完整安装均通过。先前测试的进程和测试条目已清理。

参考：[Apple XPC 服务会话说明](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)、[XPC 调用方签名要求](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))。

## 交付与限制

版本 0.3.2，build 10，arm64。安装包：`build/TrueL-0.3.2-arm64.dmg`（2,843,343 字节），SHA-256：`72d65f7c4225259e3c63ad156cd6e803782ab74857f26625af0c960df32c9ff4`。发布验收见 [RELEASE-0.3.2.md](RELEASE-0.3.2.md)。未关闭或替换用户正在使用的应用。

旧 Key 首次迁移可能需要用户在「AI 服务 → 读取已存 Key」确认一次，每个已存账号独立迁移。辅助组件本身更新、更换证书或系统钥匙串策略变化时仍可能重新授权。本轮实测环境为 macOS 27.2.1；最低支持系统 macOS 26 未另行上机测试。未用用户真实 Key 执行付费 API 请求。

## 证据评分：96 / 100

| 维度 | 分数 | 依据与扣分 |
| --- | --- | --- |
| 需求与验收覆盖 | 24 / 25 | 需求矩阵均有对应实现和测试；用户真实旧凭据的首次授权迁移仍由用户安装后完成 |
| 功能正确性与边界 | 25 / 25 | 迁移、原子插入、并发、拒绝、超时、取消与双向认证通过 |
| 测试充分性 | 18 / 20 | 128 项 Swift 测试、7 项打包检查、两次真实隔离更新和四张截图；未另测 macOS 26 和真实用户条目的系统确认 |
| 架构与接口 | 10 / 10 | 主程序不直接访问生产钥匙串，固定组件与版本封存边界明确 |
| 代码、安全与维护 | 9 / 10 | 固定签名、同用户验证、双向 XPC 校验；自签方案仍依赖旧文件钥匙串 API，组件变更需要显式迁移 |
| 文档与交付 | 10 / 10 | 开发、架构、发布、使用和变更记录已同步，提供验证过的本地 DMG 与校验文件 |
