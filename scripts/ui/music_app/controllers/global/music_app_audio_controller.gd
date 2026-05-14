class_name MusicAppPlaybackStateController
extends RefCounted

const MusicAppShowcaseControllerScript := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppControllerBaseScript := preload("res://scripts/ui/music_app/controllers/music_app_controller_base.gd")

var controller

const SUPPORTED_AUDIO_LOADERS := ["mp3", "ogg", "wav"]
const REMOTE_STREAM_TIMEOUT_SECONDS := 20.0

var _audio_sync_request_id := 0
var _loaded_track_key := ""

func _init(owner = null) -> void:
	controller = owner

func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

func _get_base_controller() -> MusicAppControllerBase:
	return MusicAppControllerBaseScript.new(controller)

func get_selected_track_index() -> int:
	return _get_base_controller().get_selected_track_index()

func get_elapsed_seconds() -> int:
	return _get_base_controller().get_elapsed_seconds()

func set_elapsed_seconds(value: int) -> void:
	_get_base_controller().set_elapsed_seconds(value)

func is_playing() -> bool:
	return _get_base_controller().is_playing()

func set_is_playing(value: bool) -> void:
	_get_base_controller().set_is_playing(value)

func save_app_state() -> void:
	_get_base_controller().save_app_state()

func get_popup_router_controller():
	return _get_base_controller().get_popup_router_controller()

func get_playback_controller():
	return _get_base_controller().get_playback_controller()

## 判断当前是否存在有效的播放队列。
func has_tracks() -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller != null and playback_controller.has_playback_queue()

## 返回当前播放队列指向的曲目对象。
func get_current_track() -> TrackData:
	var playback_controller = get_playback_controller()
	return playback_controller.get_current_playback_track() if playback_controller != null else null

## 返回当前播放曲目的时长。
func get_current_duration() -> int:
	var track := get_current_track()
	return track.duration if track != null else 0

## 切换全局播放或暂停状态，并请求同步底层播放器。
func toggle_playback() -> void:
	if not has_tracks():
		set_is_playing(false)
		request_audio_sync()
		return

	set_is_playing(not is_playing())
	request_audio_sync()
	save_app_state()

## 将底层播放器与全局状态同步到指定秒数。
func seek_to_elapsed_seconds(value: int, persist_state: bool = true) -> void:
	if not has_tracks():
		return

	var track := get_current_track()
	if track == null:
		return

	var target_seconds := clampi(value, 0, get_current_duration())
	if target_seconds == get_elapsed_seconds():
		if persist_state:
			save_app_state()
		return

	set_elapsed_seconds(target_seconds)

	var audio_player = _get_audio_player()
	var desired_track_key := _get_track_playback_key(track)
	if audio_player != null and audio_player.stream != null and _loaded_track_key == desired_track_key:
		_apply_audio_seek(audio_player, target_seconds)
	elif is_playing():
		request_audio_sync()

	if persist_state:
		save_app_state()

## 发起一次异步音频状态同步请求。
func request_audio_sync() -> void:
	_audio_sync_request_id += 1
	call_deferred("_sync_audio_state_deferred", _audio_sync_request_id)

## 每秒同步一次播放进度，并在状态变化时刷新界面。
func tick_playback_progress() -> void:
	var audio_player = _get_audio_player()
	if audio_player == null:
		return

	if not has_tracks():
		if is_playing():
			set_is_playing(false)
			request_audio_sync()
		return

	if not is_playing() or audio_player.stream == null or not audio_player.playing or audio_player.stream_paused:
		return

	var next_elapsed := clampi(int(floor(audio_player.get_playback_position())), 0, get_current_duration())
	if next_elapsed == get_elapsed_seconds():
		return
	set_elapsed_seconds(next_elapsed)

## 响应音频播放完成事件，自动切到队列下一首。
func on_audio_finished() -> void:
	if not has_tracks() or not is_playing():
		return
	_loaded_track_key = ""
	var playback_controller = get_playback_controller()
	if playback_controller != null:
		playback_controller.advance_after_finish()

