extends RefCounted

# Cyclic references are unsupported; the depth guard prevents stack overflows.
const DEFAULT_MAX_DEPTH := 64

static var _property_types_cache = {}
static var _property_types_cache_signatures = {}
static var _global_class_path_cache = {}
static var _script_type_cache = {}
static var _last_error_message: String = ""
static var _has_error: bool = false
static var _error_messages: Array[String] = []

static func serialize(obj, include_ignored: bool = false, max_depth: int = DEFAULT_MAX_DEPTH) -> Dictionary:
	_reset_error_state()
	var safe_max_depth := _sanitize_max_depth(max_depth)
	_warn_if_zero_max_depth(safe_max_depth, "serialize")
	return _serialize_object(obj, include_ignored, 0, safe_max_depth)

static func deserialize(
	data: Dictionary,
	target,
	include_ignored: bool = false,
	max_depth: int = DEFAULT_MAX_DEPTH
) -> void:
	_reset_error_state()
	var safe_max_depth := _sanitize_max_depth(max_depth)
	_warn_if_zero_max_depth(safe_max_depth, "deserialize")
	_deserialize_object(data, target, include_ignored, 0, safe_max_depth)

static func create_from_dict(
	script_path: String,
	data: Dictionary,
	include_ignored: bool = false,
	max_depth: int = DEFAULT_MAX_DEPTH
):
	_reset_error_state()
	var script = load(script_path)
	if script == null:
		_report_error("JsonSerializer.create_from_dict failed to load script '%s'." % script_path)
		return null

	var instance = script.new()
	if not _is_json_object(instance):
		_report_error(
			"JsonSerializer.create_from_dict expected a JsonObject-compatible instance for '%s'."
			% script_path
		)
		return null

	var safe_max_depth := _sanitize_max_depth(max_depth)
	_warn_if_zero_max_depth(safe_max_depth, "create_from_dict")
	_deserialize_object(data, instance, include_ignored, 0, safe_max_depth)
	if has_error():
		return null
	return instance

static func clear_cache() -> void:
	_property_types_cache.clear()
	_property_types_cache_signatures.clear()
	_global_class_path_cache.clear()
	_script_type_cache.clear()

static func refresh_cache_for(object: Object) -> void:
	var script_path = _get_script_path(object)
	_property_types_cache.erase(script_path)
	_property_types_cache_signatures.erase(script_path)
	_ensure_property_types_cached(object)

static func clear_last_error() -> void:
	_reset_error_state()

static func has_error() -> bool:
	return _has_error

static func get_last_error() -> String:
	return _last_error_message

static func get_error_messages() -> Array[String]:
	return _error_messages.duplicate()

static func _serialize_object(obj, include_ignored: bool, depth: int, max_depth: int) -> Dictionary:
	if _is_depth_exceeded(depth, max_depth, "serialize"):
		return {}

	var config = obj._get_serialize_config()
	var data = {}
	for prop_name in _get_script_property_names(obj):
		var prop_config: Dictionary = config.get(prop_name, {})
		if prop_config.get("ignore", false) and not include_ignored:
			continue

		var json_key: String = prop_config.get("json_name", prop_name)
		data[json_key] = _serialize_value(obj.get(prop_name), include_ignored, depth + 1, max_depth)
		if has_error():
			return {}
	return data

static func _serialize_value(
	value,
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
) -> Variant:
	if value == null:
		return null
	if _is_depth_exceeded(depth, max_depth, "serialize"):
		return null
	if _is_json_object(value):
		return _serialize_object(value, include_ignored, depth, max_depth)

	match typeof(value):
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR4:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_VECTOR4I:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_RECT2:
			var rect2_pos = _serialize_value(value.position, include_ignored, depth + 1, max_depth)
			if has_error():
				return null
			var rect2_size = _serialize_value(value.size, include_ignored, depth + 1, max_depth)
			if has_error():
				return null
			return {
				"pos": rect2_pos,
				"size": rect2_size
			}
		TYPE_RECT2I:
			var rect2i_pos = _serialize_value(value.position, include_ignored, depth + 1, max_depth)
			if has_error():
				return null
			var rect2i_size = _serialize_value(value.size, include_ignored, depth + 1, max_depth)
			if has_error():
				return null
			return {
				"pos": rect2i_pos,
				"size": rect2i_size
			}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_STRING_NAME:
			return str(value)
		TYPE_NODE_PATH:
			return str(value)
		TYPE_DICTIONARY:
			var dict = {}
			for key in value:
				dict[key] = _serialize_value(value[key], include_ignored, depth + 1, max_depth)
				if has_error():
					return null
			return dict
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
		TYPE_PACKED_VECTOR4_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			var array_data = []
			for item in value:
				array_data.append(_serialize_value(item, include_ignored, depth + 1, max_depth))
				if has_error():
					return null
			return array_data

	if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value

	_report_error(
		"JsonSerializer.serialize does not support Variant type %s." % type_string(typeof(value))
	)
	return null

