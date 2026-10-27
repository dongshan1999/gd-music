class_name MusicDownloadRecordData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

## 已下载音乐索引记录。
##
## 该记录独立于 TrackData.file_path 存在：本地音乐控制器用
## `not track.file_path.is_empty()` 判定“本地扫描曲目”，如果把下载路径写回
## 曲目会污染本地音乐页，并在移除本地文件夹时被误删。下载记录只保存
## 「曲目 ID -> 文件」的映射，播放层按需查询。

## 曲目 ID（与 TrackData.id 一致）。
var track_id: String = ""
## 来源插件 ID。
var plugin_id: String = ""
## 插件内的媒体 ID，用于重新解析与生成来源链接。
var media_id: String = ""
var title: String = ""
var artist: String = ""
## 下载文件的 DX 虚拟路径（app://music_downloads/...）。
var path: String = ""
## 归一化后的扩展名，如 m4a / mp3。
var format: String = ""
## 文件字节数。
var bytes: int = 0
## 曲目时长（秒），仅用于列表展示。
var duration: int = 0
## 来源页面链接，如 https://www.bilibili.com/video/BVxxx。
var source_url: String = ""
## 下载完成时间（本地时间字符串）。
var created_at: String = ""

func normalize() -> void:
	track_id = track_id.strip_edges()
	plugin_id = plugin_id.strip_edges()
	media_id = media_id.strip_edges()
	title = title.strip_edges()
	artist = artist.strip_edges()
	path = path.strip_edges().replace("\\", "/")
	format = format.strip_edges().to_lower().trim_prefix(".")
	source_url = source_url.strip_edges()
	created_at = created_at.strip_edges()
	bytes = maxi(0, bytes)
	duration = maxi(0, duration)

## 文件名（不含目录）。
func get_file_name() -> String:
	return path.get_file()

## 供列表展示的大小文本。
func get_size_text() -> String:
	if bytes <= 0:
		return "未知大小"
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
