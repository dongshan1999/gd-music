class_name DX_DebugManager
extends RefCounted

const DebugMetricsScript := preload("res://dx/runtime/scripts/debug/debug_metrics.gd")
const DebugOptionsRegistryScript := preload("res://dx/runtime/scripts/debug/debug_options_registry.gd")

const GROUP_DEFAULT := "Default"
const TYPE_ACTION := "action"
const TYPE_STRING := "string"
const TYPE_NUMBER := "number"
const TYPE_BOOLEAN := "boolean"
const TYPE_SELECT := "select"
const TYPE_READONLY := "readonly"
const DEFAULT_RUNTIME_TARGET_ID := "Runtime"
const DEFAULT_OPTIONS_TARGET_ID := "Options"

enum GroupDisplayMode {
	INLINE,
	COLLAPSE,
	PAGE,
}

var dx: Node
var _targets: Dictionary = {}
var _options_registry
var _options_scripts: Array[Script] = []
var _group_display_modes: Dictionary = {}
var _metrics := DebugMetricsScript.new()

func register_options_scripts(options_scripts: Array[Script]) -> void:
	for options_script in options_scripts:
		if options_script != null and not _options_scripts.has(options_script):
			_options_scripts.append(options_script)

	if _options_registry != null:
		_options_registry.set_options_scripts(_options_scripts)

func register_target(target_id: String, target: Object) -> void:
	if not OS.is_debug_build() or not _is_valid_target(target):
		return

	var normalized_target_id := _resolve_target_id(target_id, target)
	var existing: Dictionary = _targets.get(normalized_target_id, {})
	_targets[normalized_target_id] = {
		"id": normalized_target_id,
		"target": target,
		"items": existing.get("items", []),
	}

func clear_runtime_targets() -> void:
	for key in _targets.keys().duplicate():
		var entry: Dictionary = _targets[key]
		if entry.get("target", null) != null:
			_targets.erase(key)

func set_group_display_mode(target_id: String, group: String, mode: int) -> void:
	_group_display_modes[_get_group_key(_normalize_target_id(target_id, DEFAULT_OPTIONS_TARGET_ID), group)] = mode

func register_action(group: String, target: Object, method_name: String, name: String, target_id: String = "") -> void:
	_register_member_item(target_id, target, TYPE_ACTION, group, name, method_name, true)

func register_number(
	group: String,
	target: Object,
	member_name: String,
	name: String,
	target_id: String = "",
	value_range: Dictionary = {}
) -> void:
	_register_member_item(target_id, target, TYPE_NUMBER, group, name, member_name, false, {
		"range": value_range,
	})

func register_string(group: String, target: Object, member_name: String, name: String, target_id: String = "") -> void:
	_register_member_item(target_id, target, TYPE_STRING, group, name, member_name, false)

func register_boolean(group: String, target: Object, member_name: String, name: String, target_id: String = "") -> void:
	_register_member_item(target_id, target, TYPE_BOOLEAN, group, name, member_name, false)

func register_select(
	group: String,
	target: Object,
	member_name: String,
	name: String,
	options: Array,
	target_id: String = ""
) -> void:
	_register_member_item(target_id, target, TYPE_SELECT, group, name, member_name, false, {
		"options": options,
	})

func register_readonly(group: String, getter: Callable, name: String, target_id: String = DEFAULT_RUNTIME_TARGET_ID) -> void:
	if not OS.is_debug_build() or not getter.is_valid():
		return

	var normalized_target_id := _normalize_target_id(target_id, DEFAULT_RUNTIME_TARGET_ID)
	_ensure_virtual_target(normalized_target_id)
	_upsert_item(
		normalized_target_id,
		{
			"target_id": normalized_target_id,
			"type": TYPE_READONLY,
			"group": _normalize_group(group),
			"name": _normalize_label(name, TYPE_READONLY),
			"member_name": "",
			"is_method": false,
			"getter": getter,
		}
	)