static func _deserialize_object(
	data: Dictionary,
	target,
	include_ignored: bool,
	depth: int,
	max_depth: int
) -> void:
	if _is_depth_exceeded(depth, max_depth, "deserialize"):
		return

	var config = target._get_serialize_config()
	for prop_name in _get_script_property_names(target):
		if has_error():
			return

		var prop_config: Dictionary = config.get(prop_name, {})
		if prop_config.get("ignore", false) and not include_ignored:
			continue

		var dict_key: String = prop_config.get("json_name", prop_name)
		if not data.has(dict_key):
			continue

		var current = target.get(prop_name)
		var expected_type_info = _get_property_type_info(target, prop_name)
		target.set(
			prop_name,
			_deserialize_value(
				data[dict_key],
				current,
				expected_type_info,
				include_ignored,
				depth + 1,
				max_depth
			)
		)
		if has_error():
			return

static func _deserialize_value(
	raw,
	current,
	expected_type_info: Dictionary = {},
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
):
	if raw == null:
		return null
	if _is_depth_exceeded(depth, max_depth, "deserialize"):
		return current

	var expected_type: int = int(expected_type_info.get("type", TYPE_NIL))
	var hint_string: String = str(expected_type_info.get("hint_string", ""))
	var class_name_hint: String = str(expected_type_info.get("class_name", ""))

	match expected_type:
		TYPE_STRING_NAME:
			return _deserialize_string_like_value(raw, current, TYPE_STRING_NAME)
		TYPE_NODE_PATH:
			return _deserialize_string_like_value(raw, current, TYPE_NODE_PATH)

	if typeof(raw) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
		return raw

	if raw is Array:
		if _is_array_like_type(expected_type):
			return _deserialize_array_like(
				raw,
				current,
				expected_type_info,
				include_ignored,
				depth,
				max_depth
			)
		if current is Array:
			return _deserialize_untyped_array(raw, current, include_ignored, depth, max_depth)
		if expected_type != TYPE_NIL:
			_report_error(
				"JsonSerializer.deserialize expected %s but received Array. Keeping the current value."
				% type_string(expected_type)
			)
			return current
		return raw

	if raw is Dictionary:
		if expected_type == TYPE_OBJECT:
			return _deserialize_object_value(
				raw,
				current,
				hint_string,
				class_name_hint,
				include_ignored,
				depth,
				max_depth
			)

		if _is_builtin_struct_type(expected_type):
			return _deserialize_builtin_struct(raw, expected_type, depth, max_depth)

		if expected_type == TYPE_DICTIONARY:
			return _deserialize_dictionary(
				raw,
				current,
				expected_type_info,
				include_ignored,
				depth,
				max_depth
			)

		if _is_json_object(current):
			_deserialize_object(raw, current, include_ignored, depth, max_depth)
			return current
		if current is Dictionary:
			return _deserialize_dictionary(raw, current, {}, include_ignored, depth, max_depth)
		if expected_type != TYPE_NIL:
			_report_error(
				"JsonSerializer.deserialize expected %s but received Dictionary. Keeping the current value."
				% type_string(expected_type)
			)
			return current

	return raw

static func _deserialize_object_value(
	raw: Dictionary,
	current,
	hint_string: String,
	class_name_hint: String,
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
):
	if _is_json_object(current):
		_deserialize_object(raw, current, include_ignored, depth, max_depth)
		return current

	var instance = _create_instance_from_type(hint_string, class_name_hint)
	if _is_json_object(instance):
		_deserialize_object(raw, instance, include_ignored, depth, max_depth)
		return instance

	_report_error(
		(
			"JsonSerializer.deserialize failed to instantiate object for hint '%s' / class '%s'. "
			+ "Keeping the current value."
		)
		% [hint_string, class_name_hint]
	)
	return current

