class_name PopupManager
extends Node

const PopupRegistryType := preload("res://dx/runtime/scripts/popup/popup_registry.gd")
const PopupViewType := preload("res://dx/runtime/scripts/popup/popup_view.gd")
const PopupId = PopupRegistryType.PopupId

signal popup_shown(popup_id, popup)
signal popup_hidden(popup_id)

var _root: Control
var _layer: CanvasLayer
var _overlay: ColorRect
var _host: Control
var _current_popup: PopupView
var _current_popup_id: int = -1

func _ready() -> void:
	_ensure_ui()

func show(popup_id: int) -> PopupView:
	_ensure_ui()
	hide()

	if not PopupRegistryType.has_popup(popup_id):
		push_error("Popup id is not registered: %s" % popup_id)
		return null

	var scene: PackedScene = PopupRegistry.get_scene(popup_id)
	var instance: Node = scene.instantiate()
	if not (instance is PopupViewType):
		push_error("Popup root must extend PopupView.")
		instance.queue_free()
		return null

	var popup: PopupViewType = instance as PopupViewType
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.offset_left = 0.0
	popup.offset_top = 0.0
	popup.offset_right = 0.0
	popup.offset_bottom = 0.0
	_host.add_child(popup)

	_current_popup = popup
	_current_popup_id = popup_id
	_root.visible = true
	popup._popup_open(self)
	popup_shown.emit(popup_id, popup)
	return popup

func hide() -> void:
	_ensure_ui()
	if _current_popup == null:
		_root.visible = false
		_current_popup_id = -1
		return

	var popup_id: int = _current_popup_id
	var popup: PopupViewType = _current_popup
	_current_popup = null
	_current_popup_id = -1
	popup._popup_close()
	popup.queue_free()
	_root.visible = false
	popup_hidden.emit(popup_id)

func is_showing() -> bool:
	return _current_popup != null

func get_current_popup() -> PopupViewType:
	return _current_popup

func _on_overlay_gui_input(event: InputEvent) -> void:
	if _current_popup == null or not _current_popup.allow_overlay_close:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			hide()

func _ensure_ui() -> void:
	if _root != null:
		return

	_layer = CanvasLayer.new()
	_layer.name = "PopupLayer"
	_layer.layer = 100
	add_child(_layer)

	_root = Control.new()
	_root.name = "PopupRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_layer.add_child(_root)

	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.58)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_root.add_child(_overlay)

	_host = Control.new()
	_host.name = "PopupHost"
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_host)
