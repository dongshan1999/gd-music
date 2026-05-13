@tool
extends EditorPlugin

var picker: Node
var selected_signal: Signal
var selected_callback: Callable

var toggle: CheckButton

var i18n_handler: RefCounted

const PRESET_ANCHORS := {
	Control.PRESET_TOP_LEFT: {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0},
	Control.PRESET_TOP_RIGHT: {"left": 1.0, "top": 0.0, "right": 1.0, "bottom": 0.0},
	Control.PRESET_BOTTOM_LEFT: {"left": 0.0, "top": 1.0, "right": 0.0, "bottom": 1.0},
	Control.PRESET_BOTTOM_RIGHT: {"left": 1.0, "top": 1.0, "right": 1.0, "bottom": 1.0},
	Control.PRESET_CENTER_LEFT: {"left": 0.0, "top": 0.5, "right": 0.0, "bottom": 0.5},
	Control.PRESET_CENTER_TOP: {"left": 0.5, "top": 0.0, "right": 0.5, "bottom": 0.0},
	Control.PRESET_CENTER_RIGHT: {"left": 1.0, "top": 0.5, "right": 1.0, "bottom": 0.5},
	Control.PRESET_CENTER_BOTTOM: {"left": 0.5, "top": 1.0, "right": 0.5, "bottom": 1.0},
	Control.PRESET_CENTER: {"left": 0.5, "top": 0.5, "right": 0.5, "bottom": 0.5},
	Control.PRESET_LEFT_WIDE: {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 1.0},
	Control.PRESET_TOP_WIDE: {"left": 0.0, "top": 0.0, "right": 1.0, "bottom": 0.0},
	Control.PRESET_RIGHT_WIDE: {"left": 1.0, "top": 0.0, "right": 1.0, "bottom": 1.0},
	Control.PRESET_BOTTOM_WIDE: {"left": 0.0, "top": 1.0, "right": 1.0, "bottom": 1.0},
	Control.PRESET_VCENTER_WIDE: {"left": 0.5, "top": 0.0, "right": 0.5, "bottom": 1.0},
	Control.PRESET_HCENTER_WIDE: {"left": 0.0, "top": 0.5, "right": 1.0, "bottom": 0.5},
	Control.PRESET_FULL_RECT: {"left": 0.0, "top": 0.0, "right": 1.0, "bottom": 1.0},
}

func _enter_tree() -> void:
	if picker == null:
		picker = get_editor_interface().get_base_control().find_child("@AnchorPresetPicker@*", true, false)
		assert(picker.get_class() == "AnchorPresetPicker")
		selected_signal = picker.get("anchors_preset_selected")
		var con = selected_signal.get_connections()
		selected_callback = con[0]["callable"]
	
	selected_signal.disconnect(selected_callback)
	selected_signal.connect(wrapped_selected)
	
	if ClassDB.class_exists("TranslationDomain"): # Add translation for Godot 4.4+
		var path = (self.get_script() as GDScript).resource_path.get_base_dir().path_join("i18n.gd")
		i18n_handler = load(path).new()
		i18n_handler.register()
	
	toggle = CheckButton.new()
	toggle.text = "Anchors Only"
	
	var vbox = picker.get_parent()
	vbox.add_child(toggle)
	vbox.move_child(toggle, 1)

func wrapped_selected(preset: int):
	if not toggle.button_pressed:
		selected_callback.call(preset)
		return
	
	var undo := get_undo_redo()
	undo.create_action(tr("Change Anchors, Grow Direction"))
	
	var selection = get_editor_interface().get_selection().get_selected_nodes()
	for node in selection:
		var control := node as Control
		if control:
			var state = control.call("_edit_get_state")
			var changes := build_preset_changes(control, preset)
			undo.add_do_property(control, "layout_mode", 1)
			undo.add_do_property(control, "anchor_left", changes["anchor_left"])
			undo.add_do_property(control, "anchor_top", changes["anchor_top"])
			undo.add_do_property(control, "anchor_right", changes["anchor_right"])
			undo.add_do_property(control, "anchor_bottom", changes["anchor_bottom"])
			undo.add_do_property(control, "offset_left", changes["offset_left"])
			undo.add_do_property(control, "offset_top", changes["offset_top"])
			undo.add_do_property(control, "offset_right", changes["offset_right"])
			undo.add_do_property(control, "offset_bottom", changes["offset_bottom"])
			undo.add_do_method(control, "set_h_grow_direction", get_h_grow_direction(preset))
			undo.add_do_method(control, "set_v_grow_direction", get_v_grow_direction(preset))
			undo.add_do_method(control, "notify_property_list_changed")
			undo.add_do_method(control, "queue_redraw")
			undo.add_undo_method(control, "_edit_set_state", state)
			undo.add_undo_method(control, "notify_property_list_changed")
			undo.add_undo_method(control, "queue_redraw")
	
	undo.commit_action()

