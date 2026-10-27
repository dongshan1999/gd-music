## 统一播放后端接口。
##
## 设计意图：让 `MusicAppPlaybackStateController` 只认一套调用方式，
## 底层可以是 Godot 原生 `AudioStreamPlayer` / `VideoStreamPlayer`，
## 也可以是 libmpv（`GDMPVPlayer`），未来还能接 ExoPlayer / AVPlayer。
##
## 关键约束：为了让 `LibMpvAudioBackend` 能**无缝替换**现有播放器节点，
## 本接口刻意对齐 Godot 播放器的「鸭子接口」：
##   stream / stream_paused / is_playing() / play() / seek() / get_playback_position()
## 这样 controller 里 20 多处 `audio_player.xxx()` 的调用一行都不用改。
class_name AudioBackend
extends RefCounted

## 当前曲目播放结束（正常播完，不含切换曲目）。
signal finished
## 播放/暂停状态变化。
signal state_changed(playing: bool)
## 后端内部错误（初始化失败、解码失败等）。
signal error_occurred(message: String)

## 与 `AudioStreamPlayer.stream` 对齐。
## libmpv 后端不真正使用该字段（它接的是 URL），保留只为兼容现有调用点。
var stream: Variant:
	get:
		return _get_stream()
	set(value):
		_set_stream(value)

## 与 `AudioStreamPlayer.stream_paused` 对齐。
var stream_paused: bool:
	get:
		return is_paused()
	set(value):
		set_paused(value)

# ── 子类必须实现 ──────────────────────────────────────────

func _get_stream() -> Variant:
	return null

func _set_stream(_value: Variant) -> void:
	pass

func is_playing() -> bool:
	return false

func is_paused() -> bool:
	return true

func set_paused(_value: bool) -> void:
	pass

func play(_from_position: float = 0.0) -> void:
	pass

func seek(_seconds: float) -> void:
	pass

func stop() -> void:
	pass

func get_playback_position() -> float:
	return 0.0

func get_duration() -> float:
	return -1.0

func set_volume_db(_db: float) -> void:
	pass

func shutdown() -> void:
	pass

# ── 通用实现 ──────────────────────────────────────────────

func has_stream() -> bool:
	return _get_stream() != null

## 后端是否可用。libmpv 未编译/未加载时返回 false，工厂据此回退。
func is_available() -> bool:
	return true