static func _deserialize_string_like_value(raw, current, expected_type: int):
	if typeof(raw) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_STRING_NAME, TYPE_NODE_PATH]:
		if expected_type == TYPE_STRING_NAME:
			return StringName(str(raw))
		return NodePath(str(raw))

	_report_error(
		"JsonSerializer.deserialize expected a scalar value for %s, got %s. Keeping the current value."
		% [type_string(expected_type), type_string(typeof(raw))]
	)
	if current != null:
		return current
	if expected_type == TYPE_STRING_NAME:
		return StringName()
	return NodePath()

static func _deserialize_untyped_array(
	raw: Array,
	current: Array,
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
) -> Array:
	var result = _make_array_result(current)
	if has_error():
		return current
	for i in raw.size():
		var elem_current = current[i] if i < current.size() else null
		result.append(_deserialize_value(raw[i], elem_current, {}, include_ignored, depth + 1, max_depth))
		if has_error():
			return current
	return result

static func _deserialize_dictionary(
	raw: Dictionary,
	current,
	expected_type_info: Dictionary = {},
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
) -> Dictionary:
	var result = _make_dictionary_result(current)
	var value_type_info = _get_dictionary_value_type_info(expected_type_info, current)
	if has_error():
		return current if current is Dictionary else result
	for key in raw:
		var old_value = current.get(key) if current is Dictionary else null
		result[key] = _deserialize_value(
			raw[key],
			old_value,
			value_type_info,
			include_ignored,
			depth + 1,
			max_depth
		)
		if has_error():
			return current if current is Dictionary else result
	return result

static func _deserialize_array_like(
	raw: Array,
	current,
	expected_type_info: Dictionary,
	include_ignored: bool = false,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
):
	var expected_type: int = int(expected_type_info.get("type", TYPE_NIL))
	if expected_type == TYPE_ARRAY:
		var result = _make_array_result(current, expected_type_info)
		if has_error():
			return current if current is Array else result
		var elem_type_info = _get_array_element_type_info(expected_type_info)
		for i in raw.size():
			var elem_current = null
			if current is Array and i < current.size():
				elem_current = current[i]
			result.append(
				_deserialize_value(
					raw[i],
					elem_current,
					elem_type_info,
					include_ignored,
					depth + 1,
					max_depth
				)
			)
			if has_error():
				return current if current is Array else result
		return result

	match expected_type:
		TYPE_PACKED_BYTE_ARRAY:
			var byte_array = PackedByteArray()
			for item in raw:
				byte_array.append(int(item))
			return byte_array
		TYPE_PACKED_INT32_ARRAY:
			var int32_array = PackedInt32Array()
			for item in raw:
				int32_array.append(int(item))
			return int32_array
		TYPE_PACKED_INT64_ARRAY:
			var int64_array = PackedInt64Array()
			for item in raw:
				int64_array.append(int(item))
			return int64_array
		TYPE_PACKED_FLOAT32_ARRAY:
			var float32_array = PackedFloat32Array()
			for item in raw:
				float32_array.append(float(item))
			return float32_array
		TYPE_PACKED_FLOAT64_ARRAY:
			var float64_array = PackedFloat64Array()
			for item in raw:
				float64_array.append(float(item))
			return float64_array
		TYPE_PACKED_STRING_ARRAY:
			var string_array = PackedStringArray()
			for item in raw:
				string_array.append(str(item))
			return string_array
		TYPE_PACKED_VECTOR2_ARRAY:
			var vector2_array = PackedVector2Array()
			for item in raw:
				vector2_array.append(_deserialize_value(item, null, {"type": TYPE_VECTOR2}, false, depth + 1, max_depth))
				if has_error():
					return current if typeof(current) == TYPE_PACKED_VECTOR2_ARRAY else vector2_array
			return vector2_array
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector3_array = PackedVector3Array()
			for item in raw:
				vector3_array.append(_deserialize_value(item, null, {"type": TYPE_VECTOR3}, false, depth + 1, max_depth))
				if has_error():
					return current if typeof(current) == TYPE_PACKED_VECTOR3_ARRAY else vector3_array
			return vector3_array
		TYPE_PACKED_VECTOR4_ARRAY:
			var vector4_array = PackedVector4Array()
			for item in raw:
				vector4_array.append(_deserialize_value(item, null, {"type": TYPE_VECTOR4}, false, depth + 1, max_depth))
				if has_error():
					return current if typeof(current) == TYPE_PACKED_VECTOR4_ARRAY else vector4_array
			return vector4_array
		TYPE_PACKED_COLOR_ARRAY:
			var color_array = PackedColorArray()
			for item in raw:
				color_array.append(_deserialize_value(item, null, {"type": TYPE_COLOR}, false, depth + 1, max_depth))
				if has_error():
					return current if typeof(current) == TYPE_PACKED_COLOR_ARRAY else color_array
			return color_array

	return raw

