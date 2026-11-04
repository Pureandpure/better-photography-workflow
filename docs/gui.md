# macOS 图形界面

图形界面是现有 `bpw` 后端的原生 SwiftUI 控制中心。它直接读取主素材库中的真实一级目录，并提供：

- 收件台基础导入：检测卡、扫描拍摄时间、项目选择/创建、设备指定、dry-run、checksum 与最近成功导入
- 进行中、Done、项目进度和收藏
- 从 `01_ORIGINALS` 或 `01_RAW` 识别设备目录
- Mac 或外接 SSD 主素材库、项目子目录和扫描间隔
- Apple 提醒事项列表、截止时间和四阶段任务
- 可选第二份外接硬盘备份、同步间隔和删除模式
- 新建项目、立即扫描、立即备份、系统诊断和日志

## 构建

需要 macOS 14 或更高版本以及 Xcode Command Line Tools：

```zsh
./install.sh
./app/build-app.sh
open "$HOME/Library/Caches/better-photography-workflow/app/摄影工作流.app"
```

将生成的 App 复制到 `~/Applications` 后，可随时运行：

```zsh
bpw app
```

应用通过 `~/.local/bin/bpw` 调用已安装的后端。第一次保存图形配置时，会生成：

```text
~/.config/better-photography-workflow/config.plist
```

这个 plist 会成为优先配置；原来的 zsh 配置仍会保留并可用于迁移或回退。保存设置时，CLI 会再次执行完整校验，然后重新加载 LaunchAgent。

项目阶段保存在 `~/.local/state/better-photography-workflow/workflow-projects`，项目 identity 写入 `.bpw-project.json`，import manifest 写入 `.bpw/imports`；不会修改原始视频内容。可用阶段依次为 `ingest`、`verify`、`organize`、`edit`、`export`、`archive`、`done`。

图形应用不启用 App Sandbox，因为它需要选择任意摄影目录、调用本地 CLI，并管理用户级 LaunchAgent。当前构建使用本机临时签名，适合本地使用；对外发布时应改用 Developer ID 签名和公证。

多 Workspace 与导入详细流程见 [ingest.md](ingest.md)。GUI 目前在后台执行命令并在完成后显示输出，实时逐文件进度请使用 CLI。

构建脚本会验证签名；为避免 Documents File Provider 持续添加 FinderInfo，默认输出到 `~/Library/Caches/better-photography-workflow/app/摄影工作流.app`，请以脚本打印路径为准。也可用 `BPW_APP_OUTPUT_DIR` 指定非 File Provider 输出目录。
