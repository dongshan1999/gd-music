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
## SAF 本地曲目落盘缓存目录：mpv 只认文件系统路径，需先把授权目录里的文件读出来。
const LOCAL_SOURCE_CACHE_DIR := "gdmusic-local-source"
## 本地曲目内嵌封面解出来的小图缓存目录（必须带 user://，Android 上相对路径会解析到根目录）。
const LOCAL_ARTWORK_CACHE_DIR := "user://gdmusic-artwork"
const AudioArtworkReaderScript := preload("res://assets/scripts/save/music/audio_artwork_reader.gd")
## Phase 1 播放后端抽象层：默认不使用，gdmpv 扩展可用时由工厂自动接管。
const AudioBackendFactoryScript := preload("res://assets/scripts/ui/music_app/audio/audio_backend_factory.gd")

var controller

const SUPPORTED_AUDIO_LOADERS := ["mp3", "ogg", "wav"]
const REMOTE_STREAM_TIMEOUT_SECONDS := 20.0

var _audio_sync_request_id := 0
var _loaded_track_key := ""
var _pending_seek_track_key := ""
var _pending_seek_until_msec := 0
var last_error := ""

## Phase 1 播放后端：null = 沿用 Godot 原生播放器（AudioStreamPlayer / FFmpegVideoStream）。
var _audio_backend: Variant = null
var _audio_backend_probed := false

## Android 前台服务节流：Android 12+ 如果在服务执行 startForeground() 之前又收到一次
## startForegroundService()，会把前一个 ServiceRecord 直接拉下，并抛
## RemoteServiceException(ForegroundServiceDidNotStartInTime) 杀掉进程。
## 因此同一状态下短时间内的重复请求必须合并成一次。
const BACKGROUND_ACTION_MIN_INTERVAL_MSEC := 600
var _background_action_key := ""
var _background_action_at_msec := 0
## Android 13+ 通知权限只申请一次。
var _notification_permission_requested := false
## 通知栏封面：当前曲目的封面来源与已下载字节缓存。
var _notification_artwork_source := ""
## 上一次推过封面的曲目 id；换到没有封面的曲目时要主动清空，避免沿用上一首的图。
var _notification_artwork_track_key := ""
var _artwork_bytes_cache: Dictionary = {}
var _artwork_inflight: Dictionary = {}
## 本地曲目内嵌封面：file_path 的 md5 -> 缓存图片路径（找不到时记空串，避免反复解析）。
var _local_artwork_sources: Dictionary = {}
## 播放音量（线性 0–1），与后端解耦后统一折算成 dB 下发。
var playback_volume := 1.0
var _playback_volume_loaded := false

## 后台播放连续失败熔断：解码器持续加载失败时不再自动跳歌，
## 否则会在几十毫秒内切光整个队列，并放大多次前台服务启动。
## 通知栏/锁屏封面：统一缩到 512px 长边再编成 JPEG，避免超过 Binder 事务上限。
const ARTWORK_MAX_EDGE := 512
const ARTWORK_JPEG_QUALITY := 0.85
const ARTWORK_TIMEOUT_SECONDS := 10.0
## 播放设置（音量）持久化位置。
const PLAYBACK_SETTINGS_PATH := "user://music_app_settings.cfg"
const BACKGROUND_ERROR_STREAK_LIMIT := 3
const BACKGROUND_ERROR_STREAK_WINDOW_MSEC := 8000
var _background_error_timestamps: Array[int] = []

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
	# 锁屏/通知栏拖动进度条：服务回传 `seek_to:<毫秒>`。
	# 同样不能只靠 seek_to_elapsed_seconds()：它命中「已加载同一首」分支才会直接 seek，
	# 否则走 request_audio_sync() 的 deferred 链路，后台主循环不推进时拖了等于没拖。
	if action.begins_with("seek_to:"):
		var millis := int(action.trim_prefix("seek_to:"))
		if millis >= 0:
			var target_seconds := int(millis / 1000.0)
			set_elapsed_seconds(target_seconds)
			_apply_immediate_seek(target_seconds)
			request_audio_sync()
		return
	match action:
		"play":
			if not is_playing() and has_tracks():
				set_is_playing(true)
				# ⚠ 这个回调是 Java 线程经由 GodotPlugin.emitSignal 同步调进来的，
				# 而 App 退到后台后 Godot 主循环基本不再推进，request_audio_sync()
				# 里的 call_deferred 可能永远排不上队 —— 表现为「点了暂停/播放，
				# 通知栏图标变了但声音不动」。所以这里必须绕过 deferred，直接对
				# 底层播放器下发一次同步指令（GDMPVPlayer 内部有 mutex，可跨线程）。
				var ready_player: Variant = _get_active_player()
				if ready_player != null and _player_has_stream(ready_player):
					_apply_immediate_transport(true)
				else:
					_apply_immediate_load()
				request_audio_sync()
		"pause":
			if is_playing():
				set_is_playing(false)
				_apply_immediate_transport(false)
				request_audio_sync()
		"toggle":
			toggle_playback()
		"next":
			var playback_controller = get_playback_controller()
			if playback_controller != null and playback_controller.step_queue(1, true):
				# 切歌要换源，纯粹靠 deferred 在后台不会执行，这里同步把新曲目交给 mpv。
				_apply_immediate_load()
		"previous":
			var playback_controller = get_playback_controller()
			if playback_controller != null and playback_controller.step_queue(-1, true):
				_apply_immediate_load()
		"stop":
			if is_playing():
				set_is_playing(false)
			stop_audio_playback(true)
			_loaded_track_key = ""

