# 本轮开发记录

## 实现与兼容

完成 CLI 导入闭环、UUID 项目与状态迁移、多 Workspace、原生图片/视频 metadata 扫描、明确设备选择、保守 Session 匹配、空间/冲突预检、copy-only 重试、原子 manifest、默认 size/count 校验及可选目标 checksum。SwiftUI 收件台加入基础操作和最近成功导入。

复用可信配置校验、scan/ingest/sync 锁、日志轮转、operation status、提醒事项和原有安全 rsync。新备份按 online Primary 的 UUID 隔离目录，始终非删除。旧状态和备份保留；不迁移或删除用户素材。

任务开始时工作区已存在许多未提交的 App/UI、项目状态、安装和文档改动。本轮在其上增量接入，没有 reset/stash/clean、没有 staging/commit/push。版本仍为工作区已有的 0.4.0，新功能记录在 Unreleased。

## 本轮新增文件

- `engine/Package.swift`
- `engine/Sources/BPWCore/Storage.swift`
- `engine/Sources/BPWCore/Projects.swift`
- `engine/Sources/BPWCore/Media.swift`
- `engine/Sources/BPWCore/Sessions.swift`
- `engine/Sources/BPWCore/Ingest.swift`
- `engine/Sources/BPWEngine/main.swift`
- `engine/Tests/BPWCoreTests/WorkflowTests.swift`
- `scripts/workflow-engine.sh`
- `app/Sources/BPWDesktop/IngestView.swift`
- `tests/mounted-volume-tests.sh`
- `docs/ingest.md`
- `docs/development-report.md`

## 本轮修改文件

- `bin/bpw`
- `lib/common.sh`
- `scripts/scan-projects.sh`
- `scripts/sync-projects.sh`
- `scripts/create-reminders.applescript`
- `scripts/doctor.sh`
- `scripts/project-state.sh`（任务开始时已存在但未跟踪；改为兼容原生命令转发）
- `install.sh`
- `app/build-app.sh`（临时构建缓存；仅清理新生成 bundle 的属性；默认本机缓存输出并验证签名）
- `config/config.example`
- `tests/run-tests.sh`
- `app/Sources/BPWDesktop/AppModel.swift`
- `app/Sources/BPWDesktop/BPWClient.swift`
- `app/Sources/BPWDesktop/DashboardView.swift`
- `app/Sources/BPWDesktop/SettingsViews.swift`
- `app/Tests/BPWDesktopTests/BPWDesktopTests.swift`
- `.github/workflows/ci.yml`
- `.gitignore`
- `README.md`
- `README.zh-CN.md`
- `CHANGELOG.md`
- `docs/configuration.md`
- `docs/gui.md`
- `docs/installation.md`
- `docs/workflow.md`

已有的 ActiveProjectsView、CreatorProjectModels、LiquidGlassStyles、RootView、MenuBarContent、BPWDesktopApp、Info.plist、design-qa 文件及图片不是本轮新做的 UI 工作，原有改动保留。

## 验证

- `./tests/run-tests.sh`：86 passed、0 failed。含原 70 条回归，以及 CLI 创建/导入、manifest、重复跳过、同大小冲突、保留源和目标、dry-run、Workspace 排除。
- `swift test --scratch-path /private/tmp/bpw-engine-validation --package-path engine`：47 passed、0 failed。
- `swift test --scratch-path /private/tmp/bpw-app-validation --package-path app`：7 passed、0 failed（原 5 条 + 2 条导入契约）。
- 所有 zsh 脚本语法检查、AppleScript 编译、`git diff --check` 通过。
- `./app/build-app.sh` release 构建通过；Documents File Provider 会重新添加 FinderInfo，构建脚本已将默认产物改为本机缓存输出并验证签名。
- 原生验收测试使用真实 EXIF JPEG fixture，从 A7R5 首次创建平潭旅行，随后 Pocket3/Action6/Air3S 不指定项目自动匹配，重插 A7R5 skip，并确认 source 保留。
- 视频测试生成真实 MOV，验证 AVFoundation creation date 和型号读取；RAW/DJI 容器类型扫描另有 fixture 测试。
- 安装/回滚/doctor 测试在隔离 HOME 和 mock Reminders/launchctl 中运行；没有重新安装或加载用户真实服务。
- `./tests/mounted-volume-tests.sh`：未完成。系统拒绝 `hdiutil create`，报“操作不被允许”；不能记作 8 条通过。该脚本保留用于具备权限的普通终端，创建并清理自己的测试映像。

构建缓存移到临时目录，是因为仓库所在 Documents 的扩展属性曾使测试签名失败。没有移除仓库属性。

## 今晚使用和风险

完整命令见 [ingest.md](ingest.md)。直接从当前本地工作区运行 `./install.sh`，不要为了这些未提交改动 `git pull`。登记工作 SSD 的项目目录，然后第一次 `bpw ingest` 创建平潭旅行；后续设备运行同样命令，Unknown 时用 `--device`。

安全路径已通过自动测试；真实外置工作 SSD、ExFAT、真实 SD/读卡器、多百 GB 导入、拔盘恢复和 GUI 视觉仍未实测。文件系统能力探测在复制前安全拒绝不支持的目标。型号推断与 Session scoring 仍是 beta，metadata 时间不足时要求手动选择。

用户已说明备份盘移除；当前不依赖它完成代码测试。真实备份挂载和第二份副本验收需之后连接再验证。没有执行真实素材导入，也没有写用户备份盘。

没有实现 mount watcher、后台自动导入和跨 Workspace move-project。格式化、确认第二份副本、相机/Mac 时钟与型号不明时设备选择均由用户手动完成。新 backup 目标布局首次会复制新的一份完整项目，旧位置保留，需额外空间。
