class_name DX_PopupManager
extends Node

const PopupId = DX_PopupRegistry.PopupId

signal popup_shown(popup_id, popup)
signal popup_hidden(popup_id)

var dx: Node
var _normal_host: Control
var _fullscreen_host: Control
var _popup_stacks := {
	DX_PopupView.PopupLayer.NORMAL: [],
	DX_PopupView.PopupLayer.FULLSCREEN: [],
}

func show(popup_id: int, layer_override: int = -1) -> DX_PopupView:
	var existing_popup := get_popup(popup_id)
	if existing_popup != null:
		_bring_popup_to_front(existing_popup)
		_touch_popup_entry(popup_id, existing_popup)
		popup_shown.emit(popup_id, existing_popup)
		return existing_popup

	return _show_new_popup(popup_id, layer_override)

func _show_new_popup(popup_id: int, layer_override: int = -1) -> DX_PopupView:
	if not DX_PopupRegistry.has_popup(popup_id):
		push_error("Popup id is not registered: %s" % popup_id)
		return null

	var scene: PackedScene = DX_PopupRegistry.get_scene(popup_id)
	if scene == null:
		push_error("Popup scene is missing for id: %s" % popup_id)
		return null

	var instance: Node = scene.instantiate()
	if not (instance is DX_PopupView):
		push_error("Popup root must extend DX_PopupView.")
		instance.queue_free()
		return null

	var popup: DX_PopupView = instance as DX_PopupView
	if layer_override >= 0:
		popup.popup_layer = layer_override
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

func get_popup(popup_id: int) -> DX_PopupView:
	var popup_entry := _find_popup_entry(popup_id)
	if popup_entry.is_empty():
		return null
	return popup_entry.get("popup") as DX_PopupView

func hide() -> void:
	var popup := get_current_popup()
	if popup == null:
		return
	hide_popup(popup)

func hide_popup(target_popup: DX_PopupView) -> void:
	if target_popup == null:
		return

	var popup_entry := _remove_popup_entry(target_popup)
	if popup_entry.is_empty():
		return

	var popup_id: int = int(popup_entry.get("id", -1))
	var popup: DX_PopupView = popup_entry.get("popup") as DX_PopupView
	if is_instance_valid(popup):
		popup._popup_close()
		popup.queue_free()
	popup_hidden.emit(popup_id)

func is_showing() -> bool:
	return get_current_popup() != null

func get_current_popup() -> DX_PopupView:
	var popup_entry := _get_current_popup_entry()
	if popup_entry.is_empty():
		return null
	return popup_entry.get("popup") as DX_PopupView

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
		DX_PopupView.PopupLayer.NORMAL:
			if is_instance_valid(_normal_host):
				return _normal_host
			return null
		DX_PopupView.PopupLayer.FULLSCREEN:
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

func _push_popup_entry(popup_layer: int, popup_id: int, popup: DX_PopupView) -> void:
	var layer_stack: Array = _popup_stacks.get(popup_layer, [])
	layer_stack.append({
		"id": popup_id,
		"popup": popup,
	})
	_popup_stacks[popup_layer] = layer_stack

func _touch_popup_entry(popup_id: int, popup: DX_PopupView) -> void:
	var popup_entry := _find_popup_entry(popup_id)
	if popup_entry.is_empty():
		return

	var popup_layer: int = int(popup_entry.get("layer", DX_PopupView.PopupLayer.NORMAL))
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
		DX_PopupView.PopupLayer.FULLSCREEN,
		DX_PopupView.PopupLayer.NORMAL,
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

func _bring_popup_to_front(popup: DX_PopupView) -> void:
	if popup == null or not is_instance_valid(popup):
		return

	var parent := popup.get_parent()
	if parent is Control:
		(parent as Control).move_child(popup, parent.get_child_count() - 1)

func _get_current_popup_entry() -> Dictionary:
	_prune_invalid_popup_entries()

	for popup_layer in [
		DX_PopupView.PopupLayer.FULLSCREEN,
		DX_PopupView.PopupLayer.NORMAL,
	]:
		var layer_stack: Array = _popup_stacks.get(popup_layer, [])
		if layer_stack.is_empty():
			continue
		return layer_stack[layer_stack.size() - 1] as Dictionary

	return {}

func _remove_popup_entry(target_popup: DX_PopupView) -> Dictionary:
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
			var popup = (layer_stack[index] as Dictionary).get("popup")
			if is_instance_valid(popup) and popup is DX_PopupView:
				continue
			layer_stack.remove_at(index)
		_popup_stacks[popup_layer] = layer_stack
