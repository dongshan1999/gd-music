class_name TrackData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

var title: String = ""
var artist: String = ""
var subtitle: String = ""
var file_path: String = ""
var platform: String = ""
var remote_id: String = ""
var stream_url: String = ""
var artwork_url: String = ""
var lyric_text: String = ""
var lyric_translation: String = ""
var stream_headers: Dictionary = {}
var qualities: Dictionary = {}
var plugin_payload: Dictionary = {}
var duration: int = 1
var preview_start: int = 0
var mark: String = ""
var source: String = ""

func normalize() -> void:
	duration = maxi(1, duration)
	preview_start = clampi(maxi(0, preview_start), 0, duration)
	platform = platform.strip_edges()
	remote_id = remote_id.strip_edges()
	stream_url = stream_url.strip_edges()
	artwork_url = artwork_url.strip_edges()
	lyric_text = str(lyric_text)
	lyric_translation = str(lyric_translation)
	stream_headers = _normalize_dictionary(stream_headers)
	qualities = _normalize_dictionary(qualities)
	plugin_payload = _normalize_dictionary(plugin_payload)

func is_plugin_track() -> bool:
	return not platform.is_empty() and not remote_id.is_empty()

func to_plugin_media_item() -> Dictionary:
	var item := plugin_payload.duplicate(true)
	if not item.has("id") or str(item.get("id", "")).strip_edges().is_empty():
		item["id"] = remote_id
	var payload_platform := str(item.get("platform", "")).strip_edges()
	if payload_platform.is_empty() or payload_platform == platform:
		item["platform"] = platform
	item["pluginId"] = platform
	item.merge({
		"id": remote_id,
		"title": title,
		"artist": artist,
		"album": subtitle,
		"duration": duration,
		"url": stream_url,
		"artwork": artwork_url,
		"qualities": qualities
	}, true)
	if not lyric_text.is_empty():
		item["rawLrc"] = lyric_text
	return item

func apply_plugin_source(source_data: Dictionary) -> void:
	stream_url = str(source_data.get("url", stream_url)).strip_edges()
	stream_headers = _normalize_dictionary(source_data.get("headers", stream_headers))

func apply_plugin_lyric(lyric_data: Dictionary) -> void:
	lyric_text = str(lyric_data.get("rawLrc", lyric_text))
	lyric_translation = str(lyric_data.get("translation", lyric_translation))

func _normalize_dictionary(value: Variant) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value.keys():
			result[str(key)] = value[key]
	return result
