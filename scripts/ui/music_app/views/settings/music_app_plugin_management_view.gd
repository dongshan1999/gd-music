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
var _plugin_picker_popup

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

	var ensure_ok: bool = await _plugin_management_controller.ensure_plugins_ready()
	if not ensure_ok:
		_plugins.clear()
		_is_loading = false
		var ensure_error = _plugin_management_controller.last_error
		status_label.text = ensure_error if not ensure_error.is_empty() else tr("music_app.plugin_management.status.host_unavailable")
		refresh()
		return

	status_label.text = tr("music_app.plugin_management.status.loading_plugins")
	var list_result: Array[Dictionary] = _plugin_management_controller.list_plugins()
	_is_loading = false
	if list_result.is_empty() and not _plugin_management_controller.last_error.is_empty():
		_plugins.clear()
		status_label.text = _plugin_management_controller.last_error
		refresh()
		return

	_plugins = list_result

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
	if OS.get_name() == "Android":
		_open_android_plugin_directory_picker()
		return
	var popup_router = _plugin_management_controller.get_popup_router_controller()
	if popup_router == null:
		return
	_plugin_picker_popup = popup_router.show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLUGIN_FILE_PICKER)
	if _plugin_picker_popup != null and _plugin_picker_popup.has_signal("plugin_selected"):
		if not _plugin_picker_popup.plugin_selected.is_connected(_on_plugin_file_picked):
			_plugin_picker_popup.plugin_selected.connect(_on_plugin_file_picked)

func _open_android_plugin_directory_picker() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.install.title"),
			"Current Android runtime does not support native SAF directory picker."
		)
		return
	DisplayServer.file_dialog_show(
		"",
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
		PackedStringArray(),
		Callable(self, "_on_android_plugin_directory_picked")
	)

func _on_android_plugin_directory_picked(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	if not status or selected_paths.is_empty():
		return
	call_deferred("_install_plugin_from_android_tree_uri", selected_paths[0])

func _install_plugin_from_android_tree_uri(tree_uri: String) -> void:
	var normalized_tree_uri := tree_uri.strip_edges()
	if normalized_tree_uri.is_empty():
		return
	_install_plugin_from_android_tree_async(normalized_tree_uri)

func _install_plugin_from_android_tree_async(tree_uri: String) -> void:
	await _install_plugin_from_android_tree(tree_uri)

func _install_plugin_from_android_tree(tree_uri: String) -> Dictionary:
	var result: Dictionary = await _plugin_management_controller.install_plugin_from_android_tree(tree_uri)
	if result.is_empty():
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.install.title"),
			tr("music_app.plugin_management.install.local_failed").format(
				{
					"error": _plugin_management_controller.last_error if not _plugin_management_controller.last_error.is_empty() else tr("music_app.plugin_management.common.unknown_error")
				}
			)
		)
		return {}
	_plugin_management_controller.show_toast(tr("music_app.plugin_management.install.success"))
	_request_reload()
	return result

func _install_plugin_from_path(plugin_path: String) -> void:
	var normalized_plugin_path := plugin_path.strip_edges()
	if normalized_plugin_path.is_empty():
		return

	var result: Dictionary = await _plugin_management_controller.install_plugin_from_file(normalized_plugin_path)
	if result.is_empty():
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.install.title"),
			tr("music_app.plugin_management.install.local_failed").format(
				{
					"error": _plugin_management_controller.last_error if not _plugin_management_controller.last_error.is_empty() else tr("music_app.plugin_management.common.unknown_error")
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
	var ok: bool = await _plugin_management_controller.uninstall_plugin(plugin_id)
	if not ok:
		_plugin_management_controller.show_common_alert(
			tr("music_app.plugin_management.uninstall.title"),
			_plugin_management_controller.last_error if not _plugin_management_controller.last_error.is_empty() else tr("music_app.plugin_management.uninstall.failed")
		)
		return
	_plugin_management_controller.show_toast(tr("music_app.plugin_management.uninstall.success"))
	_request_reload()

func _on_plugin_source_redirect_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_source_redirect_placeholder()

func _on_plugin_import_playlist_requested(_plugin_id: String) -> void:
	_plugin_management_controller.show_import_playlist_placeholder()

func _on_plugin_file_picked(path: String) -> void:
	_install_plugin_from_path(path)
