extends Node

const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupViewType := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")
const PopupId = PopupRegistryType.PopupId

signal popup_shown(popup_id, popup)
signal popup_hidden(popup_id)

var dx: Node
var _normal_host: Control
var _fullscreen_host: Control
var _popup_stacks := {
	PopupViewType.PopupLayer.NORMAL: [],
	PopupViewType.PopupLayer.FULLSCREEN: [],
}

func show(popup_id: int) -> PopupViewType:
	if not PopupRegistryType.has_popup(popup_id):
		push_error("Popup id is not registered: %s" % popup_id)
		return null

	var scene: PackedScene = PopupRegistryType.get_scene(popup_id)
	if scene == null:
		push_error("Popup scene is missing for id: %s" % popup_id)
		return null

	var instance: Node = scene.instantiate()
	if not (instance is PopupViewType):
		push_error("Popup root must extend PopupView.")
		instance.queue_free()
		return null

	var popup: PopupViewType = instance as PopupViewType
	var popup_layer := popup.get_resolved_popup_layer()
	var host := _get_popup_host(popup_layer)
	if host == null:
		push_error("Popup host is missing for popup id: %s" % popup_id)
		instance.queue_free()
		return null

	_stretch_popup(popup)
	host.add_child(popup)
	_push_popup_entry(popup_layer, popup_id, popup)

	popup._popup_open(self)
	popup_shown.emit(popup_id, popup)
	return popup

func show_or_reuse(popup_id: int) -> PopupViewType:
	var existing_popup := get_popup(popup_id)
	if existing_popup != null:
		_bring_popup_to_front(existing_popup)
		_touch_popup_entry(popup_id, existing_popup)
		popup_shown.emit(popup_id, existing_popup)
		return existing_popup
	return show(popup_id)

func get_popup(popup_id: int) -> PopupViewType:
	var popup_entry := _find_popup_entry(popup_id)
	if popup_entry.is_empty():
		return null
	return popup_entry.get("popup") as PopupViewType

func hide() -> void:
	var popup := get_current_popup()
	if popup == null:
		return
	hide_popup(popup)

func hide_popup(target_popup: PopupViewType) -> void:
	if target_popup == null:
		return

	var popup_entry := _remove_popup_entry(target_popup)
	if popup_entry.is_empty():
		return

	var popup_id: int = int(popup_entry.get("id", -1))
	var popup: PopupViewType = popup_entry.get("popup") as PopupViewType
	if is_instance_valid(popup):
		popup._popup_close()
		popup.queue_free()
	popup_hidden.emit(popup_id)

func is_showing() -> bool:
	return get_current_popup() != null

func get_current_popup() -> PopupViewType:
	var popup_entry := _get_current_popup_entry()
	if popup_entry.is_empty():
		return null
	return popup_entry.get("popup") as PopupViewType

func set_normal_host(host: Control) -> void:
	_normal_host = host
	_prune_invalid_popup_entries()

func set_fullscreen_host(host: Control) -> void:
	_fullscreen_host = host
	_prune_invalid_popup_entries()

func clear_normal_host(host: Control = null) -> void:
	if host == null or _normal_host == host:
		_normal_host = null
	_prune_invalid_popup_entries()

func clear_fullscreen_host(host: Control = null) -> void:
	if host == null or _fullscreen_host == host:
		_fullscreen_host = null
	_prune_invalid_popup_entries()

func _get_popup_host(popup_layer: int) -> Control:
	match popup_layer:
		PopupViewType.PopupLayer.NORMAL:
			if is_instance_valid(_normal_host):
				return _normal_host
			return null
		PopupViewType.PopupLayer.FULLSCREEN:
			if is_instance_valid(_fullscreen_host):
				return _fullscreen_host
			return null
	return null

func _stretch_popup(popup: Control) -> void:
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.offset_left = 0.0
	popup.offset_top = 0.0
	popup.offset_right = 0.0
	popup.offset_bottom = 0.0

func _push_popup_entry(popup_layer: int, popup_id: int, popup: PopupViewType) -> void:
	var layer_stack: Array = _popup_stacks.get(popup_layer, [])
	layer_stack.append({
		"id": popup_id,
		"popup": popup,
	})
	_popup_stacks[popup_layer] = layer_stack

func _touch_popup_entry(popup_id: int, popup: PopupViewType) -> void:
	var popup_entry := _find_popup_entry(popup_id)
	if popup_entry.is_empty():
		return

	var popup_layer: int = int(popup_entry.get("layer", PopupViewType.PopupLayer.NORMAL))
	var layer_stack: Array = _popup_stacks.get(popup_layer, [])
	var index: int = int(popup_entry.get("index", -1))
	if index >= 0 and index < layer_stack.size():
		layer_stack.remove_at(index)
		layer_stack.append(popup_entry)
		_popup_stacks[popup_layer] = layer_stack
		return

	layer_stack.append({
		"id": popup_id,
		"popup": popup,
	})
	_popup_stacks[popup_layer] = layer_stack

func _find_popup_entry(popup_id: int) -> Dictionary:
	_prune_invalid_popup_entries()

	for popup_layer in [
		PopupViewType.PopupLayer.FULLSCREEN,
		PopupViewType.PopupLayer.NORMAL,
	]:
		var layer_stack: Array = _popup_stacks.get(popup_layer, [])
		for index in range(layer_stack.size() - 1, -1, -1):
			var popup_entry: Dictionary = layer_stack[index]
			if int(popup_entry.get("id", -1)) != popup_id:
				continue
			return {
				"layer": popup_layer,
				"index": index,
				"id": popup_id,
				"popup": popup_entry.get("popup"),
			}

	return {}

func _bring_popup_to_front(popup: PopupViewType) -> void:
	if popup == null or not is_instance_valid(popup):
		return

	var parent := popup.get_parent()
	if parent is Control:
		(parent as Control).move_child(popup, parent.get_child_count() - 1)

func _get_current_popup_entry() -> Dictionary:
	_prune_invalid_popup_entries()

	for popup_layer in [
		PopupViewType.PopupLayer.FULLSCREEN,
		PopupViewType.PopupLayer.NORMAL,
	]:
		var layer_stack: Array = _popup_stacks.get(popup_layer, [])
		if layer_stack.is_empty():
			continue
		return layer_stack[layer_stack.size() - 1] as Dictionary

	return {}

func _remove_popup_entry(target_popup: PopupViewType) -> Dictionary:
	_prune_invalid_popup_entries()

	for popup_layer in _popup_stacks.keys():
		var layer_stack: Array = _popup_stacks.get(popup_layer, [])
		for index in range(layer_stack.size() - 1, -1, -1):
			var popup_entry: Dictionary = layer_stack[index]
			if popup_entry.get("popup") != target_popup:
				continue
			layer_stack.remove_at(index)
			_popup_stacks[popup_layer] = layer_stack
			return popup_entry

	return {}

func _prune_invalid_popup_entries() -> void:
	for popup_layer in _popup_stacks.keys():
		var layer_stack: Array = _popup_stacks.get(popup_layer, [])
		for index in range(layer_stack.size() - 1, -1, -1):
			var popup: PopupViewType = (layer_stack[index] as Dictionary).get("popup") as PopupViewType
			if is_instance_valid(popup):
				continue
			layer_stack.remove_at(index)
		_popup_stacks[popup_layer] = layer_stack
