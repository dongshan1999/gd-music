class_name MusicAppLibraryController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 音乐库控制器：向界面层提供曲目、歌单、播放和收藏等业务接口。
const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const MusicAppPlaybackControllerType := preload("res://scripts/ui/music_app/controllers/music_app_playback_controller.gd")

var _playback_controller: MusicAppPlaybackControllerType = MusicAppPlaybackControllerType.new()

## 返回当前状态中的全部曲目列表。
func get_tracks() -> Array[TrackDataType]:
	var result: Array[TrackDataType] = []
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		return resolved_controller._tracks
	return result

## 按索引获取单首曲目，越界时返回 null。
func get_track(track_index: int) -> TrackDataType:
	var tracks := get_tracks()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 返回当前状态中的全部歌单列表。
func get_playlists() -> Array[PlaylistDataType]:
	var result: Array[PlaylistDataType] = []
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		return resolved_controller._playlists
	return result

## 返回当前选中的歌单对象，无效时返回 null。
func get_selected_playlist() -> PlaylistDataType:
	var playlists := get_playlists()
	var playlist_index := get_selected_playlist_index()
	if playlist_index < 0 or playlist_index >= playlists.size():
		return null
	return playlists[playlist_index]

## 判断当前是否存在有效的播放列表。
func has_tracks() -> bool:
	return _playback_controller.has_playback_queue()

## 返回当前播放列表中的曲目对象。
func get_current_track() -> TrackDataType:
	return _playback_controller.get_current_playback_track()

## 返回当前播放曲目的时长，未播放时返回 0。
func get_current_duration() -> int:
	var track: TrackDataType = _playback_controller.get_current_playback_track()
	return track.duration if track != null else 0

## 返回当前选中歌单中的曲目索引列表。
func get_selected_playlist_track_indices() -> Array[int]:
	return get_playlist_track_indices(get_selected_playlist_index())

## 按歌单索引返回其包含的曲目索引列表。
func get_playlist_track_indices(index: int) -> Array[int]:
	var playlists := get_playlists()
	if index < 0 or index >= playlists.size():
		return []

	var result: Array[int] = []
	for item in playlists[index].tracks:
		result.append(item)
	return result

## 判断当前曲目是否已被收藏。
func is_current_track_liked() -> bool:
	var track: TrackDataType = get_current_track()
	if track == null:
		return false
	return bool(get_liked_tracks().get(track_key(track), false))

## 判断指定索引的曲目是否已被收藏。
func is_track_liked(track_index: int) -> bool:
	var track: TrackDataType = get_track(track_index)
	if track == null:
		return false
	return bool(get_liked_tracks().get(track_key(track), false))

## 生成曲目的唯一标识，用于收藏等状态映射。
func track_key(track: TrackDataType) -> String:
	if not track.file_path.is_empty():
		return track.file_path
	if track.is_plugin_track():
		return "%s:%s" % [track.platform, track.remote_id]
	return "%s - %s" % [track.title, track.artist]

## 返回全部本地曲目的索引列表。
func get_local_track_indices() -> Array[int]:
	var result: Array[int] = []
	var tracks := get_tracks()
	for index in tracks.size():
		var track: TrackDataType = tracks[index]
		if track == null:
			continue
		if not track.file_path.is_empty() or track.source == "LOCAL":
			result.append(index)
	return result

## 判断某个歌单是否为系统内置的“我喜欢”歌单。
func is_system_favorite_playlist(playlist: PlaylistDataType) -> bool:
	return MusicAppStateDataType.is_system_favorite_playlist(playlist)

## 返回歌单用于界面显示的标题。
func get_playlist_display_title(playlist: PlaylistDataType) -> String:
	if is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_title")
	return playlist.title

## 返回歌单用于界面显示的角标/首字标记。
func get_playlist_display_mark(playlist: PlaylistDataType) -> String:
	if is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_mark")
	if not playlist.mark.is_empty():
		return playlist.mark
	var title := get_playlist_display_title(playlist)
	return title.left(1) if not title.is_empty() else ""

## 格式化歌单总曲目数文案。
func format_total_track_count(count: int) -> String:
	return tr("music_app.playlist.total_tracks").format({"count": count})

## 返回曲目用于显示的歌手名，缺省时回退到副标题或本地文件文案。
func get_track_display_artist(track: TrackDataType) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

## 生成一个不重复的新歌单标题。
func next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
	var suffix := 1
	var title := base_title
	while playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

## 判断歌单标题是否已经存在。
func playlist_title_exists(title: String) -> bool:
	for playlist in get_playlists():
		if playlist.title == title:
			return true
	return false

## 创建一个新的空歌单，并切换到该歌单。
func create_playlist_from_current() -> bool:
	var playlists := get_playlists()
	var title := next_playlist_title()
	var playlist := PlaylistDataType.new()
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

