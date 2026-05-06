class_name TrackData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const DEFAULT_ACCENT := Color(0.309804, 0.388235, 0.490196, 1.0)
const DEFAULT_SECONDARY := Color(0.737255, 0.631373, 0.509804, 1.0)
const DEFAULT_TERTIARY := Color(0.176471, 0.192157, 0.223529, 1.0)

var title: String = ""
var artist: String = ""
var subtitle: String = ""
var file_path: String = ""
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

func _get_save_ignored_fields() -> PackedStringArray:
	return PackedStringArray(["accent", "secondary", "tertiary"])
