# better-photography-workflow

一个面向视频创作者的原生 macOS 素材与项目工作流。SwiftUI App 会读取主素材库中的真实项目目录，按设备展示素材来源，保存每个项目的制作阶段、进度、收藏与 Done 状态；底层命令行仍可创建提醒事项、补齐目录结构，并通过 `rsync` 进行可选的第二份备份。

项目只使用 macOS 原生能力：SwiftUI、zsh、AppleScript、Reminders、launchd、rsync 及系统命令；同时支持 Apple Silicon 与 Intel Mac，也不会直接读写 Apple Photos Library 的内部文件。

## 素材导入 MVP

已增加稳定 Project ID、多 Workspace、媒体扫描、复制导入、manifest、重复保护、Session 匹配和 Primary 项目备份。今晚使用步骤、配置、迁移和实测边界见 [素材导入说明](docs/ingest.md)。

## 快速开始

```zsh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
bpw doctor
bpw new "猫咪写真"
./app/build-app.sh
open "$HOME/Library/Caches/better-photography-workflow/app/摄影工作流.app"
```

默认会创建：

```text
~/Pictures/Photography_Work/2026-07-19_猫咪写真/
├── 01_MEDIA/
├── 02_PHOTO/
├── 03_VIDEO/
├── 04_CACHE_DELETE/
├── 05_EXPORTS/
└── 99_DOC/
```

并在配置的提醒事项列表中创建初筛、精选、调色精修、导出归档四项任务。默认截止日分别为项目创建后第 1、3、7、10 天的 20:00。

## 命令

```text
bpw install              安装或更新程序及后台服务
bpw uninstall [--purge]  卸载；默认保留配置、状态和日志
bpw init                 创建默认配置和工作目录，不覆盖已有配置
bpw new "项目名称"       新建项目并立即创建提醒事项
bpw scan                 扫描一级非隐藏项目目录
bpw sync                 执行安全增量备份
bpw status               查看配置、项目、硬盘和服务状态
bpw projects list        以 JSON 输出真实项目及工作流状态
bpw projects set-stage <项目路径> <阶段>
bpw projects set-favorite <项目路径> <true|false>
bpw doctor               检查系统环境、配置、权限和服务
bpw logs                 查看最近 100 行主日志
bpw version              显示当前版本
bpw config export        输出供图形界面使用的 JSON 配置
bpw config apply <文件>  校验并应用 plist 或 JSON 配置
bpw app                  打开图形界面
bpw help                 显示帮助
```

详细资料：[安装](docs/installation.md)、[配置](docs/configuration.md)、[权限](docs/permissions.md)、[工作流](docs/workflow.md)、[故障排查](docs/troubleshooting.md)。

原生 macOS 菜单栏与设置应用的构建和使用方法见：[图形界面](docs/gui.md)。

主素材库可以位于 Mac，也可以选择 SSD 的项目库根目录，例如 `/Volumes/<SSD 名称>/01_PROJECTS`。新项目名称以年份开头（如 `2027-01_旅行`）时会放入对应年份目录；没有年份前缀时按当前年份归档。项目内部按配置创建子目录。如果 SSD 是唯一素材库，可将它设为主素材库并关闭可选的第二份备份。

## 安全与幂等

- 处理 online Primary Workspace 下的一级非隐藏项目目录。
- 第一层幂等：项目 UUID 完成标记；旧路径 SHA-256 标记与阶段状态会自动复制迁移，旧标记保留。
- 第二层幂等：AppleScript 在列表中查找标题、完整项目路径及来源均匹配的提醒事项。
- 仅在四条提醒事项全部成功创建或确认已存在后写入本地状态；中断后重试不会重复创建。
- 备份同时检查 `diskutil` 与系统挂载表，不会只因 `/Volumes/卷名` 目录存在就判断硬盘在线。
- 默认不向 `rsync` 传递 `--delete`，因此不会删除目标硬盘已有文件。
- 扫描和同步锁记录 PID 与进程启动身份；崩溃或重启留下的失效锁会自动回收。
- 备份目标逐级拒绝符号链接，并确认真实路径和文件系统仍属于已挂载外接卷。
- 主日志达到 1 MiB 后自动轮转，保留最近三份；`bpw status` 显示最近扫描和同步结果。

## 配置文件信任说明（重要）

第一版把 `~/.config/better-photography-workflow/config` 作为**当前用户可信的本地 zsh 配置**加载。该文件通过 `source` 执行，因此其中的 shell 内容拥有当前用户权限。不要直接使用来源不明、未经审查的配置文件。

程序会拒绝符号链接、非当前用户所有，以及组或其他用户可写的配置文件。建议始终保持：

```zsh
chmod 600 ~/.config/better-photography-workflow/config
```

## License

[MIT](LICENSE)
