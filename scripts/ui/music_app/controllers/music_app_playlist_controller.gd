class_name MusicAppPlaylistController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 返回当前全部歌单列表。
func get_playlists() -> Array:
	return get_playlists_ref()

## 返回当前选中的歌单对象。
func get_selected_playlist():
	var playlists: Array[PlaylistData] = get_playlists_ref()
	var playlist_index := get_selected_playlist_index()
	if playlist_index < 0 or playlist_index >= playlists.size():
		return null
	return playlists[playlist_index]

## 返回当前选中歌单内的曲目索引列表。
func get_selected_playlist_track_indices() -> Array[int]:
	return _get_playlist_track_indices(get_selected_playlist_index())

## 根据全量曲目索引获取曲目对象。
func get_track(track_index: int):
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 返回歌单详情页展示标题。
func get_playlist_display_title(playlist) -> String:
	var playlist_state_controller = get_playlist_state_controller()
	if playlist_state_controller != null and MusicAppStateData.is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_title")
	return playlist.title

## 返回歌单详情页展示角标。
func get_playlist_display_mark(playlist) -> String:
	if MusicAppStateData.is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_mark")
	if not playlist.mark.is_empty():
		return playlist.mark
	var title := get_playlist_display_title(playlist)
	return title.left(1) if not title.is_empty() else ""

## 格式化歌单总曲目数文案。
func format_total_track_count(count: int) -> String:
	return tr("music_app.playlist.total_tracks").format({"count": count})

## 从当前歌单第一首开始播放并打开播放器。
func play_selected_playlist_from_start() -> bool:
	var track_indices := get_selected_playlist_track_indices()
	if track_indices.is_empty():
		return false
	return _play_track_list(track_indices, 0, true)

## 播放当前歌单指定槽位的曲目并打开播放器。
func play_selected_playlist_track(slot_index: int) -> bool:
	var track_indices := get_selected_playlist_track_indices()
	if slot_index < 0 or slot_index >= track_indices.size():
		return false
	return _play_track_list(track_indices, slot_index, true)

## 创建一个新的空歌单并切换到它。
func create_playlist_from_current() -> bool:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	var title := _next_playlist_title()
	var playlist := PlaylistData.new()
	playlist.title = title
	playlist.count = 0
	playlist.mark = title.left(1)
	playlist.tracks = []
	playlist.deletable = true
	playlists.append(playlist)
	set_selected_playlist_index(playlists.size() - 1)
	notify_state_changed()
	save_app_state()
	return true

## 返回指定歌单中的曲目索引列表副本。
func _get_playlist_track_indices(index: int) -> Array[int]:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	if index < 0 or index >= playlists.size():
		return []

	var result: Array[int] = []
	for track_index in playlists[index].tracks:
		result.append(track_index)
	return result

## 按给定顺序构建播放队列并跳到目标槽位。
func _play_track_list(track_indices: Array[int], start_slot_index: int, autoplay: bool = true) -> bool:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_indices, start_slot_index):
		return false
	if not playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), autoplay):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true

## 生成一个新的不重复歌单标题。
func _next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
	var suffix := 1
	var title := base_title
	while _playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

## 判断歌单标题是否已存在。
func _playlist_title_exists(title: String) -> bool:
	for playlist in get_playlists_ref():
		if playlist.title == title:
			return true
	return false
