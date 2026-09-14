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
	var media_id := str(item.get("id", "")).strip_edges()
	if media_id.is_empty() or plugin_id.strip_edges().is_empty():
		return -1
	var track_id := "plugin:%s:%s" % [plugin_id.uri_encode(), media_id.uri_encode()]
	var tracks := get_tracks_ref()
	for index in tracks.size():
		if tracks[index].id == track_id:
			return index
	var track := TrackData.new()
	track.id = track_id
	track.title = str(item.get("title", item.get("name", "")))
	track.artist = str(item.get("artist", ""))
	track.subtitle = str(item.get("album", ""))
	track.source = plugin_id
	track.plugin_id = plugin_id
	track.plugin_data = item.duplicate(true)
	track.duration = int(item.get("duration", 0))
	track.normalize()
	tracks.append(track)
	return tracks.size() - 1

## 将一组搜索结果按当前顺序导入为全局曲目索引列表。
func ensure_plugin_tracks_from_search_results(items: Array[Dictionary], plugin_id: String) -> Array[int]:
	var indices: Array[int] = []
	for item in items:
		var index := ensure_plugin_track_from_search_result(item, plugin_id)
		if index >= 0:
			indices.append(index)
	return indices

## 按搜索页语义播放单曲：空队列播放全部结果，非空队列把当前单曲放到队首播放。
func play_search_result(
	items: Array[Dictionary],
	selected_result_index: int,
	plugin_id: String
) -> bool:
	if selected_result_index < 0 or selected_result_index >= items.size():
		return false
	var plugins = get_plugin_controller()
	if plugins == null or not plugins.is_plugin_enabled(plugin_id):
		return false
	var playback = get_playback_controller()
	if playback == null:
		return false
	var selected_index := ensure_plugin_track_from_search_result(items[selected_result_index], plugin_id)
	if selected_index < 0:
		return false
	var selected_id := get_tracks_ref()[selected_index].id
	if playback.has_playback_queue():
		return playback.play_track_at_queue_top(selected_id)
	var ids: Array[String] = []
	for index in ensure_plugin_tracks_from_search_results(items, plugin_id):
		var id := get_tracks_ref()[index].id
		if not ids.has(id):
			ids.append(id)
	var queue_index := ids.find(selected_id)
	return playback.set_playback_queue(ids, queue_index) and playback.play_queue_index(queue_index)

## 打开专辑或歌手作品的临时详情弹窗，关闭时自动清理临时歌单。
func open_collection_result(item: Dictionary, plugin_id: String, collection_type: String) -> void:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return
	if not plugin_controller.is_plugin_enabled(plugin_id):
		show_toast("该插件已停用，请先在设置中启用。")
		return
	var plugin_entry := plugin_controller._get_plugin_entry(plugin_id)
	if plugin_entry.is_empty():
		return
	var plugin = plugin_entry.get("plugin")
	_cleanup_temporary_collections()
	show_toast("正在加载%s…" % ("专辑" if collection_type == "album" else "作者作品"))
	var response: Dictionary = {}
	print("[PluginBrowser] collection request: ", {"plugin_id": plugin_id, "collection_type": collection_type, "item_id": item.get("id", ""), "bvid": item.get("bvid", "")})
	if collection_type == "album" and plugin.has_method("get_album_info"):
		response = await plugin.get_album_info(item, 1)
	elif collection_type == "artist" and plugin.has_method("get_artist_works"):
		response = await plugin.get_artist_works(item, 1, "music")
	var raw_items: Array = response.get("musicList", response.get("data", [])) if response is Dictionary else []
	var typed_items: Array[Dictionary] = []
	for value in raw_items:
		if value is Dictionary:
			typed_items.append(value)
	print("[PluginBrowser] resolved collection evidence: ", {"item_id": item.get("id", ""), "pages_or_tracks": typed_items.size(), "title": item.get("title", ""), "description": item.get("description", ""), "tag": item.get("tag", "")})
	print("[PluginBrowser] collection result: ", {"collection_type": collection_type, "count": typed_items.size(), "first_keys": typed_items[0].keys() if not typed_items.is_empty() else []})
	var indices := ensure_plugin_tracks_from_search_results(typed_items, plugin_id)
	if indices.is_empty():
		print("[PluginBrowser] collection open aborted: no playable tracks")
		show_toast("未找到可播放内容。")
		return
	var playlist := PlaylistData.new()
	playlist.title = str(item.get("title", item.get("name", "未命名专辑")))
	playlist.mark = "__plugin_collection__"
	playlist.deletable = false
	for index in indices:
		playlist.tracks.append(get_tracks_ref()[index].id)
	playlist.count = playlist.tracks.size()
	# 每次从搜索打开都创建独立的临时展示歌单。不能直接复用已收藏歌单，
	# 否则弹窗会显示成“已收藏”状态，收藏按钮也会错误地消失。
	get_playlists_ref().append(playlist)
	set_selected_playlist_index(get_playlists_ref().size() - 1)
	var popup = get_popup_router_controller().show_popup(
		DX_PopupRegistry.PopupId.MUSIC_APP_PLAYLIST,
		DX_PopupView.PopupLayer.FULLSCREEN
	)
	print("[PluginBrowser] collection popup shown: ", popup != null)

## Resolve collection size without mutating playlists; used for music-tab videos.
func resolve_collection_result(item: Dictionary, plugin_id: String) -> Dictionary:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null or not plugin_controller.is_plugin_enabled(plugin_id):
		return {}
	var entry := plugin_controller._get_plugin_entry(plugin_id)
	if entry.is_empty() or not entry.plugin.has_method("get_album_info"):
		return {}
	var response: Dictionary = await entry.plugin.get_album_info(item, 1)
	var tracks: Array = response.get("musicList", []) if response is Dictionary else []
	print("[PluginBrowser] collection probe: ", {"id": item.get("id", ""), "track_count": tracks.size(), "title": item.get("title", "")})
	return {"track_count": tracks.size()}

func cleanup_temporary_collection() -> void:
	_cleanup_temporary_collections()

func _cleanup_temporary_collections() -> void:
	var playlists := get_playlists_ref()
	var selected := get_selected_playlist_index()
	for index in range(playlists.size() - 1, -1, -1):
		if playlists[index].mark != "__plugin_collection__":
			continue
		playlists.remove_at(index)
		if index < selected:
			selected -= 1
	set_selected_playlist_index(clampi(selected, 0, maxi(0, playlists.size() - 1)))

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
func resolve_track_plugin_source(track_id: String, quality: String = "standard") -> Dictionary:
	var plugins = get_plugin_controller()
	return await plugins.get_media_source(get_track_by_id(track_id), quality) if plugins != null else {}

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(track_id: String) -> Dictionary:
	var plugins = get_plugin_controller()
	return await plugins.get_lyric(get_track_by_id(track_id)) if plugins != null else {}
