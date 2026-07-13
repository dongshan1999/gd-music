class_name DX_Root
extends Node

const LoggerScript := preload("res://dx/runtime/scripts/managers/logger.gd")
const SignalManagerScript := preload("res://dx/runtime/scripts/managers/signals/signal_manager.gd")
const ConfigManagerScript := preload("res://dx/runtime/scripts/managers/config/config_manager.gd")
const TimeManagerScript := preload("res://dx/runtime/scripts/managers/time/time_manager.gd")
const BackgroundStateManagerScript := preload("res://dx/runtime/scripts/managers/background_state_manager.gd")
const CountdownManagerScript := preload("res://dx/runtime/scripts/managers/countdown/countdown_manager.gd")
const SaveManagerScript := preload("res://dx/runtime/scripts/managers/save/save_manager.gd")
const LocalizationManagerScript := preload("res://dx/runtime/scripts/managers/localization/localization_manager.gd")
const DebugManagerScript := preload("res://dx/runtime/scripts/debug/debug_manager.gd")
const JsonSerializerScript := preload("res://dx/runtime/scripts/serializer/json_serializer.gd")
const DebugOptionsDataScript := preload("res://dx/runtime/scripts/debug/debug_options_data.gd")
const UiFlyEffectScript := preload("res://dx/runtime/scripts/effects/dx_ui_fly_effect.gd")
const ResManagerScript := preload("res://dx/runtime/scripts/managers/res/res_manager.gd")
const FileManagerScript := preload("res://dx/runtime/scripts/managers/files/file_manager.gd")

const MANAGER_READY_METHOD := &"in_ready"
const MANAGER_PROCESS_METHOD := &"in_process"
const MANAGER_EXIT_TREE_METHOD := &"in_exit_tree"
const MANAGER_QUIT_METHOD := &"in_quit"
const MANAGER_PAUSE_METHOD := &"in_pause"
const MANAGER_FOCUS_METHOD := &"in_focus"
const MANAGER_TRANSLATION_CHANGED_METHOD := &"in_translation_changed"

const MANAGER_POPUP := &"popup"
const MANAGER_TIME := &"time"
const MANAGER_LOGGER := &"logger"
const MANAGER_SIGNAL := &"signal"
const MANAGER_CONFIG := &"config"
const MANAGER_BACKGROUND_STATE := &"background_state"
const MANAGER_COUNTDOWN := &"countdown"
const MANAGER_POOL := &"pool"
const MANAGER_SAVE := &"save"
const MANAGER_LOCALIZATION := &"localization"
const MANAGER_DEBUG := &"debug"
const MANAGER_EFFECT := &"effect"
const MANAGER_RES := &"res"
const MANAGER_FILES := &"files"

const POPUP_NODE_PATH := ^"Popup"
const POOL_NODE_PATH := ^"Pool"

var popup:
	get:
		return get_manager(MANAGER_POPUP)

var time:
	get:
		return get_manager(MANAGER_TIME)

var logger:
	get:
		return get_manager(MANAGER_LOGGER)

var signals:
	get:
		return get_manager(MANAGER_SIGNAL)

var config:
	get:
		return get_manager(MANAGER_CONFIG)

var background_state:
	get:
		return get_manager(MANAGER_BACKGROUND_STATE)

var countdown:
	get:
		return get_manager(MANAGER_COUNTDOWN)

var pool:
	get:
		return get_manager(MANAGER_POOL)

var save:
	get:
		return get_manager(MANAGER_SAVE)

var localization:
	get:
		return get_manager(MANAGER_LOCALIZATION)

var debug:
	get:
		return get_manager(MANAGER_DEBUG)

var effect:
	get:
		return get_manager(MANAGER_EFFECT)

var res:
	get:
		return get_manager(MANAGER_RES)

var files:
	get:
		return get_manager(MANAGER_FILES)

var _manager_map: Dictionary = {}
var _manager_order: Array = []
var _quit_dispatched := false

func _enter_tree() -> void:
	_bootstrap()

func _ready() -> void:
	_register_pool_manager()
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

	register_manager(MANAGER_TIME, TimeManagerScript.new())
	register_manager(MANAGER_LOGGER, LoggerScript.new())
	register_manager(MANAGER_SIGNAL, SignalManagerScript.new())
	register_manager(MANAGER_CONFIG, ConfigManagerScript.new())
	register_manager(MANAGER_BACKGROUND_STATE, BackgroundStateManagerScript.new())
	register_manager(MANAGER_COUNTDOWN, CountdownManagerScript.new())
	register_manager(MANAGER_SAVE, SaveManagerScript.new())
	register_manager(MANAGER_LOCALIZATION, LocalizationManagerScript.new())
	var debug_manager = register_manager(MANAGER_DEBUG, DebugManagerScript.new())
	debug_manager.register_options_scripts(DebugOptionsDataScript.new().get_options_scripts())
	register_manager(MANAGER_EFFECT, UiFlyEffectScript.new())
	register_manager(MANAGER_RES, ResManagerScript.new())
	register_manager(MANAGER_FILES, FileManagerScript.new())

func _register_pool_manager() -> void:
	if has_manager(MANAGER_POOL):
		return

	var pool_manager = get_node_or_null(POOL_NODE_PATH)
	if pool_manager == null:
		push_error("DX pool manager node is missing.")
		return
	register_manager(MANAGER_POOL, pool_manager)

func _register_popup_manager() -> void:
	if has_manager(MANAGER_POPUP):
		return

	var popup_manager = get_node_or_null(POPUP_NODE_PATH)
	if popup_manager == null:
		push_error("DX popup manager node is missing.")
		return
	register_manager(MANAGER_POPUP, popup_manager)

func _broadcast_pause(paused: bool) -> void:
	for manager in _manager_order:
		_call_manager_one_arg(manager, MANAGER_PAUSE_METHOD, paused)

func _broadcast_focus(has_focus: bool) -> void:
	for manager in _manager_order:
		_call_manager_one_arg(manager, MANAGER_FOCUS_METHOD, has_focus)

func _broadcast_translation_changed() -> void:
	for manager in _manager_order:
		_call_manager_no_args(manager, MANAGER_TRANSLATION_CHANGED_METHOD)

func _dispatch_quit() -> void:
	if _quit_dispatched:
		return
	_quit_dispatched = true
	for index in range(_manager_order.size() - 1, -1, -1):
		_call_manager_no_args(_manager_order[index], MANAGER_QUIT_METHOD)
	JsonSerializerScript.clear_cache()

func _call_manager_no_args(manager, method_name: StringName) -> void:
	if manager == null or not manager.has_method(method_name):
		return
	manager.call(method_name)

func _call_manager_one_arg(manager, method_name: StringName, value) -> void:
	if manager == null or not manager.has_method(method_name):
		return
	manager.call(method_name, value)
