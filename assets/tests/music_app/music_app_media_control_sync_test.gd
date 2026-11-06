extends Node
## 验证「App 外部媒体入口（Android 通知栏 / 锁屏 / 灵动岛 / 蓝牙耳机）改了播放状态后，
## App 内的迷你播放器和播放页会跟着刷新」。
##
## 背景：两个视图只订阅 PlaybackStarted / PlaybackFinished / PlaybackProgressChanged
## 三条信号来 refresh()，自己不轮询播放队列；而 _on_background_media_control()
## 原先只改状态、不发事件，于是通知栏换了歌或按了暂停之后，App 里还是旧歌名和旧图标。
##
## 运行：
##   HOME=/tmp/godot-home godot --headless --path . res://assets/tests/music_app/music_app_media_control_sync_test.tscn
##
## 退出码 0 = 全过。

const SHOWCASE_SCENE := "res://assets/scenes/music_app_showcase_scene.tscn"
const ScriptPaths := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const ProgressEventScript := preload(ScriptPaths.MUSIC_APP_PLAYBACK_PROGRESS_CHANGED_EVENT)

var _failures: Array[String] = []
var _events: Array = []
var _showcase: Control
var _audio
var _playback

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[media_sync] OK    %s" % message)
	else:
		_failures.append(message)
		printerr("[media_sync] FAIL  %s" % message)

func _on_progress(event: Variant) -> void:
	_events.append(event)

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	# 存档重定向到缓存目录，别碰真实存档。
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-media-sync-test/data.json")
	DX.save.data = DX_SaveData.new()

	var packed: PackedScene = load(SHOWCASE_SCENE)
	_check(packed != null, "展示场景可加载")
	if packed == null:
		_finish()
		return
	_showcase = packed.instantiate() as Control
	add_child(_showcase)
	await get_tree().process_frame
	await get_tree().process_frame

	_audio = _showcase._playback_state_controller
	_playback = _showcase._playback_controller
	_check(_audio != null, "能拿到播放状态控制器")
	_check(_playback != null, "能拿到播放队列控制器")
	if _audio == null or _playback == null:
		_finish()
		return

	# 造两首占位曲目：只验证状态与事件，不验证真的出声（没有真实音频文件）。
	var state: MusicAppStateData = DX.save.data.music
	state.tracks.clear()
	for index in 2:
		var track := TrackData.new()
		track.id = "media_sync_%d" % index
		track.title = "媒体同步测试 %d" % index
		track.artist = "测试歌手"
		track.duration = 100
		state.tracks.append(track)
	var queue: Array[String] = ["media_sync_0", "media_sync_1"]
	_check(_playback.set_playback_queue(queue, 0), "能建立测试播放队列")

	DX.signals.subscribe(ProgressEventScript, _on_progress)
	await get_tree().process_frame
	_events.clear()

	# 1) 通知栏「暂停」：状态要变，并且界面要收到刷新事件。
	_audio.set_is_playing(true)
	await get_tree().process_frame
	_events.clear()
	_audio._on_background_media_control("pause")
	await get_tree().process_frame
	_check(not _audio.is_playing(), "媒体暂停后播放状态变为未播放")
	_check(_events.size() >= 1, "媒体暂停会通知界面刷新")

	# 2) 通知栏「下一首」
	_events.clear()
	var before_index: int = _playback.get_playback_queue_index()
	_audio._on_background_media_control("next")
	await get_tree().process_frame
	_check(_playback.get_playback_queue_index() != before_index, "媒体下一首推进了队列游标")
	_check(_events.size() >= 1, "媒体切歌会通知界面刷新")
	if not _events.is_empty():
		var latest = _events[_events.size() - 1]
		_check(
			latest.track != null and latest.track.id == "media_sync_1",
			"切歌事件带的是队列里的下一首"
		)

	# 3) 通知栏拖动进度条
	_events.clear()
	_audio._on_background_media_control("seek_to:42000")
	await get_tree().process_frame
	_check(_audio.get_elapsed_seconds() == 42, "媒体拖动进度写入了 42 秒")
	_check(_events.size() >= 1, "媒体拖动进度会通知界面刷新")

	# 4) 心跳 tick 不该额外刷界面（每秒都刷会打断滚动和动画）
	_events.clear()
	_audio._on_background_media_control("tick")
	await get_tree().process_frame
	_check(_events.is_empty(), "心跳 tick 不额外刷新界面")

	# 5) 巡检是幂等的：状态没变就不重复发事件
	_events.clear()
	_audio._refresh_ui_if_playback_state_changed()
	_check(_events.is_empty(), "状态没变时巡检不重复刷新界面")

	# 6) 巡检兜底：外部改了状态（没走媒体回调）也能被发现
	_events.clear()
	_playback.play_queue_index(0, false)
	_audio._refresh_ui_if_playback_state_changed()
	_check(_events.size() >= 1, "巡检能发现外部改动的曲目并补刷界面")

	# 7) 迷你播放器真的换成了新曲目
	var mini := _showcase.get_node_or_null("%MiniPlayer")
	_check(mini != null, "主场景有迷你播放器")
	if mini != null:
		var label: Label = mini.get("mini_track_label")
		_check(
			label != null and label.text.contains("媒体同步测试"),
			"迷你播放器刷新到了测试曲目（实际：%s）" % ("" if label == null else label.text)
		)

	# 8) App 在后台连按几下时，deferred 刷新要合并成一次
	_events.clear()
	_audio._on_background_media_control("pause")
	_audio._on_background_media_control("play")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		_events.size() == 1,
		"同一帧内多次媒体操作只触发一次界面刷新（实际 %d 次）" % _events.size()
	)

	_finish()

func _finish() -> void:
	for failure in _failures:
		printerr("[media_sync] failure: %s" % failure)
	print("Music app media control sync tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)
