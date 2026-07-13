class_name DX_ConfigManager
extends RefCounted

const ConfigDataScript := preload("res://dx/runtime/scripts/managers/config/config_data.gd")
const DEFAULT_CONFIG_PATH := "res://dx/data/config.json"

var dx: Node
var data = ConfigDataScript.new()

func in_ready() -> void:
	self.load()

func load(config_path: String = DEFAULT_CONFIG_PATH):
	var next_data = ConfigDataScript.new()
	var raw_json := _load_config_json(config_path)
	if not raw_json.is_empty():
		DX_JsonSerializer.deserialize(raw_json, next_data)
	data = next_data
	_normalize_object(data)
	return data

func _load_config_json(config_path: String) -> String:
	if not FileAccess.file_exists(config_path):
		return ""

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

func _normalize_object(object: Variant) -> void:
	if object != null and object.has_method("normalize"):
		object.call("normalize")