## 后台媒体按钮专用：同步把播放位置跳到指定秒数（拖动通知栏进度条）。
func _apply_immediate_seek(target_seconds: int) -> void:
	var player: Variant = _get_active_player()
	if player == null or not _player_has_stream(player):
		return
	var target := float(target_seconds)
	var duration := float(get_current_duration())
	if duration > 1.0:
		# 正好 seek 到结尾会被当成自然播完，留 1 秒余量。
		target = clampf(target, 0.0, maxf(0.0, duration - 1.0))
	player.seek(target)
	_push_background_seek_position(int(target))


## 拖动进度条后立刻把新位置推给通知栏/锁屏的 PlaybackState。
## 不能走 _dispatch_background_action()：它的节流 key 是「曲目|艺人|播放态|时长」，
## 位置不在 key 里，同一个曲目内的拖动会被整段节流掉，Java 侧就会继续用旧基准外推。
func _push_background_seek_position(seconds: int) -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null or not _plugin_has_java_method(plugin, "updatePlayback"):
		return
	var track := get_current_track()
	if track == null:
		return
	var title := track.title
	var artist := track.artist if not track.artist.is_empty() else track.subtitle
	var duration := get_current_duration()
	if duration <= 0:
		duration = _get_streaming_duration_seconds()
	var playing := is_playing()
	plugin.updatePlayback(title, artist, seconds, duration, playing)
	# 与节流状态对齐，避免紧接着的 tick 又把旧位置推回去。
	_background_action_key = "%s|%s|%s|%s" % [title, artist, playing, duration]
	_background_action_at_msec = Time.get_ticks_msec()

## 后台媒体按钮专用：同步把「当前选中的曲目」直接交给播放器并开播。
## 覆盖本地文件与已下载文件；远端直链要先等插件解析，退回 deferred 链路。
func _apply_immediate_load() -> void:
	var player: Variant = _get_active_player()
	var track := get_current_track()
	if player == null or track == null:
		return
	var url := ""
	if not track.file_path.is_empty():
		url = track.file_path
		if _is_virtual_local_path(url):
			url = _materialize_local_source(url)
	else:
		var downloads = _get_base_controller().get_download_controller()
		if downloads != null:
			var record = downloads.get_download_record(track.id)
			if record != null and not record.path.is_empty():
				url = record.path
	if url.is_empty():
		request_audio_sync()
		return
	if _player_has_stream(player):
		player.stop()
	var err: int = int(player.load_source(url, {}))
	if err != OK:
		printerr("[MusicAppAudio] immediate load failed err=", err)
		request_audio_sync()
		return
	_loaded_track_key = _get_track_playback_key(track)
	set_elapsed_seconds(0)
	player.play()
	_start_background_audio_service(track)

