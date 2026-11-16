# 0.5.1 窗口品牌组合验收

REQ-087：主浮窗、快速浮窗及设置页的标题左侧显示当前应用图标；设置中选择六款图标时同步更新。图标与标题作为整体保持窗口水平居中，垂直中心沿用 52 pt 顶栏的中心线。

输入为现有 `Preferences.appIcon`（六个 `AppIconStyle`，默认 3A）；输出为共享 `WindowChrome` 中的 20 pt 透明标志、8 pt 间距和原有标题。复用六款原有 SVG 轮廓，去掉 Dock 底板与留白，分层使用正文色与强调色适应深浅外观。不增加偏好、通知或依赖。标题组合不接受鼠标事件，保留原生拖动和工具按钮。

验收：六款样式在设置中实际点击后立即更新标题，关闭设置返回主窗保持选择；默认快速窗及普通宽度、缩放后窗口的整体标题中心不偏移。浅色、深色及五个设置页面逐页检查。正式发布沿用固定凭据组件和已签名 Sparkle 更新流程。

| 用例 | 验收结果 | 证据 |
| --- | --- | --- |
| TC-087a 六款同步 | 原生点击 1A、1B、1C、3A、3B、3C 后，设置标题即时改变；关闭设置回到主窗保持相同标志，再次选择 3A 正常恢复 | `artifacts/brand-0.5.1/logs/native-controls.log`、`brand-settings-*`、`brand-workspace-*` |
| TC-087b 组合居中 | 快速窗 464 pt、普通窗 736/840 pt 的整体中心误差为 0；设置窗误差 0.125 pt。所有标题组合垂直中心均为 26 pt。穿过组合拖动窗口实际移动 28 × 20 pt | `brand-geometry.json`、`brand-dragged.png` |
| TC-087c 透明与明暗 | 六款轮廓和强调层均可读取、角落透明且有可见图形；深色使用浅色轮廓，浅色使用深色轮廓，无白色底板。62 张全页面状态与 14 张图标选择截图均为实际屏幕捕获，逐页检查通过 | `AppIconTests.windowMarksHaveTransparentCornersAndVisibleGlyphLayers`、`all/`、`icons/`、`contact/` |
| TC-087d 回归 | 153 项测试、17 个套件通过；网格、图标来源哈希、Impeccable 静态检查通过；凭据打包 4 项与发布脚本 3 项通过 | `artifacts/brand-0.5.1/logs/` |
| TC-087e 更新凭据 | 固定组件 revision 3 保持 CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`；两次实际 Sparkle 安装与重启后读取测试凭据均无交互，错误身份被拒绝，临时凭据清理通过 | `artifacts/credential-continuity/truel-credential-continuity-wfls9eu3/result.json` |

原生拖动检查首次在窗口贴近屏幕边界时失败，窗口尺寸也被系统限制；将隔离预览移至屏幕内部后，相同拖动断言通过。未修改应用的拖动实现。当前验收没有遗留失败。截图使用模拟内容，不读取用户 Key；没有退出或替换已安装的日常应用。

原生补拍脚本首次使用按钮的视觉文案「改写」查找，实际辅助功能名称为「语法检查与改写」，因此没有点击成功；改用现有辅助功能名称后补拍。应用控件无需修改。

版本 0.5.1 / build 15。DMG 挂载内容与构建产物 195 项一致；安装包与 feed 的 Ed25519 签名验证通过。实际 Sparkle 从旧 build 14 发现 15，build 15 显示最新，篡改 feed 被拒绝。证据：`artifacts/release-0.5.1/{package.log,local-update-check.log,local-update-results.json}`。

安装包为 `build/releases/0.5.1/TrueL-0.5.1-arm64.dmg`，SHA-256：`7bd8984079ac7c8c391cabb471b224e612838ac36cfaf6769489a8abc7d613db`。

公开发布与回读证据待补齐。
