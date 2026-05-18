class_name MusicAppPluginManagementItem
extends PanelContainer

signal enabled_toggled(plugin_id: String, enabled: bool)
signal update_requested(plugin_id: String)
signal share_requested(plugin_id: String)
signal uninstall_requested(plugin_id: String)
signal source_redirect_requested(plugin_id: String)
signal import_playlist_requested(plugin_id: String)

@onready var title_label: Label = %TitleLabel
@onready var meta_label: Label = %MetaLabel
@onready var enabled_check_box: CheckBox = %EnabledCheckBox
@onready var update_button: Button = %UpdateButton
@onready var share_button: Button = %ShareButton
@onready var uninstall_button: Button = %UninstallButton
@onready var source_redirect_button: Button = %SourceRedirectButton
@onready var import_playlist_button: Button = %ImportPlaylistButton

var _plugin_id := ""

func _ready() -> void:
	enabled_check_box.toggled.connect(_on_enabled_toggled)
	update_button.pressed.connect(_on_update_pressed)
	share_button.pressed.connect(_on_share_pressed)
	uninstall_button.pressed.connect(_on_uninstall_pressed)
	source_redirect_button.pressed.connect(_on_source_redirect_pressed)
	import_playlist_button.pressed.connect(_on_import_playlist_pressed)

func configure(plugin: Dictionary, enabled: bool) -> void:
	_plugin_id = str(plugin.get("id", ""))
	var title := str(plugin.get("name", "")).strip_edges()
	if title.is_empty():
		title = _plugin_id
	title_label.text = title

	var meta_parts := PackedStringArray()
	var version := str(plugin.get("version", "")).strip_edges()
	var author := str(plugin.get("author", "")).strip_edges()
	if not version.is_empty():
		meta_parts.append(tr("music_app.plugin_management.item.version").format({"value": version}))
	if not author.is_empty():
		meta_parts.append(tr("music_app.plugin_management.item.author").format({"value": author}))
	meta_label.text = "   ".join(meta_parts)

	enabled_check_box.set_pressed_no_signal(enabled)

func _on_enabled_toggled(toggled_on: bool) -> void:
	enabled_toggled.emit(_plugin_id, toggled_on)

func _on_update_pressed() -> void:
	update_requested.emit(_plugin_id)

func _on_share_pressed() -> void:
	share_requested.emit(_plugin_id)

func _on_uninstall_pressed() -> void:
	uninstall_requested.emit(_plugin_id)

func _on_source_redirect_pressed() -> void:
	source_redirect_requested.emit(_plugin_id)

func _on_import_playlist_pressed() -> void:
	import_playlist_requested.emit(_plugin_id)
