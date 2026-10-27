## AudioBackend 层冒烟测试：验证工厂 + LibMpvAudioBackend 的 GDScript 封装。
##
## 运行：
##   SMOKE_AUDIO=/tmp/gdmpv_test_tone.m4a \
##   godot --headless --path . res://addons/gdmpv/test/audio_backend_smoke_scene.tscn
extends Node

const Factory := preload("res://assets/scripts/ui/music_app/audio/audio_backend_factory.gd")
const LibMpvBackend := preload("res://assets/scripts/ui/music_app/audio/libmpv_audio_backend.gd")

const SETTING_USE_MPV := "audio/backend/use_mpv"

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail.is_empty() else "  " + detail
	if condition:
		print("[backend] OK    %s%s" % [label, suffix])
	else:
		var message := "%s%s" % [label, suffix]
		_failures.append(message)
		printerr("[backend] FAIL  %s" % message)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _audio_path() -> String:
	var override := OS.get_environment("SMOKE_AUDIO")
	if not override.is_empty():
		return override
	return "res://assets/tests/music_app/fixtures/tone.m4a"


func _run() -> void:
	# 1. 工厂：未强制 + 桌面平台时应回退
	ProjectSettings.set_setting(SETTING_USE_MPV, false)
	_check(not Factory.should_use_mpv(), "macOS + use_mpv=false → 走原生后端")
	_check(Factory.try_create(self) == null, "try_create 返回 null（回退）")

	# 2. 工厂：强制开启时应创建 mpv 后端
	ProjectSettings.set_setting(SETTING_USE_MPV, true)
	_check(Factory.should_use_mpv(), "use_mpv=true → 走 mpv 后端")

	var backend: Variant = Factory.try_create(self)
	_check(backend != null, "try_create 成功创建 LibMpvAudioBackend")
	if backend == null:
		ProjectSettings.set_setting(SETTING_USE_MPV, false)
		return
	_check(backend is LibMpvBackend, "返回类型是 LibMpvAudioBackend")
	_check(backend.is_available(), "is_available() == true")

	# 3. 接口：load_source → play → 位置推进
	backend.set_volume_db(-80.0)
	var load_err: int = backend.load_source(_audio_path())
	_check(load_err == OK, "load_source()", "err=%d" % load_err)

	backend.play()
	await _wait(1.0)

	_check(backend.is_playing(), "is_playing() 播放中")
	var position: float = backend.get_playback_position()
	var duration: float = backend.get_duration()
	_check(position > 0.0, "get_playback_position()", "pos=%.3f" % position)
	_check(duration > 0.0, "get_duration()", "dur=%.3f" % duration)

	# 4. has_stream（controller 用它判断「有没有歌」）
	_check(backend.has_stream(), "has_stream() == true（已 load 过）")

	# 5. pause / seek / stop
	backend.set_paused(true)
	await _wait(0.2)
	_check(backend.is_paused(), "set_paused(true)")
	backend.set_paused(false)
	await _wait(0.2)
	_check(not backend.is_paused(), "set_paused(false)")

	backend.seek(1.0)
	await _wait(0.5)
	var seek_pos: float = backend.get_playback_position()
	_check(absf(seek_pos - 1.0) < 0.6, "seek(1.0)", "pos=%.3f" % seek_pos)

	backend.stop()
	await _wait(0.3)
	_check(not backend.is_playing(), "stop() 后不播放")

	# 6. 控制器对流式后端的探测与「清空流」兼容性（Phase 1 接入点）
	var controller_script: Script = load("res://assets/scripts/ui/music_app/controllers/global/music_app_audio_controller.gd")
	var ctrl: Variant = controller_script.new()
	_check(ctrl._is_streaming_backend(backend), "_is_streaming_backend(mpv) == true")
	var native_player := AudioStreamPlayer.new()
	add_child(native_player)
	_check(not ctrl._is_streaming_backend(native_player), "_is_streaming_backend(AudioStreamPlayer) == false")

	backend.play()
	await _wait(0.2)
	ctrl._set_player_stream(backend, null)
	await _wait(0.2)
	_check(not backend.is_playing(), "_set_player_stream(mpv, null) 停止播放且不崩溃")

	# 7. 流式来源解析：本地文件分支应原样直通给 mpv（不读整首字节）
	var track := TrackData.new()
	track.id = "smoke-track"
	track.file_path = _audio_path()
	var resolved: Dictionary = await ctrl._resolve_streaming_source(track, ctrl._audio_sync_request_id)
	_check(
		str(resolved.get("url", "")) == _audio_path(),
		"_resolve_streaming_source 本地文件直通",
		"url=%s" % str(resolved.get("url", ""))
	)

	backend.shutdown()
	_check(true, "shutdown() 未崩溃")

	ProjectSettings.set_setting(SETTING_USE_MPV, false)

	if _failures.is_empty():
		print("[backend] ===== 全部通过 =====")
	else:
		printerr("[backend] ===== 失败 %d 项 =====" % _failures.size())
		for item in _failures:
			printerr("[backend]   - %s" % item)
