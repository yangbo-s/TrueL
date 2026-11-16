# 开发

## 环境

macOS 26+、Apple silicon、Swift 6.2 或更新版本、Xcode 26（含 Icon Composer）、Python 3。项目使用 SwiftPM；Sparkle 固定版本见 `Package.resolved`。

```sh
./tools/test.sh
./tools/grid-lint.sh
```

测试通过内存凭据与独立 UserDefaults 验证模型选择、网络契约、输入、快捷键和窗口行为。窗口测试需要当前已登录的图形会话。

## 构建与签名

构建需要本机已有的代码签名身份。选择证书并固定一次：

```sh
python3 tools/signing.py setup --identity <证书SHA-1>
# 使用自签证书时：
python3 tools/signing.py setup --self-signed --identity <证书SHA-1>
./build.sh
```

证书选择保存在 `~/Library/Application Support/TrueL/Signing/identity.json`，可通过 `TRUEL_SIGNING_CONFIG` 指定其他本地配置。连续发布使用同一个身份与应用标识。Sparkle 内嵌组件按从内到外的顺序签名。

凭据组件是例外：`Resources/CredentialBroker` 保存已封存的签名产物，普通构建只校验和复制，不重新编译或签名。源码、产物或证书不匹配时构建停止。组件确需升级或使用自己的签名证书构建时，审阅改动后显式运行 `python3 tools/credential_broker.py seal --revision <大于当前值的整数>`；这会改变组件身份，必须重新测试凭据迁移。不要在发布脚本中自动执行 seal。

凭据回归：

```sh
python3 tools/test-credential-packaging.py
python3 tools/test-credential-continuity.py
```

后者使用登录钥匙串中的 UUID 测试条目与临时更新签名密钥，在本机临时目录执行两次实际 Sparkle 安装、重启及非交互读取，同时验证错误应用标识、证书和组件被拒绝。不会读取真实 API Key、替换 `/Applications/TrueL.app` 或使用发布私钥；成功后清理测试条目、密钥、测试应用和独立偏好域，证据保存在 `artifacts/credential-continuity`。失败时保留测试目录用于诊断。

迁移入口截图：`APP_SNAPSHOT_SCOPE=credentials ./tools/snap.sh`，覆盖浅深外观下待授权和已恢复两种状态，使用模拟凭据。

构建输出为 `build/TrueL.app`。退出当前 TrueL 后安装：

```sh
./tools/install-local.sh --open
```

## 界面验收

```sh
./tools/snap.sh
python3 tools/check-layout.py artifacts/screenshots
```

截图模式 `APP_SNAPSHOT` 使用模拟 API、内存设置和固定权限状态，不访问真实 Key；自动覆盖主浮窗、结果、异常、长内容、调整尺寸及五个设置页的浅深两种外观。输出包括 PNG 与 `captures.json`。须逐张检查对齐、裁切、焦点和材料效果，不能只凭截图数量判断通过。

正文与滚动对齐可定向运行 `APP_SNAPSHOT_SCOPE=alignment ./tools/snap.sh`，再执行 `python3 tools/check-layout.py artifacts/screenshots --alignment`。该矩阵覆盖两种任务、窄宽窗口、浅深外观与长文本的顶部/中部/底部；直接运行应用并传入 `-AppleShowScrollBars WhenScrolling` 可补查自动隐藏滚动条。`PopupAlignmentTests` 在真实窗口中校验正文属性、滚动区域坐标及末字符可见性。

快速工作流的结果、调整焦点、只读、错误及左右对照：`APP_SNAPSHOT_SCOPE=workflows ./tools/snap.sh`，随后运行 `python3 tools/check-layout.py artifacts/screenshots --workflows`。绿色主动作与 Return 意图记录在截图元数据中；原生调整框的回车行为由 `QuickWorkflowTests` 验证。

已具备辅助功能和输入监控权限的开发终端可运行 `./tools/check-quick-workflows.sh`。它编译并启动独立测试窗口，真实发送 Ctrl+A+A / Ctrl+C+C，验证结果窗激活后的 AX 替换、超时归还按键、选区变化、来源关闭与只读拒写。仅操作自建窗口，完成后关闭，不读取用户文档和 Key。

图标母版保存在 `design/logo-refinements/native`，默认原生图标为 `Icon/AppIcon.icon`。`build.sh` 调用 `python3 tools/make-icons.py`，按内容哈希缓存编译产物。`Resources` 中保留可审查的资源，`python3 tools/make-icons.py --check` 验证是否与母版一致。

逐款切换验收可运行 `APP_SNAPSHOT_SCOPE=icons ./tools/snap.sh`，再执行 `python3 tools/check-layout.py artifacts/screenshots --icons`。

主程序保持单个工作浮窗；设置显示时隐藏工作浮窗。修改状态和布局时，同时维护 Snapshot 状态矩阵和实际行为测试。

## 发布配置

`Config/release.json` 集中保存版本、递增 build number、最低系统版本、更新源 URL、Sparkle 版本及公钥。公钥可以进入仓库；签名私钥与 API Key 保留在本机钥匙串。

模块与持久化契约见 [ARCHITECTURE.md](ARCHITECTURE.md)，发布步骤见 [RELEASING.md](RELEASING.md)。
