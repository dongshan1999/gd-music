class_name MusicAppPlaybackStateController
extends RefCounted

const MusicAppShowcaseControllerScript := preload("res://assets/scripts/ui/music_app/music_app_showcase.gd")
const MusicAppControllerBaseScript := preload("res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd")
const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const PlaybackStartedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STARTED_EVENT)
const PlaybackFinishedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_FINISHED_EVENT)
const PlaybackProgressChangedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_PROGRESS_CHANGED_EVENT)
const M4ADecoderScript := preload("res://assets/scripts/audio/music_app_m4a_decoder.gd")
const FFMPEG_CACHE_DIR := "gdmusic-ffmpeg-audio"

var controller

const SUPPORTED_AUDIO_LOADERS := ["mp3", "ogg", "wav"]
const REMOTE_STREAM_TIMEOUT_SECONDS := 20.0

var _audio_sync_request_id := 0
var _loaded_track_key := ""
var _pending_seek_track_key := ""
var _pending_seek_until_msec := 0
var last_error := ""

## 记录当前全局播放状态控制器所属的 showcase。
func _init(owner = null) -> void:
	controller = owner

func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

func _get_base_controller() -> MusicAppControllerBase:
	return MusicAppControllerBaseScript.new(controller)

func get_elapsed_seconds() -> int:
	return _get_base_controller().get_elapsed_seconds()

func set_elapsed_seconds(value: int) -> void:
	_get_base_controller().set_elapsed_seconds(value)

func is_playing() -> bool:
	return _get_base_controller().is_playing()

func set_is_playing(value: bool) -> void:
	_get_base_controller().set_is_playing(value)
	# Start the Android media session as soon as the queue enters the playing
	# state.  The stream loader is asynchronous, so waiting only for the final
	# player callback can leave the notification card absent when the decoder
	# finishes later or when the player is temporarily buffering.
	if value:
		var track: TrackData = get_current_track()
		if track != null:
			call_deferred("_ensure_background_audio_service", track)

func get_popup_router_controller():
	return _get_base_controller().get_popup_router_controller()

func get_playback_controller():
	return _get_base_controller().get_playback_controller()

## 绑定 Android 通知、耳机和锁屏媒体按钮。
func bind_background_audio_controls() -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null or not plugin.has_signal("media_control"):
		return
	var callback := Callable(self, "_on_background_media_control")
	if not plugin.is_connected("media_control", callback):
		plugin.connect("media_control", callback)

## 将 Android 媒体会话操作映射到同一套播放队列状态。
func _on_background_media_control(action: String) -> void:
	match action:
		"play":
			if not is_playing() and has_tracks():
				set_is_playing(true)
				request_audio_sync()
		"pause":
			if is_playing():
				set_is_playing(false)
				request_audio_sync()
		"toggle":
			toggle_playback()
		"next":
			var playback_controller = get_playback_controller()
			if playback_controller != null:
				playback_controller.step_queue(1, true)
		"previous":
			var playback_controller = get_playback_controller()
			if playback_controller != null:
				playback_controller.step_queue(-1, true)
		"stop":
			if is_playing():
				set_is_playing(false)
			stop_audio_playback(true)
			_loaded_track_key = ""

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
	_emit_playback_progress_changed()

## 将底层播放器与全局状态同步到指定秒数。
func seek_to_elapsed_seconds(value: int, _persist_state: bool = true) -> void:
	if not has_tracks():
		return

	var track := get_current_track()
	if track == null:
		return

	var duration := get_current_duration()
	# Seeking exactly to the stream length is treated as EOF by both Godot
	# players. Keep the cursor in the playable range so a progress-bar click
	# cannot be mistaken for natural completion of the current track.
	var max_seek_seconds := maxi(0, duration - 1)
	var target_seconds := clampi(value, 0, max_seek_seconds)
	if target_seconds == get_elapsed_seconds():
		return

	set_elapsed_seconds(target_seconds)

	var audio_player: Variant = _get_active_player()
	var desired_track_key := _get_track_playback_key(track)
	_pending_seek_track_key = desired_track_key
	_pending_seek_until_msec = Time.get_ticks_msec() + 750
	if audio_player != null and _player_has_stream(audio_player) and _loaded_track_key == desired_track_key:
		_apply_audio_seek(audio_player, target_seconds)
	elif is_playing():
		request_audio_sync()

	_emit_playback_progress_changed(track)

