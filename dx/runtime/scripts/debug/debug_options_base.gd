class_name DX_DebugOptionsBase
extends RefCounted

const DebugTargetFinder := preload("res://dx/runtime/scripts/debug/debug_target_finder.gd")

enum GroupDisplayMode {
	INLINE,
	COLLAPSE,
	PAGE,
}

const DEFAULT_OPTIONS_TARGET_ID := "Options"

var debug

func setup(debug_manager) -> void:
	debug = debug_manager

func register_options() -> void:
	pass

func get_target_id() -> String:
	return ""

func bind(_target: Object) -> void:
	pass

func get_targets() -> Array:
	return []

func action(group: String, arg1, arg2, arg3 = "", target_id: String = "") -> void:
	if debug == null:
		return
	if arg2 is Callable:
		_register_callable_action(group, str(arg1), arg2, target_id, str(arg3))
	elif arg1 is Object:
		_register_target_action(group, arg1, str(arg2), str(arg3), target_id)

func register_target(target: Object, target_id: String = "") -> void:
	if debug == null or target == null:
		return
	debug.register_target(_resolve_target_id(target_id, get_target_id()), target)

func group_display(group: String, mode: GroupDisplayMode, target_id: String = "") -> void:
	if debug == null or not debug.has_method("set_group_display_mode"):
		return
	debug.set_group_display_mode(
		_resolve_target_id(target_id, get_target_id()),
		group,
		int(mode)
	)

func number(
	group: String,
	target: Object,
	member_name: String,
	name: String,
	value_range: Dictionary = {},
	target_id: String = ""
) -> void:
	if debug == null or target == null:
		return
	debug.register_number(
		group,
		target,
		member_name,
		name,
		_resolve_target_id(target_id, get_target_id()),
		value_range
	)

func string(group: String, target: Object, member_name: String, name: String, target_id: String = "") -> void:
	if debug == null or target == null:
		return
	debug.register_string(group, target, member_name, name, _resolve_target_id(target_id, get_target_id()))

func boolean(group: String, target: Object, member_name: String, name: String, target_id: String = "") -> void:
	if debug == null or target == null:
		return
	debug.register_boolean(group, target, member_name, name, _resolve_target_id(target_id, get_target_id()))

func select(
	group: String,
	target: Object,
	member_name: String,
	name: String,
	options,
	target_id: String = ""
) -> void:
	if debug == null or target == null:
		return
	debug.register_select(
		group,
		target,
		member_name,
		name,
		_normalize_select_options(options),
		_resolve_target_id(target_id, get_target_id())
	)

func readonly(group: String, getter: Callable, name: String, target_id: String = "") -> void:
	if debug == null:
		return
	debug.register_readonly(group, getter, name, _resolve_target_id(target_id, get_target_id()))

func get_bound_target(target_id: String = "") -> Object:
	if debug == null or not debug.has_method("get_target"):
		return null
	return debug.get_target(_resolve_target_id(target_id, get_target_id()))

func find_in_current_scene_by_script(script_path: String) -> Object:
	return DebugTargetFinder.find_in_current_scene_by_script(script_path)

func get_root_node(path: NodePath) -> Node:
	return DebugTargetFinder.get_root_node(path)

func get_current_scene() -> Node:
	return DebugTargetFinder.get_current_scene()

func _has_script_path(target: Object, script_path: String) -> bool:
	return DebugTargetFinder.has_script_path(target, script_path)

func _resolve_target_id(target_id: String, fallback: String) -> String:
	var resolved := target_id.strip_edges()
	if resolved.is_empty():
		resolved = fallback.strip_edges()
	if resolved.is_empty():
		resolved = DEFAULT_OPTIONS_TARGET_ID
	return resolved

func _resolve_action_member_name(callback: Callable, member_name: String, group: String, name: String) -> String:
	var resolved := member_name.strip_edges()
	if not resolved.is_empty():
		return resolved
	if callback.is_valid():
		resolved = str(callback.get_method()).strip_edges()
		if not resolved.is_empty():
			return resolved
	return "%s:%s" % [group.strip_edges(), name.strip_edges()]

func _normalize_select_options(options) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if options is Dictionary:
		for key in (options as Dictionary).keys():
			result.append({
				"label": str(key),
				"value": (options as Dictionary)[key],
			})
		return result

	if options is Array:
		for item in options:
			if item is Dictionary:
				result.append({
					"label": str(item.get("label", item.get("name", item.get("value", "")))),
					"value": item.get("value", item.get("id", item.get("name", ""))),
				})
			else:
				result.append({
					"label": str(item),
					"value": item,
				})
	return result

func _register_callable_action(
	group: String,
	name: String,
	callback: Callable,
	target_id: String,
	member_name: String
) -> void:
	if not callback.is_valid() or not debug.has_method("register_callable_action"):
		return
	debug.register_callable_action(
		group,
		callback,
		name,
		_resolve_target_id(target_id, DEFAULT_OPTIONS_TARGET_ID),
		_resolve_action_member_name(callback, member_name, group, name)
	)

func _register_target_action(
	group: String,
	target: Object,
	method_name: String,
	name: String,
	target_id: String
) -> void:
	if target == null:
		return
	debug.register_action(group, target, method_name, name, _resolve_target_id(target_id, get_target_id()))