## 后台媒体按钮专用：不经过 deferred，直接给底层播放器下播放/暂停指令。
## 只在「已加载同一首曲目」的前提下使用，避免和 load/seek 链路抢状态。
func _apply_immediate_transport(playing: bool) -> void:
	var player: Variant = _get_active_player()
	if player == null or not _player_has_stream(player):
		return
	if playing:
		if _player_is_paused(player):
			_set_player_paused(player, false)
		if not player.is_playing():
			player.play()
	else:
		if player.is_playing() and not _player_is_paused(player):
			_set_player_paused(player, true)

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
	# 后台连续加载失败时熔断，避免一次坏流把整队列在几十毫秒内全部跳过、
	# 并顺带放大多次前台服务启动（Android 上就是闪退）。
	if _is_background_error_streak_exceeded():
		push_warning("[MusicAppAudio] playback stopped: %d consecutive load failures." % _background_error_timestamps.size())
		set_is_playing(false)
		last_error = "连续多首音频加载失败，已停止自动切歌。"
		return
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
	# libmpv 流式后端：把来源直接交给 mpv，跳过「整首下载 → 解码成 AudioStream」的旧链路。
	if _is_streaming_backend(audio_player):
		await _sync_streaming_playback(audio_player, track, desired_track_key, sync_request_id)
		return
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
		return await _load_local_stream(track.file_path)
	# 已下载的插件曲目优先读本地文件，避免再次请求 playurl 与 CDN。
	var downloads = _get_base_controller().get_download_controller()
	if downloads != null:
		var download_record = downloads.get_download_record(track.id)
		if download_record != null and not download_record.path.is_empty():
			var downloaded_stream = await _load_local_stream(download_record.path)
			if sync_request_id != _audio_sync_request_id:
				return null
			if downloaded_stream != null:
				return downloaded_stream
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
	# 本地 m4a/AAC 在桌面端必须经系统解码后端（macOS afconvert / FFmpeg），
	# Godot 原生加载器不支持 AAC；下载功能落盘的正是 m4a。
	if extension in ["m4a", "aac", "mp4"] or (bytes.size() > 8 and bytes.slice(4, 8).get_string_from_ascii() == "ftyp"):
		var decoder := M4ADecoderScript.new()
		var decoded_stream: AudioStream = await decoder.decode(bytes, func() -> bool: return false)
		if decoded_stream != null:
			return decoded_stream
		last_error = decoder.last_error
		if not _ffmpeg_available():
			push_warning("Local m4a decode failed for %s: %s" % [path, last_error])
			return null
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
	var downloads = _get_base_controller().get_download_controller()
	if downloads != null and downloads.has_download(track.id):
		return "download:%s" % track.id
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

## 是否为流式音频后端（libmpv 等）。这类后端自己管理解码与缓冲，
## 不需要控制器把整首歌读成 AudioStream。
func _is_streaming_backend(player) -> bool:
	return player != null and player.has_method("load_source")

## 流式后端的播放状态同步：来源直通后端，不做整首下载与解码。
func _sync_streaming_playback(
	audio_player: Variant,
	track: TrackData,
	desired_track_key: String,
	sync_request_id: int
) -> void:
	# 已加载同一首歌：只协调播放/暂停，必要时补一次 seek。
	if _loaded_track_key == desired_track_key and _player_has_stream(audio_player):
		if not is_playing():
			if audio_player.is_playing() and not _player_is_paused(audio_player):
				var paused_elapsed := _get_audio_position_seconds()
				if paused_elapsed != get_elapsed_seconds():
					set_elapsed_seconds(paused_elapsed)
				_set_player_paused(audio_player, true)
				_pause_background_audio_service()
			return
		# 已经播到结尾：mpv 此时既不 playing 也不 paused（区别于用户手动暂停）。
		# 这里必须直接返回，交给 finished 信号去切下一首；若在这里补 play()，
		# mpv 会从头重播当前曲目，表现为「一首歌播完不切歌、原地循环」。
		if not audio_player.is_playing() and not _player_is_paused(audio_player):
			return
		var did_start := false
		if not audio_player.is_playing():
			audio_player.play()
			if get_elapsed_seconds() > 0:
				audio_player.seek(float(get_elapsed_seconds()))
			did_start = true
		if _player_is_paused(audio_player):
			_set_player_paused(audio_player, false)
			did_start = true
		if did_start:
			_start_background_audio_service(track)
			_emit_playback_started(track)
			_emit_playback_progress_changed(track)
		return

	if not is_playing():
		if _player_has_stream(audio_player) or _loaded_track_key == desired_track_key:
			_loaded_track_key = ""
			stop_audio_playback(true)
		return

	stop_audio_playback(true)
	_loaded_track_key = ""
	last_error = ""
	var source: Dictionary = await _resolve_streaming_source(track, sync_request_id)
	if sync_request_id != _audio_sync_request_id:
		return
	if source.is_empty():
		_loaded_track_key = ""
		_mark_playback_unavailable(track)
		return

	var url := str(source.get("url", ""))
	var headers: Dictionary = source.get("headers", {}) if source.get("headers", {}) is Dictionary else {}
	var load_err: int = int(audio_player.load_source(url, headers))
	if load_err != OK:
		last_error = str(audio_player.get_last_error())
		_loaded_track_key = ""
		_mark_playback_unavailable(track)
		return

	_loaded_track_key = desired_track_key
	audio_player.play()
	_clear_background_errors()
	if get_elapsed_seconds() > 0:
		audio_player.seek(float(get_elapsed_seconds()))
	_sync_track_duration_from_backend(track, audio_player)
	_start_background_audio_service(track)
	_emit_playback_started(track)
	_emit_playback_progress_changed(track)