## 发起一次异步音频状态同步请求。
func request_audio_sync() -> void:
	_audio_sync_request_id += 1
	call_deferred("_sync_audio_state_deferred", _audio_sync_request_id)

## 每秒同步一次播放进度，并在状态变化时刷新界面。
func tick_playback_progress() -> void:
	var audio_player: Variant = _get_active_player()
	if audio_player == null:
		return

	if not has_tracks():
		if is_playing():
			set_is_playing(false)
			request_audio_sync()
		return

	if not is_playing() or not _player_has_stream(audio_player) or not audio_player.is_playing() or _player_is_paused(audio_player):
		return

	var next_elapsed := clampi(int(floor(_player_position(audio_player))), 0, get_current_duration())
	if next_elapsed == get_elapsed_seconds():
		return
	set_elapsed_seconds(next_elapsed)
	_update_background_playback_position()
	_emit_playback_progress_changed()

## 响应音频播放完成事件，自动切到队列下一首。
func on_audio_finished(source_player: Node = null) -> void:
	if not has_tracks() or not is_playing():
		return
	var active_player: Variant = _get_active_player()
	if source_player != null and source_player != active_player:
		return
	var finished_track := get_current_track()
	if finished_track == null:
		return
	var finished_track_key := _get_track_playback_key(finished_track)
	if finished_track_key == _pending_seek_track_key and Time.get_ticks_msec() <= _pending_seek_until_msec:
		# A seek can briefly make VideoStreamPlayer report `finished` while its
		# decoder is resynchronizing. The next natural completion after this
		# protection window will still advance the queue normally.
		request_audio_sync()
		return
	_pending_seek_track_key = ""
	_pending_seek_until_msec = 0
	_loaded_track_key = ""
	_emit_playback_finished(finished_track)
	var playback_controller = get_playback_controller()
	if playback_controller != null:
		playback_controller.advance_after_finish()

## 停止底层音频播放，并按需清空已挂载的音频流。
func stop_audio_playback(clear_stream: bool) -> void:
	var player: Variant = _get_active_player()
	if player == null:
		_stop_background_audio_service()
		return
	player.stop()
	_set_player_paused(player, false)
	_stop_background_audio_service()
	if clear_stream:
		_set_player_stream(player, null)
		_get_ffmpeg_player().stream = null

## 通过 deferred 调度一次异步音频状态同步。
func _sync_audio_state_deferred(sync_request_id: int) -> void:
	await _sync_audio_state(sync_request_id)

