class_name MusicAppPluginController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 返回全局音乐插件管理器。
func get_music_plugin_manager() -> DX_MusicPluginManager:
	return DX.music_plugins as DX_MusicPluginManager

## 启动本地音乐插件宿主服务。
func start_music_plugin_host() -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.start_local_host()

## 按配置尝试自动启动本地音乐插件宿主服务。
func auto_start_music_plugin_host() -> void:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return
	if not plugin_manager.get_settings().auto_start_local_host:
		return
	await resolved_controller.get_tree().process_frame
	var result: Dictionary = await plugin_manager.start_local_host()
	if not bool(result.get("ok", false)):
		push_warning("Music plugin host auto-start failed: %s" % str(result.get("error", "Unknown error.")))

## 从远程 URL 安装音乐插件。
func install_music_plugin_from_url(plugin_url: String) -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.install_plugin_from_url(plugin_url)

## 从本地文件安装音乐插件。
func install_music_plugin_from_file(plugin_path: String) -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.install_plugin_from_file(plugin_path)

## 调用指定插件执行音乐搜索。
func search_music_plugin(plugin_id: String, query: String, page: int = 1, media_type: String = "music") -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.search(plugin_id, query, page, media_type)

## 将插件搜索结果导入曲目库并挂到目标歌单。
func import_music_plugin_search_results(
	plugin_id: String,
	results: Array,
	target_playlist_index: int = -1,
	autoplay_first: bool = false
) -> Array[int]:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return []

	var imported_indices: Array[int] = []
	var target_playlist := _get_plugin_target_playlist(plugin_id, target_playlist_index)
	if target_playlist == null:
		return imported_indices
	var tracks: Array[TrackData] = get_tracks_ref()
	for item in results:
		var track := _make_remote_track_from_plugin_item(plugin_id, item)
		if track == null:
			continue
		tracks.append(track)
		var new_index: int = tracks.size() - 1
		imported_indices.append(new_index)
		target_playlist.tracks.append(new_index)

	target_playlist.count = target_playlist.tracks.size()
	if imported_indices.is_empty():
		return imported_indices

	notify_state_changed()
	save_app_state()
	if autoplay_first:
		var start_slot := maxi(0, target_playlist.tracks.size() - imported_indices.size())
		_play_track_list(target_playlist.tracks, start_slot, true)
	return imported_indices

## 解析指定插件曲目的可播放音频源。
func resolve_track_plugin_source(track_index: int, quality: String = "standard") -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		return build_plugin_error("Track index is out of range.")
	if track == null or not track.is_plugin_track():
		return build_plugin_error("Selected track is not a plugin track.")

	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")

	var result := await plugin_manager.get_media_source(track, quality)
	if bool(result.get("ok", false)) and result.get("data", null) is Dictionary:
		track.apply_plugin_source(result.data)
		notify_state_changed()
		save_app_state()
	return result

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(track_index: int) -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		return build_plugin_error("Track index is out of range.")
	if track == null or not track.is_plugin_track():
		return build_plugin_error("Selected track is not a plugin track.")

	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")

	var result := await plugin_manager.get_lyric(track)
	if bool(result.get("ok", false)) and result.get("data", null) is Dictionary:
		track.apply_plugin_lyric(result.data)
		notify_state_changed()
		save_app_state()
	return result

## 将插件返回的数据项转换为远程曲目对象。
func _make_remote_track_from_plugin_item(plugin_id: String, item) -> TrackData:
	if item == null or not (item is Dictionary):
		return null
	var payload: Dictionary = item

	var track := TrackData.new()
	track.platform = str(payload.get("platform", plugin_id))
	track.remote_id = str(payload.get("id", ""))
	track.title = str(payload.get("title", ""))
	track.artist = str(payload.get("artist", ""))
	track.subtitle = str(payload.get("album", ""))
	track.duration = maxi(1, int(payload.get("duration", 180)))
	track.preview_start = int(payload.get("preview_start", 0))
	track.mark = str(payload.get("mark", "") if payload.has("mark") else track.title.left(1))
	track.source = track.platform
	track.file_path = ""
	track.stream_url = str(payload.get("url", ""))
	track.artwork_url = str(payload.get("artwork", ""))
	track.lyric_text = str(payload.get("rawLrc", ""))
	track.lyric_translation = str(payload.get("translation", ""))
	track.stream_headers = payload.get("headers", {})
	track.qualities = payload.get("qualities", {})
	track.normalize()
	return track

## 获取插件导入的目标歌单，不存在时自动创建。
func _get_plugin_target_playlist(plugin_id: String, target_playlist_index: int) -> PlaylistData:
	var playlists: Array[PlaylistData] = get_playlists_ref()

	if target_playlist_index >= 0 and target_playlist_index < playlists.size():
		return playlists[target_playlist_index]

	var selected_playlist := _get_selected_playlist()
	if playlists.is_empty() or selected_playlist == null or MusicAppStateData.is_system_favorite_playlist(selected_playlist):
		return _create_playlist_for_plugin(plugin_id)

	return selected_playlist

## 为插件导入结果创建新的歌单。
func _create_playlist_for_plugin(plugin_id: String) -> PlaylistData:
	var playlists: Array[PlaylistData] = get_playlists_ref()

	var title := plugin_id if not plugin_id.is_empty() else _next_playlist_title()
	if _playlist_title_exists(title):
		title = _next_playlist_title()

	var playlist := PlaylistData.new()
	playlist.title = title
	playlist.count = 0
	playlist.mark = title.left(1) if not title.is_empty() else "P"
	playlist.tracks = []
	playlist.deletable = true
	playlists.append(playlist)
	set_selected_playlist_index(playlists.size() - 1)
	return playlist

## 构造统一格式的插件错误返回。
func build_plugin_error(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "error": message}
	for key in extra.keys():
		result[key] = extra[key]
	return result

## 根据全量曲目索引返回曲目对象。
func _get_track(track_index: int) -> TrackData:
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 返回当前选中的歌单对象。
func _get_selected_playlist() -> PlaylistData:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	var playlist_index := get_selected_playlist_index()
	if playlist_index < 0 or playlist_index >= playlists.size():
		return null
	return playlists[playlist_index]

## 按给定曲目顺序构建播放队列，并切到目标槽位播放。
func _play_track_list(track_indices: Array[int], start_slot_index: int, autoplay: bool = true) -> bool:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_indices, start_slot_index):
		return false
	return playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), autoplay)

## 生成一个新的不重复歌单标题。
func _next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
	var suffix := 1
	var title := base_title
	while _playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

## 判断歌单标题是否已经存在。
func _playlist_title_exists(title: String) -> bool:
	for playlist in get_playlists_ref():
		if playlist.title == title:
			return true
	return false