## 解析流式后端要播放的来源：本地文件、已下载文件、或插件返回的直链。
func _resolve_streaming_source(track: TrackData, sync_request_id: int) -> Dictionary:
	if not track.file_path.is_empty():
		var local_path := track.file_path
		if _is_virtual_local_path(local_path):
			local_path = _materialize_local_source(local_path)
			if local_path.is_empty():
				return {}
		return {"url": local_path, "headers": {}}
	var downloads = _get_base_controller().get_download_controller()
	if downloads != null:
		var download_record = downloads.get_download_record(track.id)
		if download_record != null and not download_record.path.is_empty():
			return {"url": download_record.path, "headers": {}}
	if not track.plugin_id.is_empty():
		var plugins = _get_base_controller().get_plugin_controller()
		if plugins == null:
			return {}
		var source: Dictionary = await plugins.get_media_source(track)
		if sync_request_id != _audio_sync_request_id:
			return {}
		if source.is_empty():
			last_error = plugins.last_error
			return {}
		var url := str(source.get("url", ""))
		if url.is_empty():
			last_error = "插件返回了空的音频地址。"
			return {}
		var headers: Dictionary = source.get("headers", {}) if source.get("headers", {}) is Dictionary else {}
		return {"url": url, "headers": headers}
	push_warning("Track \"%s\" does not have a playable source." % track.title)
	return {}

## 判断路径是不是 Android SAF 之类的虚拟路径（mpv 只认真实文件系统路径）。
func _is_virtual_local_path(path: String) -> bool:
	return path.begins_with("saf-file://") or path.begins_with("saf-tree://") or path.begins_with("content://")

