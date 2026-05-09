class_name DX_SignalManager
extends RefCounted

var dx: Node

var _subscriptions: Dictionary = {}

func subscribe(key: Variant, callback: Callable, priority: int = 0) -> void:
	if not callback.is_valid():
		return

	var normalized: StringName = _normalize_key(key)
	var bucket: Array = _subscriptions.get(normalized, [])
	for index in range(bucket.size()):
		var item: Dictionary = bucket[index]
		if item.get("callback") == callback:
			item["priority"] = priority
			bucket[index] = item
			bucket.sort_custom(_sort_subscription)
			_subscriptions[normalized] = bucket
			return

	bucket.append({
		"priority": priority,
		"callback": callback,
	})
	bucket.sort_custom(_sort_subscription)
	_subscriptions[normalized] = bucket

func unsubscribe(key: Variant, callback: Callable) -> void:
	var normalized: StringName = _normalize_key(key)
	if not _subscriptions.has(normalized):
		return

	var bucket: Array = _subscriptions[normalized]
	for index in range(bucket.size() - 1, -1, -1):
		var item: Dictionary = bucket[index]
		if item.get("callback") == callback:
			bucket.remove_at(index)
	if bucket.is_empty():
		_subscriptions.erase(normalized)
	else:
		_subscriptions[normalized] = bucket

func fire(key_or_payload: Variant, payload: Variant = null) -> void:
	var normalized: StringName = _normalize_key(key_or_payload)
	var actual_payload: Variant = payload
	if actual_payload == null and not (key_or_payload is String or key_or_payload is StringName):
		actual_payload = key_or_payload

	if not _subscriptions.has(normalized):
		return

	var bucket: Array = (_subscriptions[normalized] as Array).duplicate()
	for item in bucket:
		var callback: Callable = item.get("callback", Callable())
		if not callback.is_valid():
			continue
		if callback.get_argument_count() <= 0:
			callback.call()
		else:
			callback.call(actual_payload)

func clear(key: Variant = null) -> void:
	if key == null:
		_subscriptions.clear()
		return
	_subscriptions.erase(_normalize_key(key))

func has_listeners(key: Variant) -> bool:
	return _subscriptions.has(_normalize_key(key))

func _normalize_key(key: Variant) -> StringName:
	if key is StringName:
		return key
	if key is String:
		return StringName(key)
	if key == null:
		return &""
	if key is Object:
		var object_key: Object = key as Object
		if object_key.has_method("get_signal_key"):
			return StringName(str(object_key.call("get_signal_key")))
	return StringName(str(key))

func _sort_subscription(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("priority", 0)) < int(b.get("priority", 0))
