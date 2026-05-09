class_name DX_DataManager
extends RefCounted

var dx: Node

var _buckets: Dictionary = {}

func set_value(bucket: StringName, key: StringName, value: Variant) -> void:
	var target := _get_or_create_bucket(bucket)
	target[String(key)] = _duplicate_value(value)

func get_value(bucket: StringName, key: StringName, default_value: Variant = null) -> Variant:
	var target: Dictionary = _buckets.get(String(bucket), {})
	if not target.has(String(key)):
		return _duplicate_value(default_value)
	return _duplicate_value(target[String(key)])

func has_value(bucket: StringName, key: StringName) -> bool:
	var target: Dictionary = _buckets.get(String(bucket), {})
	return target.has(String(key))

func get_bucket(bucket: StringName) -> Dictionary:
	return (_buckets.get(String(bucket), {}) as Dictionary).duplicate(true)

func clear_bucket(bucket: StringName) -> void:
	_buckets.erase(String(bucket))

func clear() -> void:
	_buckets.clear()

func _get_or_create_bucket(bucket: StringName) -> Dictionary:
	var string_bucket := String(bucket)
	if not _buckets.has(string_bucket):
		_buckets[string_bucket] = {}
	return _buckets[string_bucket]

func _duplicate_value(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).duplicate(true)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value
