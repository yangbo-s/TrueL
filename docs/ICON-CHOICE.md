# 应用图标选择

## 需求与契约

| 需求 / 验收 | 实现契约 | 验证 |
| --- | --- | --- |
| REQ-053 / AC-053：保留六款图标，默认 3A | 稳定 ID 为 1A、1B、1C、3A、3B、3C；原生 bundle 图标为 3A；1C 使用修复后的轮廓 | TC-053：母版、编译产物、六款预览与默认值 |
| REQ-054 / AC-054：用户在设置中即时选择，重启恢复 | 设置「图标」页；UserDefaults 仅保存 ID；NSApplication.applicationIconImage 更新 Dock；3A 使用 nil 恢复系统图标 | TC-054：逐款切换、持久化、恢复默认、预览隔离 |
| REQ-055 / AC-055：不改变凭据和签名身份 | 不修改已安装 bundle；Finder 显示 3A；资源缺失回退默认并同步选择；未知偏好值回退 3A | TC-055：缺失资源、未知 ID、签名验证、深浅色界面 |

## 方案

设置页使用现有岛屿、间距、字体和悬停反馈，六款图标以三列两行显示。
偏好负责持久化，独立控制器负责资源读取和运行时应用；注入读取与应用函数，避免单元测试影响全局 NSApp。
原生 3A 由 Icon Composer 母版编译。其余样式使用同一原生渲染器导出的白底 PNG，并留出 Dock 透明边距。

## 验收记录

2026-11-15，本地 0.3.1 / build 9：

- `./tools/test.sh`：115 项测试、11 个 suite 通过。图标定向测试覆盖首次启动、未知 ID、六款保存与恢复、同步切换、默认复位、失效资源及预览隔离。
- `tools/check-layout.py`：完整状态矩阵 62 张窗口截图通过；图标专项 14 张截图通过，逐张检查 `selectedAppIcon == appliedAppIcon`。记录位于 `artifacts/icon-choice/screenshots` 与 `artifacts/icon-choice/final-variants`。
- 五个设置页逐页检查浅深色：通用表单、服务输入/保存行、快捷键五行、图标三列两行、关于页均无截断或重叠。导航等宽，按钮与标签有稳定的内外间距。
- 通过实际界面点击选择 1C，再恢复 3A；辅助功能树准确返回对应 selected 状态。
- 六款图标均为 512×512、50px 透明 Dock 边距；默认 3A 的普通/深色保持白底，染色/透明外观遵循系统样式且字形可读。母版轮廓与缓存输入/输出哈希已验证。
- `grid-lint.sh`、`git diff --check`、Python 编译检查通过。构建使用原有固定签名身份。

另以 PNG 原始像素验证图形完整性：14 张图中六款的 84 个字形区域逐字节一致。证据保存在 `artifacts/icon-choice/initial-vs-cgimage-pixel-proof.json`。

| 页面 | 浅色 | 深色 |
| --- | --- | --- |
| 图标选择，默认 3A | [截图](images/icon-settings-light.png) | [截图](images/icon-settings-dark.png) |

## 平台边界

Apple 明确支持用 [applicationIconImage](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage) 临时更改 Dock 图标；TrueL 负责保存选择并在启动时重新应用。设为 nil 恢复 bundle 图标。Finder 保持 3A，运行时不会修改签名包。

Dock 自身的自动化连接超时，未取得其窗口的直接截图；当前系统下 Tab 未进入按钮，未完成键盘焦点环的实际截图验收。Command-Tab 的同步效果没有单独验证。持久化与重新应用使用独立 UserDefaults / 控制器重建测试，未为此退出用户安装版或访问真实 API Key。

## 证据评分：94 / 100

| 维度 | 分数 | 证据 |
| --- | --- | --- |
| 需求与资源覆盖 | 25 / 25 | 六款全部保留，默认 3A，原始轮廓与打包资源对应 |
| 行为 | 24 / 30 | 自动化状态链、持久化恢复和实际点击通过；Dock 直接观察、真实进程重启和键盘焦点仍有验收限制 |
| 视觉 | 25 / 25 | 五页浅深色、14 个选中状态、原始像素与四种原生外观 |
| 构建与交付 | 20 / 20 | 最终 DMG 校验通过，挂载包签名通过，175 项 bundle 内容与原构建一致 |

本地安装包：`build/TrueL.dmg`，校验日志：`artifacts/icon-choice/package-final.log`。本轮未发布新的 GitHub Release。
