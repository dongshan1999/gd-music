class_name TrackData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

var id: String = ""
var title: String = ""
var artist: String = ""
var subtitle: String = ""
var file_path: String = ""
var lyric_path: String = ""
var duration: int = 1
var preview_start: int = 0
var mark: String = ""
var source: String = ""
var plugin_id: String = ""
var plugin_data: Dictionary = {}

func normalize() -> void:
	id = id.strip_edges()
	title = title.strip_edges()
	artist = artist.strip_edges()
	subtitle = subtitle.strip_edges()
	file_path = file_path.strip_edges()
	lyric_path = lyric_path.strip_edges()
	if id.is_empty():
		id = make_local_id(file_path) if not file_path.is_empty() else make_generated_id()
	duration = maxi(1, duration)
	preview_start = clampi(maxi(0, preview_start), 0, duration)
	mark = mark.strip_edges()
	source = source.strip_edges()
	plugin_id = plugin_id.strip_edges()

static func make_local_id(path: String) -> String:
	var normalized_path := path.strip_edges().replace("\\", "/")
	if normalized_path.is_empty():
		return ""
	return "local:%s" % normalized_path.sha256_text()

static func make_generated_id() -> String:
	return "track:%d:%d:%d" % [
		Time.get_unix_time_from_system(),
		Time.get_ticks_usec(),
		randi()
	]
