# Music App 脚本引用树

> 范围：围绕 `scripts/ui/music_app`、对应 `scenes/ui/music_app`、`DX_PopupRegistry`、音乐插件宿主链路整理。重点是“界面 -> View -> Controller -> 功能实现/下游依赖”。

## 1. 总入口

Music App Showcase
├─ 场景宿主
│  └─ `scripts/ui/music_app/music_app_showcase.gd`
│     ├─ 作用：音乐 App 总入口，持有弹窗宿主、迷你播放器、音频播放器、状态广播
│     ├─ 初始化
│     │  ├─ `mini_player.setup(self)`
│     │  ├─ `MusicAppPopupRouterController.attach_popup_hosts(...)`
│     │  ├─ `MusicAppPlaylistStateController.sync_favorite_playlist_from_likes()`
│     │  ├─ `show_home_popup()`
│     │  ├─ `request_audio_sync()`
│     │  └─ `auto_start_music_plugin_host()`
│     └─ 显式持有全局 Controller
│        ├─ `scripts/ui/music_app/controllers/global/music_app_playback_controller.gd`
│        ├─ `scripts/ui/music_app/controllers/global/music_app_audio_controller.gd`
│        ├─ `scripts/ui/music_app/controllers/global/music_app_playlist_state_controller.gd`
│        └─ `scripts/ui/music_app/controllers/global/music_app_popup_router_controller.gd`
├─ Controller 公共基类
│  └─ `scripts/ui/music_app/controllers/music_app_controller_base.gd`
│     ├─ 统一提供：`get_app_state()` / `save_app_state()`
│     ├─ 统一提供：`get_tracks_ref()` / `get_playlists_ref()`
│     ├─ 统一提供：`get_playback_controller()` / `get_playback_state_controller()`
│     ├─ 统一提供：`get_playlist_state_controller()` / `get_popup_router_controller()`
│     └─ 统一提供：`show_popup()` / `show_common_alert()` / `show_toast()`
└─ 弹窗注册表
   └─ `dx/runtime/scripts/managers/popup/popup_registry.gd`
	  ├─ `MUSIC_APP_HOME`
	  ├─ `MUSIC_APP_PLAYLIST`
	  ├─ `MUSIC_APP_PLAYER`
	  ├─ `MUSIC_APP_PLAYBACK_QUEUE`
	  ├─ `MUSIC_APP_LOCAL_MUSIC`
	  ├─ `MUSIC_APP_LOCAL_SCAN`
	  └─ `MUSIC_APP_PLUGIN_BROWSER`

## 2. 全局功能域

Global Controllers
├─ `MusicAppPlaybackController`
│  └─ `scripts/ui/music_app/controllers/global/music_app_playback_controller.gd`
│     ├─ 播放队列：设置/清空/追加/删除队列
│     ├─ 播放索引：当前曲目、当前队列位置、上一首/下一首
│     ├─ 播放模式：循环全部 / 单曲循环 / 随机
│     └─ 队列推进：`step_queue()` / `advance_after_finish()`
├─ `MusicAppPlaybackStateController`
│  └─ `scripts/ui/music_app/controllers/global/music_app_audio_controller.gd`
│     ├─ 音频状态：播放/暂停/seek/elapsed/duration
│     ├─ 同步音频播放器：`request_audio_sync()` / `tick_playback_progress()`
│     ├─ 加载本地音频：`_load_local_stream()`
│     ├─ 加载远程音频：`_load_remote_stream()`
│     ├─ 插件曲目补源：`MusicAppPluginBrowserController.resolve_track_plugin_source()`
│     └─ 播放结束回调：`on_audio_finished()`
├─ `MusicAppPlaylistStateController`
│  └─ `scripts/ui/music_app/controllers/global/music_app_playlist_state_controller.gd`
│     ├─ 喜欢列表同步到收藏歌单
│     ├─ 获取或创建收藏歌单
│     └─ 维护 liked track key
└─ `MusicAppPopupRouterController`
   └─ `scripts/ui/music_app/controllers/global/music_app_popup_router_controller.gd`
	  ├─ 绑定/解绑 normal/fullscreen popup host
	  ├─ `show_popup()` 后自动调用 popup `setup(showcase)`
	  ├─ 打开首页：`show_home_popup()`
	  ├─ 通用弹窗：`show_common_alert()` / `show_toast()`
	  └─ 返回键关闭当前非首页弹窗

## 3. 界面树

### 3.1 首页 Home

