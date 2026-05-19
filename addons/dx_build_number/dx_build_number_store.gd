class_name DXBuildNumberStore
extends RefCounted

const STORAGE_PATH := "user://dx_build_numbers.cfg"

const SECTION_BUILD_NUMBERS := "build_numbers"

const PLATFORM_WINDOWS := "windows"
const PLATFORM_ANDROID := "android"

func read_build_number(platform_name: String) -> int:
	var platform_key := normalize_platform_name(platform_name)
	if platform_key.is_empty():
		return 0
	var config := _load_config()
	return maxi(0, int(config.get_value(SECTION_BUILD_NUMBERS, platform_key, 0)))

func get_next_build_number(platform_name: String) -> int:
	return read_build_number(platform_name) + 1

func increment_build_number(platform_name: String) -> int:
	var platform_key := normalize_platform_name(platform_name)
	if platform_key.is_empty():
		return 0

	var config := _load_config()
	var next_build_number := maxi(0, int(config.get_value(SECTION_BUILD_NUMBERS, platform_key, 0))) + 1
	config.set_value(SECTION_BUILD_NUMBERS, platform_key, next_build_number)
	_save_config(config)
	return next_build_number

func set_build_number(platform_name: String, build_number: int) -> void:
	var platform_key := normalize_platform_name(platform_name)
	if platform_key.is_empty():
		return

	var config := _load_config()
	config.set_value(SECTION_BUILD_NUMBERS, platform_key, maxi(0, build_number))
	_save_config(config)

static func normalize_platform_name(platform_name: String) -> String:
	var normalized_name := platform_name.strip_edges().to_lower()
	if normalized_name.contains("windows"):
		return PLATFORM_WINDOWS
	if normalized_name.contains("android"):
		return PLATFORM_ANDROID
	return ""

func _load_config() -> ConfigFile:
	var config := ConfigFile.new()
	var load_error := config.load(STORAGE_PATH)
	if load_error != OK:
		_apply_defaults(config)
		_save_config(config)
	else:
		_ensure_defaults(config)
	return config

func _save_config(config: ConfigFile) -> void:
	var save_error := config.save(STORAGE_PATH)
	if save_error != OK:
		push_warning("Failed to save build number config: %s" % STORAGE_PATH)

func _ensure_defaults(config: ConfigFile) -> void:
	var changed := false

	for platform_key in [PLATFORM_WINDOWS, PLATFORM_ANDROID]:
		if not config.has_section_key(SECTION_BUILD_NUMBERS, platform_key):
			config.set_value(SECTION_BUILD_NUMBERS, platform_key, 0)
			changed = true

	if changed:
		_save_config(config)

func _apply_defaults(config: ConfigFile) -> void:
	config.set_value(SECTION_BUILD_NUMBERS, PLATFORM_WINDOWS, 0)
	config.set_value(SECTION_BUILD_NUMBERS, PLATFORM_ANDROID, 0)
