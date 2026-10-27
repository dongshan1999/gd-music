# gd-music 功能实现文档索引

本目录按「**一个功能 = 一份实现文档**」组织，覆盖当前项目的全部功能域：从界面页面、播放内核、音源插件，到 DX 框架、原生扩展与工程化流程。

- 文档命名规则：`YYYY-MM-DD_功能名.md`（日期为文档生成日期，本次统一 `2026-10-27`）。
- 文档结构模板与写作要求见 [_文档规范.md](_文档规范.md)。
- 对应代码版本：`develop` 分支，工作区状态 2026-10-27（HEAD `91d939d`）。

## 1. 功能全景

```
┌──────────────────────────────────────────────────────────────┐
│ 界面层  Home / Player / Playlist / LocalMusic / PluginBrowser │
│        Settings / DownloadManagement / Queue / MiniPlayer    │
├──────────────────────────────────────────────────────────────┤
│ 控制器层  MusicAppShowcaseController + 各页面 Controller       │
│          全局：Playback / PlaybackState / PlaylistState       │
│                Plugin / Download / PopupRouter               │
├──────────────────────────────────────────────────────────────┤
│ 音频层  AudioBackend 抽象 → NodeAudioBackend / LibMpvAudio    │
│         M4A 解码、封面读取、歌词解析                            │
├──────────────────────────────────────────────────────────────┤
│ 音源层  22 个 TS 音源 → 代码生成 → GDScript 插件 → 插件宿主     │
├──────────────────────────────────────────────────────────────┤
│ 框架层  DX：存档 / 文件(SAF) / 弹窗 / 调试 / 本地化 / 时间 …    │
├──────────────────────────────────────────────────────────────┤
│ 平台层  gdmpv(libmpv GDExtension) / Android 后台音频服务       │
└──────────────────────────────────────────────────────────────┘
```

## 2. 文档索引

### 2.1 应用界面与交互

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 1 | 应用框架与页面导航 | [应用框架与页面导航](2026-10-27_应用框架与页面导航.md) | `assets/scripts/ui/music_app/music_app_showcase.gd`、`music_app_page.gd` |
| 2 | 首页 | [首页](2026-10-27_首页.md) | `assets/scripts/ui/music_app/views/home/`、`controllers/music_app_home_controller.gd` |
| 3 | 播放器页 | [播放器页](2026-10-27_播放器页.md) | `assets/scripts/ui/music_app/views/player/`、`controllers/music_app_player_controller.gd` |
| 4 | 歌词解析与显示 | [歌词解析与显示](2026-10-27_歌词解析与显示.md) | `assets/scripts/ui/music_app/player/` |
| 5 | 迷你播放器 | [迷你播放器](2026-10-27_迷你播放器.md) | `assets/scripts/ui/music_app/views/mini_player/` |
| 6 | 播放队列 | [播放队列](2026-10-27_播放队列.md) | `assets/scripts/ui/music_app/views/playback_queue/` |
| 7 | 歌单管理 | [歌单管理](2026-10-27_歌单管理.md) | `assets/scripts/ui/music_app/views/playlist/`、`controllers/global/music_app_playlist_state_controller.gd` |
| 8 | 本地音乐 | [本地音乐](2026-10-27_本地音乐.md) | `assets/scripts/ui/music_app/views/local_music/` |
| 9 | 本地扫描导入 | [本地扫描导入](2026-10-27_本地扫描导入.md) | `assets/scripts/ui/music_app/views/local_scan/`、`controllers/music_app_local_scan_controller.gd` |
| 10 | 插件浏览器与搜索 | [插件浏览器与搜索](2026-10-27_插件浏览器与搜索.md) | `assets/scripts/ui/music_app/views/plugin_browser/` |
| 11 | 插件管理 | [插件管理](2026-10-27_插件管理.md) | `assets/scripts/ui/music_app/views/settings/music_app_plugin_*` |
| 12 | 插件账号登录 | [插件账号登录](2026-10-27_插件账号登录.md) | `assets/scripts/ui/music_app/controllers/music_app_plugin_login_controller.gd` |
| 13 | 设置页 | [设置页](2026-10-27_设置页.md) | `assets/scripts/ui/music_app/views/settings/music_app_settings_view.gd` |
| 14 | 下载与离线播放 | [下载与离线播放](2026-10-27_下载与离线播放.md) | `assets/scripts/ui/music_app/controllers/global/music_app_download_controller.gd` |
| 15 | 曲目信息编辑 | [曲目信息编辑](2026-10-27_曲目信息编辑.md) | `assets/scripts/popup/music_app_track_edit_popup.gd` |

