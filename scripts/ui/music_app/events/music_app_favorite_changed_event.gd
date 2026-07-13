class_name MusicAppFavoriteChangedEvent
extends DX_SignalEvent

var track
var liked := false

func _init(track_value = null, liked_value: bool = false) -> void:
	track = track_value
	liked = liked_value
