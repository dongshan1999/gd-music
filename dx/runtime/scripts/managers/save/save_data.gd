class_name DX_SaveData
extends DX_JsonObject
const MUSIC_APP_STATE_DATA_SCRIPT := preload("res://scripts/save/music/music_app_state_data.gd")
const MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT := preload("res://scripts/save/music/music_plugin_settings_data.gd")

var music = MUSIC_APP_STATE_DATA_SCRIPT.new()
var music_plugins = MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT.new()

func sanitize_payload(payload: Variant) -> Variant:
	if not payload is Dictionary:
		return payload

	var result: Dictionary = payload.duplicate(true)
	var music_payload: Variant = result.get("music", null)
	if music_payload is Dictionary:
		var payload_version: Variant = (music_payload as Dictionary).get("version", "")
		if not (payload_version is String) or str(payload_version) != MUSIC_APP_STATE_DATA_SCRIPT.SAVE_VERSION:
			result.erase("music")
	return result

func normalize() -> void:
	if music == null:
		music = MUSIC_APP_STATE_DATA_SCRIPT.new()
	music.normalize()
	if music_plugins == null:
		music_plugins = MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT.new()
	music_plugins.normalize()
