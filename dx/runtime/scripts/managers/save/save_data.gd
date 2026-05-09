extends "res://dx/runtime/scripts/serializer/json_object.gd"
const MUSIC_APP_STATE_DATA_SCRIPT := preload("res://scripts/save/music/music_app_state_data.gd")
const MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT := preload("res://scripts/save/music/music_plugin_settings_data.gd")

var music = MUSIC_APP_STATE_DATA_SCRIPT.new()
var music_plugins = MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT.new()

func normalize() -> void:
	if music == null:
		music = MUSIC_APP_STATE_DATA_SCRIPT.new()
	music.normalize()
	if music_plugins == null:
		music_plugins = MUSIC_PLUGIN_SETTINGS_DATA_SCRIPT.new()
	music_plugins.normalize()
