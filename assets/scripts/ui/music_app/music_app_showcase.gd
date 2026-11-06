class_name MusicAppShowcaseController
extends Control

static var instance = null

const APP_THEME_PATH := "res://assets/themes/gd_music_theme.tres"

const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const PlaybackControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_CONTROLLER)
const PlaybackStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STATE_CONTROLLER)
const PlaylistStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYLIST_STATE_CONTROLLER)
const PopupRouterControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_POPUP_ROUTER_CONTROLLER)
const PluginControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLUGIN_CONTROLLER)
const DownloadControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_DOWNLOAD_CONTROLLER)
const HistoryStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_HISTORY_STATE_CONTROLLER)

@onready var normal_popup_host: Control = %NormalPopupHost
@onready var mini_player: Control = %MiniPlayer
@onready var fullscreen_popup_host: Control = %FullscreenPopupHost
@onready var audio_player: AudioStreamPlayer = %AudioPlayer
@onready var ffmpeg_player: VideoStreamPlayer = %FFmpegPlayer

var _timer: Timer = Timer.new()
var _playback_controller = PlaybackControllerScript.new(self)
var _playback_state_controller = PlaybackStateControllerScript.new(self)
var _playlist_state_controller = PlaylistStateControllerScript.new(self)
var _popup_router_controller = PopupRouterControllerScript.new(self)
var _plugin_controller = PluginControllerScript.new(self)
var _download_controller = DownloadControllerScript.new(self)
var _history_state_controller = HistoryStateControllerScript.new(self)

const BACK_CONFIRM_WINDOW_MSEC := 2000
const BACK_EVENT_DEBOUNCE_MSEC := 120
var _last_root_back_msec := -1
var _last_back_event_msec := -BACK_EVENT_DEBOUNCE_MSEC

# @dx_debug_action(name="Toggle Playback", group="Playback")
func debug_toggle_playback() -> void:
	toggle_playback()

# @dx_debug_action(name="Refresh Plugins", group="Plugin")
func debug_refresh_plugins() -> void:
	_plugin_controller.refresh_plugins()

# @dx_debug_number(name="Engine Time Scale", group="Runtime")
var debug_engine_time_scale := 1.0

# @dx_debug_string(name="Debug Note", group="Runtime")
var debug_note := ""

## 初始化音乐应用展示层，挂接弹窗宿主、播放器与定时同步逻辑。
func _ready() -> void:
	instance = self
	# Keep the audio pipeline processing while Android pauses the UI Activity.
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	ffmpeg_player.process_mode = Node.PROCESS_MODE_ALWAYS

	_popup_router_controller.attach_popup_hosts(normal_popup_host, fullscreen_popup_host)
	_plugin_controller.in_ready()
	_download_controller.in_ready()
	_playback_state_controller.bind_background_audio_controls()
	# 播放历史挂在全局播放事件上，四条起播链路（native/ffmpeg/mpv）统一计数。
	_history_state_controller.bind_playback_events()
	if DX != null and DX.debug != null:
		DX.debug.register_target("MusicAppShowcase", self)

	mini_player.setup(self)
	_playlist_state_controller.normalize_favorite_playlist()

	# 应用全部用指针操作，按钮不参与焦点，避免点击后残留聚焦框。
	get_tree().node_added.connect(_on_tree_node_added)
	_suppress_button_focus(self)
	# 触摸端没有鼠标悬停，但触摸会被引擎模拟成鼠标，点过的行会一直保持 hover 底色，这里直接去掉。
	if OS.has_feature("mobile"):
		_strip_hover_styles()

	add_child(_timer)
	_timer.wait_time = 1.0
	if not _timer.timeout.is_connected(_on_tick):
		_timer.timeout.connect(_on_tick)
	_timer.start()
	var audio_finished_callback := _on_audio_finished.bind(audio_player)
	if not audio_player.finished.is_connected(audio_finished_callback):
		audio_player.finished.connect(audio_finished_callback)
	var ffmpeg_finished_callback := _on_audio_finished.bind(ffmpeg_player)
	if not ffmpeg_player.finished.is_connected(ffmpeg_finished_callback):
		ffmpeg_player.finished.connect(ffmpeg_finished_callback)

	_popup_router_controller.show_home_popup()
	_playback_state_controller.request_audio_sync()
	call_deferred("_auto_refresh_plugins")

