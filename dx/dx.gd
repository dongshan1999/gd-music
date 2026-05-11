class_name DX_DXRoot
extends Node

const SIGNAL_APP_PAUSE := &"app/pause"
const SIGNAL_APP_FOCUS := &"app/focus"
const SIGNAL_APP_BACKGROUND := &"app/background"
const MANAGER_READY_METHOD := &"in_ready"
const MANAGER_PROCESS_METHOD := &"in_process"
const MANAGER_EXIT_TREE_METHOD := &"in_exit_tree"
const MANAGER_QUIT_METHOD := &"in_quit"
const MANAGER_PAUSE_METHOD := &"in_pause"
const MANAGER_FOCUS_METHOD := &"in_focus"

const LoggerScript := preload("res://dx/runtime/scripts/managers/logger.gd")
const SignalManagerScript := preload("res://dx/runtime/scripts/managers/signal_manager.gd")
const DataManagerScript := preload("res://dx/runtime/scripts/managers/data_manager.gd")
const TimeManagerScript := preload("res://dx/runtime/scripts/managers/time_manager.gd")
const BackgroundStateManagerScript := preload("res://dx/runtime/scripts/managers/background_state_manager.gd")
const CountdownManagerScript := preload("res://dx/runtime/scripts/managers/countdown_manager.gd")
const PoolManagerScript := preload("res://dx/runtime/scripts/managers/pool_manager.gd")
const SaveManagerScript := preload("res://dx/runtime/scripts/managers/save/save_manager.gd")
const LocalizationManagerScript := preload("res://dx/runtime/scripts/managers/localization/localization_manager.gd")
const MusicPluginManagerScript := preload("res://dx/runtime/scripts/managers/music_plugin_manager.gd")

var popup:
	get:
		return get_manager(&"popup")

var time:
	get:
		return get_manager(&"time")

var logger:
	get:
		return get_manager(&"logger")

var signals:
	get:
		return get_manager(&"signal")

var data:
	get:
		return get_manager(&"data")

var background_state:
	get:
		return get_manager(&"background_state")

var countdown:
	get:
		return get_manager(&"countdown")

var pool:
	get:
		return get_manager(&"pool")

var save:
	get:
		return get_manager(&"save")

var localization:
	get:
		return get_manager(&"localization")

var music_plugins:
	get:
		return get_manager(&"music_plugins")

var _manager_map: Dictionary = {}
var _manager_order: Array = []
var _quit_dispatched := false

func _enter_tree() -> void:
	_bootstrap()

func _ready() -> void:
	_register_popup_manager()
	for manager in _manager_order:
		_call_manager_no_args(manager, MANAGER_READY_METHOD)

func _process(delta: float) -> void:
	for manager in _manager_order:
		_call_manager_one_arg(manager, MANAGER_PROCESS_METHOD, delta)

func _exit_tree() -> void:
	_dispatch_quit()
	for index in range(_manager_order.size() - 1, -1, -1):
		_call_manager_no_args(_manager_order[index], MANAGER_EXIT_TREE_METHOD)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_dispatch_quit()
		NOTIFICATION_APPLICATION_PAUSED:
			_broadcast_pause(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_broadcast_pause(false)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_broadcast_focus(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_broadcast_focus(true)
		NOTIFICATION_TRANSLATION_CHANGED:
			_broadcast_translation_changed()

func register_manager(manager_name: StringName, manager):
	if manager == null:
		return null
	manager.dx = self
	_manager_map[manager_name] = manager
	_manager_order.append(manager)
	return manager

func get_manager(manager_name: StringName):
	return _manager_map.get(manager_name)

func has_manager(manager_name: StringName) -> bool:
	return _manager_map.has(manager_name)

func get_manager_names() -> Array[StringName]:
	var result: Array[StringName] = []
	for key in _manager_map.keys():
		result.append(key)
	return result

func _bootstrap() -> void:
	if not _manager_order.is_empty():
		return

	register_manager(&"time", TimeManagerScript.new())
	register_manager(&"logger", LoggerScript.new())
	register_manager(&"signal", SignalManagerScript.new())
	register_manager(&"data", DataManagerScript.new())
	register_manager(&"background_state", BackgroundStateManagerScript.new())
	register_manager(&"countdown", CountdownManagerScript.new())
	register_manager(&"pool", PoolManagerScript.new())
	register_manager(&"save", SaveManagerScript.new())
	register_manager(&"localization", LocalizationManagerScript.new())
	register_manager(&"music_plugins", MusicPluginManagerScript.new())

func _register_popup_manager() -> void:
	if has_manager(&"popup"):
		return

	var popup_manager = get_node_or_null(^"Popup")
	if popup_manager == null:
		push_error("DX popup manager node is missing.")
		return
	register_manager(&"popup", popup_manager)

func _broadcast_pause(paused: bool) -> void:
	for manager in _manager_order:
		_call_manager_one_arg(manager, MANAGER_PAUSE_METHOD, paused)

func _broadcast_focus(has_focus: bool) -> void:
	for manager in _manager_order:
		_call_manager_one_arg(manager, MANAGER_FOCUS_METHOD, has_focus)

func _broadcast_translation_changed() -> void:
	for manager in _manager_order:
		_call_manager_no_args(manager, &"in_translation_changed")

func _dispatch_quit() -> void:
	if _quit_dispatched:
		return
	_quit_dispatched = true
	for index in range(_manager_order.size() - 1, -1, -1):
		_call_manager_no_args(_manager_order[index], MANAGER_QUIT_METHOD)

func _call_manager_no_args(manager, method_name: StringName) -> void:
	if manager == null or not manager.has_method(method_name):
		return
	manager.call(method_name)

func _call_manager_one_arg(manager, method_name: StringName, value) -> void:
	if manager == null or not manager.has_method(method_name):
		return
	manager.call(method_name, value)
