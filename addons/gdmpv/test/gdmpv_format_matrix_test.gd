## gdmpv 格式矩阵测试：验证 libmpv 对各类音频容器的解码能力。
##
## 运行：
##   GDMPV_FORMAT_DIR=/tmp/gdmpv_formats \
##     godot --headless --path . res://addons/gdmpv/test/gdmpv_format_matrix_scene.tscn
##
## 目录内的每个文件独立建一个播放器，播放 1 秒后检查位置是否推进。
## 退出码 0 = 全部可播，1 = 有失败项。
extends Node

const PLAY_SECONDS := 1.0
const MIN_ADVANCE := 0.2

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail.is_empty() else "  " + detail
	if condition:
		print("[format] OK    %s%s" % [label, suffix])
	else:
		var message := "%s%s" % [label, suffix]
		_failures.append(message)
		printerr("[format] FAIL  %s" % message)


func _run() -> void:
	var directory := OS.get_environment("GDMPV_FORMAT_DIR")
	if directory.is_empty():
		printerr("[format] FAIL  需要设置 GDMPV_FORMAT_DIR")
		_failures.append("缺少 GDMPV_FORMAT_DIR")
		return
	if not ClassDB.class_exists("GDMPVPlayer"):
		printerr("[format] FAIL  GDMPVPlayer 未注册")
		_failures.append("GDMPVPlayer 未注册")
		return

	var files := _collect(directory)
	if files.is_empty():
		printerr("[format] FAIL  目录里没有音频文件：%s" % directory)
		_failures.append("样本为空")
		return

	print("[format] 共 %d 个样本：%s" % [files.size(), directory])
	for path in files:
		await _check_file(path)


func _collect(directory: String) -> Array[String]:
	var result: Array[String] = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return result
	handle.list_dir_begin()
	var name := handle.get_next()
	while name != "":
		if not handle.current_is_dir() and not name.begins_with("."):
			result.append(directory.path_join(name))
		name = handle.get_next()
	handle.list_dir_end()
	result.sort()
	return result


func _check_file(path: String) -> void:
	var label := path.get_file()
	var player: Variant = ClassDB.instantiate("GDMPVPlayer")
	if player == null:
		_check(false, label, "instantiate 失败")
		return
	add_child(player)

	if int(player.initialize()) != OK:
		_check(false, label, "initialize 失败")
		player.queue_free()
		return

	var load_err: int = player.load_file(path)
	player.play()
	await get_tree().create_timer(PLAY_SECONDS).timeout
	var duration: float = float(player.get_duration())
	var cursor: float = float(player.get_position())
	var error_message := str(player.get_last_error())
	player.stop()
	player.shutdown()
	player.queue_free()

	var advanced := cursor > MIN_ADVANCE
	var detail := "pos=%.2f duration=%.2f%s" % [
		cursor,
		duration,
		"" if error_message.is_empty() else " err=" + error_message,
	]
	_check(load_err == OK and advanced and error_message.is_empty(), label, detail)

