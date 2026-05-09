class_name MusicAppPluginController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const MusicAppLibraryControllerType := preload("res://scripts/ui/music_app/controllers/music_app_library_controller.gd")
const MusicPluginManagerType := preload("res://dx/runtime/scripts/managers/music_plugin_manager.gd")

var _library_controller: MusicAppLibraryControllerType = MusicAppLibraryControllerType.new()

func get_music_plugin_manager() -> MusicPluginManagerType:
	return DX.music_plugins as MusicPluginManagerType

func start_music_plugin_host() -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.start_local_host()

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

func install_music_plugin_from_url(plugin_url: String) -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.install_plugin_from_url(plugin_url)

func install_music_plugin_from_file(plugin_path: String) -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.install_plugin_from_file(plugin_path)

func search_music_plugin(plugin_id: String, query: String, page: int = 1, media_type: String = "music") -> Dictionary:
	var plugin_manager := get_music_plugin_manager()
	if plugin_manager == null:
		return build_plugin_error("Music plugin manager is not available.")
	return await plugin_manager.search(plugin_id, query, page, media_type)

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
	for item in results:
		var track := _make_remote_track_from_plugin_item(plugin_id, item)
		if track == null:
			continue
		var tracks := _library_controller.get_tracks()
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
		_library_controller.play_track_list(target_playlist.tracks, start_slot, true)
	return imported_indices

func resolve_track_plugin_source(track_index: int, quality: String = "standard") -> Dictionary:
	var track: TrackDataType = _library_controller.get_track(track_index)
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

func resolve_track_plugin_lyric(track_index: int) -> Dictionary:
	var track: TrackDataType = _library_controller.get_track(track_index)
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

func _make_remote_track_from_plugin_item(plugin_id: String, item) -> TrackDataType:
	if item == null or not (item is Dictionary):
		return null
	var payload: Dictionary = item

	var track := TrackDataType.new()
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

func _get_plugin_target_playlist(plugin_id: String, target_playlist_index: int) -> PlaylistDataType:
	var playlists := _library_controller.get_playlists()

	if target_playlist_index >= 0 and target_playlist_index < playlists.size():
		return playlists[target_playlist_index]

	var selected_playlist := _library_controller.get_selected_playlist()
	if playlists.is_empty() or selected_playlist == null or _library_controller.is_system_favorite_playlist(selected_playlist):
		return _create_playlist_for_plugin(plugin_id)

	return selected_playlist

func _create_playlist_for_plugin(plugin_id: String) -> PlaylistDataType:
	var playlists := _library_controller.get_playlists()

	var title := plugin_id if not plugin_id.is_empty() else _library_controller.next_playlist_title()
	if _library_controller.playlist_title_exists(title):
		title = _library_controller.next_playlist_title()

	var playlist := PlaylistDataType.new()
	playlist.title = title
	playlist.count = 0
	playlist.mark = title.left(1) if not title.is_empty() else "P"
	playlist.tracks = []
	playlist.deletable = true
	playlists.append(playlist)
	_library_controller.set_selected_playlist_index(playlists.size() - 1)
	return playlist

func build_plugin_error(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "error": message}
	for key in extra.keys():
		result[key] = extra[key]
	return result
