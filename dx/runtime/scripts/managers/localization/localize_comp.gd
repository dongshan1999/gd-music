@tool
class_name DX_LocalizeComp
extends Node

@export_placeholder("music_app.home.search_prompt")
var tr_key: String = "":
	set(value):
		tr_key = value.strip_edges()
		_queue_refresh()

@export var format_args: Array[String] = []:
	set(value):
		format_args = value.duplicate()
		_queue_refresh()

@export var named_format_args: Dictionary = {}:
	set(value):
		named_format_args = value.duplicate(true)
		_queue_refresh()

@export var refresh_in_editor := true:
	set(value):
		refresh_in_editor = value
		_queue_refresh()

@export var update_in_runtime := true:
	set(value):
		update_in_runtime = value
		_queue_refresh()

@export var warn_if_parent_has_no_text := true

var _refresh_queued := false

func _enter_tree() -> void:
	_queue_refresh()

func _ready() -> void:
	_queue_refresh()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	var localization = _get_localization_manager()
	if localization == null:
		return

	var target := _get_text_target()
	if target != null:
		localization.unbind_text(target)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		_queue_refresh()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and Engine.is_editor_hint():
		_queue_refresh()

func refresh_text() -> void:
	_refresh_queued = false

	var target := _get_text_target()
	var localization_manager = _get_localization_manager()
	if target == null:
		if Engine.is_editor_hint() and warn_if_parent_has_no_text:
			push_warning(
				"LocalizeComp parent must expose a 'text' property. Parent: %s"
				% [str(get_parent())]
			)
		return

	if tr_key.is_empty():
		if localization_manager != null:
			localization_manager.unbind_text(target)
		return

	if Engine.is_editor_hint():
		if not refresh_in_editor:
			return

		var preview_text := _translate_direct()
		if preview_text == tr_key:
			return
		if target.get("text") != preview_text:
			target.set("text", preview_text)
		return

	if not update_in_runtime:
		return

	if localization_manager == null:
		var fallback_text := _translate_direct()
		if target.get("text") != fallback_text:
			target.set("text", fallback_text)
		return

	localization_manager.bind_text(target, tr_key, _get_format_payload())

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_text")

func _translate_direct() -> String:
	var translated_text := TranslationServer.translate(tr_key)
	if translated_text.is_empty():
		translated_text = tr_key
	else:
		translated_text = translated_text.replace("\\n", "\n")
	return _format_text(translated_text)

func _format_text(source_text: String) -> String:
	if not named_format_args.is_empty():
		return source_text.format(named_format_args)
	if format_args.is_empty():
		return source_text

	var positional_args := {}
	for index in format_args.size():
		positional_args[str(index)] = format_args[index]
	return source_text.format(positional_args)

func _get_format_payload():
	if not named_format_args.is_empty():
		return named_format_args.duplicate(true)
	if format_args.is_empty():
		return null
	return format_args.duplicate()

func _get_localization_manager():
	if Engine.is_editor_hint():
		return null
	if not is_inside_tree():
		return null
	if DX == null:
		return null
	return DX.localization

func _get_text_target() -> Object:
	var parent := get_parent()
	if parent == null:
		return null
	if not (parent is Object):
		return null
	if _has_text_property(parent):
		return parent
	return null

func _has_text_property(target: Object) -> bool:
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == "text":
			return true
	return false
