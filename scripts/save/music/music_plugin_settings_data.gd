class_name MusicPluginSettingsData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

var disabled_plugin_ids: Array[String] = []

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