## 退出场景树时回收音频与弹窗宿主引用。
func _exit_tree() -> void:
	_history_state_controller.unbind_playback_events()
	_playback_state_controller.stop_audio_playback(true)
	_plugin_controller.in_quit()
	_popup_router_controller.detach_popup_hosts(normal_popup_host, fullscreen_popup_host)
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)
	if instance == self:
		instance = null

## 处理返回键与窗口关闭请求。
func _notification(_what: int) -> void:
	if _what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_requested()

## 延迟刷新外部插件目录。
func _auto_refresh_plugins() -> void:
	_plugin_controller.refresh_plugins()

## 每秒同步一次播放进度，并在状态变化时刷新界面。
func _on_tick() -> void:
	Engine.time_scale = debug_engine_time_scale
	_playback_state_controller.tick_playback_progress()

func toggle_playback() -> void:
	_playback_state_controller.toggle_playback()

func request_audio_sync() -> void:
	_playback_state_controller.request_audio_sync()

## 返回当前播放音量（线性 0–1）。
func get_playback_volume() -> float:
	return _playback_state_controller.get_playback_volume()

## 设置播放音量（线性 0–1），立即下发并持久化。
func set_playback_volume(value: float) -> void:
	_playback_state_controller.set_playback_volume(value)

## 让设置页在打开时同步一次音量。
func sync_playback_volume() -> void:
	_playback_state_controller.sync_playback_volume()

## 返回音乐下载控制器。
func get_download_controller():
	return _download_controller

func show_popup(popup_id: int):
	return _popup_router_controller.show_popup(popup_id)

## 处理返回键，先关闭弹窗，再执行根页面的二次退出确认。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	_handle_back_requested()
	get_viewport().set_input_as_handled()

func _handle_back_requested() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_back_event_msec < BACK_EVENT_DEBOUNCE_MSEC:
		return
	_last_back_event_msec = now_msec

	if _popup_router_controller.handle_back():
		_last_root_back_msec = -1
		return

	if _last_root_back_msec >= 0 and now_msec - _last_root_back_msec <= BACK_CONFIRM_WINDOW_MSEC:
		_last_root_back_msec = -1
		get_tree().quit()
		return

	_last_root_back_msec = now_msec
	_popup_router_controller.show_toast("再按一次退出应用")

func _on_audio_finished(source_player: Node = null) -> void:
	_playback_state_controller.on_audio_finished(source_player)

## 场景树里有新节点时，同步关闭其中按钮的焦点；页面与行都是运行时挂载的，所以要监听而不是只扫一次。
func _on_tree_node_added(node: Node) -> void:
	_suppress_button_focus(node)

## 触摸端没有悬停概念：把主题里所有 hover 样式替换成 normal，避免点过的行一直亮着。
## 传 null 时处理项目默认主题（所有页面共用同一份实例）。
func _strip_hover_styles(app_theme: Theme = null) -> void:
	var target: Theme = app_theme
	if target == null:
		target = load(APP_THEME_PATH) as Theme
	if target == null:
		return
	for type_name in target.get_stylebox_type_list():
		if not target.has_stylebox("hover", type_name):
			continue
		var normal := target.get_stylebox("normal", type_name)
		if normal != null:
			target.set_stylebox("hover", type_name, normal)

## 递归关闭按钮焦点：点击不再抢焦点，键盘/手柄也不会停在列表行上。
func _suppress_button_focus(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_suppress_button_focus(child)
