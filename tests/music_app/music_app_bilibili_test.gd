extends Node

const Bilibili := preload("res://plugins/builtin/bilibili.gd")
const Serializer := preload("res://dx/runtime/scripts/serializer/json_serializer.gd")
const Decoder := preload("res://scripts/audio/music_app_m4a_decoder.gd")
const ItemScene := preload("res://scenes/ui/music_app/settings/music_app_plugin_management_item.tscn")
const BrowserView := preload("res://scripts/ui/music_app/views/plugin_browser/music_app_plugin_browser_view.gd")
var failures: Array[String] = []

class FakeHTTP extends RefCounted:
	var last_error := ""
	var responses: Array = []
	var calls: Array[Dictionary] = []
	func get_json(url: String, query: Dictionary = {}, headers: Dictionary = {}) -> Variant:
		calls.append({"url": url, "query": query, "headers": headers})
		return responses.pop_front() if not responses.is_empty() else null

class Plugins extends MusicAppPluginController:
	var settings := MusicPluginSettingsData.new()
	func get_settings() -> MusicPluginSettingsData:
		return settings

class Host extends Node:
	var state := MusicAppStateData.new()
	var _plugin_controller: MusicAppPluginController
	var _playback_controller: MusicAppPlaybackController
	var _playback_state_controller = null
	var _popup_router_controller = null

class Browser extends MusicAppPluginBrowserController:
	func get_app_state() -> MusicAppStateData:
		return controller.state

class Playback extends MusicAppPlaybackController:
	func get_app_state() -> MusicAppStateData:
		return controller.state