## 把 SAF 曲目落成缓存文件并返回真实路径。
## 本地音乐保存在 Android 的 SAF 授权目录里（saf-tree://content://...），
## mpv 无法直接打开这类 URI，必须经 DX 文件层读出字节再写到缓存目录。
func _materialize_local_source(path: String) -> String:
	var directory := OS.get_cache_dir().path_join(LOCAL_SOURCE_CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var extension := _get_audio_extension(path)
	if extension.is_empty():
		extension = "audio"
	var target := directory.path_join("local-%s.%s" % [path.md5_text(), extension])
	if FileAccess.file_exists(target):
		var cached := FileAccess.open(target, FileAccess.READ)
		if cached != null:
			var cached_length := cached.get_length()
			cached.close()
			if cached_length > 0:
				_ensure_local_artwork(path, target)
				return target
	var bytes := PackedByteArray()
	if DX != null and DX.files != null:
		var read_result: Dictionary = DX.files.read_bytes(path)
		if not bool(read_result.get("ok", false)):
			last_error = "无法读取本地音频：%s" % str(read_result.get("error", ""))
			push_warning("Local audio is unreadable: %s" % path)
			return ""
		bytes = read_result.get("data", PackedByteArray())
	else:
		bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		last_error = "本地音频为空或不可读。"
		push_warning("Local audio is empty: %s" % path)
		return ""
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入本地音频缓存。"
		return ""
	file.store_buffer(bytes)
	file.close()
	_ensure_local_artwork(path, target)
	return target

## 从本地音频的标签里抽出内嵌封面，落盘成图片文件并返回其路径。
## 结果按 file_path 缓存在内存里（包括「确实没有封面」的情况），避免每次刷新都重读文件。
func _ensure_local_artwork(source_path: String, real_path: String) -> String:
	if source_path.is_empty():
		return ""
	var cache_key := source_path.md5_text()
	if _local_artwork_sources.has(cache_key):
		var known := str(_local_artwork_sources[cache_key])
		if known.is_empty() or FileAccess.file_exists(known):
			return known
		_local_artwork_sources.erase(cache_key)
	var resolved_path := real_path if not real_path.is_empty() else source_path
	if not FileAccess.file_exists(resolved_path):
		return ""
	var artwork: Dictionary = AudioArtworkReaderScript.read_embedded_artwork(resolved_path)
	var data: PackedByteArray = artwork.get("data", PackedByteArray())
	if data.is_empty():
		_local_artwork_sources[cache_key] = ""
		return ""
	var extension := "jpg"
	match str(artwork.get("mime", "")):
		"image/png":
			extension = "png"
		"image/webp":
			extension = "webp"
		"image/gif":
			extension = "gif"
	DirAccess.make_dir_recursive_absolute(LOCAL_ARTWORK_CACHE_DIR)
	var target := LOCAL_ARTWORK_CACHE_DIR.path_join("%s.%s" % [cache_key, extension])
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		_local_artwork_sources[cache_key] = ""
		return ""
	file.store_buffer(data)
	file.close()
	_local_artwork_sources[cache_key] = target
	return target

## 流式后端的时长在开始播放后才可用，延迟回读一次并回写曲目。
func _sync_track_duration_from_backend(track: TrackData, backend: Variant) -> void:
	if track == null or backend == null:
		return
	var host = get_showcase()
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	await host.get_tree().create_timer(0.6).timeout
	if not is_instance_valid(track) or not is_instance_valid(backend):
		return
	if backend != _get_active_player():
		return
	var stream_length := float(backend.get_duration())
	if stream_length <= 0.5:
		return
	var resolved_duration := maxi(1, int(ceil(stream_length)))
	if track.duration == resolved_duration:
		return
	track.duration = resolved_duration
	track.normalize()
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

## JNISingleton 暴露的 Java 方法不会进入 ClassDB，has_method() 对其恒为 false。
## 判断 Java 方法是否存在必须走 has_java_method()（见 platform/android/api/jni_singleton.cpp）。
func _plugin_has_java_method(plugin: Variant, method: String) -> bool:
	if plugin == null:
		return false
	if plugin.has_method("has_java_method"):
		return bool(plugin.has_java_method(method))
	return true

## 统一的 Android 前台服务派发入口。
## Android 12+ 对 startForegroundService() 有严格时序要求：服务还没执行
## startForeground() 时再来一次启动，系统会把前一个 ServiceRecord 直接拉下并抛
## RemoteServiceException(ForegroundServiceDidNotStartInTime) 杀掉进程。
## 旧实现里 start() 与 updatePlayback() 各调一次 startForegroundService，
## 且 set_is_playing() 与 _sync_* 会重复触发，一次点击就连发数次，必然崩溃。
## 现在统一收敛到 updatePlayback() 一条路径，并按「曲目+状态」节流。
func _dispatch_background_action(action: String, track: TrackData) -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null:
		# 桌面平台本就没有该插件，静默跳过；只在 Android 上提示缺失。
		if OS.get_name() == "Android":
			push_warning("Android media card not started: GDMusicBackgroundAudio plugin is unavailable.")
		return
	var title := ""
	var artist := ""
	if track != null:
		title = track.title
		artist = track.artist if not track.artist.is_empty() else track.subtitle
	var playing := is_playing()
	if action == "pause":
		playing = false
	var now := Time.get_ticks_msec()

	if action == "stop":
		# 刚启动或刚更新过的服务不要立刻停止：那会在 startForeground() 之前把服务
		# 记录拉下（日志 Bringing down service while still waiting for start foreground），
		# 之后系统照样按超时杀进程。
		if now - _background_action_at_msec < BACKGROUND_ACTION_MIN_INTERVAL_MSEC:
			return
		_background_action_key = ""
		_background_action_at_msec = now
		if _plugin_has_java_method(plugin, "stop"):
			plugin.stop()
		return

	# 时长缺失时通知栏画不出可拖动进度条，流式后端能给出准确时长就补上。
	var duration := get_current_duration()
	if duration <= 0:
		duration = _get_streaming_duration_seconds()
	var key := "%s|%s|%s|%s" % [title, artist, playing, duration]
	if key == _background_action_key and now - _background_action_at_msec < BACKGROUND_ACTION_MIN_INTERVAL_MSEC:
		return
	_background_action_key = key
	_background_action_at_msec = now

	if action == "pause" and _plugin_has_java_method(plugin, "pause"):
		plugin.pause()
		return
	if not _plugin_has_java_method(plugin, "updatePlayback"):
		# 兼容只实现 start() 的旧版插件。
		if _plugin_has_java_method(plugin, "start"):
			plugin.start(title, artist)
		return
	if not _notification_permission_requested and _plugin_has_java_method(plugin, "requestNotificationPermission"):
		_notification_permission_requested = true
		plugin.requestNotificationPermission()
	plugin.updatePlayback(
		title,
		artist,
		get_elapsed_seconds(),
		duration,
		playing
	)
	_push_notification_artwork(track)

## 流式后端（mpv）开始播放后才有时长，通知栏与锁屏需要它来画进度条。
func _get_streaming_duration_seconds() -> int:
	var backend: Variant = _get_audio_backend()
	if backend == null or not _is_streaming_backend(backend):
		return 0
	var seconds := float(backend.get_duration())
	if seconds <= 0.5:
		return 0
	return maxi(1, int(ceil(seconds)))

## 启动 Android 前台服务，提升 Godot 进程的后台存活优先级。
func _start_background_audio_service(track: TrackData) -> void:
	_dispatch_background_action("start", track)

func _ensure_background_audio_service(track: TrackData) -> void:
	if not is_playing() or track == null:
		return
	# 幂等：只是让通知在远程流解析期间就出现，重复调用会被节流合并。
	_dispatch_background_action("start", track)

## 停止 Android 前台服务并释放 CPU 唤醒锁。
func _stop_background_audio_service() -> void:
	_dispatch_background_action("stop", get_current_track())

## 暂停 Android 媒体会话但保留通知，方便从锁屏恢复播放。
func _pause_background_audio_service() -> void:
	_dispatch_background_action("pause", get_current_track())

func _update_background_playback_position() -> void:
	_dispatch_background_action("update", get_current_track())

func _ffmpeg_available() -> bool:
	return ClassDB.class_exists("FFmpegVideoStream") and _get_ffmpeg_player() != null

func _get_active_player():
	var backend: Variant = _get_audio_backend()
	if backend != null:
		return backend
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return null
	var ffmpeg_player := _get_ffmpeg_player()
	if _ffmpeg_available() and ffmpeg_player != null and ffmpeg_player.stream != null:
		return ffmpeg_player
	return _get_audio_player()

## 懒创建播放后端。只在首次取播放器时探测一次，避免每帧重复尝试。
## 返回 null 表示「继续用 Godot 原生播放器」，与改造前行为完全一致。
func _get_audio_backend() -> Variant:
	if _audio_backend_probed:
		return _audio_backend
	_audio_backend_probed = true
	var host = get_showcase()
	if host == null:
		return null
	_audio_backend = AudioBackendFactoryScript.try_create(host)
	if _audio_backend == null:
		return null
	if not _audio_backend.finished.is_connected(_on_backend_finished):
		_audio_backend.finished.connect(_on_backend_finished)
	if not _audio_backend.error_occurred.is_connected(_on_backend_error):
		_audio_backend.error_occurred.connect(_on_backend_error)
	_ensure_playback_volume_applied()
	return _audio_backend

func _on_backend_finished() -> void:
	on_audio_finished(null)

func _on_backend_error(message: String) -> void:
	push_warning("[MusicAppAudio] 播放后端报错：%s" % message)
	_record_background_error()

## 记录一次后端加载失败，只保留熔断窗口内的时间戳。
func _record_background_error() -> void:
	var now := Time.get_ticks_msec()
	var fresh: Array[int] = []
	for stamp in _background_error_timestamps:
		if now - stamp <= BACKGROUND_ERROR_STREAK_WINDOW_MSEC:
			fresh.append(stamp)
	fresh.append(now)
	_background_error_timestamps = fresh

## 熔断窗口内失败次数是否已达上限。
func _is_background_error_streak_exceeded() -> bool:
	return _background_error_timestamps.size() >= BACKGROUND_ERROR_STREAK_LIMIT

## 播放成功推进后清空失败计数，让后续的偶发失败重新计数。
func _clear_background_errors() -> void:
	if not _background_error_timestamps.is_empty():
		_background_error_timestamps.clear()

func _player_has_stream(player) -> bool:
	if player == null:
		return false
	if player.has_method("has_stream"):
		return bool(player.has_stream())
	return player.stream != null

func _player_is_paused(player) -> bool:
	if player == null:
		return true
	if player.has_method("is_paused"):
		return bool(player.is_paused())
	return bool(player.paused) if player is VideoStreamPlayer else bool(player.stream_paused)

func _set_player_paused(player, value: bool) -> void:
	if player == null:
		return
	if player.has_method("set_paused"):
		player.set_paused(value)
		return
	if player is VideoStreamPlayer:
		player.paused = value
	else:
		player.stream_paused = value

func _set_player_stream(player, stream) -> void:
	if player == null:
		return
	# 流式后端没有 stream 属性；「清空流」等价于停止并释放当前来源。
	if _is_streaming_backend(player):
		if stream == null:
			_set_player_paused(player, false)
			player.stop()
		return
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

## ---------------------------------------------------------------
## 通知栏 / 锁屏封面
## ---------------------------------------------------------------

## 把曲目封面推给 Android 前台服务；同一首只推一次，失败静默降级。
func _push_notification_artwork(track: TrackData) -> void:
	var plugin: Variant = _get_background_audio_plugin()
	if plugin == null or not _plugin_has_java_method(plugin, "updateArtwork"):
		return
	var source := get_track_artwork_source(track)
	var track_key := "" if track == null else str(track.id)
	if track_key == _notification_artwork_track_key and source == _notification_artwork_source:
		return
	_notification_artwork_track_key = track_key
	_notification_artwork_source = source
	if source.is_empty():
		# 这一首没有封面：把上一首的大图清掉，否则通知栏会一直挂着旧封面。
		plugin.updateArtwork("")
		return
	var encoded := await _resolve_artwork_payload(source)
	if encoded.is_empty() or source != _notification_artwork_source:
		return
	if _get_background_audio_plugin() != plugin:
		return
	plugin.updateArtwork(encoded)

## 返回曲目的封面来源（URL 或本地图片路径）；插件只给了封面文件名时再按本地标签兜底。
func get_track_artwork_source(track: TrackData) -> String:
	var plugin_source := _get_plugin_artwork_source(track)
	if not plugin_source.is_empty():
		return plugin_source
	return _get_local_embedded_artwork_source(track)

## 读取插件结果里的封面地址；协议相对地址补成 https。
func _get_plugin_artwork_source(track: TrackData) -> String:
	if track == null or not (track.plugin_data is Dictionary):
		return ""
	var source := str(track.plugin_data.get("artwork", "")).strip_edges()
	if source.is_empty():
		return ""
	if source.begins_with("//"):
		return "https:" + source
	return source

## 本地曲目：优先用已物化的缓存文件解析内嵌封面；真实路径可直接读。
func _get_local_embedded_artwork_source(track: TrackData) -> String:
	if track == null:
		return ""
	var file_path := track.file_path.strip_edges()
	if file_path.is_empty():
		return ""
	if file_path.begins_with("http://") or file_path.begins_with("https://"):
		return ""
	var cache_key := file_path.md5_text()
	if _local_artwork_sources.has(cache_key):
		return str(_local_artwork_sources[cache_key])
	if not _is_virtual_local_path(file_path) and FileAccess.file_exists(file_path):
		return _ensure_local_artwork(file_path, file_path)
	# 播放时物化过的 SAF 曲目：缓存文件已经存在，直接从中抽封面。
	var extension := _get_audio_extension(file_path)
	if extension.is_empty():
		extension = "audio"
	var materialized := OS.get_cache_dir().path_join(LOCAL_SOURCE_CACHE_DIR).path_join(
		"local-%s.%s" % [cache_key, extension]
	)
	if FileAccess.file_exists(materialized):
		return _ensure_local_artwork(file_path, materialized)
	return ""

## 取封面并归一化成 base64 JPEG；带进程内缓存，避免反复下载。
func _resolve_artwork_payload(source: String) -> String:
	if _artwork_bytes_cache.has(source):
		return str(_artwork_bytes_cache[source])
	if _artwork_inflight.has(source):
		return ""
	_artwork_inflight[source] = true
	var encoded := ""
	var raw := await _read_artwork_bytes(source)
	_artwork_inflight.erase(source)
	if not raw.is_empty():
		encoded = _encode_artwork(raw)
	if not encoded.is_empty():
		_artwork_bytes_cache[source] = encoded
	return encoded

## 按来源类型读取封面原始字节。
func _read_artwork_bytes(source: String) -> PackedByteArray:
	if source.begins_with("http://") or source.begins_with("https://"):
		return await _download_artwork_bytes(source)
	if source.begins_with("saf-file://") or source.begins_with("saf-tree://") or source.begins_with("content://"):
		var read_result: Variant = DX.files.read_bytes(source)
		if read_result is Dictionary:
			return read_result.get("data", PackedByteArray())
		return read_result if read_result is PackedByteArray else PackedByteArray()
	if FileAccess.file_exists(source):
		return FileAccess.get_file_as_bytes(source)
	return PackedByteArray()

## 下载远端封面字节。
func _download_artwork_bytes(url: String) -> PackedByteArray:
	var host: Node = get_showcase() as Node
	if host == null or not is_instance_valid(host):
		return PackedByteArray()
	var request := HTTPRequest.new()
	request.timeout = ARTWORK_TIMEOUT_SECONDS
	host.add_child(request)
	var err := request.request(url)
	if err != OK:
		request.queue_free()
		return PackedByteArray()
	var signal_result: Array = await request.request_completed
	if is_instance_valid(request):
		request.queue_free()
	if int(signal_result[0]) != HTTPRequest.RESULT_SUCCESS:
		return PackedByteArray()
	var code := int(signal_result[1])
	if code < 200 or code >= 300:
		return PackedByteArray()
	return signal_result[3]

## 解码图片、限制长边到 512px，再编码成 base64 JPEG。
func _encode_artwork(raw: PackedByteArray) -> String:
	var image := Image.new()
	var loaded := false
	for loader in ["load_jpg_from_buffer", "load_png_from_buffer", "load_webp_from_buffer"]:
		if image.call(loader, raw) == OK:
			loaded = true
			break
	if not loaded or image.is_empty():
		return ""
	if image.is_compressed():
		image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return ""
	var longest := maxi(width, height)
	if longest > ARTWORK_MAX_EDGE:
		var scale := float(ARTWORK_MAX_EDGE) / float(longest)
		var target_width := maxi(1, int(round(float(width) * scale)))
		var target_height := maxi(1, int(round(float(height) * scale)))
		image.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)
	return Marshalls.raw_to_base64(image.save_jpg_to_buffer(ARTWORK_JPEG_QUALITY))

