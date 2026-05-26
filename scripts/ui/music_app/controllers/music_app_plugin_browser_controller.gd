class_name MusicAppPluginBrowserController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const MAX_SEARCH_HISTORY := 10

## 返回插件搜索历史。
func get_plugin_search_history() -> Array[String]:
	var result: Array[String] = []
	for item in get_app_state().plugin_search_history:
		result.append(item)
	return result

## 将搜索关键字写入历史，自动去重并限制数量。
func push_plugin_search_history(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return

	var next_history := get_plugin_search_history()
	next_history.erase(normalized_query)
	next_history.push_front(normalized_query)
	if next_history.size() > MAX_SEARCH_HISTORY:
		next_history.resize(MAX_SEARCH_HISTORY)
	get_app_state().plugin_search_history = next_history

## 删除单个搜索历史。
func remove_plugin_search_history(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return
	var next_history := get_plugin_search_history()
	next_history.erase(normalized_query)
	get_app_state().plugin_search_history = next_history

## 清空插件搜索历史。
func clear_plugin_search_history() -> void:
	if get_app_state().plugin_search_history.is_empty():
		return
	get_app_state().plugin_search_history = []

## 将搜索结果条目导入为全局曲目，并返回对应曲目索引。
func ensure_plugin_track_from_search_result(item: Dictionary, plugin_id: String) -> int:
	var track := _build_plugin_track(item, plugin_id)
	if track == null:
		return -1

	var tracks: Array[TrackData] = get_tracks_ref()
	var existing_index := _find_existing_plugin_track_index(track.platform, track.remote_id)
	if existing_index >= 0:
		_update_existing_plugin_track(tracks[existing_index], track)
		return existing_index

	tracks.append(track)
	return tracks.size() - 1

## 将一组搜索结果按当前顺序导入为全局曲目索引列表。
func ensure_plugin_tracks_from_search_results(items: Array[Dictionary], plugin_id: String) -> Array[int]:
	var result: Array[int] = []
	var seen_indices := {}
	for item in items:
		var track_index := ensure_plugin_track_from_search_result(item, plugin_id)
		if track_index < 0 or seen_indices.has(track_index):
			continue
		seen_indices[track_index] = true
		result.append(track_index)
	return result

## 按搜索页语义播放单曲：空队列播放全部结果，非空队列把当前单曲放到队首播放。
func play_search_result(
	items: Array[Dictionary],
	selected_result_index: int,
	plugin_id: String
) -> bool:
	if selected_result_index < 0 or selected_result_index >= items.size():
		push_warning("Search result index is out of range.")
		return false

	var playback_controller = get_playback_controller()
	if playback_controller == null:
		push_error("Playback controller is not available.")
		return false

	var selected_track_index := -1
	if playback_controller.has_playback_queue():
		selected_track_index = ensure_plugin_track_from_search_result(
			items[selected_result_index],
			plugin_id
		)
		if selected_track_index < 0:
			push_warning("Selected search result cannot be played.")
			return false
		if not playback_controller.play_track_at_queue_top(selected_track_index, true):
			push_error("Failed to add selected track to playback queue.")
			return false
		show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
		return true

	selected_track_index = ensure_plugin_track_from_search_result(items[selected_result_index], plugin_id)
	if selected_track_index < 0:
		push_warning("Selected search result cannot be played.")
		return false
	var track_indices := ensure_plugin_tracks_from_search_results(items, plugin_id)
	if track_indices.is_empty():
		push_warning("Search results do not contain playable tracks.")
		return false
	var start_queue_index := track_indices.find(selected_track_index)
	if start_queue_index < 0:
		start_queue_index = 0
	if not playback_controller.set_playback_queue(track_indices, start_queue_index):
		push_error("Failed to create playback queue from search results.")
		return false
	if not playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), true):
		push_error("Failed to start playback from search results.")
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true

## 刷新外部 GDScript 插件目录并重新加载插件列表。
func refresh_music_plugins() -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		push_error("Music plugin controller is not available.")
		return false
	var ok: bool = plugin_controller.refresh_plugins()
	if not ok and not plugin_controller.last_error.is_empty():
		push_error(plugin_controller.last_error)
	return ok

