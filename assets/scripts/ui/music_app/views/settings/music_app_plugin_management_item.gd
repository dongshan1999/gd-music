class_name MusicAppPluginManagementItem
extends PanelContainer

signal enabled_toggled(plugin_id: String, enabled: bool)
signal login_requested(plugin_id: String)
signal logout_requested(plugin_id: String)

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var enabled_check_box: CheckBox = %EnabledCheckBox
@onready var login_button: Button = %LoginButton
@onready var logout_button: Button = %LogoutButton

var _plugin_id := ""

func _ready() -> void:
	enabled_check_box.toggled.connect(_on_enabled_toggled)
	login_button.pressed.connect(_on_login_pressed)
	logout_button.pressed.connect(_on_logout_pressed)

func configure(plugin: Dictionary, enabled: bool) -> void:
	_plugin_id = str(plugin.get("id", ""))
	var title := str(plugin.get("name", "")).strip_edges()
	if title.is_empty():
		title = _plugin_id
	title_label.text = title

	enabled_check_box.set_pressed_no_signal(enabled)

	var supports_login := bool(plugin.get("supports_login", false))
	var logged_in := bool(plugin.get("logged_in", false))
	var uname := str(plugin.get("uname", "")).strip_edges()

	# 登录态直接挂在标题右侧，避免「只看到插件名、不知道有没有登录」。
	if supports_login and enabled:
		status_label.visible = true
		if logged_in:
			status_label.text = "已登录：%s" % uname if not uname.is_empty() else "已登录"
			status_label.add_theme_color_override("font_color", Color(0.545, 0.78, 0.545))
		else:
			status_label.text = "未登录"
			status_label.add_theme_color_override("font_color", Color(0.611765, 0.611765, 0.643137))
	else:
		status_label.visible = false

	login_button.visible = supports_login and enabled and not logged_in
	logout_button.visible = supports_login and enabled and logged_in

func _on_enabled_toggled(toggled_on: bool) -> void:
	enabled_toggled.emit(_plugin_id, toggled_on)

func _on_login_pressed() -> void:
	login_requested.emit(_plugin_id)

func _on_logout_pressed() -> void:
	logout_requested.emit(_plugin_id)
