extends Node

const PluginScript = preload("res://gdmusic_plugin_codegen/godot/plugins/gdmusic_bilibili_plugin.gd")

var _failures: Array[String] = []
var _checks: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var plugin = PluginScript.new()

	print("platform=", plugin.get_platform())
	print("version=", plugin.get_version())
	_expect(plugin.get_platform() == "bilibili", "platform should be bilibili")
	_expect(not plugin.get_version().is_empty(), "version should not be empty")

	var search_result = await plugin.search("周杰伦", 1, "music")
	print("search_ok=", search_result is Dictionary)
	print("search_count=", (search_result.get("data", []) as Array).size())
	_expect(search_result is Dictionary, "search(music) should return Dictionary")
	if search_result is Dictionary:
		_expect(search_result.has("data"), "search(music) result should contain data")
		_expect(search_result.has("isEnd"), "search(music) result should contain isEnd")

	var artist_result = await plugin.search("zhoujielun", 1, "artist")
	print("artist_count=", (artist_result.get("data", []) as Array).size())
	_expect(artist_result is Dictionary, "search(artist) should return Dictionary")

	if (search_result.get("data", []) as Array).size() > 0:
		var first_song: Dictionary = search_result["data"][0]
		var album_info = await plugin.get_album_info(first_song, 1)
		print("album_music_count=", (album_info.get("musicList", []) as Array).size())
		_expect(album_info is Dictionary, "get_album_info should return Dictionary")
		if album_info is Dictionary:
			_expect(album_info.has("musicList"), "get_album_info should contain musicList")

		var media_source = await plugin.get_media_source(first_song, "standard")
		print("media_source_url=", str(media_source.get("url", "")))
		_expect(media_source is Dictionary, "get_media_source should return Dictionary")
		if media_source is Dictionary:
			_expect(media_source.has("url"), "get_media_source should contain url")
	else:
		push_warning("No music search result returned. album/media source checks were skipped.")

	_finish()

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] ", description)
		return
	_failures.append(description)
	push_warning("[FAIL] %s" % description)

func _finish() -> void:
	if _failures.is_empty():
		print("[TEST PASS] bilibili plugin checks passed: ", _checks)
		get_tree().quit(0)
		return

	print("[TEST FAIL] bilibili plugin failed checks: ", _failures.size(), "/", _checks)
	for failure in _failures:
		print(" - ", failure)
	get_tree().quit(1)