Home Popup
├─ 场景
│  └─ `scenes/ui/music_app/home/music_app_home_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/home/music_app_home_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppHomeController`
│     ├─ 生成 Feature Card
│     ├─ 动态维护 playlist rows
│     └─ 交互
│        ├─ 新建歌单
│        ├─ 打开本地音乐
│        ├─ 打开插件搜索
│        └─ 打开指定歌单/删除歌单
├─ 子 View
│  ├─ `scripts/ui/music_app/views/home/music_app_home_feature_card.gd`
│  │  └─ 信号：`pressed(index)`
│  └─ `scripts/ui/music_app/views/home/music_app_home_playlist_row.gd`
│     ├─ 信号：`open_requested(index)`
│     └─ 信号：`delete_requested(index)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_home_controller.gd`
	  ├─ 获取歌单列表 / 收藏歌单索引
	  ├─ 新建当前歌单
	  ├─ 删除歌单
	  ├─ 打开歌单页
	  ├─ 打开本地音乐页
	  └─ 打开插件浏览器

### 3.2 歌单页 Playlist

Playlist Popup
├─ 场景
│  └─ `scenes/ui/music_app/playlist/music_app_playlist_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/playlist/music_app_playlist_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppPlaylistController`
│     ├─ 刷新封面/标题/曲目数量
│     ├─ 动态维护歌曲 row
│     └─ 交互
│        ├─ 播放全部
│        ├─ 播放指定 slot
│        └─ 返回上一页
├─ 子 View
│  └─ `scripts/ui/music_app/views/playlist/music_app_playlist_song_row.gd`
│     ├─ 信号：`play_requested(index)`
│     └─ 信号：`more_requested(index)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_playlist_controller.gd`
	  ├─ 获取当前选中歌单
	  ├─ 获取歌单曲目索引
	  ├─ 根据 slot 播放
	  ├─ 歌单标题/mark/总数展示
	  └─ 从当前播放创建新歌单

### 3.3 本地音乐页 Local Music

Local Music Popup
├─ 场景
│  └─ `scenes/ui/music_app/local_music/music_app_local_music_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/local_music/music_app_local_music_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppLocalMusicController`
│     ├─ 列表化本地曲目
│     ├─ 菜单入口
│     │  ├─ 扫描音乐
│     │  ├─ 编辑占位
│     │  └─ 下载占位
│     └─ 打开插件搜索页
├─ 子 View
│  └─ `scripts/ui/music_app/views/local_music/music_app_local_music_row.gd`
│     ├─ 信号：`play_requested(index)`
│     └─ 信号：`more_requested(index)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_local_music_controller.gd`
	  ├─ 过滤本地曲目索引
	  ├─ 播放本地曲目列表
	  ├─ 打开扫描页
	  ├─ 打开插件浏览器
	  └─ 编辑/下载占位提示

### 3.4 本地扫描页 Local Scan

Local Scan Popup
├─ 场景
│  └─ `scenes/ui/music_app/local_scan/music_app_local_scan_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/local_scan/music_app_local_scan_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppLocalScanController`
│     ├─ 维护当前路径、选中路径、全选状态
│     ├─ 动态维护文件夹 row
│     └─ 启动扫描后导入本地曲目
├─ 子 View
│  └─ `scripts/ui/music_app/views/local_scan/music_app_local_music_scan_folder_row.gd`
│     ├─ 信号：`open_requested(path)`
│     └─ 信号：`selection_toggled(path, selected)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_local_scan_controller.gd`
	  ├─ 扫描根路径解析
	  ├─ 列出目录 / Windows 盘符
	  ├─ 递归收集音频文件
	  ├─ 生成 `TrackData`
	  └─ 导入到全局 tracks

### 3.5 迷你播放器 Mini Player

Mini Player
├─ 场景
│  └─ `scenes/ui/music_app/mini_player/music_app_mini_player.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/mini_player/music_app_mini_player_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppMiniPlayerController`
│     ├─ 刷新曲目信息 / 播放状态 / 进度环
│     ├─ 封面优先使用 `artwork_url`
│     ├─ 支持本地封面和远程封面加载
│     └─ 交互
│        ├─ 播放/暂停
│        ├─ 打开播放队列
│        └─ 打开全屏播放器
├─ 子 View
│  └─ `scripts/ui/music_app/views/mini_player/music_app_ring_progress.gd`
│     └─ 负责绘制圆环进度
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_mini_player_controller.gd`
	  ├─ 当前曲目 / 时长 / 已播秒数 / 进度比例
	  ├─ 播放/暂停
	  ├─ 打开播放器页
	  └─ 打开播放队列

### 3.6 全屏播放器 Player

Player Popup
├─ 场景
│  └─ `scenes/ui/music_app/player/music_app_player_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/player/music_app_player_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppPlayerController`
│     ├─ 刷新标题/歌手/来源/喜欢状态/模式/进度
│     ├─ 支持拖动与点击进度条 seek
│     └─ 交互
│        ├─ 喜欢/取消喜欢
│        ├─ 上一首 / 播放暂停 / 下一首
│        ├─ 切换播放模式
│        └─ 打开播放队列
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_player_controller.gd`
	  ├─ 当前曲目 / 时长 / elapsed
	  ├─ seek 到秒 / seek 到比例
	  ├─ 喜欢状态切换
	  ├─ 上一首 / 下一首 / 播放暂停
	  ├─ 播放模式切换
	  └─ 打开播放队列

