# 0.5.0 语言与风格工作窗验收

范围与输入输出契约见 [LANGUAGE-WORKSPACE.md](LANGUAGE-WORKSPACE.md)。本次覆盖 REQ-079–086，保留现有供应商、模型设置、单窗口与固定签名凭据组件。

| 用例 | 需求 | 结果与证据 |
| --- | --- | --- |
| TC-079 | 079 | 关闭、失焦、设置及正常重开，置顶/未置顶共 8 个组合均返回双栏；保留已完成结果，取消未完成快捷请求。`quickSessionEndsAtEveryNormalEntry`、`dismissingQuickLoadingCancelsRequestAndNormalReopenKeepsSource` 通过；原生关闭和外部激活后的重开通过。 |
| TC-080 | 080 | 中英识别、短中文、简繁、未知输入和手动语言覆盖通过；同语言目标回退，已选目标重复选择不发请求。`LanguageWorkspaceTests` 与请求测试通过。 |
| TC-081 | 081 | 互换取完整译文作为新原文，交换语言并清除外部选区绑定；快速/改写/无结果禁用。原生点击互换后显示简体中文 → English。 |
| TC-082 | 082 | 两种风格各自持久化，预览不写偏好；新风格从原文生成，不使用上次输出。`styleRegenerationUsesOriginalSourceAndTaskSpecificStyle`、`presetsReachProviderPromptAndRewriteStaysInSourceLanguage` 通过。 |
| TC-083 | 083,084 | 移除追加指令框，保留修改解释；原生回车、IME、Shift+Return 与严格选区绑定回归通过。复制与替换位于底栏，左右正文/滚动容器在 736/960 pt 下对齐。 |
| TC-084 | 086 | 语言、模型、风格和设置菜单共用渲染器；左右槽位边距 12 pt，箭头间隔 8 pt。原生鼠标打开/取消/选择、悬停截图与底栏坐标断言通过；快速菜单不结束会话。 |
| TC-085 | 079–086 | 62 张全页面状态与 28 张工作流截图通过窗口编号、尺寸、实际屏幕捕获、单窗口和状态元数据检查；逐页检查明暗、空/加载/失败/禁用、长文、长模型名和设置页。 |
| TC-086 | 085 | 签名安装包、固定凭据组件、两次实际 Sparkle 安装及公开发布验证记录于下方。 |

`./tools/test.sh`：152 项测试、17 个套件通过。网格检查与 Impeccable 检测通过，构建无警告。凭据打包 4 项与发布脚本 3 项测试通过。图标统一 SF Symbols regular/monochrome，共用工具/行内尺寸；品牌图标六个选项不变。

本地证据位于 `artifacts/workspace-0.5.0/`：`all/` 为完整 62 张矩阵，`workflows/` 为 28 张工作流，`hover-*` / `menu-*` 为真实鼠标悬停和打开菜单，`native-reopened-workspace.png`、`native-deactivated-reopened.png`、`native-swapped-languages.png` 记录实际交互后的结果。测试、构建和原生检查日志位于 `logs/`。README 和使用指南已同步本版实际窗口图。

验收中修正：旧悬停用例的固定 50 ms 等待在并行建窗时出现一次失败，改为在 1 秒期限内等待同一可观察状态，保留立即显示、跨区域保持和最终关闭断言；回归通过。预览夹具的长中文译文同步为英文。外部焦点检查器改为处理 RunLoop 通知后再读取前台进程，避免读取缓存状态；应用的关闭和失焦行为通过实测。

限制：语言识别不覆盖所有混合语种或歧义短句，可手动指定；未使用用户 Key 对七家服务商的所有风格做付费生成评测。语义提示通过实际请求组装的契约测试，窗口验收用隔离示例数据。已核对原生辅助功能标签和键盘路径，未做人工 VoiceOver 朗读评测。

## 发布证据

版本 0.5.0 / build 14。固定凭据组件 revision 3，CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`，没有重编译或重签。两次实际隔离 Sparkle 安装与重启后，三个不同主程序指纹均可非交互读取测试凭据；错误签名调用方被拒绝，测试凭据已清理。证据：`artifacts/credential-continuity/truel-credential-continuity-jdmphn7d/result.json`。

DMG 挂载检查通过，183 项 bundle 内容与构建产物一致。安装包和 appcast Ed25519 验签通过；真实 Sparkle 检查旧 build 13 发现 14、build 14 已是最新、篡改 feed 被拒绝。日志：`artifacts/release-0.5.0/{package.log,local-update-check.log}`。

源码提交 `6db5c51f01093d98b42311b84fc86fc83464c8d5` 已推送至 main，正式标签 `v0.5.0` 指向该提交。签名更新源提交为 `cdd058725fcbc31dcdeb35733b9522ebe711c13a`。

[TrueL 0.5.0](https://github.com/yangbo-s/TrueL/releases/tag/v0.5.0) 已发布为最新正式版，包含 [DMG](https://github.com/yangbo-s/TrueL/releases/download/v0.5.0/TrueL-0.5.0-arm64.dmg) 与 SHA256SUMS。匿名下载字节与本地一致，安装包签名通过。公开 HTTPS feed 与本地签名文件逐字节一致；实际 Sparkle 读取 build 14、13、12，旧 build 13 发现 14，build 14 显示最新。TC-086 通过。日志为 `artifacts/release-0.5.0/{public-release-check.log,public-update-check.log,public-update-results.json}`。

安装包 `build/releases/0.5.0/TrueL-0.5.0-arm64.dmg`，2,856,228 字节。SHA-256：`cb909756eaec38dc3445f69d650b4113de1a8b1eeb59901b2a67fb3a45a0d80c`。

## 证据评分

| 项目 | 得分 | 依据 / 保留限制 |
| --- | --- | --- |
| 需求与验收覆盖 | 25/25 | REQ-079–086 均有实现、状态测试和窗口证据 |
| 功能与边界 | 24/25 | 关闭/失焦/置顶/设置/重开、短中文、无效来源、互换和重复选择通过；混合语言和歧义短句仍可能需手选 |
| 测试 | 17/20 | 152 项、90 张状态截图、原生菜单/互换/关闭/失焦及两次真实更新；未实测七家服务商全部风格或人工 VoiceOver 朗读 |
| 架构与接口 | 10/10 | 复用单窗口、语言/风格目录、统一菜单与符号组件，无新依赖 |
| 代码、安全与维护 | 10/10 | 构建无警告，旧异步响应隔离、严格选区校验与凭据组件不变 |
| 文档与交付 | 10/10 | 使用、产品、设计、开发和架构文档及截图更新；源码、DMG、签名 feed 与公开回读完成 |
| 合计 | **96/100** | P0/P1 验收项通过；上述限制已披露 |
