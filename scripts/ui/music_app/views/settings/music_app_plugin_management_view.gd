class_name MusicAppPluginManagementView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const PluginManagementControllerScript := preload(
	MusicAppScriptPathsType.MUSIC_APP_PLUGIN_MANAGEMENT_CONTROLLER
)
const PLUGIN_ITEM_SCENE := preload(MusicAppScriptPathsType.PLUGIN_MANAGEMENT_ITEM)

var _controller: MusicAppShowcaseController
var _plugin_management_controller
var _is_bound := false
var _is_loading := false
var _plugin_items: Array = []
var _plugins: Array[Dictionary] = []

@onready var back_button: Button = %PluginManagementBackButton
@onready var more_button: Button = %PluginManagementMoreButton
@onready var plugin_list: VBoxContainer = %PluginManagementList
@onready var empty_label: Label = %PluginManagementEmptyLabel
@onready var install_panel: PanelContainer = %InstallPanel
@onready var install_from_file_button: Button = %InstallFromFileButton
@onready var install_from_url_button: Button = %InstallFromUrlButton
@onready var update_all_button: Button = %UpdateAllButton
@onready var update_subscriptions_button: Button = %UpdateSubscriptionsButton
@onready var floating_add_button: Button = %FloatingAddButton
@onready var status_label: Label = %PluginManagementStatusLabel
@onready var plugin_directory_dialog: FileDialog = %PluginDirectoryDialog

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_plugin_management_controller = PluginManagementControllerScript.new(controller)
	bind()
	refresh()
	_request_reload()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	back_button.pressed.connect(close_popup)
	more_button.pressed.connect(_toggle_install_panel)
	floating_add_button.pressed.connect(_toggle_install_panel)
	install_from_file_button.pressed.connect(_on_install_from_file_pressed)
	install_from_url_button.pressed.connect(_on_install_from_url_pressed)
	update_all_button.pressed.connect(_on_update_all_pressed)
	update_subscriptions_button.pressed.connect(_on_update_subscriptions_pressed)
	plugin_directory_dialog.dir_selected.connect(_on_plugin_dir_selected)

	plugin_directory_dialog.access = FileDialog.ACCESS_FILESYSTEM
	plugin_directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	plugin_directory_dialog.set_use_native_dialog(true)

func on_popup_shown() -> void:
	refresh()
	_request_reload()

func refresh() -> void:
	if _controller == null:
		return
	empty_label.visible = _plugins.is_empty() and not _is_loading
	status_label.text = tr("music_app.plugin_management.status.loading") if _is_loading else status_label.text
	_sync_plugin_items()

func _request_reload() -> void:
	call_deferred("_reload_plugins_deferred")

func _reload_plugins_deferred() -> void:
	_is_loading = true
	status_label.text = tr("music_app.plugin_management.status.checking_host")
	refresh()

	var ensure_result: Dictionary = await _plugin_management_controller.ensure_plugins_ready()
	if not bool(ensure_result.get("ok", false)):
		_plugins.clear()
		_is_loading = false
		status_label.text = str(
			ensure_result.get("error", tr("music_app.plugin_management.status.host_unavailable"))
		)
		refresh()
		return

	status_label.text = tr("music_app.plugin_management.status.loading_plugins")
	var list_result: Dictionary = await _plugin_management_controller.list_plugins()
	_is_loading = false
	if not bool(list_result.get("ok", false)):
		_plugins.clear()
		status_label.text = str(
			list_result.get("error", tr("music_app.plugin_management.status.load_failed"))
		)
		refresh()
		return

	var payload = list_result.get("data", {})
	if payload is Dictionary and payload.get("plugins", null) is Array:
		_plugins = _normalize_dictionary_array(payload.get("plugins", []))
	else:
		_plugins = []

	status_label.text = tr("music_app.plugin_management.status.loaded_count").format(
		{"count": _plugins.size()}
	)
	refresh()

func _sync_plugin_items() -> void:
	while _plugin_items.size() < _plugins.size():
		var item = PLUGIN_ITEM_SCENE.instantiate()
		plugin_list.add_child(item)
		item.enabled_toggled.connect(_on_plugin_enabled_toggled)
		item.update_requested.connect(_on_plugin_update_requested)
		item.share_requested.connect(_on_plugin_share_requested)
		item.uninstall_requested.connect(_on_plugin_uninstall_requested)
		item.source_redirect_requested.connect(_on_plugin_source_redirect_requested)
		item.import_playlist_requested.connect(_on_plugin_import_playlist_requested)
		_plugin_items.append(item)

	while _plugin_items.size() > _plugins.size():
		var item = _plugin_items.pop_back()
		item.queue_free()

	for index in _plugin_items.size():
		var plugin := _plugins[index]
		var plugin_id := str(plugin.get("id", ""))
		_plugin_items[index].configure(
			plugin,
			_plugin_management_controller.is_plugin_enabled(plugin_id)
		)

func _normalize_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item in value:
		if item is Dictionary:
			result.append(item)
	return result

func _toggle_install_panel() -> void:
	install_panel.visible = not install_panel.visible

func _on_install_from_file_pressed() -> void:
	install_panel.visible = false
	plugin_directory_dialog.popup_file_dialog()

func _install_plugin_from_path(plugin_path: String) -> void:
	var normalized_plugin_path := plugin_path.strip_edges()
	if normalized_plugin_path.is_empty():
		return

	var result: Dictionary = await _plugin_management_controller.install_plugin_from_file(normalized_plugin_path)
	if not bool(result.get("ok", false)):
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.install.title"),
			tr("music_app.plugin_management.install.local_failed").format(
				{
					"error": str(
						result.get("error", tr("music_app.plugin_management.common.unknown_error"))
					)
				}
			)
		)
		return
	_plugin_management_controller.show_toast(tr("music_app.plugin_management.install.success"))
	_request_reload()

func _on_install_from_url_pressed() -> void:
	install_panel.visible = false
	_plugin_management_controller.show_common_alert(
		tr("music_app.plugin_management.install.title"),
		tr("music_app.plugin_management.install.url_unavailable")
	)

func _on_update_all_pressed() -> void:
	install_panel.visible = false
	_plugin_management_controller.show_update_placeholder()

func _on_update_subscriptions_pressed() -> void:
	install_panel.visible = false
	_plugin_management_controller.show_update_placeholder()

func _on_plugin_enabled_toggled(plugin_id: String, enabled: bool) -> void:
	_plugin_management_controller.set_plugin_enabled(plugin_id, enabled)
	_plugin_management_controller.show_toast(
		tr(
			"music_app.plugin_management.toast.enabled"
			if enabled
			else "music_app.plugin_management.toast.disabled"
		)
	)

func _on_plugin_update_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_update_placeholder()

func _on_plugin_share_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_share_placeholder()

func _on_plugin_uninstall_requested(plugin_id: String) -> void:
	var result: Dictionary = await _plugin_management_controller.uninstall_plugin(plugin_id)
	if not bool(result.get("ok", false)):
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.uninstall.title"),
			str(result.get("error", tr("music_app.plugin_management.uninstall.failed")))
		)
		return
	_plugin_management_controller.show_toast(tr("music_app.plugin_management.uninstall.success"))
	_request_reload()

func _on_plugin_source_redirect_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_source_redirect_placeholder()

func _on_plugin_import_playlist_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_import_playlist_placeholder()

func _on_plugin_dir_selected(dir: String) -> void:
	_install_plugin_from_path(dir)
