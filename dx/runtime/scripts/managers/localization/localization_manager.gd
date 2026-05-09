class_name DX_LocalizationManager
extends RefCounted

const TEXT_PROPERTY := &"text"

var dx: Node
var _bindings: Dictionary = {}

func text(tr_key: String, format_payload: Variant = null) -> String:
	return _build_text(tr_key, format_payload)

func bind_text(target: Object, tr_key: String, format_payload: Variant = null) -> void:
	if target == null:
		return

	var binding_id := target.get_instance_id()
	if tr_key.strip_edges().is_empty():
		_bindings.erase(binding_id)
		return

	if not _has_text_property(target):
		push_warning("LocalizationManager target has no 'text' property: %s" % [str(target)])
		return

	_bindings[binding_id] = {
		"target": weakref(target),
		"key": tr_key.strip_edges(),
		"format_payload": _duplicate_format_payload(format_payload),
	}
	_refresh_binding(binding_id)

func unbind_text(target: Object) -> void:
	if target == null:
		return
	_bindings.erase(target.get_instance_id())

func set_locale(locale: String) -> void:
	if locale.strip_edges().is_empty():
		return
	TranslationServer.set_locale(locale.strip_edges())

func refresh_all() -> void:
	var stale_ids: Array[int] = []
	for binding_id in _bindings.keys():
		if not _refresh_binding(int(binding_id)):
			stale_ids.append(int(binding_id))

	for binding_id in stale_ids:
		_bindings.erase(binding_id)

func in_translation_changed() -> void:
	refresh_all()

func in_exit_tree() -> void:
	_bindings.clear()

func in_quit() -> void:
	_bindings.clear()

func _refresh_binding(binding_id: int) -> bool:
	if not _bindings.has(binding_id):
		return false

	var binding: Dictionary = _bindings[binding_id]
	var target_ref: WeakRef = binding.get("target")
	var target = target_ref.get_ref() if target_ref != null else null
	if target == null:
		return false
	if not _has_text_property(target):
		return false

	var final_text := _build_text(
		str(binding.get("key", "")),
		binding.get("format_payload", null)
	)
	if target.get("text") != final_text:
		target.set("text", final_text)
	return true

func _build_text(tr_key: String, format_payload: Variant = null) -> String:
	var normalized_key := tr_key.strip_edges()
	if normalized_key.is_empty():
		return ""

	var translated := TranslationServer.translate(normalized_key)
	if translated.is_empty():
		translated = normalized_key
	else:
		translated = translated.replace("\\n", "\n")

	return _format_text(translated, format_payload)

func _format_text(source_text: String, format_payload: Variant = null) -> String:
	if format_payload == null:
		return source_text

	if format_payload is Dictionary:
		var named_payload: Dictionary = format_payload
		if named_payload.is_empty():
			return source_text
		return source_text.format(named_payload)

	if format_payload is Array:
		var positional_payload: Array = format_payload
		if positional_payload.is_empty():
			return source_text

		var format_map := {}
		for index in positional_payload.size():
			format_map[str(index)] = positional_payload[index]
		return source_text.format(format_map)

	return source_text.format({"0": format_payload})

func _duplicate_format_payload(format_payload: Variant):
	if format_payload is Array:
		return (format_payload as Array).duplicate(true)
	if format_payload is Dictionary:
		return (format_payload as Dictionary).duplicate(true)
	return format_payload

func _has_text_property(target: Object) -> bool:
	for property_info in target.get_property_list():
		if StringName(str(property_info.get("name", ""))) == TEXT_PROPERTY:
			return true
	return false
