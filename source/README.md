# 略略 / Ning Ning 桌宠

原生 Swift/AppKit macOS 桌面伙伴：点击动画和鼠标互动、聊天、同济公告手动导入、三种 AI 榜单、Music Calendar、Aespa 公开图片展示、四皮肤和菜单设置，以及退出/重启入口。最新产品已移除“正在播放”独立小窗。

## 状态

本目录从 v23 产品备份整理。为可移植构建补入 Info.plist 模板，公告样本改为空列表，并调整对应自测断言；构建自测使用临时 HOME。公开提交 `f187fa0e` 的 `source/` 已在干净临时克隆中通过 Mac 编译、完整离线自测（exit 0）和严格签名验证，环境为 arm64、Swift 6.3.3、macOS SDK 26.5。尚未做真实联网或 GUI 手动端到端验收。 详见 VALIDATION.md。

## 本机构建

- Apple Silicon Mac（arm64）；构建目标最低 macOS 12，未验证 Intel。
- Xcode 或 Command Line Tools、Swift 编译器、codesign；需包含 `NSGlassEffectView` 的较新 macOS SDK（例如 macOS 26 SDK）。源码的运行时降级分支不意味着旧 SDK 一定能编译。
- 不需要第三方 Swift 包管理器。Chrome 扩展为独立可选功能。

从仓库根目录获取最新版 `source/`，不要从历史 ZIP 的 `repository/` 构建。完整流程见根 README。素材须由你确认使用权；用自备的匹配布局素材时，在本目录执行：

```sh
bash prepare-assets.sh "/绝对路径/skins"
bash build.sh
codesign --verify --deep --strict '紫色小伙伴.app'
```

仓库历史 ZIP 仅可作为可选皮肤来源，根 README 的命令将四张 PNG 提取到临时目录，再显式传给 `prepare-assets.sh`。不要把整个 ZIP 解压到未忽略的仓库目录。

`prepare-assets.sh` 把相邻隔离目录的四张 PNG 复制到被 Git 忽略的 `assets-local/`，仅供本机构建。也可传入自行准备、已有权使用的同结构素材目录。`build.sh` 可通过 `PET_ASSETS_DIR` 指定素材目录，输出 `紫色小伙伴.app`，使用本机 ad-hoc 签名，并运行默认离线 `--self-test`。不自动打开正常运行实例，不安装到 Applications，不注册开机启动。

默认自测隔离 HOME、应用支持目录与偏好，避免读取原桌宠的个人数据。不要将 `--api-test`、榜单 live test、图库 image test 或 `--music-probe` 当作离线自测执行，它们可能联网或触发系统权限。

构建和自测成功后，可双击生成的应用。应用未经过开发者公证；本包没有修改 Gatekeeper 或要求关闭系统安全保护。

## 配置与个人数据

`chat-config.json` 只含模型名称与聊天语气规则，不含密钥。聊天与 Artificial Analysis 使用各自的本机凭据文件，路径位于当前用户应用支持目录的 `imnotorange-pet/private/`，要求文件权限 0600。应用提供 `--store-key`、`--store-aa-key` 从标准输入保存凭据的入口；请在自己的 Mac 配置，不把真实密钥放进源码、命令参数、示例、日志、截图或 GitHub。具体存储逻辑见 chat.swift 与 aa-rank.swift。密钥缺失时应显示不可用状态，不是可立即联网的完整演示配置。

正常运行的聊天请求会发送到对应服务；榜单和图库会访问公开来源，服务可能有额度、授权和条款限制。Music Calendar 需用户主动启用及系统音乐自动化权限，只记录本机运行期间可观察的播放，不能补造历史。点击已有历史条目可能控制 Music 播放。

同济 news 不自动破解登录或后台抓取。用户在浏览器完成正常登录，手动通过扩展导出公告 JSON，再导入桌宠。扩展安装与隐私说明位于 `tongji-news-extension/`。仓库内公告文件是匹配应用结构的空快照，不含真实公告；扩展导出格式与内部快照格式不同，不要混用。

不要提交用户应用支持目录、钥匙串、浏览器会话、音乐记录、缓存、LaunchAgents、UserDefaults、生成的 .app 或临时测试文件。

## 可选登录启动

```sh
zsh pet-autostart.sh install
zsh pet-autostart.sh uninstall
```

只有用户自行执行 `install` 才会创建当前账户 LaunchAgent 并启动应用；第二参数可指定应用路径。`uninstall` 取消未来自动启动，正在运行的桌宠仍需自行退出。本次整理未执行这些命令。

## 发布前

- **无默认开源许可**：本包未擅自套用 MIT 等许可证。请自行确认代码、角色、品牌、第三方数据、音乐和图片的许可，再决定公开范围和许可证。
- 历史 ZIP 内含 `NOT_FOR_PUBLIC_UPLOAD/` 下的四皮肤和两个视频，仓库现已公开，文件夹名不限制它们的可访问性。商业配乐和官网宣传图片未取得公开再分发授权证明。静音版本已删音乐、官网照片和榜单片段，但角色权利仍待确认。
- `.gitignore` 不是保密或版权授权机制。公开前人工检查 `git status`、暂存区和整个提交历史，核实没有凭据或素材被强制加入。
- 公共数据不自动等于可任意再分发。保留 `AI-rank-来源与限制.txt`，并自行核查实时服务条款。

## DeepSeek API Key 配置

右键桌宠 → 设置 → 配置聊天 API Key。仅在你主动点击时打开空白安全输入框，不显示已有密钥。保存后立即更新内存缓存，无需重启；保存不发送网络请求，也不代表密钥已验证有效。凭据保存在本机权限 700 目录中的权限 600 明文文件，不是加密钥匙串，同用户权限程序仍可能读取。实际聊天才发送给 DeepSeek 官方接口。请勿提交真实密钥。
