# Syncthing for HarmonyOS

> **<span lang="en">[English](README_EN.md)</span> | 简体中文**

**Syncthing for HarmonyOS** 是一个面向 **HarmonyOS Next**（API 20，`6.0.0(20)`）平台的 Syncthing 客户端。它在应用进程内嵌原版 Go 语言 Syncthing 核心，并把 Android 版 Syncthing 的工作流（配对、状态、设备/文件夹管理、Web GUI、日志、最近更改、后台连续同步）移植到鸿蒙平板、PC/2in1 与手机。

> **一句话简介**：一个内嵌原版 Go Syncthing 核心的端到端加密文件同步客户端，支持 App 沙箱与下载/文档公共目录同步、后台连续同步与实时传输。

## 主要特性

- **内嵌原版 Syncthing 核心** —— 协议、发现、TLS 身份、BEP、索引、块交换、冲突处理与全部同步语义均由上游 Go 核心负责，ArkTS 只做 UI 与平台集成。
- **Harmony NAPI 桥接** —— 通过 `libsyncthing_napi.so` → `libsyncthing_core_bridge.so` 在 <u>同一应用进程内</u>调用 Go 核心导出函数 `Start(homeDir, logFile, guiAddress, apiKey)`，核心监听 `127.0.0.1:8384`。
- **设备与文件夹管理** —— 添加/编辑/删除设备，二维码配对（ScanKit，syscap 守卫），动态地址、Introducer、自动接受、压缩、暂停、不可信、共享文件夹；文件夹类型、变更监听、忽略权限、拉取顺序、版本化、重扫、逐文件夹状态。
- **公共目录同步** —— 申请 `READ_WRITE_DOWNLOAD_DIRECTORY` 用户授权后，可直接同步 `Download/Syncthing/<folderId>` 公共目录（统一容器），文件对用户可见。
- **后台保活（相对原版的重点增强）** —— `dataTransfer` + `multiDeviceConnection` 后台模式连续作业 + 常驻进度通知 + 定时探测兜底。

## 版本更新

### v2.0.2（2026-08-22）

相比 v2.0.1，本版主要改进：

- **启动/加载界面图标**：加载与错误界面不再使用鸿蒙默认图标，改用本应用 Syncthing 图标。
- **标签切换与高亮同步**：`设备 / 文件夹 / 状态` 切换时保留滑动动画，同时顶部选中高亮和新增的蓝色指示条会跟随页面一起移动，不再滞后到动画完全结束。
- **界面底色统一**：移除顶部/底部残留的纯白区域，避免打开设置后下方纯白遮挡内容；大部分页面统一为带灰的白（`page_background`），仅标签栏保持卡片白底。
- **设置页整理**：语言选择器与主题选择器一致地展示当前选中值；每个设置标题下的多个选项合并进同一个圆角卡片；`SYNCTHING连接` 更名为 `Syncthing连接`。
- **设备/文件夹页表头对齐**：设备页与文件夹页的“XX、添加”行背景统一为页面灰白背景。
- **运行条件/后台同步增强**：支持电源、省电、流量、定时等运行条件对 Syncthing 核心的暂停/恢复；状态页的 Follow / Force Start / Force Stop 立即生效。

## 设备支持与平台限制

**本项目当前针对平板（Tablet）与 PC/2in1 设备开发与验证（均 arm64）。** 手机的公共目录同步受鸿蒙平台能力门槛限制，目前不能开箱即用。详见下表：

| 能力 | 平板 / PC / 2in1（API 26+） | 手机（如 API 24） |
|---|---|---|
| App 沙箱内同步（`/data/storage/el2/base/files/<id>`） | ✅ 已实现 | ✅ 已实现 |
| 下载/文档公共目录同步（`Download/Syncthing/<id>`） | ✅ 已实现（无需选夹） | ❌ 平台不支持，需 API 26.0.0+ 的 HarmonyOS |
| 设备/文件夹管理、二维码、Web GUI、日志、后台同步 | ✅ 已实现 | ✅ 已实现（公共目录除外） |

