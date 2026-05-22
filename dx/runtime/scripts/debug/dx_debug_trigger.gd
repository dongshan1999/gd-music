class_name DX_DebugTrigger
extends Control

const MusicAppControllerBaseScript := preload("res://scripts/ui/music_app/controllers/music_app_controller_base.gd")
const DEBUG_POPUP_ID := DX_PopupRegistry.PopupId.DX_DEBUG

@export var showcase_path: NodePath = NodePath("..")
@export var debug_only := true
@export var keyboard_shortcut_enabled := true
@export var keyboard_shortcut_keycode: Key = KEY_F10

@onready var trigger_button: Button = %TriggerButton

func _ready() -> void:
	visible = (not debug_only) or OS.is_debug_build()
	if trigger_button != null and not trigger_button.pressed.is_connected(_on_trigger_button_pressed):
		trigger_button.pressed.connect(_on_trigger_button_pressed)

func _input(event: InputEvent) -> void:
	if not visible or not keyboard_shortcut_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == keyboard_shortcut_keycode:
		if _open_debug_popup():
			get_viewport().set_input_as_handled()

func _on_trigger_button_pressed() -> void:
	_open_debug_popup()

func _open_debug_popup() -> bool:
	var showcase = get_node_or_null(showcase_path)
	if showcase == null:
		showcase = get_parent()
	if showcase == null:
		showcase = get_tree().current_scene
	if showcase == null:
		return false

	var base_controller := MusicAppControllerBaseScript.new(showcase)
	return base_controller.show_popup(DEBUG_POPUP_ID) != null
