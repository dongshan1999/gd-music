extends Node

const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupViewType := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")
const PopupId = PopupRegistryType.PopupId

signal popup_shown(popup_id, popup)
signal popup_hidden(popup_id)

@onready var _page_host: Control = %PageHost
@onready var _mini_player_host: Control = %MiniPlayerHost
@onready var _fullscreen_host: Control = %FullscreenHost

var dx: Node
var _current_popup: PopupViewType
var _current_popup_id: int = -1

func show(popup_id: int) -> PopupViewType:
	hide()

	if not PopupRegistryType.has_popup(popup_id):
		push_error("Popup id is not registered: %s" % popup_id)
		return null

	var scene: PackedScene = PopupRegistryType.get_scene(popup_id)
	if scene == null:
		push_error("Popup scene is missing for id: %s" % popup_id)
		return null

	var instance: Node = scene.instantiate()
	if not (instance is PopupViewType):
		push_error("Popup root must extend PopupView.")
		instance.queue_free()
		return null

	var popup: PopupViewType = instance as PopupViewType
	var host := _get_popup_host(popup.get_resolved_popup_layer())
	if host == null:
		push_error("Popup host is missing for popup id: %s" % popup_id)
		instance.queue_free()
		return null

	_stretch_popup(popup)
	host.add_child(popup)

	_current_popup = popup
	_current_popup_id = popup_id
	popup._popup_open(self)
	popup_shown.emit(popup_id, popup)
	return popup

func hide() -> void:
	if _current_popup == null:
		_current_popup_id = -1
		return

	var popup_id: int = _current_popup_id
	var popup: PopupViewType = _current_popup
	_current_popup = null
	_current_popup_id = -1
	popup._popup_close()
	popup.queue_free()
	popup_hidden.emit(popup_id)

func is_showing() -> bool:
	return _current_popup != null

func get_current_popup() -> PopupViewType:
	return _current_popup

func _get_popup_host(popup_layer: int) -> Control:
	match popup_layer:
		PopupViewType.PopupLayer.PAGE:
			return _page_host
		PopupViewType.PopupLayer.MINI_PLAYER:
			return _mini_player_host
		PopupViewType.PopupLayer.FULLSCREEN:
			return _fullscreen_host
	return _fullscreen_host

func _stretch_popup(popup: Control) -> void:
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.offset_left = 0.0
	popup.offset_top = 0.0
	popup.offset_right = 0.0
	popup.offset_bottom = 0.0