**为什么手机公共目录受限，其根本原因是鸿蒙平台能力而非本应用缺陷：**

1. **直接获取下载目录的能力缺失。** 应用通过 `Environment.getUserDownloadDir()`（依赖系统能力 `SystemCapability.FileManagement.File.Environment.FolderObtain`）直连公共 `Download` 目录。据鸿蒙官方文档，该能力**仅对 2in1 / Tablet / API 26+ 设备开放**；在手机等其它设备上调用会返回错误码 `801`。实测 `canIUse` 在手机上为 `false`。
2. **文件夹选择的兜底同样受限。** 对不支持 `FolderObtain` 的手机，本应用会回退为弹出系统文件夹选择器，但鸿蒙的目录选择能力（`SystemCapability.FileManagement.UserFileService.FolderSelection`，`DocumentViewPicker` 选文件夹）**自 API 26.0.0 起才支持手机**。实测手机（API 24）该能力也不可用。
3. **动态授权结果。** 手机上 `READ_WRITE_DOWNLOAD_DIRECTORY` 的动态授权返回 `granted=false`，无法获得下载目录的写权限。

结论：**手机要支持公共目录同步，需 API 26.0.0+ 的 HarmonyOS 系统**。当前版本在手机上可正常使用 App 沙箱同步，公共目录同步与图库目录树同步暂不可用；如需在手机上同步公共目录，请使用平板/PC/2in1，或等待 API 26+ 设备。

### 其它平台限制

- **图库目录树**（如 `Gallery/Photos/2026/Trip`）与任意系统目录选择：鸿蒙公共媒体 API 只暴露 albums/assets，而非真实嵌套目录树，且通用文件夹选择器在真机上可能返回空 URI/失败。因此**无法**以系统图库目录作为同步根目录。
- 被评估并**否决**的替代方案：用 URI 抽象重写 Syncthing 文件系统后端（改造过于侵入核心）、沙箱镜像导入/导出（重复存储且无法满足目录树需求）、图库/媒体库投影（API 模型不匹配）。

## 参考与致谢

本项目深度参考并复用了以下先行项目与文档，**按重要性排序**：

### 1. 先行者项目（迁移基线）

