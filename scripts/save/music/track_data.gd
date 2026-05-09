class_name TrackData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const DEFAULT_ACCENT := Color(0.309804, 0.388235, 0.490196, 1.0)
const DEFAULT_SECONDARY := Color(0.737255, 0.631373, 0.509804, 1.0)
const DEFAULT_TERTIARY := Color(0.176471, 0.192157, 0.223529, 1.0)

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
var duration: int = 1
var preview_start: int = 0
var mark: String = ""
var source: String = ""
var accent: Color = DEFAULT_ACCENT
var secondary: Color = DEFAULT_SECONDARY
var tertiary: Color = DEFAULT_TERTIARY

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

func is_plugin_track() -> bool:
	return not platform.is_empty() and not remote_id.is_empty()

func to_plugin_media_item() -> Dictionary:
	var item := {
		"id": remote_id,
		"platform": platform,
		"title": title,
		"artist": artist,
		"album": subtitle,
		"duration": duration,
		"url": stream_url,
		"artwork": artwork_url,
		"qualities": qualities
	}
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

func _get_save_ignored_fields() -> PackedStringArray:
	return PackedStringArray(["accent", "secondary", "tertiary"])