## 停止底层音频播放，并按需清空已挂载的音频流。
func stop_audio_playback(clear_stream: bool) -> void:
	var audio_player = _get_audio_player()
	if audio_player == null:
		return
	audio_player.stop()
	audio_player.stream_paused = false
	if clear_stream:
		audio_player.stream = null

func _sync_audio_state_deferred(sync_request_id: int) -> void:
	await _sync_audio_state(sync_request_id)

func _sync_audio_state(sync_request_id: int) -> void:
	var audio_player = _get_audio_player()
	if audio_player == null:
		return
	if sync_request_id != _audio_sync_request_id:
		return

	if not has_tracks():
		_loaded_track_key = ""
		stop_audio_playback(true)
		if is_playing():
			set_is_playing(false)
			save_app_state()
		return

	var track := get_current_track()
	if track == null:
		_loaded_track_key = ""
		stop_audio_playback(true)
		if is_playing():
			set_is_playing(false)
			save_app_state()
		return

	var desired_track_key := _get_track_playback_key(track)
	if not is_playing():
		if audio_player.playing and not audio_player.stream_paused:
			var paused_elapsed := _get_audio_position_seconds()
			if paused_elapsed != get_elapsed_seconds():
				set_elapsed_seconds(paused_elapsed)
			audio_player.stream_paused = true
		elif audio_player.stream != null and _loaded_track_key != desired_track_key:
			_loaded_track_key = ""
			stop_audio_playback(true)
		return

	if _loaded_track_key == desired_track_key and audio_player.stream != null:
		if not audio_player.playing:
			audio_player.play(float(get_elapsed_seconds()))
		if audio_player.stream_paused:
			audio_player.stream_paused = false
		return

	var stream = await _resolve_stream_for_track(track, sync_request_id)
	if sync_request_id != _audio_sync_request_id:
		return
	if stream == null:
		_loaded_track_key = ""
		_mark_playback_unavailable(track)
		return

	stop_audio_playback(false)
	audio_player.stream = stream
	_loaded_track_key = desired_track_key
	_sync_track_duration_from_stream(track, stream)
	audio_player.play(float(get_elapsed_seconds()))
	audio_player.stream_paused = false

func _resolve_stream_for_track(track: TrackData, sync_request_id: int) -> AudioStream:
	if not track.file_path.is_empty():
		return _load_local_stream(track.file_path)

	if track.stream_url.is_empty() and track.is_plugin_track():
		var plugin_controller := MusicAppPluginBrowserController.new(get_showcase())
		var resolve_result = await plugin_controller.resolve_track_plugin_source(get_selected_track_index())
		if sync_request_id != _audio_sync_request_id:
			return null
		if not bool(resolve_result.get("ok", false)):
			push_warning("Failed to resolve plugin stream for track \"%s\": %s" % [
				track.title,
				str(resolve_result.get("error", "Unknown error."))
			])
			return null

	if track.stream_url.is_empty():
		push_warning("Track \"%s\" does not have a playable audio source." % track.title)
		return null

	if _is_remote_stream_url(track.stream_url):
		return await _load_remote_stream(track.stream_url, track.stream_headers, sync_request_id)

	return _load_local_stream(track.stream_url)

func _load_local_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not FileAccess.file_exists(path):
		push_warning("Audio file does not exist: %s" % path)
		return null

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("Audio file is empty or unreadable: %s" % path)
		return null

	return _load_stream_from_buffer(bytes, _get_audio_extension(path))