- **[github.com/xinjinshao/SyncthingHarmonyOSNext](https://github.com/xinjinshao/SyncthingHarmonyOSNext)** —— 本项目**最重要的参考来源**。
  本仓库以其 **c-archive + NAPI 桥接架构** 为迁移基线：把 Go Syncthing 核心编译为静态库（`libsyncthingnative.a`），通过 Harmony NAPI 在同一应用进程内启动、监听 `127.0.0.1:8384`，并提供完整 ArkTS UI、API 20 友好。配对、状态、设备/文件夹管理等 UI 工作流均在此架构之上搭建。

### 2. Syncthing 上游项目

- **[github.com/syncthing/syncthing](https://github.com/syncthing/syncthing)** —— 被内嵌的 Go 核心本体，所有协议与同步语义来源于此；桌面端同步对端使用 Syncthing v2.1.3（Hafnium Hornet）。
- **[github.com/syncthing/syncthing-android](https://github.com/syncthing/syncthing-android)** —— Android 版应用，作为 UI/工作流参考；官方中文翻译（如 Introducer 译为“作为中介”）被直接引用进本项目 i18n 字典。

### 3. GitCode 适配 Wiki 与工具链

- **[lycodestore1/thirdpartydocs Wiki](https://gitcode.com/lycodestore1/thirdpartydocs)** —— 其中的 **《syncthing适配鸿蒙PC指南》** 对理解鸿蒙上 Syncthing 的权限坑（公共目录 `operation not permitted`、`READ_WRITE_DOWNLOAD_DIRECTORY` / `READ_WRITE_DOCUMENTS_DIRECTORY` 用户授权、`HOME` 环境变量重定向到下载/文档目录）提供了关键参考；**《go应用适配鸿蒙PC指南》** 说明了鸿蒙上 Go 应用的两种集成方式（hnp 可执行文件 / C 动态库）与权限拦截模型。
- **[openharmony-sig/ohos_golang_go](https://gitcode.com/openharmony-sig/ohos_golang_go)** —— 适配鸿蒙的 Go 编译器工具链（支持 `GOOS=openharmony`，当前版本 1.24.5），用于交叉编译鸿蒙 aarch64 的 Go 核心/桥接产物。

### 4. 其他参考

- **[HarmonyOS Application Development Guide](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/application-dev-guide)** —— 鸿蒙应用开发官方文档，用于权限、后台任务、扫描等平台能力。
- **文件夹级授权思路** —— 通过 `DocumentViewPicker` 选择文件夹 + `persistPermission` 持久化授权的方案，是公共目录同步实现的依据之一。
- **[github.com/xiaobaigroup/ClashBox](https://github.com/xiaobaigroup/ClashBox)**（mihomo 代理客户端）—— 仅作为后台保活策略的分析对象。其模拟位置/画中画/伪下载等规避手段经评估明确不采用，本项目后台保活走官方合规路线。

对上述所有先行者与开源社区贡献者的成果表示敬意与感谢。

## 新增与适配功能

本仓库在基线之上，针对 HarmonyOS Next 做了以下主要新增与适配：

### 架构：c-archive 同进程集成

采用 **c-archive + NAPI 桥接**，让 Go 核心与 App <u>同一进程内启动</u>，而非 hnp 独立进程。理由是核心需要直接以 POSIX 路径读写公共目录；同进程 c-archive 能直接访问 `Environment.getUserDownloadDir()` 等授权后的公共路径。产物 `libsyncthingnative.a`（约 80 MB）与 `syncthing_core`（约 22 MB）随源码提交，普通 HAP 构建无需安装补丁 Go 工具链。

### 公共目录同步

- 修复了“公共目录不可行”的根因：此前把 `READ_WRITE_DOCUMENTS_DIRECTORY` 误当 `system_grant`，从未真正向用户申请（故始终无权限）。
- 申请 `ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY`（user_grant 对话框）→ 用 `Environment.getUserDownloadDir()` 定位下载目录 → 以 **统一容器** `Download/Syncthing/<folderId>` 承载所有同步文件夹，授权跨重启持久、无需每次重新选夹。
- 对不支持 `FolderObtain` 的手机，回退为系统文件夹选择器选取公共目录（详见 [设备支持与平台限制](#设备支持与平台限制)）。
- 新文件夹默认启用 `ignorePerms`，规避鸿蒙下载目录文件系统的权限差异导致同步失败。
- 复用了基线中的沙箱同步路径，因场景差异所作的小修正（页面加载空值守卫）已并入。

### 后台保活

- **常驻进度通知**：以约 10 秒间隔用**真实**同步指标（来自 REST 连接状态）更新系统常驻通知，避免应用被系统判定闲置而回收；并区分“用户主动删除通知”与“系统取消”两种情形（用户删除不自动重启，形成“删除即停止 → 手动重开”闭环）。
- **定时探测兜底**：注册系统定时作业（`WorkSchedulerExtensionAbility`）周期唤醒，探测核心是否存活并进行 REST 探活拉起。
- 修复了长时间后无更新导致的被杀问题，实测 4 小时无周期被杀。
- 严格走官方合规路线，明确排除任何伪造数据的规避手段（如模拟定位、伪下载、画中画等）。

### 前端中文化（i18n）

- 自建字典 `L10n.ets`（约 390 个 key），内置 `zh_CN` / `en_US` 双语言资源，`L10n.t()` 统一取词。
- 设置页提供语言选择器（跟随系统 / 中文 / English），系统语言通过 `@kit.LocalizationKit` 探测，切换后应用整体重载。
- 支持 `%s/%d` 有序格式化与 `%%` 转义；核心文件夹状态映射为中英文；Syncthing 术语（如 Introducer）沿用 syncthing-android 官方中文翻译（“作为中介”）。
- ArkUI 特点处理：`TextInput` 存在“非受控、打印文本不随外部状态刷新”的行为，采用只读 `Text` 实时展示 +「自定义」按钮方案实现文件夹标签跟随输入。

### 权限与工程适配

- 声明权限：`INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING`、`CAMERA`、`READ_WRITE_DOCUMENTS_DIRECTORY`、`READ_WRITE_DOWNLOAD_DIRECTORY`、`FILE_ACCESS_PERSIST`。
- `backgroundModes: ["dataTransfer", "multiDeviceConnection"]`。
- App 源码全部使用现代 `@kit.*` 导入，无残留 `@ohos.*`；可选能力（后台任务、扫码、文件夹选择）运行时以 syscap 守卫，缺失时安全降级。
- C 桥接层线程模型规避 `napi_env` 跨线程访问，共享错误状态以互斥锁保护。

## 与原版（Android）的差异

| Android 表面 | HarmonyOS Next 状态 |
|---|---|
| 主标签、状态、设备、文件夹 | 已实现 |
| 添加/编辑设备与二维码配对 | 已实现 |
| 添加/编辑文件夹、共享、重扫、版本化、拉取顺序 | 已实现 |
| 设置、Web GUI、日志、最近更改 | 已实现 |
| 运行条件与后台同步 | 部分实现；Wi-Fi/移动数据、流量、电源、省电、定时、强制启停、连续后台任务已启用；漫游、SSID 白名单、主同步、飞行模式仍平台受限 |
| 文件夹选择器/公共目录同步 | App 沙箱 + 下载公共目录已实现；手机与图库目录树受 API 限制（见上文） |
| 分享扩展、相机/拍照工作流、快捷设置磁贴 | 未实现 |

## 架构与核心调用流程

```text
EntryAbility
  -> pages/Index.ets
  -> SyncthingService.initialize()
  -> SyncthingProcessManager.initialize()
  -> RestApi.initialize()
  -> SyncthingService.startService()
  -> SyncthingProcessManager.start()
  -> SyncthingNative.getVersion()/startSyncthing()
  -> libsyncthing_napi.so
  -> libsyncthing_core_bridge.so
  -> Go exported Start(homeDir, logFile, guiAddress, apiKey)
  -> Syncthing core starts REST on 127.0.0.1:8384
  -> ArkTS pages consume status/config/events through RestApi
```

ArkTS 负责 UI、生命周期、应用偏好、后台任务、通知、沙箱/公共目录路径准备与 REST 轮询；Go 核心负责全部 Syncthing 协议行为（发现、TLS、BEP、索引、块交换、冲突、同步）。用 ArkTS 重写协议明确不在基线范围内。

## 存储模型

支持两种同步存储模式：

1. **App 沙箱**：`/data/storage/el2/base/files/<folder-id>` —— 任意设备均可用，但文件对系统图库不可见。
2. **下载公共目录（统一容器）**：`Download/Syncthing/<folderId>` —— 申请 `READ_WRITE_DOWNLOAD_DIRECTORY` 后直连，文件对用户可见；仅平板/PC/2in1/API 26+ 可用（见 [设备支持与平台限制](#设备支持与平台限制)）。

## 构建与运行

### 编译与安装 HAP

普通 HAP 构建**不需要**补丁 Go 工具链——所需 native/core 产物已随仓库提交：

- `entry/src/main/libs/arm64-v8a/libsyncthingnative.a`
- `entry/src/main/libs/arm64-v8a/libsyncthingnative.h`
- `entry/src/main/resources/rawfile/syncthing_core`

使用 **DevEco Studio** 或配置好的鸿蒙命令行环境：

- 需 DevEco Studio、Node.js、Hvigor 及匹配的 HarmonyOS SDK（`targetSdkVersion` / `compatibleSdkVersion` = `6.0.0(20)`）。
- 构建 HAP 时需先在 DevEco Studio 中配置你自己的 `signingConfigs`（仓库内的 `build-profile.json5` 出于安全考虑未附带任何签名材料）。
- 构建输出：签名 HAP `entry/build/default/outputs/default/entry-default-signed.hap`；未配置签名时输出 `entry-default-unsigned.hap`。
- `hdc install` 安装到平板/PC 后启动，首次运行按向导申请下载目录授权。

随 GitHub Release 发布一个可直接安装的真机 HAP：`Syncthing-for-HarmonyOS-v2.0.2-unsigned.hap`（未签名；如需安装到真机请先用 DevEco Studio 为其签名）。可从 [v2.0.2 Release](https://github.com/forwardz666/Syncthing-for-HarmonyOS/releases/tag/v2.0.2) 下载。

### （高级）重新构建 Go 核心

仅在调整内嵌核心/NAPI 桥接时需要：

- 需鸿蒙 Go 工具链（如 `ohos_golang_go`，`GOOS=openharmony`）与鸿蒙 clang 交叉编译。
- 参考 `build_syncthing_harmonyos.py` 与 GitCode Wiki 的鸿蒙适配指南（见上文“参考与致谢”）。

## 验证

- ArkTS/HAP 构建通过（API 20），签名 HAP 可安装并启动于平板（OpenHarmony 7.0 / API 26）与手机。
- 嵌入核心启动，暴露 `127.0.0.1:8384`，REST 返回本地设备 ID；桌面 Syncthing 与设备互加并显示活跃 LAN 连接。
- 文件夹创建、共享、扫描、状态渲染经 UI + REST 轮询验证；下载公共目录双向同步经平板真机验证。
- 连续后台任务创建、心跳诊断、运行条件决策与暂停/恢复在 hilog 可见。

### 已验证设备

- 平板（OpenHarmony 7.0，API 26）
- 手机（API 24，仅沙箱同步与公共目录受限验证）

## 文档

- `ARCHITECTURE.md`、`MODULE_DESIGN.md`、`CHANGELOG.md`：架构、模块设计与变更记录。

## 仓库内容

- `entry/src/main/ets/`：ArkTS UI、服务、REST 客户端与 native 封装。
- `entry/src/main/cpp/`：Harmony NAPI 桥接源码。
- `entry/src/main/libs/`、`entry/src/main/resources/rawfile/`：受控提交的预编译核心/桥接产物。
- `build_syncthing_harmonyos.py`：把 Syncthing Go 核心交叉编译为鸿蒙静态库的构建脚本。
- `Syncthing-for-HarmonyOS-v2.0.2-unsigned.hap`：随 GitHub Release 发布的未签名 HAP（不纳入仓库，避免仓库体积膨胀）。

## 许可证

本项目是一个基于 **Syncthing** 构建的 **HarmonyOS Next 迁移工程**。

- 内嵌的 Syncthing 核心遵循上游 **Mozilla Public License 2.0（MPL-2.0）**，见 [github.com/syncthing/syncthing](https://github.com/syncthing/syncthing)。重新分发源码或二进制时，必须保留上游 Syncthing 与 Syncthing Android 的许可证义务与版权声明。
- Syncthing Android（工作流/UI/翻译参考）同样遵循 MPL-2.0。
- **本迁移仓库自身未附带独立 LICENSE 文件**：新增的 ArkTS UI、Harmony NAPI 桥接、后台保活、i18n 等代码沿用上游 Syncthing（MPL-2.0）的授权方式进行对待，直至维护者明确为仓库补充独立的许可证声明。
- **第三方资源版权归属**：先行者基线（xinjinshao）、GitCode Wiki（lycodestore1）、ClashBox（xiaobaigroup）等代码/文档版权归其各自原作者所有；使用前请确认其各自授权条款。本仓库维护者对本仓库新增内容依法保留相应版权，具体授权方式以日后独立 LICENSE 文件为准。
- 运行时无第三方原生/前端依赖；`oh-package` 仅含单元测试开发依赖 `@ohos/hypium`（1.0.24）与 `@ohos/hamock`（1.0.0），均来自 OpenHarmony 官方 ohpm 仓库。
