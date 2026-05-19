class_name GDMusicPluginBase
extends RefCounted

var _runtime_user_variables: Dictionary = {}

func get_platform() -> String:
	return ""

func get_author() -> String:
	return ""

func get_description() -> String:
	return ""

func get_version() -> String:
	return ""

func get_src_url() -> String:
	return ""

func get_default_search_type() -> String:
	return "music"

func get_supported_search_types() -> PackedStringArray:
	return PackedStringArray()

func get_user_variables() -> Array[Dictionary]:
	return []

func set_runtime_user_variables(values: Dictionary) -> void:
	_runtime_user_variables = values.duplicate(true)

func get_runtime_user_variables() -> Dictionary:
	return _runtime_user_variables.duplicate(true)

func get_runtime_user_variable(key: String, default_value: Variant = null) -> Variant:
	return _runtime_user_variables.get(key, default_value)

func supports_method(method_name: String) -> bool:
	return method_name in get_supported_methods()

func get_supported_methods() -> PackedStringArray:
	return PackedStringArray()

func get_js_dependencies() -> PackedStringArray:
	return PackedStringArray()

func get_migration_capabilities() -> PackedStringArray:
	return PackedStringArray()

func get_migration_difficulty() -> String:
	return "unknown"

func get_migration_notes() -> PackedStringArray:
	return PackedStringArray()