func register_callable_action(
	group: String,
	callback: Callable,
	name: String,
	target_id: String = DEFAULT_OPTIONS_TARGET_ID,
	member_name: String = ""
) -> void:
	if not OS.is_debug_build() or not callback.is_valid():
		return

	var normalized_target_id := _normalize_target_id(target_id, DEFAULT_OPTIONS_TARGET_ID)
	var normalized_member_name := _normalize_label(member_name, str(callback.get_method()))
	_ensure_virtual_target(normalized_target_id)
	_upsert_item(
		normalized_target_id,
		{
			"target_id": normalized_target_id,
			"type": TYPE_ACTION,
			"group": _normalize_group(group),
			"name": _normalize_label(name, TYPE_ACTION),
			"member_name": normalized_member_name,
			"is_method": true,
			"callback": callback,
		}
	)

func get_target_descriptors() -> Array[Dictionary]:
	discover_targets()

	var result: Array[Dictionary] = []
	for key in _targets.keys():
		var entry: Dictionary = _targets[key]
		var target: Object = entry.get("target", null)
		if target != null and not _is_valid_target(target):
			_targets.erase(key)
			continue

		var items: Array[Dictionary] = []
		_append_unique_items(items, entry.get("items", []))
		if items.is_empty():
			continue

		var target_id := str(entry.get("id", ""))
		result.append({
			"id": target_id,
			"items": items,
			"group_display_modes": _get_target_group_display_modes(target_id),
		})
	return result

func discover_targets() -> void:
	if OS.is_debug_build():
		_get_options_registry().discover_current_scene()

func get_system_descriptors() -> Array[Dictionary]:
	return _metrics.get_system_descriptors()

func get_profiler_descriptors() -> Array[Dictionary]:
	return _metrics.get_profiler_descriptors()

func invoke_action(target_id: String, method_name: String) -> void:
	var item := _find_item(target_id, method_name)
	var callback: Callable = item.get("callback", Callable())
	if callback.is_valid():
		callback.call()
		return

	var target := _get_target(target_id)
	if target != null and target.has_method(method_name):
		target.call(method_name)

func read_item_value(item: Dictionary) -> Variant:
	var getter: Callable = item.get("getter", Callable())
	if getter.is_valid():
		return getter.call()
	return read_value(str(item.get("target_id", "")), str(item.get("member_name", "")))

func read_value(target_id: String, member_name: String) -> Variant:
	var target := _get_target(target_id)
	if target == null:
		return null
	return target.get(member_name)

func get_target(target_id: String) -> Object:
	return _get_target(target_id)

func write_number(target_id: String, member_name: String, value: float) -> void:
	var target := _get_target(target_id)
	if target == null:
		return

	var current_value: Variant = target.get(member_name)
	match typeof(current_value):
		TYPE_INT:
			target.set(member_name, int(round(value)))
		TYPE_FLOAT:
			target.set(member_name, value)

func write_string(target_id: String, member_name: String, value: String) -> void:
	var target := _get_target(target_id)
	if target == null:
		return

	var current_value: Variant = target.get(member_name)
	if typeof(current_value) == TYPE_STRING_NAME:
		target.set(member_name, StringName(value))
	else:
		target.set(member_name, value)

func write_boolean(target_id: String, member_name: String, value: bool) -> void:
	var target := _get_target(target_id)
	if target != null:
		target.set(member_name, value)

func write_select(target_id: String, member_name: String, value: Variant) -> void:
	var target := _get_target(target_id)
	if target == null:
		return

	var current_value: Variant = target.get(member_name)
	if typeof(current_value) == TYPE_STRING_NAME:
		target.set(member_name, StringName(value))
	elif typeof(current_value) == TYPE_INT:
		target.set(member_name, int(value))
	else:
		target.set(member_name, value)

func _register_member_item(
	target_id: String,
	target: Object,
	item_type: String,
	group: String,
	name: String,
	member_name: String,
	is_method: bool,
	extra_data: Dictionary = {}
) -> void:
	if not OS.is_debug_build() or not _is_valid_target(target):
		return

	var normalized_target_id := _resolve_target_id(target_id, target)
	_ensure_target_entry(normalized_target_id, target)

	var item := {
		"target_id": normalized_target_id,
		"type": item_type,
		"group": _normalize_group(group),
		"name": _normalize_label(name, member_name),
		"member_name": member_name,
		"is_method": is_method,
	}
	for key in extra_data.keys():
		item[key] = extra_data[key]
	_upsert_item(normalized_target_id, item)

