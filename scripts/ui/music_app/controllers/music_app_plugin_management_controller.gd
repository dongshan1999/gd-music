class_name MusicAppPluginManagementController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

var last_error := ""

func ensure_plugins_ready() -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = await plugin_controller.refresh_plugins()
	last_error = plugin_controller.last_error
	return ok

func list_plugins() -> Array[Dictionary]:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return []
	last_error = ""
	return plugin_controller.list_plugins()

func install_plugin_from_file(plugin_path: String) -> Dictionary:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return {}
	var result: Dictionary = await plugin_controller.install_plugin_from_file(plugin_path)
	last_error = plugin_controller.last_error
	return result

func install_plugin_from_url(plugin_url: String) -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = await plugin_controller.install_plugin_from_url(plugin_url)
	last_error = plugin_controller.last_error
	return ok

func uninstall_plugin(plugin_id: String) -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = await plugin_controller.uninstall_plugin(plugin_id)
	last_error = plugin_controller.last_error
	return ok

func is_plugin_enabled(plugin_id: String) -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return false
	return plugin_controller.is_plugin_enabled(plugin_id)

func set_plugin_enabled(plugin_id: String, enabled: bool) -> void:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return
	plugin_controller.set_plugin_enabled(plugin_id, enabled)

func show_install_placeholder() -> void:
	show_toast("请从本地文件或网络地址安装插件。")

func show_update_placeholder() -> void:
	show_toast("当前未接入插件更新接口。")

func show_share_placeholder() -> void:
	show_toast("当前未接入插件分享接口。")

func show_source_redirect_placeholder() -> void:
	show_toast("当前未接入音源重定向接口。")

func show_import_playlist_placeholder() -> void:
	show_toast("当前未接入导入歌单接口。")
