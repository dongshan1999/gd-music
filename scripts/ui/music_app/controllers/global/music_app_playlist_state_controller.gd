class_name MusicAppPlaylistStateController
extends RefCounted

const MusicAppShowcaseControllerScript := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppControllerBaseScript := preload("res://scripts/ui/music_app/controllers/music_app_controller_base.gd")

var controller

func _init(owner = null) -> void:
	controller = owner

func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

func _get_base_controller() -> MusicAppControllerBase:
	return MusicAppControllerBaseScript.new(controller)

func get_tracks_ref() -> Array[TrackData]:
	return _get_base_controller().get_tracks_ref()

func get_playlists_ref() -> Array[PlaylistData]:
	return _get_base_controller().get_playlists_ref()

func get_selected_playlist_index() -> int:
	return _get_base_controller().get_selected_playlist_index()

func set_selected_playlist_index(value: int) -> void:
	_get_base_controller().set_selected_playlist_index(value)

## 规范化系统“我喜欢”歌单，确保它始终是第一个歌单。
func normalize_favorite_playlist() -> void:
	var favorite_playlist := get_or_create_favorite_playlist()
	favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.tracks = _normalize_track_ids(favorite_playlist.tracks)
	favorite_playlist.count = favorite_playlist.tracks.size()

## 判断曲目是否存在于系统“我喜欢”歌单。
func is_track_liked(track: TrackData) -> bool:
	var track_id := track_key(track)
	if track_id.is_empty():
		return false
	var favorite_playlist := get_or_create_favorite_playlist()
	return favorite_playlist.tracks.has(track_id)

## 设置曲目是否存在于系统“我喜欢”歌单，返回是否发生变化。
func set_track_liked(track: TrackData, liked: bool) -> bool:
	var track_id := track_key(track)
	if track_id.is_empty():
		return false

	var favorite_playlist := get_or_create_favorite_playlist()
	favorite_playlist.tracks = _normalize_track_ids(favorite_playlist.tracks)
	var currently_liked := favorite_playlist.tracks.has(track_id)
	if currently_liked == liked:
		favorite_playlist.count = favorite_playlist.tracks.size()
		return false

	if liked:
		favorite_playlist.tracks.append(track_id)
	else:
		favorite_playlist.tracks.erase(track_id)
	favorite_playlist.count = favorite_playlist.tracks.size()
	return true

## 切换曲目收藏状态，返回切换后的状态。
func toggle_track_liked(track: TrackData) -> bool:
	var next_state := not is_track_liked(track)
	set_track_liked(track, next_state)
	return next_state

## 获取或创建系统“我喜欢”歌单。
func get_or_create_favorite_playlist() -> PlaylistData:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	var favorite_index := find_favorite_playlist_index()
	if favorite_index >= 0:
		var favorite_playlist: PlaylistData = playlists[favorite_index]
		if favorite_index > 0:
			playlists.remove_at(favorite_index)
			playlists.insert(0, favorite_playlist)
			_rebase_selected_playlist_index_after_favorite_move(favorite_index)
		favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
		favorite_playlist.mark = ""
		favorite_playlist.deletable = false
		favorite_playlist.count = favorite_playlist.tracks.size()
		return favorite_playlist

	var favorite_playlist := PlaylistData.new()
	favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
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
	var playlists: Array[PlaylistData] = get_playlists_ref()
	for index in playlists.size():
		if MusicAppStateData.is_system_favorite_playlist(playlists[index]):
			return index
	return -1

## 生成曲目的唯一标识，用于收藏和播放态匹配。
func track_key(track: TrackData) -> String:
	if track == null:
		return ""
	return track.id.strip_edges()

func _normalize_track_ids(source: Array) -> Array[String]:
	var result: Array[String] = []
	var track_ids := _build_track_id_map()
	for item in source:
		var track_id := str(item).strip_edges()
		if track_id.is_empty() or not track_ids.has(track_id):
			continue
		if result.has(track_id):
			continue
		result.append(track_id)
	return result

func _build_track_id_map() -> Dictionary:
	var result := {}
	for track in get_tracks_ref():
		if track == null:
			continue
		var track_id := track_key(track)
		if not track_id.is_empty():
			result[track_id] = true
	return result

func _rebase_selected_playlist_index_after_favorite_move(old_favorite_index: int) -> void:
	var selected_index := get_selected_playlist_index()
	if selected_index == old_favorite_index:
		set_selected_playlist_index(0)
	elif selected_index < old_favorite_index:
		set_selected_playlist_index(selected_index + 1)
