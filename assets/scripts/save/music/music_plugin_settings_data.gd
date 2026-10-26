class_name MusicPluginSettingsData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

var disabled_plugin_ids: Array[String] = []
var android_tree_plugins: Array[Dictionary] = []
# 插件登录态 cookie：plugin_id -> "k=v; k=v"。属于账号凭据，只落本地存档，不打日志。
var plugin_cookies: Dictionary = {}

func normalize() -> void:
	var normalized_disabled_plugin_ids: Array[String] = []
	for plugin_id in disabled_plugin_ids:
		var normalized_plugin_id := str(plugin_id).strip_edges()
		if normalized_plugin_id.is_empty():
			continue
		if normalized_disabled_plugin_ids.has(normalized_plugin_id):
			continue
		normalized_disabled_plugin_ids.append(normalized_plugin_id)
	disabled_plugin_ids = normalized_disabled_plugin_ids

	var normalized_android_tree_plugins: Array[Dictionary] = []
	var seen_android_tree_plugin_ids: Dictionary = {}
	for item in android_tree_plugins:
		if not (item is Dictionary):
			continue
		var plugin_id := str(item.get("plugin_id", "")).strip_edges()
		var tree_uri := str(item.get("tree_uri", "")).strip_edges()
		var relative_path := str(item.get("relative_path", "")).strip_edges()
		if plugin_id.is_empty() or tree_uri.is_empty() or relative_path.is_empty():
			continue
		if seen_android_tree_plugin_ids.has(plugin_id):
			continue
		seen_android_tree_plugin_ids[plugin_id] = true
		normalized_android_tree_plugins.append(
			{
				"plugin_id": plugin_id,
				"tree_uri": tree_uri,
				"relative_path": relative_path
			}
		)
	android_tree_plugins = normalized_android_tree_plugins

	var normalized_plugin_cookies: Dictionary = {}
	if plugin_cookies is Dictionary:
		for key in plugin_cookies.keys():
			var cookie_plugin_id := str(key).strip_edges()
			var cookie_header := str(plugin_cookies.get(key, "")).strip_edges()
			if cookie_header.begins_with("Cookie:"):
				cookie_header = cookie_header.substr(7).strip_edges()
			if cookie_plugin_id.is_empty() or cookie_header.is_empty():
				continue
			normalized_plugin_cookies[cookie_plugin_id] = cookie_header
	plugin_cookies = normalized_plugin_cookies
