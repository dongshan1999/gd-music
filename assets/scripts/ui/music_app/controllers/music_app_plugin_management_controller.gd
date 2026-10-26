class_name MusicAppPluginManagementController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

var last_error := ""

func ensure_plugins_ready() -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = plugin_controller.refresh_plugins()
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
	var result: Dictionary = plugin_controller.install_plugin_from_file(plugin_path)
	last_error = plugin_controller.last_error
	return result

func install_plugin_from_android_tree(tree_uri: String) -> Dictionary:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return {}
	var result: Dictionary = plugin_controller.install_plugin_from_android_tree(tree_uri)
	last_error = plugin_controller.last_error
	return result

func install_plugin_from_url(plugin_url: String) -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = plugin_controller.install_plugin_from_url(plugin_url)
	last_error = plugin_controller.last_error
	return ok

func uninstall_plugin(plugin_id: String) -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok: bool = plugin_controller.uninstall_plugin(plugin_id)
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

## 插件列表要显示登录态，这里转发到全局插件控制器。
func get_cached_login_state(plugin_id: String) -> Dictionary:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return {}
	return plugin_controller.get_cached_login_state(plugin_id)

func refresh_login_state(plugin_id: String) -> Dictionary:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return {}
	return await plugin_controller.refresh_login_state(plugin_id)

func show_install_placeholder() -> void:
	show_toast("请从本地文件或网络地址安装插件。")

func show_update_placeholder() -> void:
	show_toast("当前未接入插件更新接口。")