## ---------------------------------------------------------------
## 音量
## ---------------------------------------------------------------

## 返回当前音量（线性 0–1）。
func get_playback_volume() -> float:
	return playback_volume

## 设置音量并立即下发到当前播放后端，同时持久化。
func set_playback_volume(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, playback_volume):
		return
	playback_volume = clamped
	_apply_playback_volume()
	_save_playback_settings()

## 把音量折算成 dB 交给后端；0 视为静音（-80 dB 而不是 -inf）。
func _apply_playback_volume() -> void:
	var db := linear_to_db(playback_volume) if playback_volume > 0.001 else -80.0
	var player = _get_active_player()
	if player == null:
		return
	if _is_streaming_backend(player):
		if _audio_backend != null and _audio_backend.has_method("set_volume_db"):
			_audio_backend.set_volume_db(db)
		return
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).volume_db = db

## 首次拿到播放器时载入并应用已保存的音量。
func _ensure_playback_volume_applied() -> void:
	if not _playback_volume_loaded:
		_load_playback_settings()
	_apply_playback_volume()

## 从设置文件读取音量。
func _load_playback_settings() -> void:
	_playback_volume_loaded = true
	var config := ConfigFile.new()
	if config.load(PLAYBACK_SETTINGS_PATH) != OK:
		return
	playback_volume = clampf(float(config.get_value("playback", "volume", 1.0)), 0.0, 1.0)

## 把音量写回设置文件。
func _save_playback_settings() -> void:
	var config := ConfigFile.new()
	config.load(PLAYBACK_SETTINGS_PATH)
	config.set_value("playback", "volume", playback_volume)
	config.save(PLAYBACK_SETTINGS_PATH)

## 让外部（设置页）在界面就绪时同步一次音量状态。
func sync_playback_volume() -> void:
	_load_playback_settings()
	_apply_playback_volume()
