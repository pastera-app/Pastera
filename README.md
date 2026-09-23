<p align="center">
  <img src="docs/assets/readme-hero.svg" alt="Pastera macOS 剪贴板效率工具" width="100%" />
</p>

<p align="center">
  <a href="#下载">下载</a>&nbsp;&nbsp;
  <a href="#核心能力">功能</a>&nbsp;&nbsp;
  <a href="#安装">安装</a>&nbsp;&nbsp;
  <a href="#构建与本地开发">构建</a>&nbsp;&nbsp;
  <a href="#参与贡献">贡献</a>&nbsp;&nbsp;
  <a href="#安全与隐私">安全</a>
</p>

# Pastera

Pastera 是一款独立、开源、键盘优先的 macOS 剪贴板效率工具。它把历史搜索、片段复用、脚本转换、图片 OCR、KDBX 密码箱和 OneDrive 文件夹同步集中在轻量菜单中，让复制、查找和粘贴保持连续。

macOS 应用是当前可运行的产品基线。原生 Windows 客户端将在同一仓库中遵循共同的数据与产品契约，但不会复制 AppKit 界面。

## 下载

[下载当前 Beta](https://github.com/pastera-app/Pastera/releases/tag/v3.0.7-beta) 或 [查看全部 Releases](https://github.com/pastera-app/Pastera/releases)。

### 当前版本：3.0.7-beta

- 缩短历史写出等待，连续复制时也会及时写入本地同步快照。
- OneDrive 同步目录延迟出现或被整体替换后，自动恢复上传与导入。
- 跳过未变化的片段快照和文件清单，减少无效写入和云端同步负担。
- 停止同步或切换目录后，取消旧观察器尚未执行的历史上传。
- 仅上传时保留真实失败状态，避免无关的远端变化显示为同步成功。

跨设备传输仍由 OneDrive 完成，本版不承诺两台 Mac 在 1 秒内送达。

系统要求：macOS 15 Sequoia 或更高版本。

> [!WARNING]
> 当前公开 DMG 使用 ad-hoc 签名，尚未经过 Apple 公证。首次打开若被 macOS 阻止，请前往“系统设置 > 隐私与安全性”，确认应用来源后选择“仍要打开”。

## 核心能力

### 历史记录与搜索

- 保存并检索文本、图片、文件、URL 和富文本剪贴板内容。
- 按内容类型和文件类别筛选，快速定位需要再次使用的记录。
- 从紧凑菜单中完成键盘导航、数字选择和粘贴回目标应用。

### 复用与自动化

- 使用片段文件夹整理提示词、模板和常用文本。
- 通过本地 JavaScript 脚本转换纯文本剪贴板内容。
- 为主菜单、历史、片段、脚本和密码箱配置独立快捷键。

### OCR 与资源控制

- 为图片历史生成可搜索文字，并显示识别延迟和处理状态。
- 使用持久化任务队列处理后台 OCR，避免一次载入全部图片历史。
- 对历史清理、文件监听和后台工作采用有界资源策略。

### 隐私与同步

- 使用 KDBX 文件保存密码箱内容，并支持文件夹和条目管理。
- 按需同步 OneDrive 本地文件夹，由 OneDrive 桌面客户端负责云端传输。
- 自动粘贴默认关闭，只有用户主动启用时才请求 macOS 辅助功能权限。

## 界面预览

<p align="center">
  <img src="docs/windows-reference/preferences/01-general-dark.jpg" alt="Pastera 深色模式基础设置页面" width="62%" />
</p>

<p align="center">
  <img src="docs/windows-reference/main-panel/03-snippets-empty-dark.jpg" alt="Pastera 深色模式片段空状态" width="28%" />
  <img src="docs/windows-reference/main-panel/04-vault-locked-dark.jpg" alt="Pastera 深色模式密码箱锁定状态" width="28%" />
</p>

以上界面使用脱敏合成内容，不包含真实剪贴板数据。

## 安装

1. 从 [GitHub Releases](https://github.com/pastera-app/Pastera/releases) 下载最新 DMG。
2. 打开 DMG，将 `Pastera.app` 拖入“应用程序”。
3. 首次启动时按上方安全提示确认应用来源。
4. 只有需要自动发送 Command+V 时，才在 Pastera 设置中开启自动粘贴并授予辅助功能权限。

仓库保留 `Casks/pastera.rb` 供发布维护。使用本地 Homebrew Cask 前，请先确认其中的版本、SHA-256 和 GitHub DMG 完全一致：

```bash
brew install --cask ./Casks/pastera.rb
```

## 构建与本地开发

本地开发需要 Xcode 26.5。Xcode 工程、scheme 和源码目录使用小写 `pastera`，构建产物为 `Pastera.app`。

```bash
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -scheme pastera \
  -project pastera.xcodeproj \
  -clonedSourcePackagesDirPath "$PWD/.spm-cache/SourcePackages" \
  -packageCachePath "$PWD/.spm-cache/PackageCache" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

构建并替换本机 `/Applications/Pastera.app`：

```bash
./script/install_local.sh
```

本地构建可通过 `Configurations/CodeSigning.xcconfig` 使用 ad-hoc 签名。公开可信分发仍需要 Pastera 自有的 Developer ID 和 Apple 公证凭据。

完整测试命令、Pull Request 检查清单和代码入口见[参与贡献](.github/CONTRIBUTING.md)。

## 项目状态

Pastera 由 `pastera-app/Pastera` 公开维护。仓库已经脱离 fork 网络，是不跟踪产品 upstream 的独立产品仓库。

macOS 是当前可执行基线。Windows 客户端采用原生 Windows API 和 WinUI 3，并复用仓库内已经冻结的数据契约与脱敏测试样本。详细方向见[独立产品路线图](docs/development/PASTERA_FORK_PLAN.md)和 [Windows 移植指南](docs/development/WINDOWS_PORTING_GUIDE.md)。

## 参与贡献

欢迎提交聚焦、可验证并尊重用户隐私的改进：

- [参与贡献](.github/CONTRIBUTING.md)
- [社区行为准则](CODE_OF_CONDUCT.md)
- [项目治理](GOVERNANCE.md)
- [验证矩阵](docs/verification/VERIFICATION.md)

项目资金仅用于公开、可说明的开源维护需求。详细边界见[资金政策](docs/funding/OPEN_COLLECTIVE.md)。

## 安全与隐私

Pastera 默认在本机处理剪贴板数据，不提供托管的 Pastera 剪贴板上传服务，也不会在没有明确用户同意时收集剪贴板遥测。

- 普通缺陷可以通过 [GitHub Issues](https://github.com/pastera-app/Pastera/issues/new) 提交。
- 敏感漏洞请按照[安全政策](SECURITY.md)使用私密报告入口。
- OneDrive 同步协议和数据范围见 [ONEDRIVE_SYNC.md](docs/sync/ONEDRIVE_SYNC.md)。

## 历史归属与许可证

Pastera 保留源自 [Clipy](https://github.com/Clipy/Clipy) 的 Git 历史、版权声明和 MIT 条款，但这不表示当前存在产品上下游关系。详细归属见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。
