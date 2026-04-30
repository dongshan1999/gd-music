class_name DXFramework
extends Node

const SIGNAL_APP_PAUSE := &"app/pause"
const SIGNAL_APP_FOCUS := &"app/focus"
const SIGNAL_APP_BACKGROUND := &"app/background"
const SIGNAL_POPUP_SHOWN := &"popup/shown"
const SIGNAL_POPUP_HIDDEN := &"popup/hidden"
const LoggerScript = preload("res://dx/runtime/scripts/managers/dx_logger.gd")
const SignalManagerScript = preload("res://dx/runtime/scripts/managers/dx_signal_manager.gd")
const DataManagerScript = preload("res://dx/runtime/scripts/managers/dx_data_manager.gd")
const TimeManagerScript = preload("res://dx/runtime/scripts/managers/dx_time_manager.gd")
const BackgroundStateManagerScript = preload("res://dx/runtime/scripts/managers/dx_background_state_manager.gd")
const CountdownManagerScript = preload("res://dx/runtime/scripts/managers/dx_countdown_manager.gd")
const PoolManagerScript = preload("res://dx/runtime/scripts/managers/dx_pool_manager.gd")
const AppSaveManagerType := preload("res://dx/runtime/scripts/save/save_manager.gd")
const PopupManagerType := preload("res://dx/runtime/scripts/popup/popup_manager.gd")

var logger
var signals
var data
var time
var background_state
var countdown
var pool

var _manager_map: Dictionary = {}
var _manager_order: Array = []
var _quit_dispatched := false

func _enter_tree() -> void:
	_bootstrap()

func _ready() -> void:
	_connect_popup_bridge()
	for manager in _manager_order:
		manager.in_ready()

func _process(delta: float) -> void:
	for manager in _manager_order:
		manager.in_process(delta)

func _exit_tree() -> void:
	_dispatch_quit()
	for index in range(_manager_order.size() - 1, -1, -1):
		_manager_order[index].in_exit_tree()

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

func register_manager(manager_name: StringName, manager):
	if manager == null:
		return null
	manager.setup(self)
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

func get_save_manager() -> AppSaveManagerType:
	return get_node_or_null("/root/AppSave") as AppSaveManagerType

func get_popup_manager() -> PopupManagerType:
	return get_node_or_null("/root/Popup") as PopupManagerType

func _bootstrap() -> void:
	if not _manager_order.is_empty():
		return

	time = register_manager(&"time", TimeManagerScript.new())
	logger = register_manager(&"logger", LoggerScript.new())
	signals = register_manager(&"signal", SignalManagerScript.new())
	data = register_manager(&"data", DataManagerScript.new())
	background_state = register_manager(&"background_state", BackgroundStateManagerScript.new())
	countdown = register_manager(&"countdown", CountdownManagerScript.new())
	pool = register_manager(&"pool", PoolManagerScript.new())

func _connect_popup_bridge() -> void:
	var popup_manager := get_popup_manager()
	if popup_manager == null:
		return
	if not popup_manager.popup_shown.is_connected(_on_popup_shown):
		popup_manager.popup_shown.connect(_on_popup_shown)
	if not popup_manager.popup_hidden.is_connected(_on_popup_hidden):
		popup_manager.popup_hidden.connect(_on_popup_hidden)

func _on_popup_shown(popup_id: Variant, popup: Variant) -> void:
	signals.fire(SIGNAL_POPUP_SHOWN, {
		"id": popup_id,
		"popup": popup,
	})

func _on_popup_hidden(popup_id: Variant) -> void:
	signals.fire(SIGNAL_POPUP_HIDDEN, {
		"id": popup_id,
	})

func _broadcast_pause(paused: bool) -> void:
	for manager in _manager_order:
		manager.in_pause(paused)

func _broadcast_focus(has_focus: bool) -> void:
	for manager in _manager_order:
		manager.in_focus(has_focus)

func _dispatch_quit() -> void:
	if _quit_dispatched:
		return
	_quit_dispatched = true
	for index in range(_manager_order.size() - 1, -1, -1):
		_manager_order[index].in_quit()
