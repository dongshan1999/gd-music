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

## 返回当前选中歌单内的曲目 ID 列表。
func get_selected_playlist_track_ids() -> Array[String]:
	return _get_playlist_track_ids(get_selected_playlist_index())

## 根据曲目 ID 获取曲目对象。
func get_track(track_id: String):
	return get_track_by_id(track_id)

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
	var track_ids := get_selected_playlist_track_ids()
	if track_ids.is_empty():
		return false
	return _play_track_list(track_ids, 0, true)

## 播放当前歌单指定槽位的曲目并打开播放器。
func play_selected_playlist_track(slot_index: int) -> bool:
	var track_ids := get_selected_playlist_track_ids()
	if slot_index < 0 or slot_index >= track_ids.size():
		return false
	return _play_track_list(track_ids, slot_index, true)

func move_selected_playlist_track(from_slot_index: int, to_slot_index: int) -> bool:
	var playlist: PlaylistData = get_selected_playlist()
	if playlist == null:
		return false
	if from_slot_index < 0 or from_slot_index >= playlist.tracks.size():
		return false
	if playlist.tracks.size() <= 1:
		return false
	var clamped_to_index := clampi(to_slot_index, 0, playlist.tracks.size() - 1)
	if from_slot_index == clamped_to_index:
		return true

	var track_id: String = playlist.tracks[from_slot_index]
	playlist.tracks.remove_at(from_slot_index)
	playlist.tracks.insert(clamped_to_index, track_id)
	playlist.count = playlist.tracks.size()
	return true

func delete_selected_playlist_track(slot_index: int) -> bool:
	return delete_selected_playlist_tracks([slot_index]) > 0

func delete_selected_playlist_tracks(slot_indices: Array) -> int:
	var playlist: PlaylistData = get_selected_playlist()
	if playlist == null:
		return 0

	var normalized_slots := _normalize_slot_indices(slot_indices, playlist.tracks.size())
	if normalized_slots.is_empty():
		return 0

	for slot_index in normalized_slots:
		playlist.tracks.remove_at(slot_index)
	playlist.count = playlist.tracks.size()
	return normalized_slots.size()

func show_empty_playlist_placeholder() -> void:
	show_toast("这个歌单里还没有可播放歌曲。")

func show_search_placeholder() -> void:
	show_toast("歌单内搜索暂未接入。")

func show_more_placeholder() -> void:
	show_toast("更多歌单操作暂未接入。")

func show_sort_empty_placeholder() -> void:
	show_toast("这个歌单里还没有可排序歌曲。")

func show_delete_empty_placeholder() -> void:
	show_toast("这个歌单里还没有可删除歌曲。")

func show_delete_selection_empty_placeholder() -> void:
	show_toast("请先选择要删除的歌曲。")

func show_add_placeholder() -> void:
	show_toast("添加歌曲到歌单暂未接入。")

func show_edit_placeholder() -> void:
	show_toast("编辑歌单信息暂未接入。")

func show_song_more_placeholder() -> void:
	show_toast("歌曲操作暂未接入。")


## 返回指定歌单中的曲目 ID 列表副本。
func _get_playlist_track_ids(index: int) -> Array[String]:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	if index < 0 or index >= playlists.size():
		return []

	var result: Array[String] = []
	for track_id in playlists[index].tracks:
		result.append(track_id)
	return result

func _normalize_slot_indices(slot_indices: Array, track_count: int) -> Array[int]:
	var result: Array[int] = []
	for slot_index in slot_indices:
		var normalized_index := int(slot_index)
		if normalized_index < 0 or normalized_index >= track_count:
			continue
		if result.has(normalized_index):
			continue
		result.append(normalized_index)
	result.sort()
	result.reverse()
	return result

## 按给定顺序构建播放队列并跳到目标槽位。
func _play_track_list(track_ids: Array[String], start_slot_index: int, autoplay: bool = true) -> bool:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_ids, start_slot_index):
		return false
	if not playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), autoplay):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true
