## 用 libmpv（`addons/gdmpv` 的 `GDMPVPlayer`）作为播放后端。
##
## 与 `NodeAudioBackend` 的区别：
##   - 不走 Godot 的 AudioServer，因此**不受引擎「失焦暂停音频」影响**
##   - 直接吃 URL，不需要先解码成 AudioStream（省掉整首下载）
##   - 状态由 native 侧缓存，`get_playback_position()` 是 O(1) 读
##
## 未编译 gdmpv 扩展时，`is_available()` 返回 false，工厂会回退到
## `NodeAudioBackend`，不会影响现有播放。
class_name LibMpvAudioBackend
extends AudioBackend

## 与 `addons/gdmpv/src/register_types.cpp` 注册的类名保持一致
const GDMPV_CLASS := "GDMPVPlayer"

var _player: Variant = null
var _available := false
var _init_error := ""
var _last_loaded_url := ""


func _init(host: Node = null) -> void:
	if not ClassDB.class_exists(GDMPV_CLASS):
		_init_error = "GDMPVPlayer 未注册：addons/gdmpv 扩展未编译或未加载"
		return
	if host == null:
		_init_error = "缺少 host 节点，无法挂载 GDMPVPlayer"
		return

	_player = ClassDB.instantiate(GDMPV_CLASS)
	if _player == null:
		_init_error = "GDMPVPlayer 实例化失败"
		return

	host.add_child(_player)
	_player.finished.connect(_on_player_finished)
	_player.state_changed.connect(_on_player_state_changed)
	_player.error_occurred.connect(_on_player_error)

	if _player.initialize() != OK:
		_init_error = "gdmpv 初始化失败：%s" % _player.get_last_error()
		_player.queue_free()
		_player = null
		return

	_available = true


# ── 工厂探测 ──────────────────────────────────────────────

func is_available() -> bool:
	return _available


func get_init_error() -> String:
	return _init_error


# ── mpv 专用入口（Phase 2 起由 controller 直接调用） ──────

## 直接把地址交给 mpv 流式播放，跳过 Godot 的解码链路。
func load_source(url: String, headers: Dictionary = {}) -> Error:
	if not _available:
		return ERR_UNAVAILABLE
	_last_loaded_url = url
	return _player.load_file(url, headers)


func get_last_loaded_url() -> String:
	return _last_loaded_url


# ── 信号转发 ──────────────────────────────────────────────

func _on_player_finished() -> void:
	finished.emit()


func _on_player_state_changed(playing: bool) -> void:
	state_changed.emit(playing)


func _on_player_error(message: String) -> void:
	error_occurred.emit(message)


# ── AudioBackend 接口 ────────────────────────────────────

func _get_stream() -> Variant:
	# mpv 后端不使用 AudioStream；保留 null 让 `has_stream()` 为 false，
	# 避免 controller 误判「已有流可播」。
	return null


func _set_stream(value: Variant) -> void:
	# Phase 2 分工：controller 在 mpv 模式下不再解码出 AudioStream，
	# 而是直接把 URL 交给 `load_source()`。这里只做告警，不发生效。
	if value != null:
		push_warning("LibMpvAudioBackend 忽略 AudioStream 赋值，请改用 load_source(url)")


func has_stream() -> bool:
	# 对 controller 而言，「有流」等价于「已经 load 过一首歌」。
	return not _last_loaded_url.is_empty()


func is_playing() -> bool:
	return _available and _player.is_playing()


func is_paused() -> bool:
	return not _available or _player.is_paused()


func set_paused(value: bool) -> void:
	if not _available:
		return
	if value:
		_player.pause()
	else:
		_player.play()


func play(from_position: float = 0.0) -> void:
	if not _available:
		return
	if from_position > 0.0:
		_player.seek(from_position)
	_player.play()


func seek(seconds: float) -> void:
	if _available:
		_player.seek(seconds)


func stop() -> void:
	if _available:
		_player.stop()


func get_playback_position() -> float:
	return _player.get_position() if _available else 0.0


func get_duration() -> float:
	return _player.get_duration() if _available else -1.0


func set_volume_db(db: float) -> void:
	if _available:
		_player.set_volume(db_to_linear(db))


func shutdown() -> void:
	if _player != null:
		_player.shutdown()
		_player.queue_free()
		_player = null
	_available = false
