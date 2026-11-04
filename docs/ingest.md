# 摄影素材导入 MVP

今晚可用的入口是 CLI，收件台有基础 GUI。macOS 14+；从源码安装需要 Xcode Command Line Tools（`xcode-select --install`）。安装时编译 Swift 后端；安装后的使用无需每次编译，不需要 Python、Homebrew 或外部 metadata 工具。

## 当前架构与增量设计

原有 `bin/bpw` + `lib/common.sh` 加载可信 zsh/plist 配置，`scan-projects.sh` 创建 Apple 提醒事项，`sync-projects.sh` 验证挂载和目标后运行 safe rsync，launchd 负责补偿扫描与备份。SwiftUI App 通过 CLI JSON 读取真实目录和阶段状态。

新 `engine` Swift package 提供可测试的 ProjectStore / WorkspacePool / NativeMetadata / MediaScanner / DeviceDetector / SessionMatcher / IngestEngine。CLI、GUI 和 shell 共用这个后端。`workflow-engine.sh` 复用现有 ingest 锁、日志轮转和 operation status；原生后端再用内核 flock 保护 registry/session 写入，进程退出自动释放。备份与导入互斥，避免备份正在复制的半成品。

## 今晚步骤

此版本保留在本地工作区，没有 commit/push。不要为使用本地改动运行 `git pull`。

```zsh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
bpw doctor
bpw workspace list
```

原本的 `WORK_DIR` 自动成为默认 Workspace。若为在线外置路径，首次登记实际 Volume UUID；首次登记时原卷离线会明确报错，连接后重试。已有 pool 后离线卷仍显示 offline。Mac 的默认 local 路径继续跟随 `WORK_DIR` 配置变化；现有 GUI 选择一个新的在线外置 WORK_DIR 时会登记 UUID。

注册工作 SSD **项目根目录**（不要注册 SSD 根目录；现有素材不会搬动）：

```zsh
bpw workspace add portable "/Volumes/你的工作 SSD/Photography/Projects" --type external --name "工作 SSD"
bpw workspace list
```

可选择 SSD 实际已有的一级项目池，例如 `.../01_PROJECTS`。首层所有非隐藏目录与旧 scan 一样视为项目，会补 `.bpw-project.json`。注册外置 Workspace 会将其设为外置优先 Workspace；默认策略 `auto`：它在线优先，否则 local。

```zsh
bpw workspace preference auto
bpw new "平潭旅行" --workspace local  # 可选：提前创建
bpw ingest --dry-run                 # 只读扫描/推荐；不创建项目或复制素材
bpw ingest
```

扫描结果按拍摄日期分组，扫描到素材不会自动纳入导入。GUI 会预选所选项目日期（没有时尝试今天），显示每组文件数和容量；必须先生成 Import Plan，再单独点击“开始导入”。非交互 CLI 对多日期卡会拒绝无范围导入，使用 `--dates 2026-10-02`；多个日期用逗号分隔。单日期卡只有一个可选范围。

第一次选择“创建新项目”，输入“平潭旅行”；会建立标准目录、UUID、manifest，完成后建立 Session 并尝试补提醒。提醒权限失败不影响已完成的导入，稍后 `bpw scan` 重试。

自动检测要求系统声明介质 removable，且存在 DCIM/PRIVATE/M4ROOT；拒绝仅依据 ejectable 判断，避免普通 SSD 被当成卡。工作卷和配置的 Backup 卷均排除。读卡器若不能正确报告 removable，明确指定来源：

```zsh
bpw ingest "/Volumes/SONY_SD" --device A7R5
```

后续设备同样运行 `bpw ingest`。metadata 不足以辨认 DJI 型号时明确指定：

```zsh
bpw ingest "/Volumes/DJI_CARD" --device Pocket3
bpw ingest "/Volumes/DJI_CARD" --device Action6
bpw ingest "/Volumes/DJI_CARD" --device Air3S --dates 2026-10-02
```

可信拍摄 metadata、同一天时间重叠、7 天内 Session、项目在线且未 Done、唯一候选才自动匹配。多个候选、没有时间重叠、多日期或文件时间兜底都会要求选项目。文件创建时间兜底常见于部分视频/RAW，必须检查日期；它不会用于自动匹配。

非交互、GUI、批量脚本应明确项目或新项目：

```zsh
bpw project list
bpw ingest "/Volumes/DJI_CARD" --project <UUID> --device Pocket3 --dates 2026-10-02
bpw ingest "/Volumes/SONY_SD" --new "平潭旅行" --workspace portable --device A7R5 --dates 2026-10-02
bpw ingest "/Volumes/SONY_SD" --project <UUID> --dry-run --dates 2026-10-02
bpw ingest "/Volumes/SONY_SD" --project <UUID> --checksum --dates 2026-10-02
bpw imports
bpw status
```

`workspacePreference=ask` 时新项目交互询问 Workspace，非交互需 `--workspace`。已有同名项目不能重复 `--new`，后续使用项目编号或 UUID。

## 目录、记录与验证

```text
2026/2026-09_平潭旅行/
├── .bpw-project.json
├── 01_MEDIA/YYYY-MM-DD/A7R5/RAW/DSC01234.ARW
├── 01_MEDIA/YYYY-MM-DD/A7R5/JPEG/DSC01234.JPG
├── 01_MEDIA/YYYY-MM-DD/Pocket3/VIDEO/DJI_001.MP4
├── 02_PHOTO/
├── 03_VIDEO/
├── 04_CACHE_DELETE/
├── 05_EXPORTS/
├── 99_DOC/
└── .bpw/imports/<UUID>.json
```