static func _make_array_result(current, expected_type_info: Dictionary = {}) -> Array:
	if current is Array and current.is_typed():
		return Array(
			[],
			current.get_typed_builtin(),
			current.get_typed_class_name(),
			current.get_typed_script()
		)

	var elem_type_info = _get_array_element_type_info(expected_type_info)
	if elem_type_info.is_empty():
		return []

	var array_type = _container_type_args_from_type_info(elem_type_info)
	if not bool(array_type.get("valid", true)):
		return current if current is Array else []
	return Array(
		[],
		int(array_type.get("builtin", TYPE_NIL)),
		str(array_type.get("class_name", "")),
		array_type.get("script", null)
	)

static func _make_dictionary_result(current) -> Dictionary:
	if current is Dictionary and current.is_typed():
		return Dictionary(
			{},
			current.get_typed_key_builtin(),
			current.get_typed_key_class_name(),
			current.get_typed_key_script(),
			current.get_typed_value_builtin(),
			current.get_typed_value_class_name(),
			current.get_typed_value_script()
		)
	return {}

static func _is_json_object(value) -> bool:
	return value != null and value is Object and value.has_method("_get_serialize_config")

static func _deserialize_builtin_struct(
	raw: Dictionary,
	expected_type: int,
	depth: int = 0,
	max_depth: int = DEFAULT_MAX_DEPTH
):
	match expected_type:
		TYPE_VECTOR2:
			return Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
		TYPE_VECTOR2I:
			return Vector2i(int(raw.get("x", 0)), int(raw.get("y", 0)))
		TYPE_VECTOR3:
			return Vector3(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)), float(raw.get("z", 0.0)))
		TYPE_VECTOR3I:
			return Vector3i(int(raw.get("x", 0)), int(raw.get("y", 0)), int(raw.get("z", 0)))
		TYPE_VECTOR4:
			return Vector4(
				float(raw.get("x", 0.0)),
				float(raw.get("y", 0.0)),
				float(raw.get("z", 0.0)),
				float(raw.get("w", 0.0))
			)
		TYPE_VECTOR4I:
			return Vector4i(
				int(raw.get("x", 0)),
				int(raw.get("y", 0)),
				int(raw.get("z", 0)),
				int(raw.get("w", 0))
			)
		TYPE_RECT2:
			var rect_position: Vector2 = _deserialize_value(
				raw.get("pos", {}),
				null,
				{"type": TYPE_VECTOR2},
				false,
				depth + 1,
				max_depth
			)
			var rect_size: Vector2 = _deserialize_value(
				raw.get("size", {}),
				null,
				{"type": TYPE_VECTOR2},
				false,
				depth + 1,
				max_depth
			)
			return Rect2(rect_position, rect_size)
		TYPE_RECT2I:
			var rect_position_i: Vector2i = _deserialize_value(
				raw.get("pos", {}),
				null,
				{"type": TYPE_VECTOR2I},
				false,
				depth + 1,
				max_depth
			)
			var rect_size_i: Vector2i = _deserialize_value(
				raw.get("size", {}),
				null,
				{"type": TYPE_VECTOR2I},
				false,
				depth + 1,
				max_depth
			)
			return Rect2i(rect_position_i, rect_size_i)
		TYPE_COLOR:
			return Color(
				float(raw.get("r", 0.0)),
				float(raw.get("g", 0.0)),
				float(raw.get("b", 0.0)),
				float(raw.get("a", 1.0))
			)
	return raw

