class_name DX_SignalManager
extends RefCounted

var dx: Node

var _subscriptions: Dictionary = {}

func subscribe(event_class: Variant, callback: Callable) -> void:
	if not callback.is_valid():
		return

	var normalized: StringName = _normalize_event_class(event_class)
	var bucket: Array = _subscriptions.get(normalized, [])
	for item in bucket:
		if item == callback:
			return

	bucket.append(callback)
	_subscriptions[normalized] = bucket

func unsubscribe(event_class: Variant, callback: Callable) -> void:
	var normalized: StringName = _normalize_event_class(event_class)
	if not _subscriptions.has(normalized):
		return

	var bucket: Array = _subscriptions[normalized]
	for index in range(bucket.size() - 1, -1, -1):
		if bucket[index] == callback:
			bucket.remove_at(index)
	if bucket.is_empty():
		_subscriptions.erase(normalized)
	else:
		_subscriptions[normalized] = bucket

func fire(event: Variant) -> void:
	if event == null:
		return

	var normalized: StringName = _normalize_event_instance(event)

	if not _subscriptions.has(normalized):
		return

	var bucket: Array = (_subscriptions[normalized] as Array).duplicate()
	for callback in bucket:
		if not callback.is_valid():
			continue
		if callback.get_argument_count() <= 0:
			callback.call()
		else:
			callback.call(event)

func clear(event_class: Variant = null) -> void:
	if event_class == null:
		_subscriptions.clear()
		return
	_subscriptions.erase(_normalize_event_class(event_class))

func has_listeners(event_class: Variant) -> bool:
	return _subscriptions.has(_normalize_event_class(event_class))

func _normalize_event_class(event_class: Variant) -> StringName:
	if event_class == null:
		return &""
	if event_class is Script:
		var script: Script = event_class
		var global_name := script.get_global_name()
		if not global_name.is_empty():
			return StringName(global_name)
		if not script.resource_path.is_empty():
			return StringName(script.resource_path)
	return StringName(str(event_class))

func _normalize_event_instance(event: Variant) -> StringName:
	if event == null:
		return &""
	if event is Object:
		var script: Script = event.get_script()
		return _normalize_event_class(script)
	return StringName(str(typeof(event)))