## 控制器进入后预热外部插件目录。
func auto_refresh_music_plugins() -> void:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return
	plugin_controller.refresh_plugins()

## 解析指定插件曲目的可播放音频源。
func resolve_track_plugin_source(track_index: int, quality: String = "standard") -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		push_warning("Track index is out of range.")
		return {}
	if track == null or not track.is_plugin_track():
		push_warning("Selected track is not a plugin track.")
		return {}

	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		push_error("Music plugin controller is not available.")
		return {}

	var result: Dictionary = await plugin_controller.get_media_source(track, quality)
	if result.is_empty() and not plugin_controller.last_error.is_empty():
		push_warning(plugin_controller.last_error)
	if not result.is_empty():
		track.apply_plugin_source(result)
	return result

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(track_index: int) -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		push_warning("Track index is out of range.")
		return {}
	if track == null or not track.is_plugin_track():
		push_warning("Selected track is not a plugin track.")
		return {}

	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		push_error("Music plugin controller is not available.")
		return {}

	var result: Dictionary = await plugin_controller.get_lyric(track)
	if result.is_empty() and not plugin_controller.last_error.is_empty():
		push_warning(plugin_controller.last_error)
	if not result.is_empty():
		track.apply_plugin_lyric(result)
	return result

func _build_plugin_track(item: Dictionary, plugin_id: String) -> TrackData:
	var normalized_plugin_id := plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		normalized_plugin_id = str(item.get("pluginId", item.get("plugin_id", ""))).strip_edges()
	if normalized_plugin_id.is_empty():
		normalized_plugin_id = str(item.get("platform", "")).strip_edges()

	var remote_id := _get_result_remote_id(item)
	if normalized_plugin_id.is_empty() or remote_id.is_empty():
		push_warning("Search result is missing plugin id or track id.")
		return null

	var track := TrackData.new()
	track.title = _get_result_text(item, ["title", "name"], "Untitled")
	track.artist = _get_result_text(item, ["artist", "author", "singer"], "")
	track.subtitle = _get_result_text(item, ["album", "subtitle"], "")
	track.platform = normalized_plugin_id
	track.remote_id = remote_id
	track.stream_url = _get_result_text(item, ["url", "stream_url"], "")
	track.artwork_url = _get_result_text(item, ["artwork", "cover", "coverImg", "image"], "")
	track.duration = _get_result_duration(item)
	track.source = "PLUGIN"
	track.mark = track.title.left(1) if not track.title.is_empty() else ""
	track.plugin_payload = item.duplicate(true)
	track.normalize()
	return track

func _find_existing_plugin_track_index(plugin_id: String, remote_id: String) -> int:
	var tracks: Array[TrackData] = get_tracks_ref()
	for index in tracks.size():
		var track := tracks[index]
		if track == null:
			continue
		if track.platform == plugin_id and track.remote_id == remote_id:
			return index
	return -1

func _update_existing_plugin_track(target: TrackData, source: TrackData) -> void:
	if target == null or source == null:
		return
	target.title = source.title
	target.artist = source.artist
	target.subtitle = source.subtitle
	target.stream_url = source.stream_url
	target.artwork_url = source.artwork_url
	target.duration = source.duration
	target.mark = source.mark
	target.source = source.source
	target.plugin_payload = source.plugin_payload.duplicate(true)
	target.normalize()

func _get_result_remote_id(item: Dictionary) -> String:
	for key in ["id", "mid", "song_id", "media_id", "bvid", "aid", "url"]:
		var value := str(item.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

func _get_result_text(item: Dictionary, keys: Array[String], fallback: String) -> String:
	for key in keys:
		var value := str(item.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return fallback

func _get_result_duration(item: Dictionary) -> int:
	var value = item.get("duration", 1)
	if value is int:
		return maxi(1, int(value))
	if value is float:
		return maxi(1, int(value))
	var text := str(value).strip_edges()
	if text.is_empty():
		return 1
	if text.is_valid_int():
		return maxi(1, int(text))

	var total := 0
	for part in text.split(":"):
		total = total * 60 + (int(part) if str(part).is_valid_int() else 0)
	return maxi(1, total)

## 根据全量曲目索引返回曲目对象。
func _get_track(track_index: int) -> TrackData:
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]
