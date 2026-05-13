class_name MusicAppShowcaseController
extends Control

signal state_changed

static var instance = null

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const PlaybackControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_CONTROLLER)
const PlaybackStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STATE_CONTROLLER)
const PlaylistStateControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYLIST_STATE_CONTROLLER)
const PopupRouterControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_POPUP_ROUTER_CONTROLLER)

@onready var normal_popup_host: Control = %NormalPopupHost
@onready var mini_player: Control = %MiniPlayer
@onready var fullscreen_popup_host: Control = %FullscreenPopupHost
@onready var audio_player: AudioStreamPlayer = %AudioPlayer

var _timer: Timer = Timer.new()
var _playback_controller = PlaybackControllerScript.new(self)
var _playback_state_controller = PlaybackStateControllerScript.new(self)
var _playlist_state_controller = PlaylistStateControllerScript.new(self)
var _popup_router_controller = PopupRouterControllerScript.new(self)

## 初始化音乐应用展示层，挂接弹窗宿主、播放器与定时同步逻辑。
func _ready() -> void:
	instance = self

	_popup_router_controller.attach_popup_hosts(normal_popup_host, fullscreen_popup_host)

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
	call_deferred("_auto_start_plugin_host")

## 退出场景树时回收音频与弹窗宿主引用。
func _exit_tree() -> void:
	_playback_state_controller.stop_audio_playback(true)
	_popup_router_controller.detach_popup_hosts(normal_popup_host, fullscreen_popup_host)
	if instance == self:
		instance = null

## 处理翻译切换和窗口关闭时的状态刷新与保存。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		notify_state_changed()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_popup_router_controller.save_app_state()

## 延迟触发插件宿主自动启动流程。
func _auto_start_plugin_host() -> void:
	await MusicAppPluginBrowserController.new(self).auto_start_music_plugin_host()

## 每秒同步一次播放进度，并在状态变化时刷新界面。
func _on_tick() -> void:
	_playback_state_controller.tick_playback_progress()

func toggle_playback() -> void:
	_playback_state_controller.toggle_playback()

func request_audio_sync() -> void:
	_playback_state_controller.request_audio_sync()

func show_popup(popup_id: int):
	return _popup_router_controller.show_popup(popup_id)

## 广播状态变化信号，驱动各子页面刷新。
func notify_state_changed() -> void:
	state_changed.emit()

## 处理返回键，关闭当前非首页弹窗。
func _unhandled_input(event: InputEvent) -> void:
	if _popup_router_controller.handle_cancel_input(event):
		get_viewport().set_input_as_handled()

func _on_audio_finished() -> void:
	_playback_state_controller.on_audio_finished()
