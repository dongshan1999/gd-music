class_name DX_AppPauseEvent
extends DX_SignalEvent

var paused: bool

func _init(value: bool = false) -> void:
	paused = value
