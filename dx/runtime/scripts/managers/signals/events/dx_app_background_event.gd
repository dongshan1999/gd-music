class_name DX_AppBackgroundEvent
extends DX_SignalEvent

var is_background: bool

func _init(value: bool = false) -> void:
	is_background = value
