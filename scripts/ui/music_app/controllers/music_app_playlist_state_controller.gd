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

func get_liked_tracks() -> Dictionary:
	return _get_base_controller().get_liked_tracks()

## 根据收藏映射重建系统“我喜欢”歌单内容。
func sync_favorite_playlist_from_likes() -> void:
	var favorite_playlist := get_or_create_favorite_playlist()
	var liked_track_indices: Array[int] = []
	var tracks: Array[TrackData] = get_tracks_ref()
	var liked_tracks = get_liked_tracks()
	for index in tracks.size():
		var track: TrackData = tracks[index]
		if track == null:
			continue
		if bool(liked_tracks.get(track_key(track), false)):
			liked_track_indices.append(index)

	favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.tracks = liked_track_indices
	favorite_playlist.count = liked_track_indices.size()

## 获取或创建系统“我喜欢”歌单。
func get_or_create_favorite_playlist() -> PlaylistData:
	var playlists: Array[PlaylistData] = get_playlists_ref()
	var favorite_index := find_favorite_playlist_index()
	if favorite_index >= 0:
		return playlists[favorite_index]

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
	if not track.file_path.is_empty():
		return track.file_path
	if track.is_plugin_track():
		return "%s:%s" % [track.platform, track.remote_id]
	return "%s - %s" % [track.title, track.artist]
