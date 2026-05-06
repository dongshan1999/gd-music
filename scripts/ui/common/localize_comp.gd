@tool
class_name LocalizeComp
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_refresh()
	elif what == NOTIFICATION_PARENTED:
		_queue_refresh()

func refresh_text() -> void:
	_refresh_queued = false

	if tr_key.is_empty():
		return
	if Engine.is_editor_hint():
		if not refresh_in_editor:
			return
	elif not update_in_runtime:
		return

	var target := _get_text_target()
	if target == null:
		if Engine.is_editor_hint() and warn_if_parent_has_no_text:
			push_warning(
				"LocalizeComp parent must expose a 'text' property. Parent: %s"
				% [str(get_parent())]
			)
		return

	var translated_text := TranslationServer.translate(tr_key)
	if translated_text.is_empty():
		translated_text = tr(tr_key)
	if translated_text == tr_key and Engine.is_editor_hint():
		# Keep the editor-authored preview text if the key is unresolved.
		return

	var final_text := _format_text(translated_text)
	var current_text = target.get("text")
	if current_text == final_text:
		return
	target.set("text", final_text)

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_text")

func _format_text(source_text: String) -> String:
	if not named_format_args.is_empty():
		return source_text.format(named_format_args)
	if format_args.is_empty():
		return source_text

	var positional_args := {}
	for index in format_args.size():
		positional_args[str(index)] = format_args[index]
	return source_text.format(positional_args)

func _get_text_target() -> Object:
	var parent := get_parent()
	if parent == null:
		return null
	if not parent is Object:
		return null
	if _has_text_property(parent):
		return parent
	return null

func _has_text_property(target: Object) -> bool:
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == "text":
			return true
	return false
