class_name MusicAppPlaybackProgressChangedEvent
extends DX_SignalEvent

var track
var elapsed_seconds := 0
var duration_seconds := 0

func _init(track_value = null, elapsed_value: int = 0, duration_value: int = 0) -> void:
	track = track_value
	elapsed_seconds = elapsed_value
	duration_seconds = duration_value
