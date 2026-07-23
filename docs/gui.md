# macOS 图形界面

图形界面是现有 `bpw` 后端的原生 SwiftUI 控制中心，提供菜单栏快捷操作和以下设置页面：

- 工作目录、项目子目录和扫描间隔
- Apple 提醒事项列表、截止时间和四阶段任务
- 外接硬盘、备份目标、同步间隔和删除模式
- 新建项目、立即扫描、立即备份、系统诊断和日志

## 构建

需要 macOS 14 或更高版本以及 Xcode Command Line Tools：

```zsh
./install.sh
./app/build-app.sh
open "app/dist/摄影工作流.app"
```

After the app is copied to `~/Applications`, open it any time with:

```zsh
bpw app
```

应用通过 `~/.local/bin/bpw` 调用已安装的后端。第一次保存图形配置时，会生成：

```text
~/.config/better-photography-workflow/config.plist
```

这个 plist 会成为优先配置；原来的 zsh 配置仍会保留并可用于迁移或回退。保存设置时，CLI 会再次执行完整校验，然后重新加载 LaunchAgent。

图形应用不启用 App Sandbox，因为它需要选择任意摄影目录、调用本地 CLI，并管理用户级 LaunchAgent。当前构建使用本机临时签名，适合本地使用；对外发布时应改用 Developer ID 签名和公证。
