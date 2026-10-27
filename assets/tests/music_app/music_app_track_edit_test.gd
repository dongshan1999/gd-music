extends Node
## 离线验证「编辑曲目信息」的保存规则，不依赖播放器与网络。

const TrackEditControllerScript := preload(
	"res://assets/scripts/ui/music_app/controllers/music_app_track_edit_controller.gd"
)

var _failures := PackedStringArray()


class StubEditController extends "res://assets/scripts/ui/music_app/controllers/music_app_track_edit_controller.gd":
	var target: TrackData = null
	var synced_track: TrackData = null

	func get_target_track() -> TrackData:
		return target

	func _sync_download_record(track: TrackData) -> void:
		synced_track = track


func _ready() -> void:
	# 重定向自动保存路径，测试永不写用户资料库。
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-track-edit-test/autoload.json")
	DX.save.data = DX_SaveData.new()
	call_deferred("_run")

func _run() -> void:
	_test_save_normalizes_input()
	_test_rejects_empty_title()
	_test_rejects_missing_track()
	for failure in _failures:
		push_error(failure)
	print("Music app track edit tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _make_track() -> TrackData:
	var track := TrackData.new()
	track.id = "plugin:bilibili:39252201332.0"
	track.title = "001.周杰伦-晴天"
	track.artist = "超级爱下雨天"
	track.plugin_id = "bilibili"
	track.duration = 270
	return track

func _test_save_normalizes_input() -> void:
	var controller := StubEditController.new(null)
	var track := _make_track()
	controller.target = track

	var result: Dictionary = controller.save_track_info("  周杰伦-晴天  ", "  超级爱下雨天  ")
	_check(bool(result.get("ok", false)), "save succeeds for a valid title")
	_check(track.title == "周杰伦-晴天", "title is stripped")
	_check(track.artist == "超级爱下雨天", "artist is stripped")
	_check(controller.synced_track == track, "download record sync is requested for the saved track")

func _test_rejects_empty_title() -> void:
	var controller := StubEditController.new(null)
	var track := _make_track()
	controller.target = track

	var result: Dictionary = controller.save_track_info("   ", "超级爱下雨天")
	_check(not bool(result.get("ok", true)), "empty title is rejected")
	_check(str(result.get("error", "")) == "歌名不能为空。", "empty title returns a readable error")
	_check(track.title == "001.周杰伦-晴天", "rejected save keeps the original title")
	_check(controller.synced_track == null, "rejected save does not sync download record")

func _test_rejects_missing_track() -> void:
	var controller := StubEditController.new(null)
	var result: Dictionary = controller.save_track_info("晴天", "周杰伦")
	_check(not bool(result.get("ok", true)), "save fails without a current track")
	_check(str(result.get("error", "")) == "当前没有播放中的曲目。", "missing track returns a readable error")
