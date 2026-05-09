class_name DX_PopupView
extends Control

enum PopupLayer {
	NORMAL,
	FULLSCREEN
}

@export var popup_layer: PopupLayer = PopupLayer.FULLSCREEN

var popup_manager

func get_resolved_popup_layer() -> int:
	return popup_layer

func close_popup() -> void:
	if popup_manager != null:
		if popup_manager.has_method("hide_popup"):
			popup_manager.hide_popup(self)
		else:
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
