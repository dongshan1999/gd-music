class_name MusicAppShowcaseController
extends Control

static var instance = null

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const ControllerBaseScript := preload(MusicAppScriptPathsType.MUSIC_APP_CONTROLLER_BASE)
const PlaybackControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_CONTROLLER)
const PlaybackStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STATE_CONTROLLER)
const PlaylistStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYLIST_STATE_CONTROLLER)
const PopupRouterControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_POPUP_ROUTER_CONTROLLER)
const PluginControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLUGIN_CONTROLLER)
const SpectrumControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_SPECTRUM_CONTROLLER)
const FavoriteChangedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_FAVORITE_CHANGED_EVENT)

@onready var normal_popup_host: Control = %NormalPopupHost
@onready var music_visualizer: Control = %MusicAppVisualizer
@onready var mini_player: Control = %MiniPlayer
@onready var fullscreen_popup_host: Control = %FullscreenPopupHost
@onready var audio_player: AudioStreamPlayer = %AudioPlayer

var _timer: Timer = Timer.new()
@warning_ignore("unused_private_class_variable")
var _playback_controller = PlaybackControllerScript.new(self)
var _playback_state_controller = PlaybackStateControllerScript.new(self)
var _playlist_state_controller = PlaylistStateControllerScript.new(self)
var _popup_router_controller = PopupRouterControllerScript.new(self)
var _plugin_controller = PluginControllerScript.new(self)
var _spectrum_controller = SpectrumControllerScript.new()
var _last_visualizer_playing := false
var _last_visualizer_track_key := ""
var _visualizer_active := true

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

	_popup_router_controller.attach_popup_hosts(normal_popup_host, fullscreen_popup_host)
	_plugin_controller.in_ready()
	if music_visualizer != null and music_visualizer.has_method("setup"):
		music_visualizer.setup(_spectrum_controller)
	apply_visualizer_settings()
	if DX != null and DX.debug != null:
		DX.debug.register_target("MusicAppShowcase", self)
	DX.signals.subscribe(FavoriteChangedEventScript, _on_favorite_changed)

	mini_player.setup(self)
	_playlist_state_controller.sync_favorite_playlist_from_likes()

	add_child(_timer)
	_timer.wait_time = 1.0
	if not _timer.timeout.is_connected(_on_tick):
		_timer.timeout.connect(_on_tick)
	_timer.start()
	if not audio_player.finished.is_connected(_on_audio_finished):
		audio_player.finished.connect(_on_audio_finished)

	_popup_router_controller.show_home_popup()
	_playback_state_controller.request_audio_sync()
	call_deferred("_auto_refresh_plugins")

## 退出场景树时回收音频与弹窗宿主引用。
func _exit_tree() -> void:
	_playback_state_controller.stop_audio_playback(true)
	_plugin_controller.in_quit()
	_popup_router_controller.detach_popup_hosts(normal_popup_host, fullscreen_popup_host)
	if DX != null and DX.debug != null:
		DX.debug.unregister_target("MusicAppShowcase")
	DX.signals.unsubscribe(FavoriteChangedEventScript, _on_favorite_changed)
	if instance == self:
		instance = null

## 处理翻译切换和窗口关闭时的状态刷新与保存。
func _notification(_what: int) -> void:
	pass

func _process(delta: float) -> void:
	if _visualizer_active:
		_spectrum_controller.process(delta)
		_sync_visualizer_playback_state()

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

func apply_visualizer_settings() -> void:
	var settings := ControllerBaseScript.new(self).get_app_state().visualizer_settings
	_visualizer_active = bool(settings.get("enabled", true)) and str(settings.get("quality", "medium")) != "off"
	if music_visualizer != null and music_visualizer.has_method("apply_visualizer_settings"):
		music_visualizer.apply_visualizer_settings(settings)
	if not _visualizer_active:
		_last_visualizer_playing = false
		_last_visualizer_track_key = ""

func _sync_visualizer_playback_state() -> void:
	if music_visualizer == null:
		return

	var is_playing := _playback_state_controller.is_playing()
	if is_playing != _last_visualizer_playing:
		_last_visualizer_playing = is_playing
		if music_visualizer.has_method("set_playback_active"):
			music_visualizer.set_playback_active(is_playing)

	var current_track = _playback_controller.get_current_playback_track()
	var track_key := _get_visualizer_track_key(current_track)
	if track_key == _last_visualizer_track_key:
		return
	_last_visualizer_track_key = track_key
	if not track_key.is_empty() and music_visualizer.has_method("trigger_track_transition"):
		music_visualizer.trigger_track_transition(current_track)

func _get_visualizer_track_key(track) -> String:
	if track == null:
		return ""
	var base_controller := ControllerBaseScript.new(self)
	if base_controller.has_method("track_key"):
		return base_controller.track_key(track)
	return "%s|%s|%s|%s" % [
		str(track.source),
		str(track.platform),
		str(track.remote_id),
		str(track.file_path)
	]

func show_popup(popup_id: int):
	return _popup_router_controller.show_popup(popup_id)

## 处理返回键，关闭当前非首页弹窗。
func _unhandled_input(event: InputEvent) -> void:
	if _popup_router_controller.handle_cancel_input(event):
		get_viewport().set_input_as_handled()

func _on_audio_finished() -> void:
	_playback_state_controller.on_audio_finished()

func _on_favorite_changed(event) -> void:
	if not _visualizer_active or music_visualizer == null:
		return
	if music_visualizer.has_method("trigger_favorite_feedback"):
		music_visualizer.trigger_favorite_feedback(event.liked, event.track)
