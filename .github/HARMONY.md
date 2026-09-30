# Animeko Harmony —— 维护手册

> 面向后续接手维护的人或 AI 助手。读完本文并拿到一个有 `repo` + `workflow` 权限的 GitHub token，
> 就应能理解现状并继续维护本仓库的全部功能。
>
> 仓库：`https://github.com/Xun2202/animeko-harmony`　维护者：`Xun2202`
> 同类项目：[`Xun2202/mihon-harmony`](https://github.com/Xun2202/mihon-harmony)（Mihon 的卓易通构建，本仓库的流水线仿照它）

## 1. 背景与目标

- [Animeko](https://github.com/open-ani/animeko) 是 KMP/Compose 写的追番 App，Android 端 BT 下载跑在独立进程 `:torrent_service` 的前台服务里。
- 用户在 HarmonyOS 7 的**卓易通**（Android 兼容容器）里运行它，反馈"开始下载后不弹通知，切后台/锁屏后下载丢失"。
- 代码审计发现前台服务通知逻辑依赖 `NotificationManager.getActiveNotifications()`，在卓易通这种通知被桥接到宿主的环境里不可靠。完整分析见 [`docs/ANALYSIS.md`](../docs/ANALYSIS.md)。
- 官方不太可能专门为卓易通调整，所以本仓库维护补丁并自动出包。

## 2. 现状总览

| 项目 | 内容 |
| --- | --- |
| 仓库形态 | 不是源码 fork。只有 `patches/`、`scripts/`、workflow 和文档；源码在 Actions 运行时从官方 tag 拉取 |
| 产物 | 每个官方稳定版一个 Release，tag `v<版本>-harmony.<N>`，文件 `ani-<版本>-harmony.<N>-arm64-v8a.apk` + `.sha1` |
| 包名 | `me.him188.ani`（与官方相同），签名为自建密钥 → 与官方版不能互相覆盖，需卸载后安装 |
| versionCode | 沿用上游固定值 `android.version.code`（上游刻意不变，方便回退），harmony 版本之间可任意覆盖 |
| 构建 | `.github/workflows/harmony_release.yml`，ubuntu-24.04，Temurin JDK 21，`assembleDefaultRelease`，只编 `arm64-v8a` |
| 触发 | 每天 UTC 03:23 定时 + 手动 `workflow_dispatch` |
| 补丁健康检查 | `.github/workflows/check_patches.yml`：补丁改动时 + 每周一，试套官方最新稳定版（必须成功）和 `main`（只警告） |
| 应用内更新 | 补丁 0002 把更新源改为本仓库 Releases |

## 3. 目录结构

```
patches/
  series                                   # 套用顺序, 一行一个文件名, # 开头为注释
  0001-android-harden-foreground-service-notification.patch
  0002-updater-use-harmony-fork-releases.patch
scripts/prepare-source.sh                  # 套补丁 + 改更新器仓库名 + 改版本号, workflow 和本地都用它
.github/workflows/harmony_release.yml      # 定时/手动: 拉源码 → 套补丁 → 编译签名 → 发 Release
.github/workflows/check_patches.yml        # 补丁能否套到上游最新稳定版 / main
docs/ANALYSIS.md                           # 问题分析与真机取证方法
```

## 4. 补丁说明

### 0001 前台服务通知（`app/shared/app-data/.../torrent/service/`）

- `ServiceNotification.kt`：每次 `onStartCommand` 都调 `startForeground()`；用内部 `isForeground` 代替 `activeNotifications` 判断；保留 `lastDisplayStrategy`；捕获 `IllegalStateException`/`SecurityException` 并带堆栈打日志；通知被禁用/渠道被屏蔽时打警告。
- `AniTorrentService.kt`：前台启动被拒时 `stopSelf()`。
- `AniTorrentServiceStarter.kt`：等待启动广播 15 秒超时。

**基于 `v6.2.0` 生成。** 官方 `main`（6.2.0 之后）重构了 `ServiceNotification`：构造参数增加了 `notificationId`/`channelId`/`buildStopServiceIntent`（给新增的 `PikPakCacheService` 共用），常量改名 `TORRENT_NOTIFICATION_ID`。下一个稳定版发布时这个补丁**必然要 rebase**，做法见 §6。`main` 上对应的改法只是把 `NOTIFICATION_ID` → `notificationId`、`NOTIFICATION_CHANNEL_ID` → `channelId`。

### 0002 应用内更新（`app/shared/ui-settings/.../ui/update/`）

- 新增 `HarmonyForkUpdates.kt`：`HarmonyForkVersion` 解析/比较 `x.y.z-harmony.N`；`getHarmonyForkLatestVersion()` 请求 `https://api.github.com/repos/<repo>/releases?per_page=30`，过滤 tag 匹配的非草稿 Release，取比当前更新的最新一个，下载地址优先 `-<abi>.apk`、回退 `-universal.apk`。
- `UpdateChecker.kt`：当前版本能被解析成 harmony 版本时走上面的逻辑，否则保持官方流程。
- `UpdateNotifierHost.kt`：「详情」链接同样按版本格式指向本仓库或官方。
- 仓库名硬编码为 `Xun2202/animeko-harmony`；`prepare-source.sh` 在 `FORK_REPO`（workflow 传 `${{ github.repository }}`）不同时用 `sed` 替换，所以 fork 本仓库也能用。

为什么必须有这个补丁：官方更新服务器对 `clientVersion=6.2.0-harmony.1` 会返回 `6.2.0`（把它当预发布版），App 会不停提示更新到官方 6.2.0，而官方 APK 签名不同装不上。

## 5. 日常操作

### 5.1 手动出新版

Actions → **Harmony Release** → Run workflow：

- `upstream_tag`：官方 tag，如 `v6.3.0`；留空取最新稳定版。只接受 `vX.Y.Z`，不支持 alpha/beta。
- `patch_number`：同一官方版本第几次打包，从 `1` 开始。改了补丁想重编就填 `2`、`3`……

同名 Release 已存在会直接跳过；要重编必须换补丁号或先删旧 Release。整个流程约 30–60 分钟（Animeko 编译很重，上游自己的 CI 也是 8g 堆 + 10g swap）。

### 5.2 定时任务

每天 UTC 03:23 用 `patch_number=1` 检查最新稳定版。官方发了新版 → 自动出 `v<新版>-harmony.1`。补丁套不上 → workflow 失败（GitHub 会发邮件），按 §6 处理。

### 5.3 Secrets

| Secret | 内容 | 必需 |
| --- | --- | --- |
| `SIGNING_KEY` | keystore 文件 base64（`base64 -w0 release.jks`） | 是 |
| `KEY_STORE_PASSWORD` | keystore 密码 | 是 |
| `ALIAS` | key alias | 是 |
| `KEY_PASSWORD` | key 密码 | 是 |
| `DANDANPLAY_APP_ID` / `DANDANPLAY_APP_SECRET` | 弹弹play 开放平台密钥，不填则该弹幕源不可用 | 否 |

与 `mihon-harmony` 同名，可以直接复用同一个 keystore。**签名密钥一旦更换，用户就必须卸载重装**，务必备份（参考 `mihon-repo-keystore` 私有仓库的做法）。

Animeko 的 Gradle 通过环境变量读取签名参数（`build-logic/src/main/kotlin/properties.kt` 的 `aniProperty()` 顺序：local.properties → 系统属性 → 环境变量 → Gradle property）：
`signing_release_storeFileFromRoot`（相对仓库根的 keystore 路径）、`signing_release_storePassword`、`signing_release_keyAlias`、`signing_release_keyPassword`。没有这些变量时输出未签名 APK，不报错——所以 workflow 前面有一步显式校验 Secrets 非空。

## 6. 上游更新后补丁套不上怎么办

1. 本地拉新 tag：`git clone --depth 1 --branch vX.Y.Z https://github.com/open-ani/animeko.git /tmp/animeko`
2. 逐个套补丁：`cd /tmp/animeko && git apply --3way ../animeko-harmony/patches/0001-*.patch`。
   - 失败时看 `git status`/冲突标记，手工修到编译通过：
     `./gradlew :app:shared:app-data:compileAndroidMain :app:shared:ui-settings:compileAndroidMain`
     （需要 `local.properties` 里有 `sdk.dir`；如果本机 JDK 不是 JetBrains Runtime，再加一行 `jvm.toolchain.vendor=<本机 java.vendor 的子串>`，如 `adoptium`、`ubuntu`）
3. `git add -A && git commit`，保留原来的提交说明（`git commit -c <旧补丁里的 From 提交>` 或直接复制标题/正文）。
4. `git format-patch -1 HEAD -o /tmp/out`，把生成的文件覆盖到 `patches/` 对应文件名（文件名保持不变，`series` 不用改）。
5. 推到 `main`，`check_patches.yml` 会自动验证；然后手动或等定时任务出包。

`check_patches.yml` 的 `main` 目标失败只是预警：说明下一个稳定版发布时需要 rebase，可以提前准备。

## 7. 排错手册

| 现象 | 原因 / 处理 |
| --- | --- |
| `Patch ... does not apply` | 上游改了相关文件，按 §6 rebase |
| `Missing SIGNING_KEY secret` | 没配 Secrets（§5.3） |
| `Cannot find a Java installation ... vendor matching('jetbrains')` | `local.properties` 里 `jvm.toolchain.vendor` 没写或与实际 JDK 不匹配。workflow 用 Temurin，写 `adoptium` |
| Gradle OOM / 被 kill | 上游 CI 的参数是 `-Xmx8g` + 6g Kotlin daemon + 10G swap，本仓库照搬；若仍失败可把 `ani.android.abis` 保持 `arm64-v8a`（已是）并去掉 `--parallel` |
| `assembleDefaultRelease` 成功但找不到 APK | 路径是 `app/android/build/outputs/apk/default/release/android-default-<abi>-release.apk`；`splits.abi.isUniversalApk=true` 还会多出 `-universal-`。改了 ABI 列表要同步改 workflow 的收集步骤 |
| Release 建好了但 App 检查不到更新 | 检查 tag 是否严格是 `vX.Y.Z-harmony.N`、Release 不是 draft、资产名以 `-arm64-v8a.apk` 结尾；GitHub API 匿名限流 60 次/小时，短时间内反复点也可能 403 |
| App 提示更新到官方版本 | 说明运行的不是 harmony 版本号（补丁 0002 没套上或 `version.name` 没改），看 prepare-source.sh 的输出 |

## 8. 已知限制与后续方向

- 只出 `arm64-v8a`；需要 x86_64（卓易通 PC 端？）可把 `ani.android.abis` 改为 `all` 并在收集步骤加文件。
- 只跟踪稳定版。要跟 beta 需要放宽 workflow 和 `HarmonyForkVersion` 的正则。
- 没有 Firebase（`google-services.json` 是官方私有），Analytics/Crashlytics 不可用，属预期。
- 卓易通/鸿蒙对容器后台的冻结策略 App 无法绕过，用户仍可能需要在系统设置把卓易通/Animeko 的电池策略改为手动管理。
- 可考虑的后续补丁：在下载页提示"通知已被系统关闭"并跳转系统设置（`PermissionManager.checkNotificationPermission()` 已存在但无 UI 调用），见 `docs/ANALYSIS.md` 第五节。