func _get_options_registry():
	if _options_registry == null:
		_options_registry = DebugOptionsRegistryScript.new()
		_options_registry.setup(self)
		_options_registry.set_options_scripts(_options_scripts)
	return _options_registry

func _ensure_target_entry(target_id: String, target: Object) -> void:
	var existing: Dictionary = _targets.get(target_id, {})
	_targets[target_id] = {
		"id": target_id,
		"target": target,
		"items": existing.get("items", []),
	}

func _ensure_virtual_target(target_id: String) -> void:
	if _targets.has(target_id):
		return

	_targets[target_id] = {
		"id": target_id,
		"target": null,
		"items": [],
	}

func _upsert_item(target_id: String, item: Dictionary) -> void:
	var entry: Dictionary = _targets.get(target_id, {})
	var items: Array = entry.get("items", [])
	var item_key := _get_item_key(item)

	for index in items.size():
		var existing: Dictionary = items[index]
		if _get_item_key(existing) == item_key:
			items[index] = item
			entry["items"] = items
			_targets[target_id] = entry
			return

	items.append(item)
	entry["items"] = items
	_targets[target_id] = entry

func _append_unique_items(target_items: Array[Dictionary], source_items: Array) -> void:
	var existing_keys := {}
	for item in target_items:
		existing_keys[_get_item_key(item)] = true

	for item_variant in source_items:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var item_key := _get_item_key(item)
		if existing_keys.has(item_key):
			continue
		existing_keys[item_key] = true
		target_items.append(item)

func _find_item(target_id: String, member_name: String) -> Dictionary:
	var entry: Dictionary = _targets.get(target_id.strip_edges(), {})
	var items: Array = entry.get("items", [])
	for item_variant in items:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		if str(item.get("member_name", "")) == member_name:
			return item
	return {}

func _get_target(target_id: String) -> Object:
	var normalized_target_id := target_id.strip_edges()
	var entry: Dictionary = _targets.get(normalized_target_id, {})
	var target: Object = entry.get("target", null)
	if target == null:
		return null
	if not _is_valid_target(target):
		_targets.erase(normalized_target_id)
		return null
	return target

func _resolve_target_id(target_id: String, target: Object) -> String:
	var normalized_target_id := target_id.strip_edges()
	if not normalized_target_id.is_empty():
		return normalized_target_id

	for key in _targets.keys():
		var entry: Dictionary = _targets[key]
		if entry.get("target") == target:
			return str(entry.get("id", ""))

	return target.get_class()

func _normalize_target_id(target_id: String, fallback: String) -> String:
	var normalized_target_id := target_id.strip_edges()
	return fallback if normalized_target_id.is_empty() else normalized_target_id

func _get_item_key(item: Dictionary) -> String:
	var member_key := str(item.get("member_name", ""))
	if member_key.is_empty():
		member_key = str(item.get("name", ""))
	return "%s|%s|%s|%s" % [
		str(item.get("target_id", "")),
		str(item.get("type", "")),
		member_key,
		str(item.get("group", GROUP_DEFAULT)),
	]

func _get_group_key(target_id: String, group: String) -> String:
	return "%s|%s" % [target_id.strip_edges(), _normalize_group(group)]

func _get_target_group_display_modes(target_id: String) -> Dictionary:
	var result := {}
	var prefix := "%s|" % target_id.strip_edges()
	for key in _group_display_modes.keys():
		var key_text := str(key)
		if key_text.begins_with(prefix):
			result[key_text.substr(prefix.length())] = int(_group_display_modes[key])
	return result

func _normalize_group(group: String) -> String:
	var normalized_group := group.strip_edges()
	return GROUP_DEFAULT if normalized_group.is_empty() else normalized_group

func _normalize_label(name: String, fallback: String) -> String:
	var label := name.strip_edges()
	return fallback if label.is_empty() else label

func _is_valid_target(target: Object) -> bool:
	return target != null and is_instance_valid(target)
