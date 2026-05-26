extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "全民K歌"
const AUTHOR := "猫头猫"
const VERSION := "0.1.1"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/qmkg/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES: Array[String] = []
const SUPPORTED_METHODS := [
	"get_media_source",
	"getMediaSource",
	"import_music_item",
	"importMusicItem",
]

var _http := GDMusicHttpJsonClient.new()

func get_platform() -> String:
	return PLATFORM

func get_author() -> String:
	return AUTHOR

func get_version() -> String:
	return VERSION

func get_src_url() -> String:
	return SRC_URL

func get_default_search_type() -> String:
	return DEFAULT_SEARCH_TYPE

func get_supported_search_types() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_SEARCH_TYPES)

func get_supported_methods() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_METHODS)

func get_migration_difficulty() -> String:
	return "medium"

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if music_item.has("shareid") and not str(music_item.get("shareid", "")).is_empty():
		var refreshed = await _parse_music_item_from_url("https://kg.qq.com/node/play?s=%s" % str(music_item.get("shareid", "")))
		var refreshed_url = str(refreshed.get("url", ""))
		return {"url": refreshed_url} if not refreshed_url.is_empty() else {}
	var url = str(music_item.get("url", ""))
	return {"url": url} if not url.is_empty() else {}

func import_music_item(url_like: String) -> Dictionary:
	return await _parse_music_item_from_url(url_like)

func _parse_music_item_from_url(share_url: String) -> Dictionary:
	var html = await _http.get_text(share_url)
	if html.is_empty():
		return {}
	var data_text = GDMusicTextUtils.extract_first_match(html, "window\\.__DATA__\\s*=\\s*(\\{[\\s\\S]*?\\});")
	if data_text.is_empty():
		return {}
	var result = JSON.parse_string(data_text)
	if not (result is Dictionary):
		return {}
	var source: Dictionary = result
	var detail: Dictionary = source.get("detail", {})
	return {
		"id": detail.get("ksong_mid", ""),
		"shareid": source.get("shareid", ""),
		"lrc": str(source.get("lyric", "")),
		"artwork": str(detail.get("cover", "")),
		"title": str(detail.get("song_name", "")),
		"artist": "%s (原唱: %s)" % [str(detail.get("nick", "")), str(detail.get("singer_name", ""))],
		"album": str(detail.get("content", "")),
		"url": str(detail.get("playurl", "")),
		"detail": detail,
		"platform": PLATFORM,
	}