static func _is_array_like_type(expected_type: int) -> bool:
	return expected_type in [
		TYPE_ARRAY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_VECTOR4_ARRAY,
		TYPE_PACKED_COLOR_ARRAY
	]

static func _is_builtin_struct_type(expected_type: int) -> bool:
	return expected_type in [
		TYPE_VECTOR2,
		TYPE_VECTOR2I,
		TYPE_VECTOR3,
		TYPE_VECTOR3I,
		TYPE_VECTOR4,
		TYPE_VECTOR4I,
		TYPE_RECT2,
		TYPE_RECT2I,
		TYPE_COLOR
	]

static func _get_property_type_info(object: Object, prop_name: String) -> Dictionary:
	_ensure_property_types_cached(object)
	var script_path = _get_script_path(object)
	return _property_types_cache.get(script_path, {}).get(prop_name, {})

static func _ensure_property_types_cached(object: Object) -> void:
	var script_path = _get_script_path(object)
	var signature = _build_property_types_signature(object)
	if _property_types_cache.has(script_path) \
	and _property_types_cache_signatures.get(script_path, "") == signature:
		return

	var types_dict = {}
	for prop in object.get_property_list():
		var name: String = str(prop.get("name", ""))
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue

		types_dict[name] = {
			"type": int(prop.get("type", TYPE_NIL)),
			"hint": int(prop.get("hint", 0)),
			"hint_string": str(prop.get("hint_string", "")),
			"class_name": str(prop.get("class_name", ""))
		}
	_property_types_cache[script_path] = types_dict
	_property_types_cache_signatures[script_path] = signature

static func _build_property_types_signature(object: Object) -> String:
	var signature_parts: Array[String] = []
	for prop in object.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue

		signature_parts.append(
			"%s|%d|%d|%s|%s" % [
				str(prop.get("name", "")),
				int(prop.get("type", TYPE_NIL)),
				int(prop.get("hint", 0)),
				str(prop.get("hint_string", "")),
				str(prop.get("class_name", ""))
			]
		)
	return "||".join(signature_parts)

static func _get_script_property_names(object: Object) -> Array[String]:
	_ensure_property_types_cached(object)
	var script_path = _get_script_path(object)
	var names: Array[String] = []
	for key in _property_types_cache.get(script_path, {}).keys():
		names.append(str(key))
	return names

static func _get_script_path(object: Object) -> String:
	var script = object.get_script()
	return script.resource_path if script else object.get_class()

static func _create_instance_from_type(hint_string: String, class_name_hint: String) -> Object:
	var script = _resolve_script_type(hint_string)
	if script != null:
		var instance = _instantiate_script(script, hint_string)
		if instance != null:
			return instance
		_script_type_cache.erase(hint_string)
		script = _resolve_script_type(hint_string)
		instance = _instantiate_script(script, hint_string)
		if instance != null:
			return instance
	if not hint_string.is_empty() and ClassDB.class_exists(hint_string):
		return ClassDB.instantiate(hint_string)

	script = _resolve_script_type(class_name_hint)
	if script != null:
		var fallback_instance = _instantiate_script(script, class_name_hint)
		if fallback_instance != null:
			return fallback_instance
		_script_type_cache.erase(class_name_hint)
		script = _resolve_script_type(class_name_hint)
		fallback_instance = _instantiate_script(script, class_name_hint)
		if fallback_instance != null:
			return fallback_instance
	if not class_name_hint.is_empty() and ClassDB.class_exists(class_name_hint):
		return ClassDB.instantiate(class_name_hint)
	return null

static func _resolve_script_type(type_name: String):
	if type_name.is_empty():
		return null
	if _script_type_cache.has(type_name):
		var cached_script = _script_type_cache[type_name]
		if _is_valid_script_resource(cached_script):
			return cached_script
		_script_type_cache.erase(type_name)

	var script = null
	if type_name.ends_with(".gd") and ResourceLoader.exists(type_name):
		script = load(type_name)
	else:
		var script_path = _get_global_class_script_path(type_name)
		if not script_path.is_empty() and ResourceLoader.exists(script_path):
			script = load(script_path)

	if _is_valid_script_resource(script):
		_script_type_cache[type_name] = script
	return script

