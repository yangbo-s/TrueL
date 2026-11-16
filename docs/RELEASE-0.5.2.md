# 0.5.2 顶栏品牌比例验收

REQ-088：在透明、随图标选择更新、整体居中的基础上，缩小标志并收紧与字标的间距，使标志与文字的视觉字高和中线相称。

共用 `WindowChromeMetrics.brandIconSize = 12`、`brandGap = 4`。六款 SVG 轮廓在此尺寸下实际约 11 pt 高，与 13 pt 系统字标的可见字高接近。普通窗、快速窗和设置沿用同一组件；既有偏好与凭据组件不变。

验收范围：六款实时切换、窗口居中和拖动；全页面深浅色截图；正式发布签名与自动更新。

真实 2× 窗口截图的像素测量：3A 标志可见高度 11 pt，TrueL 字标 9.5 pt；视觉中线分别为 26 pt 与 26.25 pt，差半个物理像素。组合共用 16 pt 高的文字行，水平框宽由 64 pt 收至 52 pt。证据：`artifacts/brand-0.5.2/ink-measurements.json` 与 `brand-quick-3A.png`。

| 用例 | 验收结果 | 证据 |
| --- | --- | --- |
| TC-088a 比例与对齐 | 3A 真实像素测量通过；六款在设置中点击后即时更新并延续到主窗；464/736/840 pt 主窗标题组合中心误差为 0，544 pt 设置窗为 0.125 pt；拖动通过 | `ink-measurements.json`、`brand-geometry.json`、`logs/native-controls.log` |
| TC-088b 页面覆盖 | 62 张全页面与 14 张六款图标选择截图均通过真实窗口捕获、尺寸、红绿灯和单窗口检查；逐页复核改动的顶栏及代表性完整窗口，浅深外观、五个设置页与长内容状态无裁切、重叠或居中偏移 | `artifacts/brand-0.5.2/{all,icons,contact}/` |
| TC-088c 回归 | 153 项测试、17 个套件通过；网格、图标资产哈希检查通过；凭据打包 4 项与发布脚本 3 项通过 | `artifacts/brand-0.5.2/logs/` |
| TC-088d 更新延续 | 固定凭据组件 revision 3 保持 CDHash `47fd00ec57231d9685aede03ea335e1eecc405d8`；两次实际 Sparkle 安装与重启后非交互读取成功，错误调用身份被拒绝，测试条目已清理 | `artifacts/credential-continuity/truel-credential-continuity-7sfgtt3a/result.json` |
| TC-088e 发布校验 | 安装包挂载内容与构建 195 项一致；DMG 与 feed 验签通过；真实 Sparkle 确认 build 14、15 均可更新至 16，build 16 显示最新，篡改 feed 被拒绝 | `artifacts/release-0.5.2/{package.log,local-update-check.log}` |

本轮没有遗留失败。截图及交互使用独立预览和模拟内容；已安装的日常应用、偏好与真实 API Key 未改动。尚未在 1× 外接显示器上复核，未做人工 VoiceOver 朗读评测。

安装包 `build/releases/0.5.2/TrueL-0.5.2-arm64.dmg`，SHA-256：`2a1e95a62ef3fb32183a7c306c0b46d57b8fefaf2de64ed6d19402eb446a0068`。公开发布与回读结果待补齐。