## 将全局播放状态与底层 AudioStreamPlayer 同步到一致状态。
func _sync_audio_state(sync_request_id: int) -> void:
	var audio_player: Variant = _get_active_player()
	if audio_player == null:
		return
	if sync_request_id != _audio_sync_request_id:
		return

	if not has_tracks():
		_loaded_track_key = ""
		stop_audio_playback(true)
		if is_playing():
			set_is_playing(false)
		return

	var track := get_current_track()
	if track == null:
		_loaded_track_key = ""
		stop_audio_playback(true)
		if is_playing():
			set_is_playing(false)
		return

	var desired_track_key := _get_track_playback_key(track)
	if not is_playing():
		if audio_player.is_playing() and not _player_is_paused(audio_player):
			var paused_elapsed := _get_audio_position_seconds()
			if paused_elapsed != get_elapsed_seconds():
				set_elapsed_seconds(paused_elapsed)
			_set_player_paused(audio_player, true)
			_pause_background_audio_service()
		elif _player_has_stream(audio_player) and _loaded_track_key != desired_track_key:
			_loaded_track_key = ""
			stop_audio_playback(true)
		return

	if _loaded_track_key == desired_track_key and _player_has_stream(audio_player):
		var did_start := false
		if not audio_player.is_playing():
			audio_player.play()
			if get_elapsed_seconds() > 0:
				_apply_audio_seek(audio_player, get_elapsed_seconds())
			did_start = true
		if _player_is_paused(audio_player):
			_set_player_paused(audio_player, false)
			did_start = true
		if did_start:
			_start_background_audio_service(track)
			_emit_playback_started(track)
			_emit_playback_progress_changed(track)
		return

	stop_audio_playback(true)
	_loaded_track_key = ""
	last_error = ""
	var stream: Variant = await _resolve_stream_for_track(track, sync_request_id)
	if sync_request_id != _audio_sync_request_id:
		return
	if stream == null:
		_loaded_track_key = ""
		_mark_playback_unavailable(track)
		return

	stop_audio_playback(false)
	var target_player: Variant = _get_audio_player()
	if stream is VideoStream:
		target_player = _get_ffmpeg_player()
	_set_player_stream(target_player, stream)
	audio_player = target_player
	_loaded_track_key = desired_track_key
	_sync_track_duration_from_stream(track, stream)
	audio_player.play()
	if get_elapsed_seconds() > 0:
		_apply_audio_seek(audio_player, get_elapsed_seconds())
	_set_player_paused(audio_player, false)
	_start_background_audio_service(track)
	_emit_playback_started(track)
	_emit_playback_progress_changed(track)

## 为当前曲目解析可播放音频流。
func _resolve_stream_for_track(track: TrackData, sync_request_id: int):
	if not track.file_path.is_empty():
		return _load_local_stream(track.file_path)
	if not track.plugin_id.is_empty():
		var plugins = _get_base_controller().get_plugin_controller()
		if plugins == null:
			return null
		var source: Dictionary = await plugins.get_media_source(track)
		if sync_request_id != _audio_sync_request_id:
			return null
		if source.is_empty():
			last_error = plugins.last_error
			return null
		var url := str(source.get("url", ""))
		if not _is_remote_stream_url(url):
			last_error = "插件返回了无效的音频地址。"
			return null
		var headers: Dictionary = source.get("headers", {}) if source.get("headers", {}) is Dictionary else {}
		# Let ordinary audio use AudioStreamPlayer first. FFmpeg remains the
		# fallback for containers that Godot's native loaders cannot decode.
		var format_hint := str(source.get("format", ""))
		var format_extension := _get_audio_extension(format_hint)
		if format_extension.is_empty():
			format_extension = _get_audio_extension(url)
		if format_extension.is_empty():
			format_extension = format_hint.to_lower().trim_prefix(".")
		if format_extension in ["m4a", "aac", "mp4"] and _ffmpeg_available() and OS.get_name() == "Android":
			return await _load_remote_ffmpeg_stream(url, headers, sync_request_id, track.id)
		# Test doubles and platform-specific loaders may override this method;
		# keep the normal route observable through the native audio path.
		var native_stream: AudioStream = await _load_remote_stream(url, headers, sync_request_id, "m4a" if format_extension in ["m4a", "aac", "mp4"] else format_extension)
		if native_stream != null or not _ffmpeg_available():
			return native_stream
		return await _load_remote_ffmpeg_stream(url, headers, sync_request_id, track.id)

	push_warning("Track \"%s\" does not have a local audio file path." % track.title)
	return null

## 从本地文件系统读取音频字节并解码为 AudioStream。
func _load_local_stream(path: String):
	if path.is_empty():
		return null

	var bytes := PackedByteArray()
	if DX != null and DX.files != null:
		var read_result: Dictionary = DX.files.read_bytes(path)
		if not bool(read_result.get("ok", false)):
			push_warning("Audio file is unreadable: %s. Error: %s" % [path, str(read_result.get("error", ""))])
			return null
		bytes = read_result.get("data", PackedByteArray())
	else:
		if not FileAccess.file_exists(path):
			push_warning("Audio file does not exist: %s" % path)
			return null
		bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("Audio file is empty or unreadable: %s" % path)
		return null

	var extension := _get_audio_extension(path)
	if _ffmpeg_available() and _should_use_ffmpeg_for_extension(extension):
		return _create_ffmpeg_stream_from_buffer(bytes, "local-" + str(abs(path.hash())))
	return _load_stream_from_buffer(bytes, extension)

