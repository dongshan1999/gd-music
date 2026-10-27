## 把现有的 Godot 播放器节点（`AudioStreamPlayer` / `VideoStreamPlayer`）
## 包成 `AudioBackend`。
##
## 这是「Godot 原生路径」的正式实现：行为与改造前完全一致，
## 只是把 controller 里 `_player_is_paused` / `_player_position` /
## `_set_player_paused` 那几个手工分派函数收拢到这里。
class_name NodeAudioBackend
extends AudioBackend

## 被包装的播放器节点。不接管生命周期，由场景/controller 持有。
var _player: Node = null


func _init(player: Node) -> void:
	_player = player
	if _player != null and _player is AudioStreamPlayer:
		if not _player.finished.is_connected(_on_player_finished):
			_player.finished.connect(_on_player_finished)


func _on_player_finished() -> void:
	finished.emit()


func is_available() -> bool:
	return is_instance_valid(_player)


func _get_stream() -> Variant:
	return _player.stream if _player != null else null


func _set_stream(value: Variant) -> void:
	if _player != null:
		_player.stream = value


func is_playing() -> bool:
	if _player == null:
		return false
	if _player is VideoStreamPlayer:
		return _player.stream != null and not _player.paused
	return _player.playing


func is_paused() -> bool:
	if _player == null:
		return true
	if _player is VideoStreamPlayer:
		return _player.paused
	return _player.stream_paused


func set_paused(value: bool) -> void:
	if _player == null:
		return
	if _player is VideoStreamPlayer:
		_player.paused = value
	else:
		_player.stream_paused = value


func play(from_position: float = 0.0) -> void:
	if _player == null:
		return
	if _player is VideoStreamPlayer:
		if from_position > 0.0:
			_player.stream_position = from_position
		_player.paused = false
	else:
		_player.play(from_position)


func seek(seconds: float) -> void:
	if _player == null:
		return
	if _player is VideoStreamPlayer:
		_player.stream_position = seconds
	else:
		_player.seek(seconds)


func stop() -> void:
	if _player != null:
		_player.stop()


func get_playback_position() -> float:
	if _player == null:
		return 0.0
	if _player is VideoStreamPlayer:
		return float(_player.stream_position)
	return float(_player.get_playback_position())


func get_duration() -> float:
	if _player == null:
		return -1.0
	if _player is VideoStreamPlayer:
		return _player.get_stream_length()
	if _player.stream != null:
		return _player.stream.get_length()
	return -1.0


func set_volume_db(db: float) -> void:
	if _player != null:
		_player.volume_db = db


func shutdown() -> void:
	# 播放器节点归场景所有，这里只断开信号，不销毁节点。
	if _player != null and _player is AudioStreamPlayer:
		if _player.finished.is_connected(_on_player_finished):
			_player.finished.disconnect(_on_player_finished)
	stop()
