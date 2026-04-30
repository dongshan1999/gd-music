class_name JsonSerializer
extends RefCounted

static var _property_types_cache = {}
static var _global_class_path_cache = {}

static func serialize(obj, include_ignored: bool = false) -> Dictionary:
	var config = obj._get_serialize_config()
	var data = {}
	for prop_name in _get_script_property_names(obj):
		var prop_config: Dictionary = config.get(prop_name, {})
		if prop_config.get("ignore", false) and not include_ignored:
			continue

		var json_key: String = prop_config.get("json_name", prop_name)
		data[json_key] = _serialize_value(obj.get(prop_name), include_ignored)
	return data

static func deserialize(data: Dictionary, target, include_ignored: bool = false) -> void:
	var config = target._get_serialize_config()
	for prop_name in _get_script_property_names(target):
		var prop_config: Dictionary = config.get(prop_name, {})
		if prop_config.get("ignore", false) and not include_ignored:
			continue

		var dict_key: String = prop_config.get("json_name", prop_name)
		if not data.has(dict_key):
			continue

		var current = target.get(prop_name)
		var expected_type_info = _get_property_type_info(target, prop_name)
		target.set(prop_name, _deserialize_value(data[dict_key], current, expected_type_info, include_ignored))

static func create_from_dict(script_path: String, data: Dictionary, include_ignored: bool = false):
	var script = load(script_path)
	if script == null:
		return null

	var instance = script.new()
	if _is_json_object(instance):
		deserialize(data, instance, include_ignored)
		return instance
	return null

static func _serialize_value(value, include_ignored: bool = false) -> Variant:
	if value == null:
		return null
	if _is_json_object(value):
		return serialize(value, include_ignored)

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
			return {
				"pos": _serialize_value(value.position, include_ignored),
				"size": _serialize_value(value.size, include_ignored)
			}
		TYPE_RECT2I:
			return {
				"pos": _serialize_value(value.position, include_ignored),
				"size": _serialize_value(value.size, include_ignored)
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
				dict[key] = _serialize_value(value[key], include_ignored)
			return dict
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			var array_data = []
			for item in value:
				array_data.append(_serialize_value(item, include_ignored))
			return array_data

	return value

static func _deserialize_value(raw, current, expected_type_info: Dictionary = {}, include_ignored: bool = false):
	if raw == null:
		return null

	var expected_type: int = int(expected_type_info.get("type", TYPE_NIL))
	var hint_string: String = str(expected_type_info.get("hint_string", ""))
	var class_name_hint: String = str(expected_type_info.get("class_name", ""))

	if typeof(raw) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL]:
		match expected_type:
			TYPE_STRING_NAME:
				return StringName(str(raw))
			TYPE_NODE_PATH:
				return NodePath(str(raw))
		return raw

	if raw is Array:
		if _is_array_like_type(expected_type):
			return _deserialize_array_like(raw, current, expected_type_info, include_ignored)
		if current is Array:
			return _deserialize_untyped_array(raw, current, include_ignored)
		return raw

	if raw is Dictionary:
		if expected_type == TYPE_OBJECT:
			if _is_json_object(current):
				deserialize(raw, current, include_ignored)
				return current

			var instance = _create_instance_from_type(hint_string, class_name_hint)
			if _is_json_object(instance):
				deserialize(raw, instance, include_ignored)
				return instance
			return raw

		if _is_builtin_struct_type(expected_type):
			return _deserialize_builtin_struct(raw, expected_type)

		if expected_type == TYPE_DICTIONARY:
			return _deserialize_dictionary(raw, current, include_ignored)

		if _is_json_object(current):
			deserialize(raw, current, include_ignored)
			return current
		if current is Dictionary:
			return _deserialize_dictionary(raw, current, include_ignored)

	return raw

static func _deserialize_untyped_array(raw: Array, current: Array, include_ignored: bool = false) -> Array:
	var result = _make_array_result(current)
	for i in raw.size():
		var elem_current = current[i] if i < current.size() else null
		result.append(_deserialize_value(raw[i], elem_current, {}, include_ignored))
	return result