## 通过 HTTP 下载远程音频流并解码为 AudioStream。
func _load_remote_stream(
	url: String,
	headers: Dictionary,
	sync_request_id: int,
	format_hint: String = ""
) -> AudioStream:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null

	var request := HTTPRequest.new()
	request.timeout = REMOTE_STREAM_TIMEOUT_SECONDS
	request.body_size_limit = 64 * 1024 * 1024
	resolved_controller.add_child(request)

	var err := request.request(url, _build_http_headers(headers), HTTPClient.METHOD_GET)
	if err != OK:
		last_error = "无法发起音频下载请求。"
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
		last_error = "音频下载失败，请检查网络或尝试较短的视频。"
		push_warning("Audio request failed for URL %s with result code %d." % [url, result_code])
		return null
	if response_code < 200 or response_code >= 300:
		last_error = "音频下载失败 (HTTP %d)，请重试。" % response_code
		push_warning("Audio request returned HTTP %d for URL: %s" % [response_code, url])
		return null
	if body.is_empty():
		last_error = "音频响应为空。"
		push_warning("Audio request returned an empty response body for URL: %s" % url)
		return null

	var extension := format_hint if not format_hint.is_empty() else _get_audio_extension(url)
	if extension in ["m4a", "aac", "mp4"] or (body.size() > 8 and body.slice(4, 8).get_string_from_ascii() == "ftyp"):
		var decoder := M4ADecoderScript.new()
		var stream: AudioStream = await decoder.decode(body, func() -> bool: return sync_request_id != _audio_sync_request_id or not is_instance_valid(resolved_controller) or not resolved_controller.is_inside_tree())
		last_error = decoder.last_error
		return stream
	return _load_stream_from_buffer(body, extension)

