extends Node
## 离线验证下载索引数据结构与路径规则，不发起任何网络请求。

const DownloadControllerScript := preload(
	"res://assets/scripts/ui/music_app/controllers/global/music_app_download_controller.gd"
)

var _failures := PackedStringArray()

func _ready() -> void:
	# 重定向自动保存路径，测试永不写用户资料库。
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-download-test/autoload.json")
	DX.save.data = DX_SaveData.new()
	call_deferred("_run")

func _run() -> void:
	_test_record_data()
	_test_state_data()
	_test_save_roundtrip()
	_test_source_url()
	_test_target_path()
	for failure in _failures:
		push_error(failure)
	print("Music app download tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _make_record(track_id: String = "plugin:bilibili:BV1test") -> MusicDownloadRecordData:
	var record := MusicDownloadRecordData.new()
	record.track_id = track_id
	record.plugin_id = "bilibili"
	record.media_id = "BV1test"
	record.title = "测试曲目"
	record.artist = "测试艺人"
	record.path = "app://music_downloads/bilibili/abc.m4a"
	record.format = "m4a"
	record.bytes = 1024 * 1024
	record.duration = 180
	record.source_url = "https://www.bilibili.com/video/BV1test"
	record.created_at = "2026-10-26 15:00:00"
	return record

func _test_record_data() -> void:
	var record := _make_record()
	_check(record.get_size_text() == "1.0 MB", "record formats megabyte size")
	record.path = "app://music_downloads\\bilibili\\abc.m4a"
	record.format = ".M4A"
	record.bytes = -5
	record.duration = -1
	record.normalize()
	_check(record.path == "app://music_downloads/bilibili/abc.m4a", "record path uses forward slashes")
	_check(record.format == "m4a", "record format is normalized to lowercase extension")
	_check(record.bytes == 0 and record.duration == 0, "record clamps negative sizes and durations")
	_check(record.get_file_name() == "abc.m4a", "record exposes file name")

func _test_state_data() -> void:
	var state := MusicAppStateData.new()
	var record := _make_record()
	state.set_download_record(record)
	_check(state.has_download(record.track_id), "state reports downloaded track")
	_check(state.get_download_record(record.track_id) == record, "state returns stored record")

	var replacement := _make_record()
	replacement.path = "app://music_downloads/bilibili/def.m4a"
	state.set_download_record(replacement)
	_check(state.downloads.size() == 1, "state replaces record with same track id")
	_check(state.get_download_record(record.track_id).path.ends_with("def.m4a"), "state keeps latest record")

	state.set_download_record(_make_record("plugin:bilibili:BV2test"))
	_check(state.get_download_records().size() == 2, "state stores distinct downloads")
	var removed := state.remove_download_record(record.track_id)
	_check(removed != null and removed.track_id == record.track_id, "state removes record by track id")
	_check(not state.has_download(record.track_id), "state forgets removed record")

	var invalid := MusicDownloadRecordData.new()
	invalid.track_id = ""
	invalid.path = "app://music_downloads/x.m4a"
	var missing_path := _make_record("plugin:bilibili:BV3test")
	missing_path.path = ""
	state.downloads.append(invalid)
	state.downloads.append(missing_path)
	state.normalize()
	_check(state.downloads.size() == 1, "normalize drops incomplete and duplicate records")

func _test_save_roundtrip() -> void:
	var manager := DX_SaveManager.new()
	manager.save_path = OS.get_cache_dir().path_join("gdmusic-download-test/data.json")
	var track := TrackData.new()
	track.id = "plugin:bilibili:BV1roundtrip"
	track.title = "往返测试"
	track.plugin_id = "bilibili"
	track.plugin_data = {"bvid": "BV1roundtrip", "cid": 123}
	manager.data.music.tracks.append(track)
	var record := _make_record(track.id)
	record.path = "app://music_downloads/bilibili/roundtrip.m4a"
	manager.data.music.set_download_record(record)
	_check(manager.save(true), "save manager writes download index")

	var reloaded := DX_SaveManager.new()
	reloaded.save_path = manager.save_path
	reloaded.load()
	var loaded = reloaded.data.music.get_download_record(track.id)
	_check(loaded != null, "reloaded state keeps download record")
	_check(loaded.path == record.path and loaded.bytes == record.bytes, "reloaded record keeps path and size")
	_check(loaded.source_url == record.source_url, "reloaded record keeps source url")
	_check(reloaded.data.music.version == "0.0.2", "reloaded state uses current save version")

func _test_source_url() -> void:
	var bvid_track := TrackData.new()
	bvid_track.plugin_data = {"bvid": "BV1abc"}
	_check(
		DownloadControllerScript.build_source_url(bvid_track)
		== "https://www.bilibili.com/video/BV1abc",
		"source url derives from bvid"
	)
	var aid_track := TrackData.new()
	aid_track.plugin_data = {"aid": 987654}
	_check(
		DownloadControllerScript.build_source_url(aid_track)
		== "https://www.bilibili.com/video/av987654",
		"source url derives from aid"
	)
	_check(
		DownloadControllerScript.build_source_url(TrackData.new()) == "",
		"source url is empty without media ids"
	)

func _test_target_path() -> void:
	var controller = DownloadControllerScript.new(null)
	var track := TrackData.new()
	track.id = "plugin:bilibili:BV1path"
	track.plugin_id = "bilibili"
	var first: String = controller._build_target_path(track, "m4a")
	var second: String = controller._build_target_path(track, "m4a")
	_check(first == second, "target path is stable for the same track")
	_check(first.begins_with(controller.get_download_root_virtual()), "target path stays under download root")
	_check(first.ends_with(".m4a"), "target path keeps audio extension")
	_check(first.contains("/bilibili/"), "target path groups by plugin id")

	var other := TrackData.new()
	other.id = "plugin:bilibili:BV2path"
	other.plugin_id = "bilibili"
	_check(
		controller._build_target_path(other, "m4a") != first,
		"target path differs per track id"
	)
