# 开发

## 环境

macOS 26+、Apple silicon、Swift 6.2 或更新版本、Xcode Command Line Tools、Python 3。项目使用 SwiftPM；Sparkle 固定版本见 `Package.resolved`。

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

构建输出为 `build/TrueL.app`。退出当前 TrueL 后安装：

```sh
./tools/install-local.sh --open
```

## 界面验收

```sh
./tools/snap.sh
python3 tools/check-layout.py artifacts/screenshots
```

截图模式 `APP_SNAPSHOT` 使用模拟 API、内存设置和固定权限状态，不访问真实 Key；自动覆盖主浮窗、结果、异常、长内容、调整尺寸及四个设置页的浅深两种外观。输出包括 PNG 与 `captures.json`。须逐张检查对齐、裁切、焦点和材料效果，不能只凭截图数量判断通过。

主程序保持单个工作浮窗；设置显示时隐藏工作浮窗。修改状态和布局时，同时维护 Snapshot 状态矩阵和实际行为测试。

## 发布配置

`Config/release.json` 集中保存版本、递增 build number、最低系统版本、更新源 URL、Sparkle 版本及公钥。公钥可以进入仓库；签名私钥与 API Key 保留在本机钥匙串。

模块与持久化契约见 [ARCHITECTURE.md](ARCHITECTURE.md)，发布步骤见 [RELEASING.md](RELEASING.md)。
