> [!IMPORTANT]
> ## Animeko Harmony（非官方 HarmonyOS / 卓易通 兼容构建）
>
> 本仓库**不是** [Animeko](https://github.com/open-ani/animeko) 的源码 fork，而是一组补丁加一条自动发布流水线：
> 每天检查 Animeko 官方最新稳定版，拉取官方源码、套用 [`patches/`](./patches) 下的补丁、编译签名 APK，发布到本仓库的
> [Releases](../../releases)。tag 形如 `v6.2.0-harmony.1`。
>
> 目标是改善 Animeko 在 HarmonyOS 卓易通（Android 兼容容器）中的可用性。本项目不隶属于、也不受 OpenAni 官方支持；
> 与本构建相关的问题请提到本仓库，不要向 Animeko 上游反馈。本构建沿用上游的 [AGPL-3.0](https://github.com/open-ani/animeko/blob/main/LICENSE.txt) 许可，
> 原始项目与绝大部分代码归功于 [OpenAni 及其贡献者](https://github.com/open-ani/animeko/graphs/contributors)。

## 下载与安装

- 到 [Releases](../../releases) 下载最新的 `ani-<版本>-arm64-v8a.apk`（华为设备均为 arm64）。
- 包名为 `me.him188.ani.harmony`，桌面名称「Animeko Harmony」，与官方版（`me.him188.ani`）是两个独立应用，**可以共存、互不覆盖**，账号和下载数据需要分别设置。
- 应用内「检查更新」已改为检查本仓库的 Release，不会再提示安装官方 APK。
- 若同时装了官方版，点击 `ani://` 链接（扫码登录、分享链接等）时系统会弹出选择框，选 Animeko Harmony 即可。

> 为什么不用官方包名？卓易通安装 APK 时会按包名查自己的应用目录，包名命中但签名与官方不一致的 APK 会被拒绝，
> 系统随后交给「出境易」处理并提示「暂不支持安装该应用」。`v6.2.0-harmony.1` 就是因此装不上的，从 `harmony.2` 起改为独立包名。
> 这与 APK 是否为 universal 包无关：华为设备均为 arm64，`arm64-v8a` 包与 universal 包内容一致。

## 包含的补丁

| 补丁 | 作用 |
| --- | --- |
| [`0001-android-harden-foreground-service-notification.patch`](./patches/0001-android-harden-foreground-service-notification.patch) | BT 下载前台服务每次都真正调用 `startForeground()`，不再依赖 `activeNotifications` 判断；修复卓易通下开始下载后通知不更新、切后台/锁屏后下载停止的问题。详细分析见 [`docs/ANALYSIS.md`](./docs/ANALYSIS.md)。 |
| [`0002-updater-use-harmony-fork-releases.patch`](./patches/0002-updater-use-harmony-fork-releases.patch) | 版本号为 `x.y.z-harmony.N` 时，应用内更新改查本仓库 GitHub Releases，并按 `(x, y, z, N)` 比较版本；否则官方更新服务器会把它当成 `x.y.z` 的预发布版而推送官方 APK（签名不同无法安装）。 |
| [`0003-android-use-harmony-application-id.patch`](./patches/0003-android-use-harmony-application-id.patch) | `applicationId` 改为 `me.him188.ani.harmony`、应用名改为「Animeko Harmony」，并同步 `AndroidBuildConfig.APP_APPLICATION_ID`（FileProvider authority 由它拼出）。绕过卓易通对已知包名的签名校验，并允许与官方版共存。 |

补丁按 [`patches/series`](./patches/series) 的顺序套用。

## 版本号规则

- `version.name` = `<官方版本>-harmony.<N>`，例如 `6.2.0-harmony.1`；`N` 是同一官方版本的第几次打包，改了补丁需要重发时递增。
- `versionCode` 沿用上游的固定值（上游刻意不随版本变化，以便用户回退），因此任意 harmony 版本之间都可以互相覆盖安装（`harmony.1` 因包名不同除外，它本来也装不上）。

## 构建机制

流水线定义在 [`.github/workflows/harmony_release.yml`](./.github/workflows/harmony_release.yml)，每天 UTC 03:23（北京 11:23）定时运行，也可以在 Actions 里手动触发并指定 `upstream_tag` / `patch_number`：

1. 取官方最新稳定版 tag（或手动指定），若 `v<版本>-harmony.<N>` 的 Release 已存在则直接结束。
2. `git clone --depth 1 --branch <tag>` 官方源码（Android 端的 anitorrent 原生库来自 Maven，无需 boost 子模块）。
3. [`scripts/prepare-source.sh`](./scripts/prepare-source.sh)：按 `series` 顺序 `git apply --3way` 补丁、把更新器指向当前仓库、改写 `gradle.properties` 的 `version.name` / `package.version`，每一步各提交一次。
4. Temurin JDK 21 + `./gradlew assembleDefaultRelease`（`ani.android.abis=arm64-v8a`），签名密钥来自仓库 Secrets。
5. 产物重命名为 `ani-<版本>-arm64-v8a.apk`，附 `.sha1`，上传为 Actions artifact 并 `gh release create`。

[`.github/workflows/check_patches.yml`](./.github/workflows/check_patches.yml) 在补丁改动时和每周一，把补丁分别试套到官方最新稳定版和 `main`，上游一变就能提前知道要 rebase。

## Secrets

已配置完成，首个版本 [`v6.2.0-harmony.1`](../../releases/tag/v6.2.0-harmony.1) 由流水线自动产出。签名密钥备份在私有仓库 `Xun2202/animeko-harmony-keystore`（含各 Secret 的值）。仓库 Settings → Secrets and variables → Actions 中的条目：

   | Secret | 内容 |
   | --- | --- |
   | `SIGNING_KEY` | 签名 keystore 文件的 base64（`base64 -w0 release.jks`） |
   | `KEY_STORE_PASSWORD` | keystore 密码 |
   | `ALIAS` | key alias |
   | `KEY_PASSWORD` | key 密码 |
   | `DANDANPLAY_APP_ID` / `DANDANPLAY_APP_SECRET` | 可选。弹弹play 开放平台的 App ID/Secret；不填则弹弹play 弹幕源不可用（官方构建也是用私有密钥） |

需要手动出包时：Actions → **Harmony Release** → Run workflow，`upstream_tag` 留空、`patch_number` 填 `1`（重打包则递增），约 15 分钟出包。

维护说明（如何 rebase 补丁、排错等）见 [`.github/HARMONY.md`](./.github/HARMONY.md)。

## 本地复现构建

```bash
git clone --depth 1 --branch v6.2.0 https://github.com/open-ani/animeko.git /tmp/animeko
scripts/prepare-source.sh /tmp/animeko v6.2.0 1
cd /tmp/animeko
cat > local.properties <<EOF
sdk.dir=$ANDROID_HOME
ani.android.abis=arm64-v8a
jvm.toolchain.vendor=adoptium   # 与本机 JDK 21 的 java.vendor 匹配即可, 例如 ubuntu / adoptium
jvm.toolchain.version=21
EOF
./gradlew assembleDefaultRelease   # 未配置签名时输出未签名 APK
```
