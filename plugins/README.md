# 内置音乐插件

Bilibili 随应用预加载，首次打开「插件搜索」即可选择 Bilibili 搜索单曲。设置中的插件开关可停用它；内置版本不显示卸载、更新或分享按钮。

同 ID 的手动安装插件优先于内置版本，卸载手动版本后恢复内置版本。旧 codegen 路径保留兼容入口，维护代码位于 `builtin/bilibili.gd`。

搜索结果会保存插件 ID 与原始媒体信息（包括 BVID、AID、CID），播放时重新解析地址，不保存有时效的 CDN URL。空队列点击结果时按搜索顺序建立队列；已有队列时将点击的歌曲移到队首。Bilibili 不提供歌词，播放器保持无歌词状态。当前搜索页只支持直接播放「单曲」结果，专辑/作者展开及收藏夹导入尚未接入界面。

播放公开、无需登录即可访问的音频；需要登录、会员或服务端限制的响应会显示错误。请求仅声明 Godot 支持的 gzip 压缩，下载时保留 Referer 和 User-Agent，由 HTTP 客户端生成 Host。

## 音频支持

Bilibili DASH 通常提供 AAC/M4A，Godot 原生播放器不能直接解码。

- macOS：使用系统 `/usr/bin/afconvert` 异步转换为 PCM WAV；无需额外安装。兼容系统生成的 WAVE_FORMAT_EXTENSIBLE 头。
- Windows / Linux：需要 PATH 中可用的 FFmpeg。传给进程的只有本地缓存文件路径。
- Android / iOS / Web：当前没有 AAC 解码后端，支持搜索和解析，但无法播放这类音频，会提示缺少解码支持。

音频先下载再播放，下载超时 20 秒、大小上限 64 MiB；转换超时 30 秒。切换歌曲后的过期结果不会启动播放，转换临时文件在完成或取消后删除。

## 验证

离线集成测试覆盖加载/禁用/卸载保护、搜索映射、队列、存档往返、请求头与整数 CID/AID、失败响应及 M4A 转换：

```sh
godot --headless --path . tests/music_app/music_app_bilibili_test.tscn
```

需要网络的单独检查（访问 Bilibili，下载搜索结果中最短视频的音频并解码）：

```sh
godot --headless --path . tests/music_app/music_app_bilibili_smoke.tscn
```

`tests/music_app/fixtures/tone.m4a` 是本项目生成的 0.1 秒、440 Hz 测试音，不来自 Bilibili。
