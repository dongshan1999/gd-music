class_name MusicAppLibraryController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")

func get_tracks() -> Array[TrackDataType]:
	var result: Array[TrackDataType] = []
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		return resolved_controller._tracks
	return result

func get_track(track_index: int) -> TrackDataType:
	var tracks := get_tracks()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

func get_playlists() -> Array[PlaylistDataType]:
	var result: Array[PlaylistDataType] = []
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		return resolved_controller._playlists
	return result

func get_selected_playlist() -> PlaylistDataType:
	var playlists := get_playlists()
	var playlist_index := get_selected_playlist_index()
	if playlist_index < 0 or playlist_index >= playlists.size():
		return null
	return playlists[playlist_index]

func has_tracks() -> bool:
	return not get_tracks().is_empty()

func get_current_track() -> TrackDataType:
	return get_track(get_selected_track_index())

func get_current_duration() -> int:
	var track: TrackDataType = get_current_track()
	return track.duration if track != null else 0

func get_selected_playlist_track_indices() -> Array[int]:
	return get_playlist_track_indices(get_selected_playlist_index())

func get_playlist_track_indices(index: int) -> Array[int]:
	var playlists := get_playlists()
	if index < 0 or index >= playlists.size():
		return []

	var result: Array[int] = []
	for item in playlists[index].tracks:
		result.append(item)
	return result

func is_current_track_liked() -> bool:
	var track: TrackDataType = get_current_track()
	if track == null:
		return false
	return bool(get_liked_tracks().get(track_key(track), false))

func is_track_liked(track_index: int) -> bool:
	var track: TrackDataType = get_track(track_index)
	if track == null:
		return false
	return bool(get_liked_tracks().get(track_key(track), false))

func track_key(track: TrackDataType) -> String:
	if not track.file_path.is_empty():
		return track.file_path
	if track.is_plugin_track():
		return "%s:%s" % [track.platform, track.remote_id]
	return "%s - %s" % [track.title, track.artist]

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

func is_system_favorite_playlist(playlist: PlaylistDataType) -> bool:
	return MusicAppStateDataType.is_system_favorite_playlist(playlist)

func get_playlist_display_title(playlist: PlaylistDataType) -> String:
	if is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_title")
	return playlist.title

func get_playlist_display_mark(playlist: PlaylistDataType) -> String:
	if is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_mark")
	if not playlist.mark.is_empty():
		return playlist.mark
	var title := get_playlist_display_title(playlist)
	return title.left(1) if not title.is_empty() else ""

func format_song_count(count: int) -> String:
	return tr("music_app.common.song_count").format({"count": count})

func format_total_track_count(count: int) -> String:
	return tr("music_app.playlist.total_tracks").format({"count": count})

func get_track_display_artist(track: TrackDataType) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

func next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
	var suffix := 1
	var title := base_title
	while playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

func playlist_title_exists(title: String) -> bool:
	for playlist in get_playlists():
		if playlist.title == title:
			return true
	return false

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

func try_create_playlist_from_current() -> bool:
	return create_playlist_from_current()

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

func find_favorite_playlist_index() -> int:
	var playlists := get_playlists()
	for index in playlists.size():
		if is_system_favorite_playlist(playlists[index]):
			return index
	return -1

func select_playlist(index: int) -> bool:
	var playlists := get_playlists()
	if playlists.is_empty():
		return false
	set_selected_playlist_index(clampi(index, 0, playlists.size() - 1))
	notify_state_changed()
	save_app_state()
	return true

func open_playlist(index: int) -> bool:
	if not select_playlist(index):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST)
	return true

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

func select_track(track_index: int, autoplay: bool) -> bool:
	var tracks := get_tracks()
	if tracks.is_empty():
		return false

	var resolved_index := posmod(track_index, tracks.size())
	set_selected_track_index(resolved_index)
	set_elapsed_seconds(tracks[resolved_index].preview_start)
	set_is_playing(autoplay)
	notify_state_changed()
	save_app_state()
	return true

func play_previous_track() -> bool:
	return select_track(get_selected_track_index() - 1, true)

func play_next_track() -> bool:
	return select_track(get_selected_track_index() + 1, true)

func toggle_playback() -> void:
	if not has_tracks():
		set_is_playing(false)
		notify_state_changed()
		return

	set_is_playing(not is_playing())
	notify_state_changed()
	save_app_state()

func toggle_like_current_track() -> bool:
	if not has_tracks():
		return false

	var track_index := get_selected_track_index()
	var track := get_track(track_index)
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

func play_selected_playlist_from_start() -> bool:
	var tracks := get_selected_playlist_track_indices()
	if tracks.is_empty():
		return false
	if not select_track(tracks[0], true):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
	return true

func play_selected_playlist_track(slot_index: int) -> bool:
	var tracks := get_selected_playlist_track_indices()
	if slot_index < 0 or slot_index >= tracks.size():
		return false
	if not select_track(tracks[slot_index], true):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
	return true
