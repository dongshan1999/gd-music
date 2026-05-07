class_name CommonDialogPopup
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

var _confirm_action: Callable = Callable()
var _cancel_action: Callable = Callable()

@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton

func _ready() -> void:
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

func show_alert(
	title: String,
	message: String,
	confirm_text: String = "确定",
	on_confirm: Callable = Callable()
) -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.visible = false
	_confirm_action = on_confirm
	_cancel_action = Callable()

func show_confirm(
	title: String,
	message: String,
	on_confirm: Callable = Callable(),
	on_cancel: Callable = Callable(),
	confirm_text: String = "确定",
	cancel_text: String = "取消"
) -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	cancel_button.visible = true
	_confirm_action = on_confirm
	_cancel_action = on_cancel

func _on_confirm_pressed() -> void:
	var callback: Callable = _confirm_action
	close_popup()
	if callback.is_valid():
		callback.call()

func _on_cancel_pressed() -> void:
	var callback: Callable = _cancel_action
	close_popup()
	if callback.is_valid():
		callback.call()