### 3.7 播放队列 Popup

Playback Queue Popup
├─ 场景
│  └─ `scenes/ui/music_app/playback_queue/music_app_playback_queue_popup.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/playback_queue/music_app_playback_queue_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppPlaybackQueueController`
│     ├─ 动态维护 queue rows
│     ├─ 打开时自动滚动到当前播放项
│     └─ 交互
│        ├─ 切换播放模式
│        ├─ 清空队列
│        ├─ 播放指定队列项
│        └─ 删除指定队列项
├─ 子 View
│  └─ `scripts/ui/music_app/views/playback_queue/music_app_playback_queue_row.gd`
│     ├─ 信号：`play_requested(queue_index)`
│     └─ 信号：`remove_requested(queue_index)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_playback_queue_controller.gd`
	  ├─ 读取队列展示 rows
	  ├─ 当前队列索引
	  ├─ 队列删除 / 清空
	  ├─ 播放模式 label/icon
	  └─ 播放指定队列项

### 3.8 插件浏览器 Plugin Browser

Plugin Browser Popup
├─ 场景
│  └─ `scenes/ui/music_app/plugin_browser/music_app_plugin_browser_page.tscn`
├─ 主 View
│  └─ `scripts/ui/music_app/views/plugin_browser/music_app_plugin_browser_view.gd`
│     ├─ setup：注入 `MusicAppShowcaseController`
│     ├─ 持有 `MusicAppPluginBrowserController`
│     ├─ 历史记录区
│     │  ├─ 清空历史
│     │  ├─ 选中历史重搜
│     │  └─ 单条删除历史
│     ├─ 搜索区
│     │  ├─ 动态插件 tabs
│     │  ├─ 动态搜索类型 tabs
│     │  ├─ 搜索结果列表
│     │  └─ 单曲结果导入并可自动播放
│     ├─ 管理区
│     │  ├─ 启动 plugin host
│     │  ├─ 刷新插件列表
│     │  ├─ 从本地文件安装 `.js`
│     │  ├─ 从 URL 安装 `.js`
│     │  ├─ 读取插件变量
│     │  └─ 保存插件变量
│     └─ 依赖 `MusicAppPluginController`
├─ 子 View
│  ├─ `scripts/ui/music_app/views/plugin_browser/music_app_plugin_history_tag.gd`
│  │  ├─ 信号：`pressed(text)`
│  │  └─ 信号：`remove_requested(text)`
│  ├─ `scripts/ui/music_app/views/plugin_browser/music_app_plugin_search_tab.gd`
│  │  └─ 信号：`selected(id)`
│  └─ `scripts/ui/music_app/views/plugin_browser/music_app_plugin_result_row.gd`
│     └─ 信号：`play_requested(index)`
└─ Controller
   └─ `scripts/ui/music_app/controllers/music_app_plugin_browser_controller.gd`
	  ├─ 插件搜索历史增删改查
	  ├─ 启动/自动启动 plugin host
	  ├─ 从 URL / 本地文件安装插件
	  ├─ 调用插件搜索
	  ├─ 将搜索结果导入歌单和 tracks
	  ├─ 解析插件曲目播放地址
	  └─ 解析插件曲目歌词

## 4. 插件链路

Plugin Search Runtime
├─ UI 层
│  └─ `MusicAppPluginBrowserView`
├─ 业务 Controller
│  └─ `MusicAppPluginBrowserController`
├─ 全局插件 Controller
│  └─ `scripts/ui/music_app/controllers/global/music_app_plugin_controller.gd`
│     ├─ 启动本地 host：`start_local_host()`
│     ├─ 插件列表：`list_plugins()`
│     ├─ 安装插件：`install_plugin_from_url()` / `install_plugin_from_file()`
│     ├─ 插件变量：`get_plugin_user_variables()` / `set_plugin_user_variables()`
│     ├─ 搜索：`search()`
│     ├─ 取音源：`get_media_source()`
│     └─ 取歌词：`get_lyric()`
└─ Node 宿主
   └─ `plugin_host/src/server.js`
	  ├─ `/health`
	  ├─ `/plugins`
	  ├─ `/install`
	  ├─ `/plugin_vars`
	  ├─ `/search`
	  ├─ `/source`
	  ├─ `/lyric`
	  └─ `/toplists`

## 5. 依赖规律总结

引用规律
├─ 场景 `.tscn` 通过根节点 script 绑定对应 View
├─ View 在 `setup(controller)` 中注入 `MusicAppShowcaseController`
├─ View 自己 new 对应页面级 Controller
├─ 页面级 Controller 统一继承 `MusicAppControllerBase`
├─ `MusicAppControllerBase` 再回到 Showcase 读取全局状态与全局 Controller
├─ 弹窗打开统一经过 `MusicAppPopupRouterController -> DX_PopupRegistry`
└─ 插件能力是唯一跨进程链路，经 `MusicAppPluginController -> plugin_host/src/server.js`
