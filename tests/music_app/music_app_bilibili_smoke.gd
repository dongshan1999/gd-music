extends Node

const Plugins := preload("res://scripts/ui/music_app/controllers/global/music_app_plugin_controller.gd")
const Audio := preload("res://scripts/ui/music_app/controllers/global/music_app_audio_controller.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var plugins := Plugins.new()
	if not plugins.refresh_plugins():
		_end("Plugin load failed: " + plugins.last_error, 1)
		return
	var result: Dictionary = await plugins.search("bilibili", "钢琴", 1)
	if result.is_empty() or result.get("data", []).is_empty():
		_end("Live search failed: " + plugins.last_error, 1)
		return
	print("Live search returned %d results" % result.data.size())
	var item: Dictionary = result.data[0]
	for candidate in result.data:
		if int(candidate.get("duration", 0)) > 0 and int(candidate.get("duration", 0)) < int(item.get("duration", 0)):
			item = candidate
	var track := TrackData.new()
	track.plugin_id = "bilibili"
	track.plugin_data = item
	var source: Dictionary = await plugins.get_media_source(track)
	if source.is_empty():
		_end("Live source resolution failed: " + plugins.last_error, 1)
		return
	print("Live source resolved; checking downloaded audio (%s seconds)" % item.duration)
	var audio := Audio.new(self)
	var stream: AudioStream = await audio._load_remote_stream(source.url, source.headers, 0, source.get("format", ""))
	if stream == null:
		_end("Live audio decode failed: " + audio.last_error, 1)
		return
	_end("Live Bilibili search/source/download/decode passed: %.2fs" % stream.get_length(), 0)

func _end(message: String, code: int) -> void:
	print(message)
	get_tree().quit(code)