class Audio extends MusicAppPlaybackStateController:
	var received: Dictionary = {}
	func _load_remote_stream(url: String, headers: Dictionary, request_id: int, format_hint: String = "") -> AudioStream:
		received = {"url": url, "headers": headers, "format": format_hint, "request_id": request_id}
		return AudioStreamWAV.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Host.new()
	add_child(host)
	var plugins := Plugins.new(host)
	host._plugin_controller = plugins
	host._playback_controller = Playback.new(host)
	_check(plugins.refresh_plugins(), "Bundled plugin loads on a fresh installation")
	var entries := plugins.list_plugins().filter(func(item): return item.id == "bilibili")
	_check(entries.size() == 1, "Bilibili registered once")
	if entries.is_empty():
		_finish()
		return
	_check(entries[0].builtin and entries[0].enabled, "Bundled and enabled metadata")
	var browser_view := BrowserView.new()
	_check(browser_view._plugin_key(entries[0]) == "bilibili", "Display name is never used as the saved plugin ID")
	browser_view.free()
	var row = ItemScene.instantiate()
	add_child(row)
	row.configure(entries[0], true)
	_check(not row.uninstall_button.visible and not row.update_button.visible, "No uninstall/update for bundled plugin")
	_check(not plugins.uninstall_plugin("bilibili"), "Bundled uninstall is rejected")
	plugins.set_plugin_enabled("bilibili", false)
	plugins.refresh_plugins()
	_check(not plugins.is_plugin_enabled("bilibili"), "Disabled state survives refresh")
	_check((await plugins.search("bilibili", "test")).is_empty(), "Disabled plugins cannot search")
	_check((await plugins.search("Bilibili", "test")).is_empty(), "Display-name aliases cannot bypass disabled state")
	plugins.set_plugin_enabled("bilibili", true)
	var plugin = plugins._plugins.bilibili.plugin
	var http := FakeHTTP.new()
	plugin._http = http
	http.responses = [
		{"code": 0, "data": {"b_3": "guest3", "b_4": "guest4"}},
		{"code": 0, "data": {"numResults": 1, "result": [{"bvid": "BVfixture", "aid": 42, "cid": 123, "title": "<em class=\"keyword\">测试</em>&amp;音乐", "author": "作者", "duration": "3:05", "pic": "//example.invalid/cover.jpg"}]}}
	]
	var result: Dictionary = await plugins.search("bilibili", "测试")
	var items: Array[Dictionary] = []
	items.assign(result.get("data", []))
	_check(items.size() == 1, "Search result reaches host")
	if items.is_empty():
		_finish()
		return
	_check(items[0].title == "测试&音乐" and items[0].duration == 185, "Title/duration mapping")
	_check(items[0].artwork.begins_with("https://") and items[0].cid == 123, "HTTPS artwork and part identifier")
	_check(plugin._looks_like_collection_title("【周杰伦】50首精选合集/后台播放"), "Multi-song video is detected as a collection")
	_check(not plugin._looks_like_collection_title("周杰伦 - 七里香"), "Ordinary song is kept as music")
	_check(http.calls[1].headers.cookie == "buvid3=guest3;buvid4=guest4", "Anonymous cookies forwarded")
	var browser := Browser.new(host)
	_check(browser.play_search_result(items, 0, "bilibili"), "Search result starts queue")
	var track: TrackData = host.state.tracks[0]
	_check(host.state.playback_state.is_playing and host.state.playback_state.track_ids == [track.id], "Queue starts selected result")
	_check(browser.ensure_plugin_track_from_search_result(items[0], "bilibili") == 0 and host.state.tracks.size() == 1, "Repeated imports deduplicate")
	var second := items[0].duplicate(true)
	second.id = "other"
	_check(browser.play_search_result([second], 0, "bilibili"), "Nonempty queue accepts selected result")
	_check(host.state.playback_state.track_ids.size() == 2 and host.state.playback_state.track_ids[1] == track.id, "Existing queue preserved below selected result")
	var restored := MusicAppStateData.new()
	Serializer.deserialize(JSON.parse_string(JSON.stringify(Serializer.serialize(host.state))), restored)
	restored.normalize()
	var saved: TrackData = restored.get_track_by_id(track.id)
	_check(saved != null and saved.plugin_id == "bilibili" and saved.plugin_data.bvid == "BVfixture" and saved.plugin_data.cid == 123, "Plugin metadata survives full JSON save/load")
	http.responses = [{"code": 0, "data": {"dash": {"audio": [{"bandwidth": 1, "base_url": "https://cdn.invalid/low.m4s"}, {"bandwidth": 2, "baseUrl": "https://cdn.invalid/high.m4s"}]}}}]
	var audio := Audio.new(host)
	var stream: AudioStream = await audio._resolve_stream_for_track(saved, 0)
	_check(stream != null and audio.received.url == "https://cdn.invalid/high.m4s" and audio.received.format == "m4a", "Playback resolves audio rather than trying a local path")
	_check(audio.received.headers.referer == "https://www.bilibili.com/video/BVfixture" and not audio.received.headers.has("host"), "Referer preserved without broken Host override")
	_check(http.calls.back().query.cid is int and http.calls.back().query.cid == 123, "JSON float CID is sent as an integer to playurl")
	var no_cid := TrackData.new()
	no_cid.plugin_id = "bilibili"
	no_cid.plugin_data = {"aid": 42.0}
	http.responses = [
		{"code": 0, "data": {"cid": 987654321.0}},
		{"code": 0, "data": {"dash": {"audio": [{"bandwidth": 1, "baseUrl": "https://cdn.invalid/audio.m4s"}]}}}
	]
	_check(not (await plugins.get_media_source(no_cid)).is_empty(), "Missing CID is fetched before playurl")
	_check(http.calls[-2].query.aid is int and http.calls[-1].query.cid is int, "View and playurl use integer IDs for saved JSON numbers")
	http.responses = [{"code": -101, "data": {"wbi_img": {
		"img_url": "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png",
		"sub_url": "https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"
	}}}]
	var signature: String = await plugin._get_rid({"foo": "114", "bar": "514", "baz": "1919810", "wts": "1702204169"})
	# Expected digest independently calculated with Python hashlib from the fixture keys.
	_check(signature == "6149fdadf571698ca7e6a567265cd0ee", "Anonymous WBI signing matches fixed digest")
	_check((await plugins.get_lyric(saved)).is_empty() and plugins.last_error.is_empty(), "Unsupported lyrics return empty gracefully")
	http.responses = [null]
	_check((await plugins.search("bilibili", "offline")).is_empty() and not plugins.last_error.is_empty(), "Network failure is surfaced")
	http.responses = [{"code": -412, "message": "请求被拦截", "data": null}]
	_check((await plugins.get_media_source(saved)).is_empty() and plugins.last_error.contains("-412"), "API rejection is surfaced")
	http.responses = [{"code": 0, "data": null}]
	_check((await plugins.get_media_source(saved)).is_empty() and not plugins.last_error.is_empty(), "Null data cannot crash playback")
	plugins.set_plugin_enabled("bilibili", false)
	_check((await plugins.get_media_source(saved)).is_empty(), "Disabled plugins cannot resolve saved tracks")
	var decoder := Decoder.new()
	if not decoder._find_converter().is_empty():
		var bytes := FileAccess.get_file_as_bytes("res://tests/music_app/fixtures/tone.m4a")
		var decoded: AudioStream = await decoder.decode(bytes, func(): return false)
		_check(decoded != null and decoded.get_length() >= 0.09, "Real M4A fixture converts to playable PCM")
		_check((await decoder.decode(bytes, func(): return true)) == null, "Cancelled playback skips conversion")
	else:
		print("M4A conversion test skipped: no converter on this platform")
	row.queue_free()
	host.queue_free()
	_finish()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("Bilibili integration tests: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