func _load_remote_stream(
	url: String,
	headers: Dictionary,
	sync_request_id: int
) -> AudioStream:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null

	var request := HTTPRequest.new()
	request.timeout = REMOTE_STREAM_TIMEOUT_SECONDS
	resolved_controller.add_child(request)

	var err := request.request(url, _build_http_headers(headers), HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		push_warning("Failed to dispatch audio request for URL: %s" % url)
		return null

	var signal_result: Array = await request.request_completed
	request.queue_free()
	if sync_request_id != _audio_sync_request_id:
		return null

	var result_code := int(signal_result[0])
	var response_code := int(signal_result[1])
	var body: PackedByteArray = signal_result[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_warning("Audio request failed for URL %s with result code %d." % [url, result_code])
		return null
	if response_code < 200 or response_code >= 300:
		push_warning("Audio request returned HTTP %d for URL: %s" % [response_code, url])
		return null
	if body.is_empty():
		push_warning("Audio request returned an empty response body for URL: %s" % url)
		return null

	return _load_stream_from_buffer(body, _get_audio_extension(url))

func _load_stream_from_buffer(buffer: PackedByteArray, preferred_extension: String) -> AudioStream:
	for loader_name in _get_audio_loader_candidates(preferred_extension):
		var stream: AudioStream = null
		match loader_name:
			"mp3":
				stream = AudioStreamMP3.load_from_buffer(buffer)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_buffer(buffer)
			"wav":
				stream = AudioStreamWAV.load_from_buffer(buffer)
		if stream != null:
			return stream
	return null

func _get_audio_loader_candidates(preferred_extension: String) -> Array[String]:
	var normalized_extension := preferred_extension.to_lower()
	var candidates: Array[String] = []
	if normalized_extension in SUPPORTED_AUDIO_LOADERS:
		candidates.append(normalized_extension)
	for loader_name in SUPPORTED_AUDIO_LOADERS:
		if candidates.has(loader_name):
			continue
		candidates.append(loader_name)
	return candidates

func _build_http_headers(headers: Dictionary) -> PackedStringArray:
	var formatted_headers := PackedStringArray()
	for key in headers.keys():
		formatted_headers.append("%s: %s" % [str(key), str(headers[key])])
	return formatted_headers

func _get_audio_extension(path_or_url: String) -> String:
	var sanitized := path_or_url.split("?")[0].split("#")[0]
	return sanitized.get_extension().to_lower()

func _is_remote_stream_url(path_or_url: String) -> bool:
	return path_or_url.begins_with("http://") or path_or_url.begins_with("https://")

func _get_track_playback_key(track: TrackData) -> String:
	if not track.file_path.is_empty():
		return "file:%s" % track.file_path
	if not track.stream_url.is_empty():
		return "url:%s" % track.stream_url
	if track.is_plugin_track():
		return "plugin:%s:%s" % [track.platform, track.remote_id]
	return "title:%s:%s" % [track.title, track.artist]

func _apply_audio_seek(audio_player: AudioStreamPlayer, target_seconds: int) -> void:
	var should_resume := is_playing()
	var was_paused := audio_player.stream_paused

	if audio_player.playing:
		audio_player.seek(float(target_seconds))
	elif should_resume:
		audio_player.play(float(target_seconds))

	audio_player.stream_paused = was_paused or not should_resume

func _get_audio_position_seconds() -> int:
	var audio_player = _get_audio_player()
	if audio_player == null:
		return 0
	return clampi(int(floor(audio_player.get_playback_position())), 0, get_current_duration())

func _sync_track_duration_from_stream(track: TrackData, stream: AudioStream) -> void:
	var stream_length := stream.get_length()
	if stream_length <= 0.0:
		return

	var resolved_duration := maxi(1, int(ceil(stream_length)))
	if track.duration == resolved_duration and get_elapsed_seconds() <= resolved_duration:
		return

	track.duration = resolved_duration
	track.normalize()
	set_elapsed_seconds(clampi(get_elapsed_seconds(), 0, track.duration))
	save_app_state()

func _mark_playback_unavailable(track: TrackData) -> void:
	push_warning("Unable to play track \"%s\" with the currently supported audio loaders." % track.title)
	stop_audio_playback(true)
	if not is_playing():
		return
	set_is_playing(false)
	set_elapsed_seconds(track.preview_start)
	save_app_state()

func _get_audio_player() -> AudioStreamPlayer:
	var resolved_controller = get_showcase()
	return resolved_controller.audio_player if resolved_controller != null else null
