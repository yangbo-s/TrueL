# 发布

版本修复与功能迭代验收通过后，交付流程包括源码推送、正式 GitHub Release、安装包上传和签名 Sparkle 更新源发布，并回读验证公开产物。本地安装包是准备阶段的产物。

## 首次配置

需要仓库发布权限、已固定的代码签名证书，以及 Sparkle 更新签名密钥。

```sh
./tools/fetch-sparkle.sh
.build/sparkle-tools/bin/generate_keys --account com.truel.sparkle
```

将工具输出的公钥填入 `Config/release.json` 的 `publicEDKey`。私钥由工具保存在本机钥匙串，后续发布复用。代码签名身份与更新签名密钥是两套独立凭据。

## 准备版本

1. 修改 `Config/release.json` 的 `version` 与 `build`，build 必须递增。
2. 更新 `CHANGELOG.md` 顶部条目与相关文档。
3. 运行测试、网格检查和逐页截图审阅。
4. 运行 `python3 tools/prepare-release.py`。

脚本验证官方工具摘要与更新公钥，构建签名应用、生成 DMG、挂载检查内容，并生成、签名和验证 appcast。产物在 `build/releases/<version>/`：安装包、更新源、发布说明和 `SHA256SUMS`。

发布前用隔离的临时应用副本运行 `tools/check-update.swift`：旧 build 应发现更新，相同 build 应显示已是最新，篡改后的 feed 应被拒绝。它调用实际 Sparkle 更新器，只检查更新信息，不安装。临时副本使用独立 bundle identifier 和测试 feed，避免修改日常使用的应用与偏好。

构建必须同时启用 `SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction`，否则 Sparkle 会拒绝启动。`SUSignedFeedFailureExpirationInterval` 为 `0`，不允许签名失败的 feed 随时间恢复可用。验证安装包和 feed 使用 `tools/verify-update.swift`，只需公钥；仅生成签名时访问本机私钥。

## 发布到 GitHub

先提交并推送已验收源码，再发布标签与安装包。下面以 0.3.0 为例：

```sh
git push origin main
gh release create v0.3.0 --target main --title 'TrueL 0.3.0' \
  --notes-file build/releases/0.3.0/TrueL-0.3.0-arm64.md \
  build/releases/0.3.0/TrueL-0.3.0-arm64.dmg \
  build/releases/0.3.0/SHA256SUMS
```

确认下载包可访问且 SHA-256 一致，再把生成的 `appcast.xml` 原样复制到 `updates/appcast.xml`、提交并推送。签名后的 XML 不能手动编辑。

应用的 feed 地址为 `https://raw.githubusercontent.com/yangbo-s/TrueL/main/updates/appcast.xml`。最后从公开地址下载 feed 并验证签名，使用应用里的「检查更新…」验证实际结果。

## 签名与系统确认

当前发布使用固定自签证书；首次安装可能需要在 macOS「隐私与安全性」中确认打开。保持 bundle identifier、证书与安装位置稳定有助于权限延续。Sparkle 的 Ed25519 签名用于验证更新包和 feed。

从 0.3.2 起，普通更新复用固定凭据组件。发布前运行 `python3 tools/test-credential-continuity.py`，要求三个不同主程序指纹在两次实际 Sparkle 更新后仍可非交互读取测试凭据。不能用 feed 检查代替安装/重启验证。

旧 Key 的首次迁移可能需要在「AI 服务」中点「读取已存 Key」并由用户确认一次系统授权。凭据组件自身升级、签名身份变化或系统钥匙串策略变化仍可能要求重新确认；不承诺任何情况下永久免授权。更新不得重新编译或重签固定组件，也不得放宽钥匙串 ACL。组件源代码或签名需要调整时，单独封存新 revision 并执行迁移验收。

更新会重启应用，安装前应结束当前编辑。若版本需要回滚，发布修正版本时仍使用更高的 build number，保留同一更新公钥。
