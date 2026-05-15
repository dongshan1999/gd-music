class_name DX_AppFocusEvent
extends DX_SignalEvent

var focused: bool

func _init(value: bool = false) -> void:
	focused = value
