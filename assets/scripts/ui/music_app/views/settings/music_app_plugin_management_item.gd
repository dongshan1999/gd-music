class_name MusicAppPluginManagementItem
extends PanelContainer

signal enabled_toggled(plugin_id: String, enabled: bool)
signal login_requested(plugin_id: String)

@onready var title_label: Label = %TitleLabel
@onready var enabled_check_box: CheckBox = %EnabledCheckBox
@onready var login_button: Button = %LoginButton

var _plugin_id := ""

func _ready() -> void:
	enabled_check_box.toggled.connect(_on_enabled_toggled)
	login_button.pressed.connect(_on_login_pressed)

func configure(plugin: Dictionary, enabled: bool) -> void:
	_plugin_id = str(plugin.get("id", ""))
	var title := str(plugin.get("name", "")).strip_edges()
	if title.is_empty():
		title = _plugin_id
	title_label.text = title

	enabled_check_box.set_pressed_no_signal(enabled)
	# 已登录就不用再显示「登录账号」，避免状态自相矛盾。
	login_button.visible = (
		bool(plugin.get("supports_login", false))
		and enabled
		and not bool(plugin.get("logged_in", false))
	)

func _on_enabled_toggled(toggled_on: bool) -> void:
	enabled_toggled.emit(_plugin_id, toggled_on)

func _on_login_pressed() -> void:
	login_requested.emit(_plugin_id)