static func _deserialize_dictionary(raw: Dictionary, current, include_ignored: bool = false) -> Dictionary:
	var result = {}
	for key in raw:
		var old_value = current.get(key) if current is Dictionary else null
		result[key] = _deserialize_value(raw[key], old_value, {}, include_ignored)
	return result

static func _deserialize_array_like(raw: Array, current, expected_type_info: Dictionary, include_ignored: bool = false):
	var expected_type: int = int(expected_type_info.get("type", TYPE_NIL))
	if expected_type == TYPE_ARRAY:
		var result = _make_array_result(current)
		var elem_type_info = _get_array_element_type_info(expected_type_info)
		for i in raw.size():
			var elem_current = null
			if current is Array and i < current.size():
				elem_current = current[i]
			result.append(_deserialize_value(raw[i], elem_current, elem_type_info, include_ignored))
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
				vector2_array.append(_deserialize_value(item, null, {"type": TYPE_VECTOR2}))
			return vector2_array
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector3_array = PackedVector3Array()
			for item in raw:
				vector3_array.append(_deserialize_value(item, null, {"type": TYPE_VECTOR3}))
			return vector3_array
		TYPE_PACKED_COLOR_ARRAY:
			var color_array = PackedColorArray()
			for item in raw:
				color_array.append(_deserialize_value(item, null, {"type": TYPE_COLOR}))
			return color_array

	return raw

static func _make_array_result(current) -> Array:
	if current is Array and current.is_typed():
		var typed_result: Array = current.duplicate()
		typed_result.clear()
		return typed_result
	return []

static func _is_json_object(value) -> bool:
	return value != null and value is Object and value.has_method("_get_serialize_config")

static func _deserialize_builtin_struct(raw: Dictionary, expected_type: int):
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
			var rect_position: Vector2 = _deserialize_value(raw.get("pos", {}), null, {"type": TYPE_VECTOR2})
			var rect_size: Vector2 = _deserialize_value(raw.get("size", {}), null, {"type": TYPE_VECTOR2})
			return Rect2(rect_position, rect_size)
		TYPE_RECT2I:
			var rect_position_i: Vector2i = _deserialize_value(raw.get("pos", {}), null, {"type": TYPE_VECTOR2I})
			var rect_size_i: Vector2i = _deserialize_value(raw.get("size", {}), null, {"type": TYPE_VECTOR2I})
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
	if _property_types_cache.has(script_path):
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
		return script.new()
	if not hint_string.is_empty() and ClassDB.class_exists(hint_string):
		return ClassDB.instantiate(hint_string)

	script = _resolve_script_type(class_name_hint)
	if script != null:
		return script.new()
	if not class_name_hint.is_empty() and ClassDB.class_exists(class_name_hint):
		return ClassDB.instantiate(class_name_hint)
	return null

static func _resolve_script_type(type_name: String):
	if type_name.is_empty():
		return null
	if type_name.ends_with(".gd") and ResourceLoader.exists(type_name):
		return load(type_name)

	var script_path = _get_global_class_script_path(type_name)
	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		return load(script_path)
	return null

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

	_global_class_path_cache[type_name] = script_path
	return script_path

static func _get_array_element_type_info(array_type_info: Dictionary) -> Dictionary:
	var hint: int = int(array_type_info.get("hint", 0))
	var hint_string: String = str(array_type_info.get("hint_string", ""))
	if hint_string.is_empty():
		return {}

	if hint in [PROPERTY_HINT_ARRAY_TYPE, PROPERTY_HINT_TYPE_STRING]:
		if hint_string.is_valid_int():
			return {"type": int(hint_string), "hint_string": "", "class_name": ""}

		var parts = hint_string.split("/", false)
		if parts.size() > 0 and parts[0].is_valid_int():
			var elem_type = int(parts[0])
			var elem_hint_string = ""
			if parts.size() > 1:
				elem_hint_string = "/".join(parts.slice(1))
			return {
				"type": elem_type,
				"hint_string": elem_hint_string,
				"class_name": elem_hint_string
			}

		var builtin_type = _variant_type_from_name(hint_string)
		if builtin_type != TYPE_NIL:
			return {"type": builtin_type, "hint_string": "", "class_name": ""}

		return {"type": TYPE_OBJECT, "hint_string": hint_string, "class_name": hint_string}

	return {}

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