static func _instantiate_script(script, type_name: String) -> Object:
	if not _is_valid_script_resource(script):
		return null

	var instance = script.new()
	if instance == null:
		_report_error(
			"JsonSerializer failed to instantiate script-backed type '%s'." % type_name
		)
		return null
	return instance

static func _get_global_class_script_path(type_name: String) -> String:
	if type_name.is_empty():
		return ""
	if _global_class_path_cache.has(type_name):
		return _global_class_path_cache[type_name]

	var script_path = ""
	for item in ProjectSettings.get_global_class_list():
		if str(item.get("class", "")) != type_name:
			continue
		script_path = str(item.get("path", ""))
		break

	if script_path.is_empty():
		script_path = _guess_script_path_from_type_name(type_name)

	_global_class_path_cache[type_name] = script_path
	return script_path

static func _guess_script_path_from_type_name(type_name: String) -> String:
	var candidate_file_names: Array[String] = []
	var snake_case_name := type_name.to_snake_case()
	if not snake_case_name.is_empty():
		candidate_file_names.append("%s.gd" % snake_case_name)
	candidate_file_names.append("%s.gd" % type_name)

	for candidate_file_name in candidate_file_names:
		var script_path := _find_script_path_recursive("res://", candidate_file_name)
		if not script_path.is_empty():
			return script_path

	return ""

static func _find_script_path_recursive(directory_path: String, target_file_name: String) -> String:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return ""

	directory.list_dir_begin()
	while true:
		var entry_name := directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name in [".", ".."]:
			continue

		var entry_path := directory_path.path_join(entry_name)
		if directory.current_is_dir():
			var nested_result := _find_script_path_recursive(entry_path, target_file_name)
			if not nested_result.is_empty():
				directory.list_dir_end()
				return nested_result
			continue

		if entry_name == target_file_name:
			directory.list_dir_end()
			return entry_path

	directory.list_dir_end()
	return ""

static func _get_array_element_type_info(array_type_info: Dictionary) -> Dictionary:
	var hint: int = int(array_type_info.get("hint", 0))
	var hint_string: String = str(array_type_info.get("hint_string", ""))
	if hint_string.is_empty():
		return {}

	if hint in [PROPERTY_HINT_ARRAY_TYPE, PROPERTY_HINT_TYPE_STRING]:
		return _parse_type_spec(hint_string)

	return {}

static func _get_dictionary_value_type_info(expected_type_info: Dictionary, current) -> Dictionary:
	var declared_type_info = _parse_dictionary_value_type_info(expected_type_info)
	if not declared_type_info.is_empty():
		return declared_type_info

	if current is Dictionary and current.is_typed():
		return {
			"type": current.get_typed_value_builtin(),
			"hint_string": str(current.get_typed_value_class_name()),
			"class_name": str(current.get_typed_value_class_name()),
			"script": current.get_typed_value_script()
		}

	return {}

static func _parse_dictionary_value_type_info(dictionary_type_info: Dictionary) -> Dictionary:
	var hint: int = int(dictionary_type_info.get("hint", 0))
	var hint_string: String = str(dictionary_type_info.get("hint_string", ""))
	if hint_string.is_empty():
		return {}

	if hint not in [PROPERTY_HINT_DICTIONARY_TYPE, PROPERTY_HINT_TYPE_STRING]:
		return {}

	var hint_parts := hint_string.split(";", false, 1)
	if hint_parts.size() < 2:
		return {}

	return _parse_type_spec(hint_parts[1])

static func _parse_type_spec(type_spec: String) -> Dictionary:
	var normalized := type_spec.strip_edges()
	if normalized.is_empty():
		return {}

	var colon_index := normalized.find(":")
	if colon_index > 0:
		var prefix := normalized.substr(0, colon_index)
		var parsed_prefix = _parse_type_prefix(prefix)
		if not parsed_prefix.is_empty():
			var parsed_type: int = int(parsed_prefix.get("type", TYPE_NIL))
			var parsed_hint_string := normalized.substr(colon_index + 1)
			return {
				"type": parsed_type,
				"hint": int(parsed_prefix.get("hint", 0)),
				"hint_string": parsed_hint_string,
				"class_name": _type_spec_to_class_name(parsed_type, parsed_hint_string)
			}

	if normalized.is_valid_int():
		return {"type": int(normalized), "hint": 0, "hint_string": "", "class_name": ""}

	var builtin_type = _variant_type_from_name(normalized)
	if builtin_type != TYPE_NIL:
		return {"type": builtin_type, "hint": 0, "hint_string": "", "class_name": ""}

	return {"type": TYPE_OBJECT, "hint": 0, "hint_string": normalized, "class_name": normalized}

