class_name DX_DebugManager
extends RefCounted

const GROUP_DEFAULT := "Default"
const TYPE_ACTION := "action"
const TYPE_STRING := "string"
const TYPE_NUMBER := "number"

const META_PATTERN := "^\\s*#\\s*@dx_debug_(action|string|number)\\((.*)\\)\\s*$"
const VALUE_NAME_PATTERN := "(^|,)\\s*name\\s*=\\s*\"([^\"]+)\""
const VALUE_GROUP_PATTERN := "(^|,)\\s*group\\s*=\\s*\"([^\"]+)\""
const FUNC_PATTERN := "^\\s*func\\s+([A-Za-z0-9_]+)\\s*\\("
const VAR_PATTERN := "^\\s*var\\s+([A-Za-z0-9_]+)\\s*[:= ]"

var dx: Node
var _targets: Dictionary = {}

func register_target(target_id: String, target: Object, script_path: String = "") -> void:
	if target == null:
		return

	var normalized_target_id := target_id.strip_edges()
	if normalized_target_id.is_empty():
		normalized_target_id = target.get_class()

	var resolved_script_path := script_path.strip_edges()
	if resolved_script_path.is_empty():
		resolved_script_path = _resolve_script_path(target)
	if resolved_script_path.is_empty():
		return

	_targets[normalized_target_id] = {
		"id": normalized_target_id,
		"target": target,
		"script_path": resolved_script_path,
	}

func unregister_target(target_id: String) -> void:
	_targets.erase(target_id.strip_edges())

func get_target_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _targets.keys():
		var entry: Dictionary = _targets[key]
		var target: Object = entry.get("target")
		if target == null:
			continue

		result.append(
			{
				"id": entry.get("id", ""),
				"items": _parse_debug_items(target, str(entry.get("script_path", ""))),
			}
		)
	return result

func invoke_action(target_id: String, method_name: String) -> void:
	var target := _get_target(target_id)
	if target == null or not target.has_method(method_name):
		return
	target.call(method_name)

func read_value(target_id: String, member_name: String) -> Variant:
	var target := _get_target(target_id)
	if target == null:
		return null
	return target.get(member_name)

func write_number(target_id: String, member_name: String, value: float) -> void:
	var target := _get_target(target_id)
	if target == null:
		return

	var current_value: Variant = target.get(member_name)
	if typeof(current_value) == TYPE_INT:
		target.set(member_name, int(round(value)))
	else:
		target.set(member_name, value)

func write_string(target_id: String, member_name: String, value: String) -> void:
	var target := _get_target(target_id)
	if target == null:
		return
	target.set(member_name, value)

func _get_target(target_id: String) -> Object:
	var entry: Dictionary = _targets.get(target_id.strip_edges(), {})
	return entry.get("target", null)

func _resolve_script_path(target: Object) -> String:
	if target == null:
		return ""
	if target.has_method("get_script"):
		var script = target.get_script()
		if script != null and script is Script:
			return str((script as Script).resource_path)
	return ""

func _parse_debug_items(target: Object, script_path: String) -> Array[Dictionary]:
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return []

	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())

	var results: Array[Dictionary] = []
	var pending_meta: Dictionary = {}
	var func_regex := RegEx.new()
	func_regex.compile(FUNC_PATTERN)
	var var_regex := RegEx.new()
	var var_compile_error := var_regex.compile(VAR_PATTERN)
	if var_compile_error != OK:
		return results

	for line in lines:
		var meta := _parse_meta_line(line)
		if not meta.is_empty():
			pending_meta = meta
			continue

		if pending_meta.is_empty():
			continue

		var func_result := func_regex.search(line)
		if func_result != null and pending_meta.get("type") == TYPE_ACTION:
			var method_name := func_result.get_string(1)
			results.append(_build_item(target, pending_meta, method_name, true))
			pending_meta = {}
			continue

		var var_result := var_regex.search(line)
		if var_result != null:
			var member_name := var_result.get_string(1)
			results.append(_build_item(target, pending_meta, member_name, false))
			pending_meta = {}

	return results

func _parse_meta_line(line: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile(META_PATTERN)
	var result := regex.search(line)
	if result == null:
		return {}

	var item_type := str(result.get_string(1))
	var args_text := str(result.get_string(2))
	return {
		"type": item_type,
		"name": _extract_meta_value(args_text, VALUE_NAME_PATTERN, ""),
		"group": _extract_meta_value(args_text, VALUE_GROUP_PATTERN, GROUP_DEFAULT),
	}

func _extract_meta_value(args_text: String, pattern: String, default_value: String) -> String:
	var regex := RegEx.new()
	regex.compile(pattern)
	var result := regex.search(args_text)
	if result == null:
		return default_value
	return result.get_string(2)

func _build_item(target: Object, meta: Dictionary, member_name: String, is_method: bool) -> Dictionary:
	var label := str(meta.get("name", "")).strip_edges()
	if label.is_empty():
		label = member_name

	return {
		"target_id": _find_target_id(target),
		"type": str(meta.get("type", "")),
		"group": str(meta.get("group", GROUP_DEFAULT)),
		"name": label,
		"member_name": member_name,
		"is_method": is_method,
	}

func _find_target_id(target: Object) -> String:
	for key in _targets.keys():
		var entry: Dictionary = _targets[key]
		if entry.get("target") == target:
			return str(entry.get("id", ""))
	return ""