项目库根目录选择 `01_PROJECTS` 这一层。名称以 `YYYY`、`YYYY-MM` 或 `YYYY-MM-DD` 加下划线开头时，项目会进入匹配的年份文件夹；没有年份前缀时归入当前年份。

媒体原文件名不变。RAW / JPEG（包含 HEIC/PNG）/ VIDEO 分类为保守统一布局；DJI 也按实际类型分类。`MediaCaptureDateResolver` 集中处理 metadata 优先，其次文件 birth time、最后 mtime。EXIF 没有时区时采用当前 Mac 时区；QuickTime 携带偏移量的日期先转成绝对时刻再按本地日历分组，旅行时仍需核对相机与 Mac 时钟。

本地状态继续使用 `~/.local/state/better-photography-workflow`：`workspaces.json`、`projects.json`、`sessions.json`、`import-history.json`（最近 100 次成功导入摘要）、`last-import.json`、原有 logs/status。Manifest 留在项目中，会随备份一起保留。GUI 显示最近成功导入、日期分组、字节和文件进度、当前文件、平均速度与预计剩余时间；扫描每发现 25 个素材报告一次计数。

Manifest 先记 running，逐文件原子记 verified，最后 success；错误写 failed。复制分块计算源 SHA-256，同时写目标临时文件并 fsync，发布使用 exclusive rename。默认核对源稳定性、目标存在、每文件大小、总数量和总字节；`--checksum` 再读取目标核对 SHA-256。

重复导入有对应 manifest 且源与目标 stat fingerprint（device/inode/size/mtime/ctime）、路径、capture timestamp 全部未变时快速 skip。来源换卡、目标改变、无记录或 `--checksum` 时比较内容；同名异内容是 conflict，整批预检失败，不覆盖。第一次复制流中计算哈希无需单独再读几百 GB 源文件。正常重复无需全量 hash；冲突比较和完整 checksum 可能较慢。

正常中断/失败保留 verified 文件，再执行相同命令即可跳过已完成文件、补未完成文件。使用 GUI“安全取消”或 `bpw cancel-ingest` 可在当前分块/文件边界停止；句柄关闭，未完成临时文件清理，已完成文件保留，manifest 标记 cancelled。强制终止可能留下 `.bpw/partials`，它们不会被当作成功媒体，也不会被同步。复制保持串行。空间预留为待复制 bytes 的 5%，至少 256 MiB。

## 旧状态迁移和 Primary

`.bpw-project.json` 是身份来源，registry 是位置缓存。先原子写 UUID，再将旧路径哈希的 reminder `.done` 和 stage/favorite plist **复制**到 UUID 名称，不删除旧状态。原始提醒路径保存在 identity 中；AppleScript 兼容原始路径并使用 UUID 识别后续提醒，完成标记继续避免重复创建。目录在同 Workspace 内移动/改名后 ID、阶段、收藏、提醒标记不变。

metadata 记录 `primaryWorkspaceId`。保留副本不会自动作为另一个 Workspace 的 active 项目；原路径仍存在时 registry 优先已登记位置。Primary 离线仍保留记录，`bpw project list/show` 显示 offline，旧 `bpw projects list` 兼容 App 只输出 online。

跨 Workspace 的 `move-project` 本轮没有实现，不能只在 Finder 复制后把两个副本都当作工作项目。未来接口必须在锁内执行 copy → verify → 原子改 Primary/registry；旧副本保留。当前 metadata/registry 已为它保留字段。

## 备份

沿用原有备份配置、挂载检查、目标逐级 containment/symlink/同文件系统检查及 rsync 错误码：

```zsh
bpw sync
bpw sync --project <UUID>
```

仍需 `ENABLE_BACKUP=true`，且配置的 Backup 卷在线。新目标为 `BACKUP_DESTINATION/<Project UUID>/<项目目录>/`，遍历 online Primary 项目；同名项目不同 UUID 不合并。旧备份位置保留，不搬动也不删除；首次使用新布局会再生成完整项目副本，需要空间。

新 multi-workspace sync 总是非删除模式，即使旧配置启用删除也不对多 Workspace 做 destructive rsync；`BACKUP_ALLOW_DELETE=false` 默认不变，原库 helper 的显式删除能力保留。排除 `.bpw/partials`，避免强制中断残留被作为备份成功媒体。

“导入完成”仅代表工作副本验证完成。程序不声明卡可以格式化；备份成功后仍建议自行核对目标并抽查素材可读性，再由你手动决定格式化。程序从不删除卡、不格式化。

## 验证边界

自动测试验证 fixture、真实 EXIF adapter、本机文件系统复制、CLI、原有安装回滚/提醒幂等/锁/rsync 和 GUI 数据契约。`tests/mounted-volume-tests.sh` 是需显式运行的真实挂载/ExFAT/卷改名/备份测试，只创建自己的临时 sparse images。当前 Codex 环境拒绝 `hdiutil create`（操作不被允许），所以这部分没有通过实测；真实 SD、读卡器、外置 SSD、大文件断连和 GUI 视觉均未验收。

目标文件系统在正式复制前探测 exclusive rename 支持；不支持时安全拒绝。自动型号识别和 Session score 是 beta；有明确设备选择和手动项目选择兜底。无 mount watcher、无后台自动复制，`autoIngestMatchedSession=false` 字段保留给未来 watcher，目前没有任何后台导入入口。