### 2.2 播放内核与数据

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 16 | 播放状态与全局控制 | [播放状态与全局控制](2026-10-27_播放状态与全局控制.md) | `assets/scripts/ui/music_app/controllers/global/music_app_audio_controller.gd` |
| 17 | 音频后端与解码 | [音频后端与解码](2026-10-27_音频后端与解码.md) | `assets/scripts/ui/music_app/audio/`、`assets/scripts/audio/` |
| 18 | 存档与数据模型 | [存档与数据模型](2026-10-27_存档与数据模型.md) | `assets/scripts/save/music/` |
| 19 | 音频内嵌封面 | [音频内嵌封面](2026-10-27_音频内嵌封面.md) | `assets/scripts/save/music/audio_artwork_reader.gd` |

### 2.3 音源插件体系

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 20 | 插件系统与代码生成 | [插件系统与代码生成](2026-10-27_插件系统与代码生成.md) | `gdmusic_plugin_codegen/`、`plugins/builtin/` |
| 21 | 音源插件清单 | [音源插件清单](2026-10-27_音源插件清单.md) | `gdmusic_plugin_codegen/source_plugins/` |

### 2.4 原生与平台能力

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 22 | libmpv 原生扩展 | [libmpv 原生扩展](2026-10-27_libmpv原生扩展.md) | `addons/gdmpv/` |
| 23 | Android 后台音频 | [Android 后台音频](2026-10-27_Android后台音频.md) | `android/plugins/GDMusicBackgroundAudio/` |

### 2.5 DX 框架

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 24 | DX 框架总览 | [DX 框架总览](2026-10-27_DX框架总览.md) | `dx/dx.gd`、`dx/runtime/scenes/managers/dx.tscn` |
| 25 | DX 存档与序列化 | [DX 存档与序列化](2026-10-27_DX存档与序列化.md) | `dx/runtime/scripts/managers/save/`、`serializer/` |
| 26 | DX 文件系统与 SAF | [DX 文件系统与 SAF](2026-10-27_DX文件系统与SAF.md) | `dx/runtime/scripts/managers/files/` |
| 27 | DX 弹窗系统 | [DX 弹窗系统](2026-10-27_DX弹窗系统.md) | `dx/runtime/scripts/managers/popup/` |
| 28 | DX 调试工具 | [DX 调试工具](2026-10-27_DX调试工具.md) | `dx/runtime/scripts/debug/` |
| 29 | DX 通用管理器与 UI 组件 | [DX 通用管理器与 UI 组件](2026-10-27_DX通用管理器与UI组件.md) | `dx/runtime/scripts/managers/`（其余）、`component/`、`effects/`、`utility/` |

### 2.6 工程化

| # | 功能 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 30 | 构建与发布 | [构建与发布](2026-10-27_构建与发布.md) | `export_presets.cfg`、`tools/`、`addons/dx_build_number/` |
| 31 | 测试体系 | [测试体系](2026-10-27_测试体系.md) | `assets/tests/music_app/`、`addons/gdmpv/test/` |

## 3. 历史归档（已合并，文件不再保留）

本目录只保留当前有效的功能文档。整理前的三份早期材料已按「有效内容并入对应功能文档、过程性内容丢弃」的规则处理，原文件已删除，仅可通过 git 历史找回（`git log -- <path>` 或 `git log --diff-filter=D -- docs/`）：

| 原文件 | 主题 | 归宿 |
| --- | --- | --- |
| `插件功能汇总案_2026-10-26.md` | Bilibili 插件能力 + 下载/离线播放方案底稿 | [下载与离线播放](2026-10-27_下载与离线播放.md) §1 需求边界、§4.2 设计取舍、§5、§8；[插件系统与代码生成](2026-10-27_插件系统与代码生成.md) §4.9、§4.10；[插件账号登录](2026-10-27_插件账号登录.md) §4.8；[测试体系](2026-10-27_测试体系.md) §4.6、§6.1 |
| `2026-10-26_libmpv_落地实施手册.md` | libmpv 后端落地的设计、构建与接入手册 | [libmpv原生扩展](2026-10-27_libmpv原生扩展.md) §1、§4.2–4.9、§5、§8；[构建与发布](2026-10-27_构建与发布.md) §4.5、§6.1、§8；[Android后台音频](2026-10-27_Android后台音频.md) §4.2、§4.4、§4.9、§6.1 |
| `eirteam_ffmpeg_integration.md` | EIRTeam.FFmpeg 解码扩展集成说明 | [音频后端与解码](2026-10-27_音频后端与解码.md) §4.4、§4.7、§4.8、§5、§8 |

合并过程暴露的「旧文档与当前代码不符」之处，已按代码改写并记在各自文档的「文档与代码不一致」小节（如 [插件系统与代码生成](2026-10-27_插件系统与代码生成.md) §4.10、[libmpv原生扩展](2026-10-27_libmpv原生扩展.md) §4.9 末尾的许可证/产物口径）。

## 4. 术语表

