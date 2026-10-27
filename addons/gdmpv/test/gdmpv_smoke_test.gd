## gdmpv 冒烟测试（Phase 0 验收用）。
##
## 运行：
##   godot --headless --path . res://addons/gdmpv/test/gdmpv_smoke_scene.tscn
##
## 覆盖：扩展注册 → initialize → load_file → play → 位置推进 →
##       duration → pause/resume → seek → stop → shutdown。
## 退出码 0 = 全过，1 = 有失败项。
extends Node

const TEST_AUDIO := "res://assets/tests/music_app/fixtures/tone.m4a"


func _resolve_audio() -> String:
	# 允许用更长的音频做测试（fixtures/tone.m4a 只有 0.163 秒）
	var override := OS.get_environment("SMOKE_AUDIO")
	return override if not override.is_empty() else TEST_AUDIO

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail.is_empty() else "  " + detail
	if condition:
		print("[smoke] OK    %s%s" % [label, suffix])
	else:
		var message := "%s%s" % [label, suffix]
		_failures.append(message)
		printerr("[smoke] FAIL  %s" % message)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	if not ClassDB.class_exists("GDMPVPlayer"):
		printerr("[smoke] FAIL  GDMPVPlayer 未注册（扩展没加载）")
		_failures.append("GDMPVPlayer 未注册")
		return
	print("[smoke] OK    GDMPVPlayer 已注册")

	var player: Variant = ClassDB.instantiate("GDMPVPlayer")
	if player == null:
		printerr("[smoke] FAIL  ClassDB.instantiate 返回 null")
		_failures.append("instantiate 失败")
		return
	add_child(player)

	var init_err: int = player.initialize()
	_check(init_err == OK, "initialize", "err=%d %s" % [init_err, player.get_last_error()])
	if init_err != OK:
		return

	# 静音，避免测试时扬声器突然出声
	player.set_volume(0.0)
	_check(is_equal_approx(player.get_volume(), 0.0), "set_volume(0.0)")

	var audio_path := _resolve_audio()
	var load_err: int = player.load_file(audio_path, {})
	_check(load_err == OK, "load_file", "err=%d %s" % [load_err, audio_path])
	if load_err != OK:
		return

	await _wait(0.2)
	# play/pause/seek/stop 在 C++ 侧返回 void，不要比较返回值
	player.play()
	_check(true, "play() 调用未抛错")

	await _wait(1.0)

	_check(player.is_playing(), "is_playing() 播放中")
	var position: float = player.get_position()
	var duration: float = player.get_duration()
	_check(position > 0.0, "get_position()", "pos=%.3f" % position)
	_check(duration > 0.0, "get_duration()", "dur=%.3f" % duration)

	player.pause()
	await _wait(0.3)
	_check(player.is_paused(), "pause() 后 is_paused()")
	var paused_pos: float = player.get_position()
	await _wait(0.5)
	_check(
		absf(player.get_position() - paused_pos) < 0.1,
		"停顿期间位置不推进",
		"%.3f -> %.3f" % [paused_pos, player.get_position()]
	)

	player.play()
	await _wait(0.3)
	_check(not player.is_paused(), "resume 后不再 paused")

	var seek_target: float = minf(1.5, duration * 0.5)
	player.seek(seek_target)
	await _wait(0.5)
	var seek_pos: float = player.get_position()
	_check(absf(seek_pos - seek_target) < 0.5, "seek(%.2f)" % seek_target, "pos=%.3f" % seek_pos)

	player.stop()
	await _wait(0.3)
	_check(not player.is_playing(), "stop() 后不再播放")

	player.shutdown()
	_check(true, "shutdown() 未崩溃")

	await _wait(0.2)
	if _failures.is_empty():
		print("[smoke] ===== 全部通过 =====")
	else:
		printerr("[smoke] ===== 失败 %d 项 =====" % _failures.size())
		for item in _failures:
			printerr("[smoke]   - %s" % item)
