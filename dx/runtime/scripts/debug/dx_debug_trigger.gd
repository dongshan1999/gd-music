class_name DX_DebugTrigger
extends Control

const PopupRegistryScript := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupViewScript := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")
const DEBUG_POPUP_ID := PopupRegistryScript.PopupId.DX_DEBUG
const DEBUG_POPUP_SCENE := preload("res://dx/runtime/scenes/debug/dx_debug_popup.tscn")

@export var showcase_path: NodePath = NodePath("..")
@export var debug_only := true
@export var keyboard_shortcut_enabled := true
@export var keyboard_shortcut_keycode: Key = KEY_F10
@export var required_tap_count := 3
@export var tap_reset_seconds := 1.2

@onready var trigger_button: Button = %TriggerButton

var _tap_count := 0
var _last_tap_msec := 0

func _ready() -> void:
	refresh_visibility()
	if trigger_button != null and not trigger_button.pressed.is_connected(_on_trigger_button_pressed):
		trigger_button.pressed.connect(_on_trigger_button_pressed)

func refresh_visibility() -> void:
	visible = (not debug_only) or OS.is_debug_build()

func _input(event: InputEvent) -> void:
	if not visible or not keyboard_shortcut_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == keyboard_shortcut_keycode:
		if _open_debug_popup():
			get_viewport().set_input_as_handled()

func _on_trigger_button_pressed() -> void:
	if _register_trigger_tap():
		_open_debug_popup()

func _register_trigger_tap() -> bool:
	var now_msec := Time.get_ticks_msec()
	var reset_msec := int(maxf(0.1, tap_reset_seconds) * 1000.0)
	if _last_tap_msec <= 0 or now_msec - _last_tap_msec > reset_msec:
		_tap_count = 0
	_last_tap_msec = now_msec
	_tap_count += 1
	if _tap_count < maxi(1, required_tap_count):
		return false
	_tap_count = 0
	_last_tap_msec = 0
	return true

func _open_debug_popup() -> bool:
	var showcase = get_node_or_null(showcase_path)
	if showcase == null:
		showcase = get_parent()
	if showcase == null:
		showcase = get_tree().current_scene
	if showcase == null:
		return false

	if showcase.has_method("show_popup"):
		return showcase.call("show_popup", DEBUG_POPUP_ID) != null

	var popup = _show_debug_popup_on_debug_layer()
	if popup != null and popup.has_method("setup"):
		popup.call("setup", showcase)
	return popup != null

func _show_debug_popup_on_debug_layer():
	var host := _get_debug_popup_host()
	if host == null:
		return null
	var popup = DEBUG_POPUP_SCENE.instantiate()
	if not (popup is PopupViewScript):
		popup.queue_free()
		return null
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.offset_left = 0.0
	popup.offset_top = 0.0
	popup.offset_right = 0.0
	popup.offset_bottom = 0.0
	host.add_child(popup)
	popup._popup_open(null)
	return popup

func _get_debug_popup_host() -> Node:
	if DX != null:
		var debug_layer := DX.get_node_or_null("DebugLayer") as CanvasLayer
		if debug_layer != null:
			return debug_layer
	return get_parent()
