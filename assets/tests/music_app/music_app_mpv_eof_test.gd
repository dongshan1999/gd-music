extends Node
## 验证 gdmpv 播完一段本地音频后一定会派发 `finished` 信号。
##
## 回归背景：改用 libmpv 流式后端后，出现「一首播完不自动切下一首」。
## 自动切歌链路是 GDMPVPlayer.finished → AudioBackend.finished →
## MusicAppAudioController._on_backend_finished → on_audio_finished →
## advance_after_finish，因此这套链路的第一环必须可靠。
##
## 运行：
##   godot --headless --path . res://assets/tests/music_app/music_app_mpv_eof_test.tscn
##
## 退出码 0 = 通过（或桌面未编译 gdmpv 而跳过）。

const FIXTURE := "res://assets/tests/music_app/fixtures/tone.m4a"
const GDMPV_CLASS := "GDMPVPlayer"
const TIMEOUT_SEC := 20.0

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[mpv-eof] OK    %s" % message)
	else:
		_failures.append(message)
		printerr("[mpv-eof] FAIL  %s" % message)


func _run() -> void:
	if not ClassDB.class_exists(GDMPV_CLASS):
		print("[mpv-eof] SKIP  GDMPVPlayer 未注册（桌面未编译 gdmpv）")
		get_tree().quit(0)
		return

	var player: Variant = ClassDB.instantiate(GDMPV_CLASS)
	if player == null:
		printerr("[mpv-eof] FAIL  实例化 GDMPVPlayer 失败")
		get_tree().quit(1)
		return
	add_child(player)
	_check(player.initialize() == OK, "mpv 初始化成功")
	if not _failures.is_empty():
		get_tree().quit(1)
		return

	var fired := [false]
	var fired_at := [0]
	player.finished.connect(func() -> void:
		fired[0] = true
		fired_at[0] = Time.get_ticks_msec()
	)

	var path := ProjectSettings.globalize_path(FIXTURE)
	_check(player.load_file(path, {}) == OK, "load_file 接受本地音频路径")
	player.play()

	var start := Time.get_ticks_msec()
	while not fired[0] and (Time.get_ticks_msec() - start) < int(TIMEOUT_SEC * 1000.0):
		await get_tree().process_frame

	var waited := (Time.get_ticks_msec() - start) / 1000.0
	_check(fired[0], "播放结束后派发 finished（等了 %.2fs）" % waited)
	if fired[0]:
		print("[mpv-eof] finished 在 %.2fs 到达" % ((fired_at[0] - start) / 1000.0))
	else:
		printerr("[mpv-eof] 超时 %.1fs 未收到 finished —— 自动切歌链路第一环断了" % TIMEOUT_SEC)

	get_tree().quit(0 if _failures.is_empty() else 1)
