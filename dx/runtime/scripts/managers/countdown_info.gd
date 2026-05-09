class_name DX_CountdownInfo
extends RefCounted

enum CountdownStatus {
	RUNNING,
	PAUSED,
	COMPLETED,
}

var id: StringName
var status: CountdownStatus = CountdownStatus.RUNNING
var end_unix_timestamp := 0
var remaining_seconds := 0
var run_in_background := true
var destroy_on_complete := true
var metadata: Dictionary = {}

var _update_callbacks: Array[Callable] = []
var _completed_callbacks: Array[Callable] = []

func _init(
	countdown_id: StringName = &"",
	end_timestamp: int = 0,
	initial_status: CountdownStatus = CountdownStatus.RUNNING,
	can_destroy: bool = true,
	background_enabled: bool = true
) -> void:
	id = countdown_id
	end_unix_timestamp = end_timestamp
	status = initial_status
	destroy_on_complete = can_destroy
	run_in_background = background_enabled

func is_completed() -> bool:
	return status == CountdownStatus.COMPLETED

func refresh_end_unix_timestamp(value: int) -> void:
	status = CountdownStatus.RUNNING
	end_unix_timestamp = value

func pause() -> void:
	if status == CountdownStatus.RUNNING:
		status = CountdownStatus.PAUSED

func resume(now_unix_timestamp: int) -> void:
	if status != CountdownStatus.PAUSED:
		return
	status = CountdownStatus.RUNNING
	end_unix_timestamp = now_unix_timestamp + remaining_seconds

func subscribe_update(callback: Callable, replace_existing: bool = true) -> void:
	_bind_callback(_update_callbacks, callback, replace_existing)

func unsubscribe_update(callback: Callable) -> void:
	_unbind_callback(_update_callbacks, callback)

func clear_update_callbacks() -> void:
	_update_callbacks.clear()

func subscribe_completed(callback: Callable, replace_existing: bool = true) -> void:
	_bind_callback(_completed_callbacks, callback, replace_existing)

func unsubscribe_completed(callback: Callable) -> void:
	_unbind_callback(_completed_callbacks, callback)

func clear_completed_callbacks() -> void:
	_completed_callbacks.clear()

func notify_update() -> void:
	for callback in _update_callbacks:
		_call_callback(callback)

func complete() -> void:
	remaining_seconds = 0
	status = CountdownStatus.COMPLETED
	notify_update()
	for callback in _completed_callbacks:
		_call_callback(callback)

func _bind_callback(target: Array[Callable], callback: Callable, replace_existing: bool) -> void:
	if not callback.is_valid():
		return
	if replace_existing:
		_unbind_callback(target, callback)
	target.append(callback)

func _unbind_callback(target: Array[Callable], callback: Callable) -> void:
	for index in range(target.size() - 1, -1, -1):
		if target[index] == callback:
			target.remove_at(index)

func _call_callback(callback: Callable) -> void:
	if not callback.is_valid():
		return
	if callback.get_argument_count() <= 0:
		callback.call()
	else:
		callback.call(self)
