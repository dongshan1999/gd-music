class_name MusicAppPlaybackFinishedEvent
extends DX_SignalEvent

var track

func _init(track_value = null) -> void:
	track = track_value
