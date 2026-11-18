# aespa_desktop_pet

## Of Course Ning Ning

略略是一款为 macOS 打造的互动桌宠。以紫色为主视觉，搭配玻璃质感浮窗，把轻松陪伴、校园公告、AI 榜单和听歌记忆放在桌面上的一个小伙伴里。

## 功能介绍

- **互动与十套皮肤**：鼠标点击触发动画，移动时产生互动反馈；可切换 Ning Ning、Giselle、Karina、Winter，也可切换 IVE 的六款角色。
- **陪伴聊天**：接入 DeepSeek，围绕讲笑话、偶尔出现的暧昧韩语、安慰与鼓励展开。打开聊天会显示话题提示，双方消息以玻璃风格气泡呈现。情绪回应仅根据你主动发送的对话，不是屏幕监控或心理诊断。
- **同济 news**：在浏览器正常登录同济门户后，使用配套扩展手动提取、导入公告，桌宠再整理为列表。不是后台自动登录，不绕过验证，也不攻击网站。
- **AI rank**：分别查看 Arena、Artificial Analysis、LiveBench。每次启动尝试更新，运行期间在本机午夜检查；关机、休眠或网络失败时不保证准点更新。不同榜单保持各自指标、版本和来源，不混为一个总分。
- **Music Calendar**：启用并获得系统授权后，观察本机 Apple Music 的播放，为每天留下播放次数最多的歌曲，可显示封面或歌名、歌手。今日以紫色和 💜 标记，支持按月翻看，数据按年本机保存。日期格展示封面和歌名，左键尝试播放历史胜出曲，右键查看当天的播放统计。
- **双团图库**：在玻璃浮窗中查看官网公开宣传图，支持 Aespa / Ning Ning 筛选与轮播，并保留原文入口。选择 IVE 角色后，图库切换到 IVE 日本官网照片。
- **个性化设置**：选择皮肤、控制功能菜单的显示与排序；提供重启和退出入口。另附可选登录自启动脚本，不会因下载源码而自动安装。

### 音乐日历如何计数

仅记录启用后、桌宠实际运行并观察到的播放，不读取或补全 Apple Music 的全部历史。观察到的有效播放满 30 秒或半首歌（较短者）计一次；暂停不重复计数，拖动进度不当作已听时长。午夜结算当天结果，最高次数并列时随机选一首并保存，睡眠后补结算。空白日期表示没有记录，不代表当天没有听歌。

历史日期可尝试在本机音乐资料库中定位并播放对应歌曲；需要授权且歌曲仍可访问，无法保证所有流媒体曲目都能匹配。听歌记录和封面保存在本机，不发送给聊天模型。

## 当前仓库文件

- `略略-源码与演示-私人交付包.zip`：当前基于 v23 的整理包。解压后的 `repository/` 包含 Swift 源码、构建脚本、浏览器扩展和验证记录；`NOT_FOR_PUBLIC_UPLOAD/` 分开保存四套皮肤与视频。
- `略略动态快剪版.mp4`：38 秒真实界面快剪，含用户指定配乐。素材为隔离离线演示，聊天未实际发送，重启只展示入口，并非全部联网功能的端到端测试。
- `demo-muted.mp4`：约 28 秒静音版本，已移除官网照片与榜单画面；仍包含角色素材。

## 最新源码

`source/` 是最新源码，包含可填写/修改 DeepSeek API Key 的设置入口。2026 年 11 月 18 日的双团皮肤与音乐日历更新已在 Apple Silicon Mac 上通过编译、离线自测和严格签名校验。原 ZIP 保留为历史版本，构建最新版不要使用其中的 `repository/`。

## 构建与配置

新版增加六款 IVE 精灵图的绘制脚本，运行需要 Python 3 和 Pillow 9.1 或更高版本。如果素材目录已经包含六张 IVE 精灵图，可以跳过绘制步骤。

使用仓库的 `source/` 构建，需要 Apple Silicon Mac、Xcode 或 Command Line Tools，以及支持 `NSGlassEffectView` 的较新 macOS SDK。以下命令只从历史 ZIP 提取四张 PNG 到临时目录，不使用旧源码。素材公开传播许可仍未核实；你也可以使用自己有权使用且符合精灵图布局的替代素材。

```bash
git clone https://github.com/imnotorangewong/aespa_desktop_pet.git
cd aespa_desktop_pet
ASSET_TMP="$(mktemp -d)"
unzip -q '略略-源码与演示-私人交付包.zip' '*/NOT_FOR_PUBLIC_UPLOAD/skins/*.png' -d "$ASSET_TMP"
cd source
bash prepare-assets.sh "$ASSET_TMP/NingNing-Source-and-Demos/NOT_FOR_PUBLIC_UPLOAD/skins"
python3 art/draw_ive_skins.py
bash build.sh
```

若使用自备素材，可省略 ZIP 提取，在 `source/` 执行 `bash prepare-assets.sh "/你的素材目录"` 后再执行 `bash build.sh`。目录需含四张文件名匹配的精灵图，详见 `source/prepare-assets.sh`。

生成文件为 `source/紫色小伙伴.app`，构建会进行本机 ad-hoc 签名及隔离 HOME 的离线自测，不自动启动正式应用、不注册登录启动。详情见 [源码构建说明](source/README.md)。

DeepSeek 聊天和 Artificial Analysis 需要使用者自己的 API key。仓库不包含实际密钥、账号密码、个人公告、听歌历史或运行缓存。最新源码在 `source/`：右键桌宠 → 设置 → 配置聊天 API Key，可填写或更换自己的密钥，保存后立即生效。输入框不预填现有密钥，保存不联网，也不代表验证有效；本机凭据是权限 600 的明文文件、所在目录权限 700，不是加密钥匙串，同用户程序可能读取。旧 ZIP 保留为历史版本，尚无这个入口。无需也不应把真实 key 写进源码或提交到 GitHub。

已对最新 `source/` 完成静态检查、Mac 干净构建、离线自测（exit 0）和签名验证；未执行真实 API 调用、账号登录或 GUI 手动端到端验收。未验证 Intel 或旧版 SDK，构建目标 macOS 12 不代表所有系统版本均已实机测试。

## 许可与素材

目前未添加开源许可证。公开可见与获得开源使用许可是两回事。

商业配乐、官网照片和四套角色素材的公开传播许可尚未核实；静音视频也不代表全部素材权利已确认。文件夹名 `NOT_FOR_PUBLIC_UPLOAD` 和 `.gitignore` 不能限制已上传 ZIP 的下载或改变素材许可。第三方榜单与官网内容保留原来源和各自使用条件，不随本项目授予额外权利。
