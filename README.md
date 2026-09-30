# Animeko 在鸿蒙 7 卓易通下 BT 下载通知不弹出 / 后台下载丢失 — 排查与修复

针对 [open-ani/animeko](https://github.com/open-ani/animeko) 在 HarmonyOS 7 的卓易通（Android 兼容容器）中出现的现象:

> 开启下载任务后不弹出"正在下载"通知; App 切到后台或锁屏后下载停止 / 下载活动丢失。

本仓库包含:

- 本文: 对 Animeko 源码 (`b3c522f`, 2026-09) 中 Android 前台服务与通知链路的分析、可确认的问题点、修复方案与设备端验证方法。
- [`patches/0001-android-harden-foreground-service-notification.patch`](patches/0001-android-harden-foreground-service-notification.patch): 可直接 `git am` 到 animeko 主分支的修复补丁。

## 结论摘要

1. **可以从代码层面确认**: Animeko 的前台服务通知逻辑依赖 `NotificationManager.getActiveNotifications()` 来决定"要不要调用 `startForeground()`"和"要不要刷新通知"。这个假设在 AOSP 手机上基本成立, 但在卓易通这类把 Android 通知桥接到宿主系统的环境里并不可靠。一旦 `activeNotifications` 的返回和真实状态不一致, 就会出现下面两种后果, 与用户描述的现象一致:
   - 通知永远停留在"BT 下载服务正在运行", 开始下载后不会变成"正在下载 N 个资源" (更新被跳过);
   - 更严重的: 服务根本没有调用 `startForeground()`, 以普通后台服务在跑。App 切后台 / 锁屏后容器进程被系统冻结或回收, 下载就"丢"了。
2. **无法在这里 100% 复现**: 我没有鸿蒙 7 + 卓易通设备, 只能做代码审计与逻辑推演。卓易通本身对后台进程的管控非常激进 (华为社区多篇反馈"鸿蒙 NEXT 猛杀卓易通后台"), 这部分不是 App 能修的。补丁的目标是**把 App 侧能做对的做对**, 让前台服务在任何环境下都真正处于前台状态, 并在通知被系统屏蔽时留下清晰日志, 便于进一步定位。
3. **修复内容 (3 个文件, 均在 `app/shared/app-data/src/androidMain/kotlin/domain/torrent/service/`)**:
   - `ServiceNotification.kt`: 每次 `onStartCommand` 都调用 `startForeground()`; 用内部状态代替 `activeNotifications` 判断; 保留上一次的显示状态避免重启后回退成"空闲"; 放宽异常捕获并带堆栈打日志; 通知被禁用/渠道被屏蔽时打警告日志。
   - `AniTorrentService.kt`: 前台启动被系统拒绝时 `stopSelf()`, 不再以"僵尸后台服务"继续运行 (与 `PikPakCacheService` 现有做法一致)。
   - `AniTorrentServiceStarter.kt`: 等待服务启动广播加 15 秒超时, 广播丢失时走重试而不是永久挂起。

## 一、涉及的代码链路

Animeko Android 端 BT 下载引擎运行在独立进程 `:torrent_service` 的前台服务里:

| 组件 | 位置 | 职责 |
| --- | --- | --- |
| `AniTorrentService` | `app-data/.../service/AniTorrentService.kt` | 前台服务本体, `onStartCommand` 里创建通知并广播启动结果 |
| `ServiceNotification` | `app-data/.../service/ServiceNotification.kt` | 封装通知渠道、`startForeground()`、通知更新 |
| `AniTorrentServiceStarter` | `app-data/.../service/AniTorrentServiceStarter.kt` | App 进程侧: `startForegroundService()` → 等启动广播 → `bindService()` |
| `TorrentServiceConnectionManager` | `app-data/.../service/TorrentServiceConnectionManager.kt` | 根据 App 前后台状态与未完成任务决定是否保持服务 |
| `AniApplication` | `app/android/src/default/kotlin/AniApplication.kt` | 组装以上组件; 提供 `startForegroundService` 实现 |
| Manifest | `app/android/src/default/AndroidManifest.xml` | API 34+ 用 `mediaPlayback` 类型, 以下用 `dataSync`; 声明 `POST_NOTIFICATIONS`/`FOREGROUND_SERVICE*` |

流程: 用户点下载 → `SubjectDownloadsHost` 申请 `POST_NOTIFICATIONS` (仅在此处申请) → `ConnectionManager` 把服务生命周期置为 `RESUMED` → `Starter.start()` 调 `startForegroundService()` → 服务 `onStartCommand` → `ServiceNotification.createNotification()` → `startForeground()` → 广播 `INTENT_STARTUP` → App 侧 `bindService()` → 引擎开始工作 → 服务内协程每 2s 调 `updateNotification()` 刷新下载数/速度。

## 二、确认的问题点

### 1. `createNotification()` 用 `activeNotifications` 决定是否调用 `startForeground()`

原代码 (`ServiceNotification.kt`):

```kotlin
fun createNotification(service: Service): Boolean {
    val currentNotification = notificationService.activeNotifications.find { it.id == notificationId }
    if (currentNotification != null) return true   // <-- 直接返回, 不调用 startForeground
    ...
    service.startForeground(notificationId, notification)
}
```

在 AOSP 上, 前台服务进程死亡时系统会一并撤掉它的通知, 所以"通知还在"≈"服务还在前台"。但这个等价关系在卓易通里不成立: 卓易通是运行在 iSulad 容器里的 Android 子系统, 通知要经容器桥接到鸿蒙通知中心。只要出现下面任意一种情况, 服务就会**跳过 `startForeground()`**:

- 上一次服务进程被容器回收, 但桥接出去的通知没有同步撤销 (残留通知);
- `getActiveNotifications()` 在容器内返回了宿主侧已存在的同 id 通知。

跳过 `startForeground()` 的后果:

- 服务实际上是普通后台服务。App 一切到后台或锁屏, 容器按宿主策略冻结进程, 下载停止 → 用户看到的"后台/锁屏后下载活动丢失";
- 在标准 Android 上还会因为 `startForegroundService()` 之后没有及时 `startForeground()` 抛 `RemoteServiceException` 让 `:torrent_service` 崩溃。

### 2. `updateNotification()` 也用 `activeNotifications` 做门禁

```kotlin
fun updateNotification(displayStrategy: NotificationDisplayStrategy) {
    notificationService.activeNotifications.find { it.id == notificationId } ?: return  // <-- 找不到就不更新
    notificationService.notify(notificationId, buildNotification(...))
}
```

如果容器内 `getActiveNotifications()` **不**回报前台服务通知 (返回空列表), 那么 `startForeground()` 之后所有更新都被静默丢弃: 通知一直显示"BT 下载服务正在运行", 永远不会出现"正在下载 N 个资源"。这直接对应"下载任务开启后不弹出通知"。

### 3. 前台启动被拒绝后服务没有退出

`AniTorrentService.onStartCommand` 在 `createNotification()` 返回 `false` 时只是返回 `START_NOT_STICKY`, 服务仍在运行。它此时没有前台状态, 进入后台就会被冻结; 同一仓库里后来写的 `PikPakCacheService` 已经改为 `stopSelf()`, 两处行为应一致。

### 4. 只捕获 `ForegroundServiceStartNotAllowedException` 且不打堆栈

其他同族异常 (`MissingForegroundServiceTypeException`、`SecurityException`) 不会被捕获, 在兼容层上更容易触发; 而已捕获的异常只记录 message, 排查时缺少上下文。

### 5. 等待启动广播没有超时

`AniTorrentServiceStarter.start()` 在收到 `INTENT_STARTUP` 广播前无限挂起。服务进程若在 `onStartCommand` 之前就被回收, 或者容器对跨进程 `RECEIVER_NOT_EXPORTED` 广播的投递方式与 AOSP 不同, App 侧会永远停在"启动中", 下载不会开始也不会报错。

### 6. 通知权限只在"开始下载"时申请, 且没有任何"通知已被关闭"的提示

`POST_NOTIFICATIONS` 只在 `SubjectDownloadsHost` 里申请一次; `PermissionManager.checkNotificationPermission()` / `openSystemNotificationSettings()` 已实现但**没有任何 UI 调用**。用户在卓易通里拒绝过一次 (或卓易通/鸿蒙侧关闭了该应用的通知), 之后就再也看不到通知, App 也不会提示。前台服务本身在通知被关时仍可运行, 但用户失去了"看到在下载、点通知停止"的入口。这一点补丁只做了日志层面的处理 (见下方"未包含的改动")。

## 三、修复方案 (补丁内容)

### `ServiceNotification.kt`

- 新增 `isForeground`、`lastDisplayStrategy` 两个内部状态。
- `createNotification()`:
  - **每次都调用** `startForeground()` (幂等), 不再根据 `activeNotifications` 跳过;
  - 通知内容用 `lastDisplayStrategy`, 粘性重启 / 重复 start 不会把"正在下载"回退成"空闲";
  - 捕获 `IllegalStateException` (覆盖 `ForegroundServiceStartNotAllowedException`、`MissingForegroundServiceTypeException` 等) 与 `SecurityException`, 带堆栈记录警告;
  - 新增 `warnIfNotificationsAreHidden()`: `areNotificationsEnabled()` 为假或渠道 importance 为 `NONE` 时打警告, 方便从用户日志里直接确认"通知被系统屏蔽"。
- `updateNotification()`: 记录 `lastDisplayStrategy`; 仅当 `isForeground` 时 `notify()`; 不再查询 `activeNotifications`。

### `AniTorrentService.kt`

- `onStartCommand` 中 `createNotification()` 返回 `false` 时 `stopSelf()` 并返回 `START_NOT_STICKY`, 让 App 回到前台后由 `ConnectionManager` 重新拉起。

### `AniTorrentServiceStarter.kt`

- 把等待启动广播抽成 `awaitStartupBroadcast()`, 外层 `withTimeoutOrNull(15s)`; 超时抛 `StartRespondFailure`, 交给 `LifecycleAwareTorrentServiceConnection` 的重试循环。

### 应用补丁

```bash
git clone https://github.com/open-ani/animeko.git && cd animeko
git am /path/to/patches/0001-android-harden-foreground-service-notification.patch
```

补丁基于 `b3c522f` (main, 2026-09-30) 生成。

## 四、在设备上验证 / 进一步确认根因

卓易通支持 adb (需在鸿蒙开发者选项开启 USB 调试), 建议按以下步骤取证:

1. **确认容器 Android 版本** (决定走 `dataSync` 还是 `mediaPlayback` 分支, 以及是否需要 `POST_NOTIFICATIONS`):

   ```bash
   adb shell getprop ro.build.version.sdk
   ```

2. **开始一个 BT 下载, 然后查看服务是否真的处于前台**:

   ```bash
   adb shell dumpsys activity services me.him188.ani | grep -E "isForeground|foregroundId|AniTorrentService"
   ```

   期望 `isForeground=true`、`foregroundId=114`。若为 `false`, 就是本文第 1 点的情况。

3. **查看通知是否真的被投递**:

   ```bash
   adb shell dumpsys notification --noredact | grep -A5 "me.him188.ani"
   adb shell cmd notification list me.him188.ani   # 若容器支持
   ```

4. **查看通知权限与渠道状态**:

   ```bash
   adb shell dumpsys package me.him188.ani | grep -i POST_NOTIFICATIONS
   adb shell cmd notification get_importance me.him188.ani me.him188.ani.app.domain.torrent.service.AniTorrentService
   ```

5. **抓日志** (打了补丁后关键字更完整):

   ```bash
   adb logcat | grep -E "ServiceNotification|AniTorrentService|TorrentServiceConnection|ForegroundService"
   ```

   关注: `Foreground service start not allowed`、`Notifications are disabled for this app`、`Notification channel ... is blocked`、`startup broadcast not received`。

6. **切后台 / 锁屏 1~2 分钟后回到 App**: 若日志出现 `client unbind anitorrent` 后再无 `AniTorrentService is stopping` 却重新走了 `[1/4] Started service`, 说明进程被容器直接杀掉 (不是 App 逻辑主动停止), 属于卓易通/鸿蒙后台策略问题, 需要用户侧在"设置 > 应用 > 卓易通 / Animeko > 电池"里改为手动管理、允许后台活动。

## 五、未包含在补丁中的改动 (建议后续跟进)

- **UI 提示通知被关闭**: 在下载页 / 设置页调用已有的 `PermissionManager.checkNotificationPermission()`, 为假时给出 banner 并提供 `openSystemNotificationSettings()` 入口; 同时在依赖服务的播放路径 (`requestService(token, true)`) 也申请一次通知权限。涉及 commonMain UI 与 i18n 字符串, 需要 UI 层测试, 本次未改。
- **`mediaPlayback` 前台服务类型的风险**: API 34+ 为绕开 Android 15 对 `dataSync` 6 小时后台限制而声明了 `mediaPlayback`。若卓易通把它映射为鸿蒙的 `AUDIO_PLAYBACK` 长时任务, 没有真实音频会话时可能被宿主提前结束。目前无法验证, 仅作风险提示。
- **卓易通 / 鸿蒙宿主的后台冻结**: App 无法绕过, 只能通过系统设置放开。

## 六、验证状态

- 修改仅限 3 个 Android 源文件, 未改动公共接口。
- 已在 animeko `b3c522f` 上执行 `./gradlew :app:shared:app-data:compileAndroidMain` (Android SDK 37, JDK 21), 编译通过, 修改的文件无新增告警。
- 补丁已验证可用 `git am` 干净地应用到上游 `main`。
- 本环境无 Android 设备 / 卓易通, 未能进行运行时验证, 请按第四节步骤在真机上确认。
