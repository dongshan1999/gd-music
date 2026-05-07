extends Control

enum PopupLayer {
	PAGE,
	MINI_PLAYER,
	FULLSCREEN
}

@export var popup_layer: PopupLayer = PopupLayer.FULLSCREEN

var popup_manager

func get_resolved_popup_layer() -> int:
	return popup_layer

func close_popup() -> void:
	if popup_manager != null:
		popup_manager.hide()

func _popup_open(manager) -> void:
	popup_manager = manager
	visible = true
	on_popup_shown()

func _popup_close() -> void:
	on_popup_hidden()
	popup_manager = null

func on_popup_shown() -> void:
	pass

func on_popup_hidden() -> void:
	pass
