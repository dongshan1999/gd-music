class_name MusicAppShowcaseController
extends Control

signal state_changed

static var instance = null

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const AppSaveManagerType := preload("res://dx/runtime/scripts/managers/save/save_manager.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupManagerType := preload("res://dx/runtime/scripts/managers/popup/popup_manager.gd")
const PopupViewType := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")

const HOME_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_HOME
const TOAST_POPUP_ID := PopupRegistryType.PopupId.COMMON_TOAST
const SUPPORTED_AUDIO_LOADERS := ["mp3", "ogg", "wav"]
const REMOTE_STREAM_TIMEOUT_SECONDS := 20.0

@onready var normal_popup_host: Control = %NormalPopupHost
@onready var mini_player: Control = %MiniPlayer
@onready var fullscreen_popup_host: Control = %FullscreenPopupHost
@onready var audio_player: AudioStreamPlayer = %AudioPlayer

var _timer: Timer = Timer.new()
var _fallback_state := MusicAppStateData.new()
var _audio_sync_request_id := 0
var _loaded_track_key := ""

var _state: MusicAppStateData:
	get:
		var save_manager := DX.save as AppSaveManagerType
		return save_manager.data.music if save_manager != null else _fallback_state
	set(value):
		var save_manager := DX.save as AppSaveManagerType
		if save_manager != null:
			save_manager.data.music = value
		else:
			_fallback_state = value

var _selected_playlist_index: int:
	get:
		return _state.selected_playlist_index
	set(value):
		_state.selected_playlist_index = value

var _selected_track_index: int:
	get:
		return _state.selected_track_index
	set(value):
		_state.selected_track_index = value

var _playback_track_indices: Array[int]:
	get:
		return _state.playback_track_indices
	set(value):
		_state.playback_track_indices = value

var _playback_queue_index: int:
	get:
		return _state.playback_queue_index
	set(value):
		_state.playback_queue_index = value

var _elapsed_seconds: int:
	get:
		return _state.elapsed_seconds
	set(value):
		_state.elapsed_seconds = value

var _is_playing: bool:
	get:
		return _state.is_playing
	set(value):
		_state.is_playing = value

var _liked_tracks: Dictionary:
	get:
		return _state.liked_tracks
	set(value):
		_state.liked_tracks = value

var _tracks: Array[TrackData]:
	get:
		return _state.tracks
	set(value):
		_state.tracks = value

var _playlists: Array[PlaylistData]:
	get:
		return _state.playlists
	set(value):
		_state.playlists = value

## 初始化音乐应用展示层，挂接弹窗宿主、播放器与定时同步逻辑。
func _ready() -> void:
	instance = self

	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.set_normal_host(normal_popup_host)
		popup_manager.set_fullscreen_host(fullscreen_popup_host)

	mini_player.setup(self)
	_sync_favorite_playlist_from_likes()

	add_child(_timer)
	_timer.wait_time = 1.0
	if not _timer.timeout.is_connected(_on_tick):
		_timer.timeout.connect(_on_tick)
	_timer.start()
	if not audio_player.finished.is_connected(_on_audio_finished):
		audio_player.finished.connect(_on_audio_finished)

	_show_home_popup()
	request_audio_sync()
	call_deferred("_auto_start_plugin_host")

## 退出场景树时回收音频与弹窗宿主引用。
func _exit_tree() -> void:
	_stop_audio_playback(true)
	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.clear_normal_host(normal_popup_host)
		popup_manager.clear_fullscreen_host(fullscreen_popup_host)
	if instance == self:
		instance = null

## 处理翻译切换和窗口关闭时的状态刷新与保存。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		notify_state_changed()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_app_state()

## 延迟触发插件宿主自动启动流程。
func _auto_start_plugin_host() -> void:
	await MusicAppPluginController.new().auto_start_music_plugin_host()

## 每秒同步一次播放进度，并在状态变化时刷新界面。
func _on_tick() -> void:
	if not _has_tracks():
		if _is_playing:
			_is_playing = false
			request_audio_sync()
			notify_state_changed()
		return

	if not _is_playing or audio_player.stream == null or not audio_player.playing or audio_player.stream_paused:
		return

	var next_elapsed := clampi(int(floor(audio_player.get_playback_position())), 0, _get_current_duration())
	if next_elapsed == _elapsed_seconds:
		return
	_elapsed_seconds = next_elapsed
	notify_state_changed()

## 判断当前是否存在有效的播放队列。
func _has_tracks() -> bool:
	return not _playback_track_indices.is_empty()

## 按播放队列游标返回当前曲目对象。
func _get_current_track() -> TrackData:
	if _playback_track_indices.is_empty():
		return null

	var queue_index := clampi(_playback_queue_index, 0, _playback_track_indices.size() - 1)
	var track_index := _playback_track_indices[queue_index]
	if track_index < 0 or track_index >= _tracks.size():
		return null
	return _tracks[track_index]

## 返回当前曲目时长，未命中曲目时返回 0。
func _get_current_duration() -> int:
	var current_track := _get_current_track()
	if current_track == null:
		return 0
	return current_track.duration

## 将当前音乐状态写回存档管理器。
func _save_app_state() -> void:
	var save_manager := DX.save as AppSaveManagerType
	if save_manager != null:
		save_manager.save_data()

## 弹出通用提示对话框。
func _show_common_alert(title: String, message: String) -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		push_error("Popup autoload is not available.")
		return

	var popup: PopupViewType = popup_manager.show(PopupRegistryType.PopupId.COMMON_DIALOG)
	if popup is CommonDialogPopup:
		var dialog: CommonDialogPopup = popup as CommonDialogPopup
		dialog.show_alert(title, message)

## 根据收藏映射重建系统“我喜欢”歌单内容。
func _sync_favorite_playlist_from_likes() -> void:
	var favorite_playlist := _get_or_create_favorite_playlist()
	var liked_track_indices: Array[int] = []
	for index in _tracks.size():
		var track: TrackData = _tracks[index]
		if track == null:
			continue
		if bool(_liked_tracks.get(_track_key(track), false)):
			liked_track_indices.append(index)

	favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.tracks = liked_track_indices
	favorite_playlist.count = liked_track_indices.size()

## 获取或创建系统“我喜欢”歌单。
func _get_or_create_favorite_playlist() -> PlaylistData:
	var favorite_index := _find_favorite_playlist_index()
	if favorite_index >= 0:
		return _playlists[favorite_index]

	var favorite_playlist := PlaylistData.new()
	favorite_playlist.title = MusicAppStateData.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.count = 0
	favorite_playlist.tracks = []
	_playlists.insert(0, favorite_playlist)
	if _playlists.size() > 1:
		_selected_playlist_index += 1
	return favorite_playlist

## 查找系统“我喜欢”歌单在列表中的索引。
func _find_favorite_playlist_index() -> int:
	for index in _playlists.size():
		if MusicAppStateData.is_system_favorite_playlist(_playlists[index]):
			return index
	return -1

## 生成曲目的唯一标识，用于收藏和播放态匹配。
func _track_key(track: TrackData) -> String:
	if not track.file_path.is_empty():
		return track.file_path
	if track.is_plugin_track():
		return "%s:%s" % [track.platform, track.remote_id]
	return "%s - %s" % [track.title, track.artist]

## 切换全局播放或暂停状态，并请求同步底层播放器。
func toggle_playback() -> void:
	if not _has_tracks():
		_is_playing = false
		request_audio_sync()
		notify_state_changed()
		return

	_is_playing = not _is_playing
	request_audio_sync()
	notify_state_changed()
	_save_app_state()

## 发起一次异步音频状态同步请求。
func request_audio_sync() -> void:
	_audio_sync_request_id += 1
	call_deferred("_sync_audio_state_deferred", _audio_sync_request_id)

## 通过 deferred 方式串联音频状态同步，避免同帧重入。
func _sync_audio_state_deferred(sync_request_id: int) -> void:
	await _sync_audio_state(sync_request_id)

## 根据当前曲目、播放态和加载结果同步 AudioStreamPlayer。
func _sync_audio_state(sync_request_id: int) -> void:
	if sync_request_id != _audio_sync_request_id:
		return

	if not _has_tracks():
		_loaded_track_key = ""
		_stop_audio_playback(true)
		if _is_playing:
			_is_playing = false
			notify_state_changed()
			_save_app_state()
		return

	var track := _get_current_track()
	if track == null:
		_loaded_track_key = ""
		_stop_audio_playback(true)
		if _is_playing:
			_is_playing = false
			notify_state_changed()
			_save_app_state()
		return

	var desired_track_key := _get_track_playback_key(track)
	if not _is_playing:
		if audio_player.playing and not audio_player.stream_paused:
			var paused_elapsed := _get_audio_position_seconds()
			if paused_elapsed != _elapsed_seconds:
				_elapsed_seconds = paused_elapsed
				notify_state_changed()
			audio_player.stream_paused = true
		elif audio_player.stream != null and _loaded_track_key != desired_track_key:
			_loaded_track_key = ""
			_stop_audio_playback(true)
		return

	if _loaded_track_key == desired_track_key and audio_player.stream != null:
		if not audio_player.playing:
			audio_player.play(float(_elapsed_seconds))
		if audio_player.stream_paused:
			audio_player.stream_paused = false
		return

	var stream := await _resolve_stream_for_track(track, sync_request_id)
	if sync_request_id != _audio_sync_request_id:
		return
	if stream == null:
		_loaded_track_key = ""
		_mark_playback_unavailable(track)
		return

	_stop_audio_playback(false)
	audio_player.stream = stream
	_loaded_track_key = desired_track_key
	_sync_track_duration_from_stream(track, stream)
	audio_player.play(float(_elapsed_seconds))
	audio_player.stream_paused = false

## 按曲目来源解析出可播放的音频流。
func _resolve_stream_for_track(track: TrackData, sync_request_id: int) -> AudioStream:
	if not track.file_path.is_empty():
		return _load_local_stream(track.file_path)

	if track.stream_url.is_empty() and track.is_plugin_track():
		var resolve_result := await MusicAppPluginController.new().resolve_track_plugin_source(_selected_track_index)
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

## 从本地文件路径加载音频流。
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

## 通过 HTTP 请求加载远程音频流。
func _load_remote_stream(
	url: String,
	headers: Dictionary,
	sync_request_id: int
) -> AudioStream:
	var request := HTTPRequest.new()
	request.timeout = REMOTE_STREAM_TIMEOUT_SECONDS
	add_child(request)

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

## 按扩展名候选顺序尝试从字节缓冲解析音频流。
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

## 返回按优先级排序的音频解析器候选列表。
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

## 将请求头字典转换为 HTTPRequest 所需的字符串数组。
func _build_http_headers(headers: Dictionary) -> PackedStringArray:
	var formatted_headers := PackedStringArray()
	for key in headers.keys():
		formatted_headers.append("%s: %s" % [str(key), str(headers[key])])
	return formatted_headers

## 从路径或 URL 中解析音频扩展名。
func _get_audio_extension(path_or_url: String) -> String:
	var sanitized := path_or_url.split("?")[0].split("#")[0]
	return sanitized.get_extension().to_lower()

## 判断给定地址是否为远程音频 URL。
func _is_remote_stream_url(path_or_url: String) -> bool:
	return path_or_url.begins_with("http://") or path_or_url.begins_with("https://")

## 生成用于识别当前已加载音频流的播放键。
func _get_track_playback_key(track: TrackData) -> String:
	if not track.file_path.is_empty():
		return "file:%s" % track.file_path
	if not track.stream_url.is_empty():
		return "url:%s" % track.stream_url
	if track.is_plugin_track():
		return "plugin:%s:%s" % [track.platform, track.remote_id]
	return "title:%s:%s" % [track.title, track.artist]

## 返回底层播放器当前播放位置的秒数。
func _get_audio_position_seconds() -> int:
	return clampi(int(floor(audio_player.get_playback_position())), 0, _get_current_duration())

## 用实际流长度回写曲目时长，并校正当前进度。
func _sync_track_duration_from_stream(track: TrackData, stream: AudioStream) -> void:
	var stream_length := stream.get_length()
	if stream_length <= 0.0:
		return

	var resolved_duration := maxi(1, int(ceil(stream_length)))
	if track.duration == resolved_duration and _elapsed_seconds <= resolved_duration:
		return

	track.duration = resolved_duration
	track.normalize()
	_elapsed_seconds = clampi(_elapsed_seconds, 0, track.duration)
	notify_state_changed()
	_save_app_state()

## 停止底层音频播放，并按需清空已挂载的音频流。
func _stop_audio_playback(clear_stream: bool) -> void:
	audio_player.stop()
	audio_player.stream_paused = false
	if clear_stream:
		audio_player.stream = null

## 标记当前曲目不可播放，并复位播放状态。
func _mark_playback_unavailable(track: TrackData) -> void:
	push_warning("Unable to play track \"%s\" with the currently supported audio loaders." % track.title)
	_stop_audio_playback(true)
	if not _is_playing:
		return
	_is_playing = false
	_elapsed_seconds = track.preview_start
	notify_state_changed()
	_save_app_state()

## 响应音频播放完成事件，自动切到队列下一首。
func _on_audio_finished() -> void:
	if not _has_tracks() or not _is_playing:
		return
	_loaded_track_key = ""
	MusicAppPlaybackController.new(self).step_queue(1, true)

## 返回全局弹窗管理器。
func _get_popup_manager() -> PopupManagerType:
	return DX.popup as PopupManagerType

## 按弹窗 ID 获取已创建的弹窗实例。
func _get_popup(popup_id: int):
	var popup_manager := _get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_popup"):
		return null
	return popup_manager.get_popup(popup_id)

## 返回当前处于显示态的弹窗实例。
func _get_current_popup():
	var popup_manager := _get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_current_popup"):
		return null
	return popup_manager.get_current_popup()

## 打开音乐应用首页弹窗。
func _show_home_popup() -> void:
	show_popup(HOME_POPUP_ID)

## 打开指定弹窗，并在支持时注入 showcase 控制器。
func show_popup(popup_id: int):
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return null

	var popup = popup_manager.show(popup_id)
	if popup != null and popup.has_method("setup"):
		popup.setup(self)
	return popup

## 显示底部轻提示。
func _show_toast(message: String) -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return

	var popup: PopupViewType = popup_manager.show(TOAST_POPUP_ID)
	if popup is CommonToastPopup:
		var toast_popup := popup as CommonToastPopup
		toast_popup.show_message(message, 104.0 if mini_player.visible else 28.0)

## 广播状态变化信号，驱动各子页面刷新。
func notify_state_changed() -> void:
	state_changed.emit()

## 处理返回键，关闭当前非首页弹窗。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	var current_popup = _get_current_popup()
	if current_popup == null or current_popup == _get_popup(HOME_POPUP_ID):
		return

	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.hide()
		get_viewport().set_input_as_handled()
