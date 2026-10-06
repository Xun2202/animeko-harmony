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
- 包名为 `me.him188.ani.harmony`，桌面名称仍是「Animeko」，与官方版（`me.him188.ani`）是两个独立应用，**可以共存、互不覆盖**（同时安装时桌面会有两个「Animeko」图标），账号和下载数据需要分别设置。
- 应用内「检查更新」已改为检查本仓库的 Release，不会再提示安装官方 APK。
- 若同时装了官方版，点击 `ani://` 链接（扫码登录、分享链接等）时系统会弹出选择框，两个都叫 Animeko，不想纠结的话卸载官方版即可。

### 安装步骤（鸿蒙 NEXT / 6 / 7）

出现「出境易暂不支持安装该应用」说明 APK 被交给了**出境易**而不是卓易通。出境易是一个只有几十个海外应用的白名单商店，
任何不在名单里的 APK 它都装不了，与包名、签名、是否 universal 包都无关。典型触发场景：在出境易里的 Chrome / Edge 等浏览器下载 APK，
然后直接在浏览器的下载列表里点开——这个文件在出境易容器内，自然由出境易安装。

要让**卓易通**来装，按下面任一方式操作（实测有效的是第 1 种）：

1. **用系统「文件管理」打开**：把 APK 复制到手机本机存储（例如 `Download/`）——出境易容器里下载的文件在
   文件管理 → 浏览 → 我的手机 → 兼容应用数据 → `Download/`，长按复制出来即可——然后在文件管理里点开这份副本，系统会用卓易通安装。
2. **在卓易通里面下载并安装**：打开卓易通 → 「搜应用」装一个浏览器（如 X Browser / Via）或 MT 管理器 →
   在它里面打开本仓库 Releases 页下载 APK → 下载完成后直接点开安装。若提示「不支持」，勾选「APK 共存」/「自动签名」后继续。
3. **文件互传**：卓易通 → 文件互传，把 APK 导入容器；再在卓易通里用 MT 管理器或 XAPK Installer 打开 `Download/` 下的 APK 安装。

若三种方式都提示「卓易通不支持」而不是出境易的提示，请把弹窗截图发到 Issue，附上鸿蒙版本和卓易通版本。

### 让下载在后台继续（必做）

鸿蒙会在 App 退后台后几秒内冻结进程，前台服务和通知**不足以**阻止。从 `harmony.6` 起 App 在缓存期间会播放一段静音音轨来保活（卓易通只对音频播放网开一面；2026-10-06 用户真机确认有效，Mihon / Anikku 的鸿蒙版随后采用同一做法）；系统侧的设置仍建议做一次：

1. 鸿蒙 设置 → 应用和服务 → **应用启动管理** → 找到 **Animeko**（找不到就找 **卓易通**）→ 关闭「自动管理」→ 勾选「允许自启动」「允许关联启动」「**允许后台活动**」。
2. 第一次开始缓存时，App 会弹出 Android 的「忽略电池优化」请求，选**允许**。拒绝过的话到卓易通里 Animeko 的应用信息 → 电池 里手动改。
3. 鸿蒙 设置 → 电池 → 更多电池设置 → 打开「休眠时始终保持网络连接」。
4. 多任务界面把 Animeko 卡片下拉加锁，避免被自动清理。

缓存进行中通知栏会有「正在缓存 N 个资源」，全部完成后通知自动消失、服务退出。

> 为什么不用官方包名？卓易通安装 APK 时会按包名查自己的应用目录，包名命中但签名与官方不一致的 APK 会被拒绝，
> 系统随后交给「出境易」处理并提示「暂不支持安装该应用」。`v6.2.0-harmony.1` 就是因此装不上的，从 `harmony.2` 起改为独立包名。
> 这与 APK 是否为 universal 包无关：华为设备均为 arm64，`arm64-v8a` 包与 universal 包内容一致。

## 包含的补丁

| 补丁 | 作用 |
| --- | --- |
| [`0001-android-harden-foreground-service-notification.patch`](./patches/0001-android-harden-foreground-service-notification.patch) | BT 下载前台服务每次都真正调用 `startForeground()`，不再依赖 `activeNotifications` 判断；只影响 **BT 源**缓存；在线源缓存见 0004。详细分析见 [`docs/ANALYSIS.md`](./docs/ANALYSIS.md)。 |
| [`0002-updater-use-harmony-fork-releases.patch`](./patches/0002-updater-use-harmony-fork-releases.patch) | 版本号为 `x.y.z-harmony.N` 时，应用内更新改查本仓库 GitHub Releases，并按 `(x, y, z, N)` 比较版本；否则官方更新服务器会把它当成 `x.y.z` 的预发布版而推送官方 APK（签名不同无法安装）。 |
| [`0004-android-foreground-service-for-http-caches.patch`](./patches/0004-android-foreground-service-for-http-caches.patch) | 在线源（HTTP / m3u8）缓存原本在主进程里直接下载，没有任何前台服务和通知，App 一退后台进程就被冻结、下载停摆。新增 `HttpCacheService`：有在线源缓存进行中时在主进程挂一个 `dataSync` 前台服务并显示进度通知（带「暂停全部」），缓存完成后自动退出。与上游 `main` 为 PikPak 做的 `PikPakCacheService` 同一思路。 |
| [`0005-android-battery-exemption-and-wake-lock.patch`](./patches/0005-android-battery-exemption-and-wake-lock.patch) | 第一次开始在线源缓存时请求「忽略电池优化」（FlClash 等能常驻后台的应用都这么做），`HttpCacheService` 存活期间持有 partial WakeLock。应对鸿蒙在前台服务存在时仍冻结进程的情况。 |
| [`0006-android-silent-audio-keep-alive.patch`](./patches/0006-android-silent-audio-keep-alive.patch) | `HttpCacheService` 改为 `mediaPlayback` 类型，存活期间循环播放一段静音音轨（不申请音频焦点，不影响其他 App 放音）。实测卓易通对 dataSync 前台服务 + WakeLock + 电池豁免仍在退后台几秒内冻结进程，只有音频播放会被宿主保活。 |
| [`0003-android-use-harmony-application-id.patch`](./patches/0003-android-use-harmony-application-id.patch) | `applicationId` 改为 `me.him188.ani.harmony`（应用名保持「Animeko」），并同步 `AndroidBuildConfig.APP_APPLICATION_ID`（FileProvider authority 由它拼出）。绕过卓易通对已知包名的签名校验，并允许与官方版共存。 |
| [`0007-android-download-notification-progress.patch`](./patches/0007-android-download-notification-progress.patch) | 两个下载前台服务的通知与 Mihon / Anikku 鸿蒙版统一：正文在速度后追加「 · N%」并显示确定型进度条（在线源缓存按文件大小加权汇总各任务进度，大小未知时取平均；BT 用 `TorrentDownloader.Stats.downloadProgress`），在线源缓存通知下拉展开还显示正在缓存的「番剧 - 集」。`NotificationDisplayStrategy.Working` 新增可选的 `progress` / `detail`，不改任何字符串。 |

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

已配置完成，[`v6.2.0-harmony.6`](../../releases/tag/v6.2.0-harmony.6)、[`v6.2.0-harmony.7`](../../releases/tag/v6.2.0-harmony.7) 等版本均由流水线自动产出。签名密钥备份在私有仓库 `Xun2202/keystores` 的 `animeko-harmony/` 目录（含各 Secret 的值、校验与一键恢复脚本；旧仓库 `animeko-harmony-keystore` 已归档）。仓库 Settings → Secrets and variables → Actions 中的条目：

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
