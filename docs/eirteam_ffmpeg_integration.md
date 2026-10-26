# EIRTeam.FFmpeg 集成说明

播放器已经支持在 EIRTeam.FFmpeg GDExtension 可用时自动切换到 `FFmpegVideoStream`：

1. 插件返回任何远程音频地址时，若 FFmpeg 可用，音频数据会缓存到 `OS.get_cache_dir()/gdmusic-ffmpeg-audio`，由 FFmpeg 根据文件内容自动探测容器和编码。
2. 音频播放器控制器将缓存文件交给 `FFmpegVideoStream`，并由隐藏的 `VideoStreamPlayer` 播放。
3. 普通本地音频和未安装扩展的平台继续使用现有 `AudioStreamPlayer` 解码链路。

扩展已补充纯音频容器支持：没有视频流的 M4A/AAC 会直接选择音频流解码，不再报 `Couldn't find video stream`。播放控制器也使用 `VideoStreamPlayer` 的实际接口处理时长、暂停、跳转和播放起点。

当前项目已内置编译产物：macOS（Apple Silicon）和 Android `arm64-v8a`，并保留同一份 `ffmpeg.gdextension` 配置。Godot 启动时已验证 `FFmpegVideoStream` 和 `FFmpegVideoStreamPlayback` 注册成功。

Android 后台播放使用项目内置的 `GDMusicBackgroundAudio` 插件：播放时启动
`mediaPlayback` 前台服务，申请媒体音频焦点、创建 `MediaSession` 通知并持有短时唤醒锁；暂停或停止时释放这些资源。通知和锁屏上的播放、暂停、上一首、下一首操作会通过插件信号回到 Godot 的同一套播放队列。真正的音频数据仍由 Godot 的 `AudioStreamPlayer` 或 FFmpeg `VideoStreamPlayer` 解码，原生服务不维护第二个播放器。

Android 13 及以上首次播放会请求通知权限；拒绝权限不会阻止音频播放，但系统可能隐藏媒体通知。导出 Android 时要保持 Gradle 构建开启，并使用项目 `android/` 模板目录。

播放卡片由 Android 的 `MediaSession` 和 `MediaStyle` 通知提供，系统会把它显示在通知栏、锁屏和 Android 13+ 媒体中心；播放位置、时长、标题和歌手会随播放状态同步。小米 HyperOS 的“灵动岛/超级岛”没有公开的第三方绘制接口，系统是否把媒体通知提升为胶囊由系统版本、通知权限和用户设置决定。小米设备需要在应用通知设置中开启通知、悬浮通知和锁屏显示，并关闭对本应用的后台限制；应用本身不能强制创建系统灵动岛。

构建脚本使用已初始化的源码仓库，不会自动下载二进制或覆盖项目文件。默认源码目录是 `~/Downloads/EIRTeam.FFmpeg-master`，也可以通过 `EIRTEAM_FFMPEG_SOURCE` 指定。Android 构建只启用解码相关组件，因此不依赖 x264、x265、LAME 或 libiconv。