func _load_remote_ffmpeg_stream(url: String, headers: Dictionary, sync_request_id: int, cache_key: String):
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null
	var request := HTTPRequest.new()
	request.timeout = REMOTE_STREAM_TIMEOUT_SECONDS
	request.body_size_limit = 64 * 1024 * 1024
	resolved_controller.add_child(request)
	var err := request.request(url, _build_http_headers(headers), HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		last_error = "无法发起音频下载请求。"
		return null
	var signal_result: Array = await request.request_completed
	request.queue_free()
	if sync_request_id != _audio_sync_request_id:
		return null
	var body: PackedByteArray = signal_result[3]
	if int(signal_result[0]) != HTTPRequest.RESULT_SUCCESS or int(signal_result[1]) < 200 or int(signal_result[1]) >= 300 or body.is_empty():
		last_error = "音频下载失败，请重试。"
		return null
	return _create_ffmpeg_stream_from_buffer(body, cache_key)

func _create_ffmpeg_stream_from_buffer(body: PackedByteArray, cache_key: String):
	var directory := OS.get_cache_dir().path_join(FFMPEG_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var safe_key := cache_key.replace("/", "_").replace(":", "_")
	var path := directory.path_join(safe_key + ".audio")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入音频缓存。"
		return null
	file.store_buffer(body)
	file.close()
	var stream: Variant = ClassDB.instantiate("FFmpegVideoStream")
	if stream == null:
		last_error = "FFmpeg 音频扩展不可用。"
		return null
	stream.file = path
	return stream

## 按候选格式顺序尝试从二进制缓冲区构建音频流。
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

## 根据文件后缀生成音频解码器候选顺序。
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

## 将字典形式的请求头转换为 HTTPRequest 所需的字符串数组。
func _build_http_headers(headers: Dictionary) -> PackedStringArray:
	var formatted_headers := PackedStringArray()
	for key in headers.keys():
		formatted_headers.append("%s: %s" % [str(key), str(headers[key])])
	return formatted_headers

## 从路径或 URL 中提取音频资源扩展名。
func _get_audio_extension(path_or_url: String) -> String:
	var sanitized := path_or_url.split("?")[0].split("#")[0]
	# 插件可能直接返回裸扩展名（如 "m4a"），此时 get_extension() 为空。
	if not sanitized.contains("/") and not sanitized.contains("."):
		return sanitized.to_lower()
	return sanitized.get_extension().to_lower()

## 仅让原生不支持的容器进入 FFmpeg/VideoStreamPlayer。
func _should_use_ffmpeg_for_extension(extension: String) -> bool:
	var normalized := extension.to_lower().trim_prefix(".")
	return not SUPPORTED_AUDIO_LOADERS.has(normalized)

## 判断给定来源是否属于远程 HTTP 音频。
func _is_remote_stream_url(path_or_url: String) -> bool:
	return path_or_url.begins_with("http://") or path_or_url.begins_with("https://")

## 生成当前曲目的播放唯一键，用于判断是否需要重新装载音频流。
func _get_track_playback_key(track: TrackData) -> String:
	if not track.file_path.is_empty():
		return "file:%s" % track.file_path
	if not track.plugin_id.is_empty():
		return track.id
	return "title:%s:%s" % [track.title, track.artist]

## 在已存在的 AudioStreamPlayer 上应用 seek，并维持暂停/播放状态。
func _apply_audio_seek(audio_player, target_seconds: int) -> void:
	var should_resume := is_playing()
	var was_paused := _player_is_paused(audio_player)

	if audio_player.is_playing():
		if audio_player is VideoStreamPlayer:
			audio_player.stream_position = float(target_seconds)
		else:
			audio_player.seek(float(target_seconds))
	elif should_resume:
		audio_player.play()
		if target_seconds > 0:
			if audio_player is VideoStreamPlayer:
				audio_player.stream_position = float(target_seconds)
			else:
				audio_player.seek(float(target_seconds))

	_set_player_paused(audio_player, was_paused or not should_resume)

## 读取底层播放器当前秒数，并约束到曲目时长范围内。
func _get_audio_position_seconds() -> int:
	var audio_player: Variant = _get_active_player()
	if audio_player == null:
		return 0
	return clampi(int(floor(_player_position(audio_player))), 0, get_current_duration())

## 当底层流提供时长信息时，回写曲目时长并同步当前进度。
func _sync_track_duration_from_stream(track: TrackData, stream) -> void:
	var stream_length := 0.0
	if stream is VideoStream:
		var ffmpeg_player := _get_ffmpeg_player()
		if ffmpeg_player != null:
			stream_length = ffmpeg_player.get_stream_length()
	else:
		stream_length = stream.get_length()
	if stream_length <= 0.0:
		return

	var resolved_duration := maxi(1, int(ceil(stream_length)))
	if track.duration == resolved_duration and get_elapsed_seconds() <= resolved_duration:
		return

	track.duration = resolved_duration
	track.normalize()
	set_elapsed_seconds(clampi(get_elapsed_seconds(), 0, track.duration))
	_emit_playback_progress_changed(track)

## 在当前曲目无法播放时停止音频并回退到可恢复状态。
func _mark_playback_unavailable(track: TrackData) -> void:
	push_warning("Unable to play track \"%s\" with the currently supported audio loaders." % track.title)
	stop_audio_playback(true)
	if not last_error.is_empty():
		_get_base_controller().show_toast(last_error)
	if not is_playing():
		return
	set_is_playing(false)
	set_elapsed_seconds(track.preview_start)

## 返回 showcase 上实际承载播放的 AudioStreamPlayer。
func _get_audio_player() -> AudioStreamPlayer:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null
	var player: Variant = resolved_controller.get("audio_player")
	return player as AudioStreamPlayer

func _get_ffmpeg_player() -> VideoStreamPlayer:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null
	var player: Variant = resolved_controller.get("ffmpeg_player")
	return player as VideoStreamPlayer

## 返回 Android 后台播放插件；桌面平台不加载此桥接层。
func _get_background_audio_plugin() -> Variant:
	if OS.get_name() != "Android":
		return null
	var plugin: Variant = Engine.get_singleton("GDMusicBackgroundAudio")
	if plugin == null:
		push_warning("Android background audio plugin is not loaded.")
	return plugin

## 启动 Android 前台服务，提升 Godot 进程的后台存活优先级。
func _start_background_audio_service(track: TrackData) -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null:
		push_warning("Android media card not started: GDMusicBackgroundAudio plugin is unavailable.")
		return
	print("[MusicAppAudio] starting Android media card: ", track.title)
	if plugin.has_method("start"):
		plugin.start(track.title, track.artist if not track.artist.is_empty() else track.subtitle)
	if plugin.has_method("updatePlayback"):
		plugin.updatePlayback(
			track.title,
			track.artist if not track.artist.is_empty() else track.subtitle,
			get_elapsed_seconds(),
			get_current_duration(),
			is_playing()
		)

func _ensure_background_audio_service(track: TrackData) -> void:
	if not is_playing() or track == null:
		return
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null or not plugin.has_method("start"):
		return
	# This call is idempotent.  It makes the foreground service appear while
	# the remote stream is resolving; _sync_audio_state() updates it again with
	# the final duration and position after decoding succeeds.
	_start_background_audio_service(track)

## 停止 Android 前台服务并释放 CPU 唤醒锁。
func _stop_background_audio_service() -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null:
		return
	if plugin.has_method("stop"):
		plugin.stop()

## 暂停 Android 媒体会话但保留通知，方便从锁屏恢复播放。
func _pause_background_audio_service() -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null:
		return
	if plugin.has_method("pause"):
		plugin.pause()
	_update_background_playback_position()

func _update_background_playback_position() -> void:
	var plugin: Variant = _get_background_audio_plugin()
	var track := get_current_track()
	if plugin == null or track == null or not plugin.has_method("updatePlayback"):
		return
	plugin.updatePlayback(
		track.title,
		track.artist if not track.artist.is_empty() else track.subtitle,
		get_elapsed_seconds(),
		get_current_duration(),
		is_playing()
	)

func _ffmpeg_available() -> bool:
	return ClassDB.class_exists("FFmpegVideoStream") and _get_ffmpeg_player() != null

func _get_active_player():
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null
	var ffmpeg_player := _get_ffmpeg_player()
	if _ffmpeg_available() and ffmpeg_player != null and ffmpeg_player.stream != null:
		return ffmpeg_player
	return _get_audio_player()

func _player_has_stream(player) -> bool:
	return player != null and player.stream != null

func _player_is_paused(player) -> bool:
	return bool(player.paused) if player is VideoStreamPlayer else bool(player.stream_paused)

func _set_player_paused(player, value: bool) -> void:
	if player is VideoStreamPlayer:
		player.paused = value
	else:
		player.stream_paused = value

func _set_player_stream(player, stream) -> void:
	player.stream = stream

func _player_position(player) -> float:
	return float(player.stream_position) if player is VideoStreamPlayer else float(player.get_playback_position())

func _emit_playback_started(track = null) -> void:
	var resolved_track = track if track != null else get_current_track()
	if resolved_track == null:
		return
	DX.signals.fire(PlaybackStartedEventScript.new(resolved_track))

func _emit_playback_finished(track = null) -> void:
	var resolved_track = track if track != null else get_current_track()
	if resolved_track == null:
		return
	DX.signals.fire(PlaybackFinishedEventScript.new(resolved_track))

func _emit_playback_progress_changed(track = null) -> void:
	var resolved_track = track if track != null else get_current_track()
	if resolved_track == null:
		return
	DX.signals.fire(
		PlaybackProgressChangedEventScript.new(
			resolved_track,
			get_elapsed_seconds(),
			get_current_duration()
		)
	)
