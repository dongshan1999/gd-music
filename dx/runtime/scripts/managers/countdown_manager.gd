extends RefCounted

const SIGNAL_APP_BACKGROUND := &"app/background"
const CountdownInfoScript = preload("res://dx/runtime/scripts/managers/countdown_info.gd")

var dx: Node
var _active: Dictionary = {}
var _inactive: Dictionary = {}
var _is_background := false
var _background_entered_unix := 0

func in_ready() -> void:
	dx.signals.subscribe(SIGNAL_APP_BACKGROUND, _on_app_background_changed)

func in_exit_tree() -> void:
	dx.signals.unsubscribe(SIGNAL_APP_BACKGROUND, _on_app_background_changed)

func in_process(_delta: float) -> void:
	_refresh_all()

func start(info):
	if info == null or String(info.id).is_empty():
		return null

	_active[info.id] = info
	_inactive.erase(info.id)
	_refresh_single(info, true)
	return info

func start_seconds(
	id: StringName,
	duration_seconds: int,
	destroy_on_complete: bool = true,
	run_in_background: bool = true
) -> Object:
	var end_timestamp: int = dx.time.now_unix() + maxi(0, duration_seconds)
	return start(
		CountdownInfoScript.new(
			id,
			end_timestamp,
			CountdownInfoScript.CountdownStatus.RUNNING,
			destroy_on_complete,
			run_in_background
		)
	)

func get_countdown(id: StringName):
	if _active.has(id):
		return _active[id]
	if _inactive.has(id):
		return _inactive[id]
	return null

func contains(id: StringName) -> bool:
	return _active.has(id) or _inactive.has(id)

func subscribe_update(id: StringName, callback: Callable, immediate: bool = true):
	var info = get_countdown(id)
	if info == null:
		return null
	info.subscribe_update(callback)
	if immediate:
		_refresh_single(info, true)
	return info

func subscribe_completed(id: StringName, callback: Callable):
	var info = get_countdown(id)
	if info == null:
		return null
	info.subscribe_completed(callback)
	return info

func refresh_end_time(id: StringName, end_unix_timestamp: int) -> void:
	var info = get_countdown(id)
	if info == null:
		return
	_inactive.erase(id)
	_active[id] = info
	info.refresh_end_unix_timestamp(end_unix_timestamp)
	_refresh_single(info, true)

func pause(id: StringName) -> void:
	var info = _active.get(id)
	if info == null:
		return
	_refresh_single(info, true)
	info.pause()

func resume(id: StringName) -> void:
	var info = get_countdown(id)
	if info == null:
		return
	_inactive.erase(id)
	_active[id] = info
	info.resume(dx.time.now_unix())
	_refresh_single(info, true)

func remove(id: StringName) -> void:
	_active.erase(id)
	_inactive.erase(id)

func clear(clear_inactive: bool = true) -> void:
	_active.clear()
	if clear_inactive:
		_inactive.clear()

func get_active_items() -> Array:
	var result: Array = []
	for value in _active.values():
		var info = value
		if info != null:
			result.append(info)
	return result

func _refresh_all() -> void:
	var completed_ids: Array[StringName] = []
	for key in _active.keys():
		var info = _active[key]
		if info == null:
			completed_ids.append(key)
			continue
		if info.status != CountdownInfoScript.CountdownStatus.RUNNING:
			continue
		_refresh_single(info, false)
		if info.is_completed():
			completed_ids.append(key)

	for key in completed_ids:
		_finalize_countdown(key)

func _refresh_single(info, force_notify: bool) -> void:
	if info == null:
		return
	if info.status == CountdownInfoScript.CountdownStatus.PAUSED:
		if force_notify:
			info.notify_update()
		return

	var new_remaining: int = maxi(0, info.end_unix_timestamp - dx.time.now_unix())
	if force_notify or new_remaining != info.remaining_seconds:
		info.remaining_seconds = new_remaining
		info.notify_update()

	if new_remaining <= 0 and info.status == CountdownInfoScript.CountdownStatus.RUNNING:
		info.complete()

func _finalize_countdown(id: StringName) -> void:
	var info = _active.get(id)
	_active.erase(id)
	if info == null:
		return
	if info.destroy_on_complete:
		_inactive.erase(id)
	else:
		_inactive[id] = info

func _on_app_background_changed(value: Variant) -> void:
	var background: bool = bool(value)
	if background == _is_background:
		return

	_is_background = background
	if background:
		_background_entered_unix = dx.time.now_unix()
		return

	var paused_seconds: int = maxi(0, dx.time.now_unix() - _background_entered_unix)
	if paused_seconds <= 0:
		return

	for info in get_active_items():
		if info.run_in_background:
			continue
		if info.status != CountdownInfoScript.CountdownStatus.RUNNING:
			continue
		info.end_unix_timestamp += paused_seconds
		_refresh_single(info, true)
