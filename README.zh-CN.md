# better-photography-workflow

一个仅支持 macOS、无第三方依赖的摄影工作流自动化命令行工具。它会扫描摄影项目目录，在 Apple「提醒事项」中创建四阶段任务，可补齐统一的项目目录结构，并可通过 `rsync` 将项目安全地增量备份到真实挂载的外接硬盘。

项目只使用 macOS 原生能力：zsh、AppleScript、Reminders、launchd、rsync 及系统命令；同时支持 Apple Silicon 与 Intel Mac。不开发 GUI，也不会直接读写 Apple Photos Library 的内部文件。

## 快速开始

```zsh
./install.sh
export PATH="$HOME/.local/bin:$PATH"
bpw doctor
bpw new "猫咪写真"
```

默认会创建：

```text
~/Pictures/Photography_Work/2026-07-19_猫咪写真/
├── 01_RAW/
├── 02_EXPORT/
├── 03_PRINT/
└── 99_REFERENCE/
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
bpw doctor               检查系统环境、配置、权限和服务
bpw logs                 查看最近 100 行主日志
bpw help                 显示帮助
```

详细资料：[安装](docs/installation.md)、[配置](docs/configuration.md)、[权限](docs/permissions.md)、[工作流](docs/workflow.md)、[故障排查](docs/troubleshooting.md)。

## 安全与幂等

- 只处理 `WORK_DIR` 下的一级非隐藏目录。
- 第一层幂等：使用项目绝对路径的 SHA-256 在 `~/.local/state/better-photography-workflow/projects` 中保存完成标记。
- 第二层幂等：AppleScript 在列表中查找标题、完整项目路径及来源均匹配的提醒事项。
- 仅在四条提醒事项全部成功创建或确认已存在后写入本地状态；中断后重试不会重复创建。
- 备份同时检查 `diskutil` 与系统挂载表，不会只因 `/Volumes/卷名` 目录存在就判断硬盘在线。
- 默认不向 `rsync` 传递 `--delete`，因此不会删除目标硬盘已有文件。

## 配置文件信任说明（重要）

第一版把 `~/.config/better-photography-workflow/config` 作为**当前用户可信的本地 zsh 配置**加载。该文件通过 `source` 执行，因此其中的 shell 内容拥有当前用户权限。不要直接使用来源不明、未经审查的配置文件。

程序会拒绝符号链接、非当前用户所有，以及组或其他用户可写的配置文件。建议始终保持：

```zsh
chmod 600 ~/.config/better-photography-workflow/config
```

## License

[MIT](LICENSE)
