extends Node
## 联网验证：B 站搜索 → 下载到临时目录 → 本地解码 → 删除清理。
## 需要可用的 Bilibili 网络连接；不读写用户真实的下载目录与资料库。

const Plugins := preload(
	"res://assets/scripts/ui/music_app/controllers/global/music_app_plugin_controller.gd"
)
const DownloadsScript := preload(
	"res://assets/scripts/ui/music_app/controllers/global/music_app_download_controller.gd"
)
const AudioScript := preload(
	"res://assets/scripts/ui/music_app/controllers/global/music_app_audio_controller.gd"
)

const FALLBACK_BVID := "BV1GJ411x7h7"
const FALLBACK_CID := 137649199
const FALLBACK_TITLE := "Never Gonna Give You Up"
const FALLBACK_ARTIST := "Rick Astley"
const FALLBACK_DURATION := 213

class PluginHosts extends MusicAppPluginController:
	var settings := MusicPluginSettingsData.new()
	func get_settings() -> MusicPluginSettingsData:
		return settings

class Host extends Node:
	var _plugin_controller
	var _download_controller

var _failures := PackedStringArray()

func _ready() -> void:
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-download-smoke/autoload.json")
	DX.save.data = DX_SaveData.new()
	call_deferred("_run")

func _run() -> void:
	var host := Host.new()
	add_child(host)
	var plugins := PluginHosts.new(host)
	host._plugin_controller = plugins
	if not plugins.refresh_plugins():
		_end("Plugin load failed: " + plugins.last_error, 1)
		return

	var downloads = DownloadsScript.new(host)
	host._download_controller = downloads
	downloads.download_root_relative = "temp/music_download_smoke"
	downloads.in_ready()

	var result: Dictionary = {}
	for attempt in range(3):
		if attempt > 0:
			await get_tree().create_timer(3.0).timeout
		result = await plugins.search("bilibili", "钢琴", 1)
		if not result.is_empty() and not result.get("data", []).is_empty():
			break
	var item: Dictionary = {}
	if result.is_empty() or result.get("data", []).is_empty():
		# 未登录搜索可能触发风控（v_voucher）；改用固定 BVID 继续验证下载链路。
		print("Search skipped (%s); falling back to %s" % [plugins.last_error, FALLBACK_BVID])
		item = {
			"bvid": FALLBACK_BVID,
			"cid": FALLBACK_CID,
			"title": FALLBACK_TITLE,
			"artist": FALLBACK_ARTIST,
			"duration": FALLBACK_DURATION,
		}
	else:
		item = result.data[0]
		for candidate in result.data:
			var candidate_duration := int(candidate.get("duration", 0))
			if candidate_duration > 0 and candidate_duration < 120:
				item = candidate
				break

	var track := TrackData.new()
	track.id = "plugin:bilibili:download-smoke"
	track.plugin_id = "bilibili"
	track.title = str(item.get("title", ""))
	track.artist = str(item.get("artist", ""))
	track.duration = maxi(1, int(item.get("duration", 1)))
	track.plugin_data = item

	var started_msec := Time.get_ticks_msec()
	var download_result: Dictionary = await downloads.download_track(track)
	if not bool(download_result.get("ok", false)):
		_end("Download failed: " + str(download_result.get("error", "")), 1)
		return
	var record: MusicDownloadRecordData = download_result.get("record")
	if record == null:
		_end("Download returned no record", 1)
		return
	var elapsed := float(Time.get_ticks_msec() - started_msec) / 1000.0
	print(
		"Downloaded %s (%.1f MB, %.2fs) -> %s"
		% [record.format, float(record.bytes) / 1048576.0, elapsed, record.path]
	)
	_check(not record.path.is_empty(), "record path is set")
	_check(DX.files.exists(record.path), "downloaded file exists")
	_check(record.bytes > 0, "record size is positive")
	_check(record.format == "m4a", "record format is m4a")
	_check(not record.source_url.is_empty(), "source url is derived")
	_check(downloads.has_download(track.id), "index reports downloaded track")

	var audio = AudioScript.new(host)
	var stream: AudioStream = await audio._load_local_stream(record.path)
	_check(stream != null, "downloaded file decodes for playback: " + audio.last_error)

	var removed: Dictionary = downloads.remove_download(track.id)
	_check(bool(removed.get("ok", false)), "remove download succeeds")
	_check(not DX.files.exists(record.path), "remove download deletes file")
	_check(not downloads.has_download(track.id), "remove download clears index")

	for failure in _failures:
		push_error(failure)
	_end("Download smoke tests: %s failures" % _failures.size(),
		OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _end(message: String, code: int) -> void:
	print(message)
	get_tree().quit(code)