| 术语 | 含义 |
| --- | --- |
| Showcase | 应用主场景控制器 `MusicAppShowcaseController`，持有全部全局控制器 |
| Controller | 页面控制器，负责把存档数据整理成 View 可直接渲染的只读数据 |
| Popup / Page | 应用的所有页面都是弹窗（`DX_PopupView` 子类），由 `DX_PopupRegistry` 注册 |
| 插件宿主 | `MusicAppPluginController`，负责发现、加载、调用 `plugins/` 下的音源插件 |
| TrackData | 曲目模型，插件曲目靠 `plugin_id` + `plugin_data` 定位 |
| AudioBackend | 播放后端抽象，屏蔽 `AudioStreamPlayer` 与 libmpv 的差异 |
| DX | 项目内置运行时框架（`dx/`），提供存档、文件、弹窗、调试等管理器 |
| SAF | Android Storage Access Framework，`saf-tree://` 虚拟路径的来源 |

## 5. 实现状态速查（与「看起来应该有的功能」的差距）

本次逐份文档核对代码后发现：**部分入口在 UI 上不存在或被隐藏**。阅读文档前先看这张表，避免把「代码实现了」当成「用户用得到」：

| 位置 | 实际状态 | 详见 |
| --- | --- | --- |
| 本地音乐 | 内置扫描页（`MusicAppLocalScanView`）已实现但无调用方，只能走系统目录选择器 | [本地扫描导入](2026-10-27_本地扫描导入.md) |
| 本地音乐 | 无文件夹/专辑分组、无「播放全部/随机播放」按钮；扫描不读音频标签（`duration` 固定 180）、无进度与取消 | [本地音乐](2026-10-27_本地音乐.md) |
| 播放队列 | 无「加入队列」入口（`append_tracks_to_queue()` 无调用方，搜索点行是置顶插入）；不支持拖拽排序 | [播放队列](2026-10-27_播放队列.md) |
| 歌单 | 封面是图标而非首曲封面；无重命名、无「添加曲目」、无歌单内搜索（仅占位提示） | [歌单管理](2026-10-27_歌单管理.md) |
| 曲目编辑 | 只改标题/艺术家，不写回音频标签与封面；弹窗打开后切歌，保存会落到「保存时刻」的当前曲目 | [曲目信息编辑](2026-10-27_曲目信息编辑.md) |
| 首页 | 无「最近播放/历史」；4 张功能卡中 3 张为占位卡 | [首页](2026-10-27_首页.md) |
| 播放器页 | 无分享、无评论入口；「下载」按钮只对插件曲目出现 | [播放器页](2026-10-27_播放器页.md) |
| 歌词 | 只读本地旁挂 `.lrc`/`.txt`；插件 `get_lyric()` 有接口但未接入，无翻译行合并 | [歌词解析与显示](2026-10-27_歌词解析与显示.md) |
| 迷你播放器 | 常驻显示，全仓无显隐赋值；Toast 的 28px 分支不可达 | [迷你播放器](2026-10-27_迷你播放器.md) |
| 插件浏览器 | 无「加载更多」（是显式上一页/下一页）、无加入歌单/下载入口；行尾 `⋮` 仅装饰 | [插件浏览器与搜索](2026-10-27_插件浏览器与搜索.md) |
| 插件管理 | 无删除按钮（`uninstall_plugin()` 已实现未接 UI）、无拖拽排序；导入的是 `.gd` 脚本/目录而非 `.zip` | [插件管理](2026-10-27_插件管理.md) |
| 插件登录 | 只有二维码 + 手动粘贴 cookie，无账号密码登录 | [插件账号登录](2026-10-27_插件账号登录.md) |
| 设置页 | 只有一个「功能」分组（插件管理/音乐下载/语言三个跳转 + 音量滑条 + 版本号），唯一持久化项是音量 | [设置页](2026-10-27_设置页.md) |
| DX 框架 | 无 settings 管理器、无 scene 管理器；存档单槽纯 JSON，无加密/压缩/迁移，版本不符直接丢弃 `music` 段 | [DX框架总览](2026-10-27_DX框架总览.md)、[DX存档与序列化](2026-10-27_DX存档与序列化.md) |

## 6. 维护约定

- 新增功能时：先按 [_文档规范.md](_文档规范.md) 新增一份 `YYYY-MM-DD_功能名.md`，再更新本索引。
- 功能大改时：**在原文档内更新**（改「最后更新」日期与受影响小节），不要让新旧两份文档并存；确需重写时合并后删除旧文件，规则见 [_文档规范.md](_文档规范.md) §5。
- 文档中的代码引用若随重构失效，应在同一次改动中同步修正。
- 2026-10-27 校订记录：三份早期材料（`插件功能汇总案_2026-10-26.md`、`2026-10-26_libmpv_落地实施手册.md`、`eirteam_ffmpeg_integration.md`）的有效内容已并入 §2 索引中的对应功能文档并删除原文件；全目录做过一次重复段落扫描（无跨文档成段重复）与「旧文档引用 / 本机绝对路径」清零检查。