## 根据收藏状态同步系统“我喜欢”歌单中的曲目索引。
func sync_favorite_playlist_from_likes() -> void:
	var tracks := get_tracks()
	var favorite_playlist := get_or_create_favorite_playlist()
	var liked_track_indices: Array[int] = []
	for index in tracks.size():
		if is_track_liked(index):
			liked_track_indices.append(index)

	favorite_playlist.title = MusicAppStateDataType.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.tracks = liked_track_indices
	favorite_playlist.count = liked_track_indices.size()

## 获取或创建系统“我喜欢”歌单。
func get_or_create_favorite_playlist() -> PlaylistDataType:
	var playlists := get_playlists()
	var favorite_index := find_favorite_playlist_index()
	if favorite_index >= 0:
		return playlists[favorite_index]

	var favorite_playlist := PlaylistDataType.new()
	favorite_playlist.title = MusicAppStateDataType.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.count = 0
	favorite_playlist.tracks = []
	playlists.insert(0, favorite_playlist)
	if playlists.size() > 1:
		set_selected_playlist_index(get_selected_playlist_index() + 1)
	return favorite_playlist

## 查找系统“我喜欢”歌单在列表中的索引。
func find_favorite_playlist_index() -> int:
	var playlists := get_playlists()
	for index in playlists.size():
		if is_system_favorite_playlist(playlists[index]):
			return index
	return -1

## 选择指定索引的歌单并刷新界面状态。
func select_playlist(index: int) -> bool:
	var playlists := get_playlists()
	if playlists.is_empty():
		return false
	set_selected_playlist_index(clampi(index, 0, playlists.size() - 1))
	notify_state_changed()
	save_app_state()
	return true

## 打开指定歌单页面。
func open_playlist(index: int) -> bool:
	if not select_playlist(index):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST)
	return true

## 删除指定歌单，并修正当前选中索引。
func delete_playlist(index: int) -> bool:
	var playlists := get_playlists()
	if index < 0 or index >= playlists.size():
		return false

	var playlist: PlaylistDataType = playlists[index]
	if not playlist.deletable:
		return false

	var selected_playlist_index := get_selected_playlist_index()
	if index < selected_playlist_index:
		selected_playlist_index -= 1

	playlists.remove_at(index)
	set_selected_playlist_index(clampi(selected_playlist_index, 0, maxi(playlists.size() - 1, 0)))
	notify_state_changed()
	save_app_state()
	return true

## 切换到指定曲目，并可选择是否立即开始播放。
func select_track(track_index: int, autoplay: bool) -> bool:
	var tracks := get_tracks()
	if tracks.is_empty():
		return false

	var resolved_index := posmod(track_index, tracks.size())
	var queue_index := _playback_controller.find_queue_index_for_track(resolved_index)
	if queue_index < 0:
		if not _playback_controller.set_single_track_queue(resolved_index):
			return false
		queue_index = 0
	return _playback_controller.play_queue_index(queue_index, autoplay)

## 以给定顺序构建播放列表，并从指定槽位开始播放。
func play_track_list(track_indices: Array[int], start_slot_index: int, autoplay: bool = true) -> bool:
	if not _playback_controller.set_playback_queue(track_indices, start_slot_index):
		return false
	return _playback_controller.play_queue_index(_playback_controller.get_playback_queue_index(), autoplay)

## 播放上一首曲目。
func play_previous_track() -> bool:
	return _playback_controller.step_queue(-1, true)

## 播放下一首曲目。
func play_next_track() -> bool:
	return _playback_controller.step_queue(1, true)

## 切换播放/暂停状态，并同步到底层音频播放器。
func toggle_playback() -> void:
	if not has_tracks():
		set_is_playing(false)
		request_audio_sync()
		notify_state_changed()
		return

	set_is_playing(not is_playing())
	request_audio_sync()
	notify_state_changed()
	save_app_state()

## 切换当前曲目的收藏状态，并同步“我喜欢”歌单。
func toggle_like_current_track() -> bool:
	if not has_tracks():
		return false

	var track_index := _playback_controller.get_current_playback_track_index()
	var track := _playback_controller.get_current_playback_track()
	if track == null:
		return false

	var next_state := not is_track_liked(track_index)
	var liked_tracks: Dictionary = get_liked_tracks().duplicate(true)
	var key := track_key(track)

	if next_state:
		liked_tracks[key] = true
	else:
		liked_tracks.erase(key)

	set_liked_tracks(liked_tracks)
	sync_favorite_playlist_from_likes()
	save_app_state()
	notify_state_changed()
	show_toast(
		tr("music_app.toast.favorite_added")
		if next_state
		else tr("music_app.toast.favorite_removed")
	)
	return next_state

## 从当前歌单的第一首开始播放，并打开播放器页面。
func play_selected_playlist_from_start() -> bool:
	var tracks := get_selected_playlist_track_indices()
	if tracks.is_empty():
		return false
	if not play_track_list(tracks, 0, true):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
	return true

## 播放当前歌单中指定槽位的曲目，并打开播放器页面。
func play_selected_playlist_track(slot_index: int) -> bool:
	var tracks := get_selected_playlist_track_indices()
	if slot_index < 0 or slot_index >= tracks.size():
		return false
	if not play_track_list(tracks, slot_index, true):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
	return true