func build_preset_changes(control: Control, preset: int) -> Dictionary:
	var anchors := get_preset_anchors(preset)
	var reference_size := get_reference_size(control)
	var rect := get_current_rect(control, reference_size)
	var horizontal_edges := get_axis_edges(
		float(anchors["left"]),
		float(anchors["right"]),
		rect.size.x,
		reference_size.x
	)
	var vertical_edges := get_axis_edges(
		float(anchors["top"]),
		float(anchors["bottom"]),
		rect.size.y,
		reference_size.y
	)
	return {
		"anchor_left": anchors["left"],
		"anchor_top": anchors["top"],
		"anchor_right": anchors["right"],
		"anchor_bottom": anchors["bottom"],
		"offset_left": horizontal_edges.x - reference_size.x * float(anchors["left"]),
		"offset_top": vertical_edges.x - reference_size.y * float(anchors["top"]),
		"offset_right": horizontal_edges.y - reference_size.x * float(anchors["right"]),
		"offset_bottom": vertical_edges.y - reference_size.y * float(anchors["bottom"]),
	}

func get_preset_anchors(preset: int) -> Dictionary:
	return PRESET_ANCHORS.get(preset, PRESET_ANCHORS[Control.PRESET_TOP_LEFT])

func get_reference_size(control: Control) -> Vector2:
	var size := control.get_parent_area_size()
	if size.x > 0.0 and size.y > 0.0:
		return size
	if control.size.x > 0.0 and control.size.y > 0.0:
		return control.size
	var minimum_size := control.get_combined_minimum_size()
	if minimum_size.x > 0.0 and minimum_size.y > 0.0:
		return minimum_size
	return Vector2.ONE

func get_current_rect(control: Control, reference_size: Vector2) -> Rect2:
	var left := reference_size.x * float(control.anchor_left) + float(control.offset_left)
	var top := reference_size.y * float(control.anchor_top) + float(control.offset_top)
	var right := reference_size.x * float(control.anchor_right) + float(control.offset_right)
	var bottom := reference_size.y * float(control.anchor_bottom) + float(control.offset_bottom)
	return Rect2(left, top, right - left, bottom - top)

func get_axis_edges(anchor_min: float, anchor_max: float, current_size: float, reference_size: float) -> Vector2:
	if not is_equal_approx(anchor_min, anchor_max):
		return Vector2(0.0, reference_size)
	var anchor_position := reference_size * anchor_min
	if is_equal_approx(anchor_min, 0.0):
		return Vector2(anchor_position, anchor_position + current_size)
	if is_equal_approx(anchor_min, 1.0):
		return Vector2(anchor_position - current_size, anchor_position)
	return Vector2(
		anchor_position - current_size * 0.5,
		anchor_position + current_size * 0.5
	)

func get_h_grow_direction(preset):
	match preset:
		Control.PRESET_TOP_LEFT, Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_LEFT, Control.PRESET_LEFT_WIDE:
			return Control.GROW_DIRECTION_END
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_RIGHT_WIDE:
			return Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER, Control.PRESET_TOP_WIDE, \
		Control.PRESET_BOTTOM_WIDE, Control.PRESET_VCENTER_WIDE, Control.PRESET_HCENTER_WIDE, Control.PRESET_FULL_RECT:
			return Control.GROW_DIRECTION_BOTH

func get_v_grow_direction(preset):
	match preset:
		Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT, Control.PRESET_CENTER_TOP, Control.PRESET_TOP_WIDE:
			return Control.GROW_DIRECTION_END
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_WIDE:
			return Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER, Control.PRESET_LEFT_WIDE, \
		Control.PRESET_RIGHT_WIDE, Control.PRESET_VCENTER_WIDE, Control.PRESET_HCENTER_WIDE, Control.PRESET_FULL_RECT:
			return Control.GROW_DIRECTION_BOTH

func _exit_tree() -> void:
	if picker != null:
		selected_signal.disconnect(wrapped_selected)
		selected_signal.connect(selected_callback)
	
	if toggle:
		toggle.queue_free()
		toggle = null
	
	if i18n_handler:
		i18n_handler.unregister()
		i18n_handler = null
