extends Node
## 验证「一首播完自动切下一首」的状态链路。
##
## 真实的完成事件链路是：
##   GDMPVPlayer.finished / AudioStreamPlayer.finished
##   → AudioBackend.finished
##   → MusicAppPlaybackStateController._on_backend_finished
##   → on_audio_finished() → PlaybackController.advance_after_finish()
##   → play_queue_index(下一首)
##
## 本测试绕过解码，直接触发 `on_audio_finished()`，验证状态机是否推进。
## 运行：
##   godot --headless --path . res://assets/tests/music_app/music_app_auto_advance_test.tscn

const ShowcaseScene := "res://assets/scenes/music_app_showcase_scene.tscn"
const FIXTURE := "res://assets/tests/music_app/fixtures/tone.m4a"

var _failures: Array[String] = []


func _ready() -> void:
	# 绝不污染用户存档：把 autoload 存档重定向到缓存目录。
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-auto-advance-test/autoload.json")
	DX.save.data = DX_SaveData.new()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[advance] OK    %s" % message)
	else:
		_failures.append(message)
		printerr("[advance] FAIL  %s" % message)


func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	var scene: PackedScene = load(ShowcaseScene)
	var showcase: Control = scene.instantiate()
	add_child(showcase)
	await get_tree().process_frame

	var ctrl = showcase._playback_state_controller
	var base = ctrl._get_base_controller()
	var state = base.get_app_state()
	var playback = state.playback_state

	var first := TrackData.new()
	first.id = "advance-test-1"
	first.title = "测试曲目一"
	first.duration = 120
	first.file_path = FIXTURE
	var second := TrackData.new()
	second.id = "advance-test-2"
	second.title = "测试曲目二"
	second.duration = 120
	second.file_path = FIXTURE
	state.tracks.append(first)
	state.tracks.append(second)

	playback.track_ids.append(first.id)
	playback.track_ids.append(second.id)
	playback.queue_index = 0
	playback.selected_track_id = first.id
	playback.is_playing = true
	playback.mode = MusicAppStateData.PlaybackMode.LOOP_ALL

	# 场景 1：顺序播放，播完应当前进到第 2 首。
	ctrl.on_audio_finished(null)
	# 播放态必须在推进「当场」就是 true：之后的异步加载若失败，
	# _mark_playback_unavailable() 会把它置否，那是解码环境问题、不是切歌链路问题。
	var playing_after_advance: bool = playback.is_playing
	await get_tree().process_frame
	await get_tree().process_frame
	_check(playback.queue_index == 1, "播完后队列游标前进到 1（实际 %d）" % playback.queue_index)
	_check(playback.selected_track_id == second.id, "播完后选中曲目切到第 2 首（实际 %s）" % playback.selected_track_id)
	_check(playing_after_advance, "自动切歌当场仍处于播放态")

	# 场景 2：单曲循环不前进。
	playback.mode = MusicAppStateData.PlaybackMode.REPEAT_ONE
	playback.queue_index = 0
	playback.selected_track_id = first.id
	playback.is_playing = true
	ctrl.on_audio_finished(null)
	await get_tree().process_frame
	_check(playback.queue_index == 0, "REPEAT_ONE 播完停在原游标（实际 %d）" % playback.queue_index)

	# 场景 3：完成事件到达时播放态已被置否——记录当前行为。
	# 若这里不推进，说明「谁先把 is_playing 置 false，谁就吃掉了自动切歌」。
	playback.mode = MusicAppStateData.PlaybackMode.LOOP_ALL
	playback.queue_index = 0
	playback.selected_track_id = first.id
	playback.is_playing = false
	ctrl.on_audio_finished(null)
	await get_tree().process_frame
	if playback.queue_index == 1:
		print("[advance] NOTE  播放态为 false 时仍会推进（不依赖 is_playing 门槛）")
	else:
		print("[advance] NOTE  播放态为 false 时不再推进（依赖 is_playing 门槛，实际 %d）" % playback.queue_index)

	# 场景 4：后台巡检的判定逻辑。App 在后台时 Godot 主循环基本不推进，
	# mpv 播完的 finished 排在延迟队列里永远不上报，只能靠前台服务每秒一次的
	# tick 回调主动查状态。这里直接验判定函数，三种状态必须分得开。
	var eof_player := PlayerStub.new(true, false, 118.0, 120.0, "")
	var stopped_player := PlayerStub.new(false, false, 0.0, 120.0, "")
	var paused_player := PlayerStub.new(false, true, 60.0, 120.0, "")
	var error_player := PlayerStub.new(true, false, 118.0, 120.0, "播放结束（异常）")
	_check(ctrl._player_reached_end(eof_player), "播到结尾能被巡检识别")
	_check(not ctrl._player_reached_end(stopped_player), "主动停止（位置归零）不会被误判成播完")
	_check(not ctrl._player_reached_end(paused_player), "暂停不会被误判成播完")
	_check(not ctrl._player_reached_end(error_player), "报错的曲目不会被当成自然播完")

	# 场景 5：真实播放到结尾，同时把 finished 信号断开——等价于「后台主循环冻结，
	# deferred 的完成事件永远排不上队」。这种情况下必须靠每秒一次的巡检把队列推进。
	playback.mode = MusicAppStateData.PlaybackMode.LOOP_ALL
	playback.queue_index = 0
	playback.selected_track_id = first.id
	playback.is_playing = true
	ctrl._loaded_track_key = ""
	ctrl._last_auto_finish_msec = 0
	ctrl.request_audio_sync()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Variant = ctrl._get_active_player()
	if player == null or not ctrl._player_has_stream(player):
		# headless 环境里原生解码器读不了 res:// 的 m4a，起播失败就跳过这一段，
		# 判定逻辑本身已经由场景 4 的桩对象覆盖。
		print("[advance] NOTE  测试环境未真正起播，跳过「真实播完 + finished 丢失」场景")
	else:
		for conn in player.finished.get_connections():
			player.finished.disconnect(conn["callable"])
		var waited := 0.0
		while waited < 15.0 and not ctrl._player_reached_end(player):
			await get_tree().create_timer(0.2).timeout
			waited += 0.2
		_check(ctrl._player_reached_end(player), "真实播放到结尾后巡检判定为播完（等待 %.1fs）" % waited)
		ctrl._poll_background_playback_end()
		await get_tree().process_frame
		_check(playback.queue_index == 1, "巡检在 finished 丢失时仍把队列推进到第 2 首（实际 %d）" % playback.queue_index)

	for failure in _failures:
		printerr("[advance] 失败：%s" % failure)
	print("[advance] 完成，失败 %d 项" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


## 播放器替身：只实现巡检判定用到的那几个方法。
class PlayerStub:
	extends RefCounted

	var _eof: bool
	var _paused: bool
	var _position: float
	var _duration: float
	var _last_error: String

	func _init(eof: bool, paused: bool, position: float, duration: float, last_error: String) -> void:
		_eof = eof
		_paused = paused
		_position = position
		_duration = duration
		_last_error = last_error

	func has_stream() -> bool:
		return true

	func is_playing() -> bool:
		return not _eof and not _paused

	func is_paused() -> bool:
		return _paused

	func get_position() -> float:
		return _position

	func get_duration() -> float:
		return _duration

	func get_last_error() -> String:
		return _last_error