static func _parse_type_prefix(prefix: String) -> Dictionary:
	var slash_index := prefix.find("/")
	if slash_index < 0:
		if prefix.is_valid_int():
			return {"type": int(prefix), "hint": 0}
		return {}

	var type_part := prefix.substr(0, slash_index)
	var hint_part := prefix.substr(slash_index + 1)
	if not type_part.is_valid_int():
		return {}

	var parsed_hint := int(hint_part) if hint_part.is_valid_int() else 0
	return {"type": int(type_part), "hint": parsed_hint}

static func _type_spec_to_class_name(parsed_type: int, parsed_hint_string: String) -> String:
	if parsed_type != TYPE_OBJECT or parsed_hint_string.is_empty():
		return ""
	return parsed_hint_string

static func _container_type_args_from_type_info(type_info: Dictionary) -> Dictionary:
	var builtin_type: int = int(type_info.get("type", TYPE_NIL))
	var resolved_class_name: String = str(
		type_info.get("class_name", type_info.get("hint_string", ""))
	)
	var script = type_info.get("script", null)
	if script == null and builtin_type == TYPE_OBJECT:
		script = _resolve_script_type(resolved_class_name)

	var is_valid := true
	if builtin_type == TYPE_OBJECT \
	and not resolved_class_name.is_empty() \
	and script == null \
	and not ClassDB.class_exists(resolved_class_name):
		is_valid = false
		_report_error(
			"JsonSerializer could not resolve object type '%s' for a typed container."
			% resolved_class_name
		)

	return {
		"builtin": builtin_type,
		"class_name": resolved_class_name,
		"script": script,
		"valid": is_valid
	}

static func _variant_type_from_name(type_name: String) -> int:
	match type_name.to_lower():
		"bool":
			return TYPE_BOOL
		"int":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"string":
			return TYPE_STRING
		"vector2":
			return TYPE_VECTOR2
		"vector2i":
			return TYPE_VECTOR2I
		"rect2":
			return TYPE_RECT2
		"rect2i":
			return TYPE_RECT2I
		"vector3":
			return TYPE_VECTOR3
		"vector3i":
			return TYPE_VECTOR3I
		"vector4":
			return TYPE_VECTOR4
		"vector4i":
			return TYPE_VECTOR4I
		"color":
			return TYPE_COLOR
		"stringname":
			return TYPE_STRING_NAME
		"nodepath":
			return TYPE_NODE_PATH
		"dictionary":
			return TYPE_DICTIONARY
		"array":
			return TYPE_ARRAY
	return TYPE_NIL

static func _sanitize_max_depth(max_depth: int) -> int:
	return max(0, max_depth)

static func _warn_if_zero_max_depth(max_depth: int, operation: String) -> void:
	if max_depth != 0:
		return
	push_warning(
		"JsonSerializer.%s called with max_depth=0. Nested values will be rejected."
		% operation
	)

static func _reset_error_state() -> void:
	_last_error_message = ""
	_has_error = false
	_error_messages.clear()

static func _report_error(message: String) -> void:
	_last_error_message = message
	_has_error = true
	if _error_messages.is_empty() or _error_messages[-1] != message:
		_error_messages.append(message)
		push_error(message)

static func _is_valid_script_resource(script) -> bool:
	if script == null:
		return false
	if not (script is Script):
		return false

	var script_path := str(script.resource_path)
	if not script_path.is_empty() and not ResourceLoader.exists(script_path):
		return false
	return true

static func _is_depth_exceeded(depth: int, max_depth: int, operation: String) -> bool:
	if depth <= max_depth:
		return false

	_report_error(
		"JsonSerializer.%s exceeded max depth %d. Cyclic references are unsupported and deeply nested data is rejected."
		% [operation, max_depth]
	)
	return true
