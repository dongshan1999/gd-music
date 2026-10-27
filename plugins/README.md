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

## 标题净化

B 站视频标题常带 UP 主自加的「001.」「01、」类序号。插件在 `_format_media()`、多 P 专辑标题、`import_music_sheet()` 三处统一调用 `_strip_title_order_prefix()` 剥掉此前缀（剥空时保留原值），避免序号进入曲库与下载记录。若某个标题仍不合意，可在播放器页点歌名/UP 主名手动编辑（只改本机）。

## 音乐下载与离线播放

播放器页右上角的下载按钮会把当前 B 站单曲的完整音频保存到本地。下载索引独立存放在 `MusicAppStateData.downloads`（`MusicDownloadRecordData`），不回写 `TrackData.file_path`，避免被本地音乐页当作扫描曲目、在移除本地文件夹时被误删。

- 下载：先通过插件重新解析 `playurl` 得到带时效的 CDN 地址，再带 Referer / User-Agent 拉取字节；超时 60 秒、上限 128 MiB、失败自动重试 2 次，先写 `.part` 临时文件，校验 M4A `ftyp` 头后再改名。
- 目录：`app://music_downloads/<插件 ID>/<曲目 ID 前 16 位>.<扩展名>`；设置 › 音乐下载可看到系统真实路径，并复制路径或打开目录。
- 播放：命中下载记录的曲目直接读取本地文件，不再请求 `playurl` 与 CDN；播放键为 `download:<track id>`，删除下载后立即回到在线解析。
- 移动端：iOS 当前没有 AAC 解码后端，能下载但无法播放；下载目录为应用私有目录，暂不支持导出到系统音乐目录。

## 验证

离线集成测试覆盖加载/禁用/卸载保护、搜索映射、队列、存档往返、请求头与整数 CID/AID、失败响应及 M4A 转换：

```sh
godot --headless --path . tests/music_app/music_app_bilibili_test.tscn
```

需要网络的单独检查（访问 Bilibili，下载搜索结果中最短视频的音频并解码）：

```sh
godot --headless --path . tests/music_app/music_app_bilibili_smoke.tscn
```

下载功能的离线单测与实网冒烟：

```sh
godot --headless --path . tests/music_app/music_app_download_test.tscn
godot --headless --path . tests/music_app/music_app_download_smoke.tscn
```

`tests/music_app/fixtures/tone.m4a` 是本项目生成的 0.1 秒、440 Hz 测试音，不来自 Bilibili。
