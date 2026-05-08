@tool
class_name RectTransformInspectorPlugin
extends EditorInspectorPlugin

class RectTransformPanel:
	extends PanelContainer

	enum LayoutMode {
		POINT,
		H_STRETCH,
		V_STRETCH,
		FULL_STRETCH,
	}

	const ANCHOR_STEP := 0.001
	const VALUE_STEP := 1.0

	var _editor_interface
	var _undo_redo
	var _control: Control
	var _ui_ready := false

	var _anchor_left_value := 0.0
	var _anchor_top_value := 0.0
	var _anchor_right_value := 0.0
	var _anchor_bottom_value := 0.0
	var _pivot_normalized_value := Vector2(0.5, 0.5)
	var _last_control_size := Vector2.ZERO
	var _has_pivot_snapshot := false

	var _root: VBoxContainer
	var _layout_mode_label: Label
	var _reference_warning_label: Label
	var _anchor_min_x_spin: SpinBox
	var _anchor_min_y_spin: SpinBox
	var _anchor_max_x_spin: SpinBox
	var _anchor_max_y_spin: SpinBox
	var _pivot_x_spin: SpinBox
	var _pivot_y_spin: SpinBox
	var _pos_x_row: HBoxContainer
	var _pos_y_row: HBoxContainer
	var _width_row: HBoxContainer
	var _height_row: HBoxContainer
	var _left_row: HBoxContainer
	var _right_row: HBoxContainer
	var _top_row: HBoxContainer
	var _bottom_row: HBoxContainer
	var _pos_x_spin: SpinBox
	var _pos_y_spin: SpinBox
	var _width_spin: SpinBox
	var _height_spin: SpinBox
	var _left_spin: SpinBox
	var _right_spin: SpinBox
	var _top_spin: SpinBox
	var _bottom_spin: SpinBox

	func _init(editor_interface = null, undo_redo = null) -> void:
		_editor_interface = editor_interface
		_undo_redo = undo_redo
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _ready() -> void:
		_build_ui()
		_ui_ready = true
		refresh_from_control()

	func _exit_tree() -> void:
		clear_control_binding()

	func bind_control(control: Control) -> void:
		_clear_control_binding()
		_control = control
		_pivot_normalized_value = Vector2(0.5, 0.5)
		_last_control_size = Vector2.ZERO
		_has_pivot_snapshot = false
		if _control == null or not is_instance_valid(_control):
			return

		if _control.has_signal("tree_exited") and not _control.tree_exited.is_connected(_on_control_tree_exited):
			_control.tree_exited.connect(_on_control_tree_exited, CONNECT_ONE_SHOT)
		if _control.has_signal("resized") and not _control.resized.is_connected(_on_control_resized):
			_control.resized.connect(_on_control_resized)

		if _ui_ready:
			refresh_from_control()

	func clear_control_binding() -> void:
		_clear_control_binding()
		refresh_from_control()

	func refresh_from_control() -> void:
		if not _ui_ready:
			return

		if _control == null or not is_instance_valid(_control):
			_set_all_rows_visible(false)
			if _reference_warning_label != null:
				_reference_warning_label.visible = false
			return

		_anchor_left_value = float(_control.anchor_left)
		_anchor_top_value = float(_control.anchor_top)
		_anchor_right_value = float(_control.anchor_right)
		_anchor_bottom_value = float(_control.anchor_bottom)

		_set_spin_value(_anchor_min_x_spin, _anchor_left_value)
		_set_spin_value(_anchor_min_y_spin, _anchor_top_value)
		_set_spin_value(_anchor_max_x_spin, _anchor_right_value)
		_set_spin_value(_anchor_max_y_spin, _anchor_bottom_value)

		_sync_pivot_state_from_control()
		_set_spin_value(_pivot_x_spin, _pivot_normalized_value.x)
		_set_spin_value(_pivot_y_spin, _pivot_normalized_value.y)

		var parent_size := _get_reference_size()
		var has_reference_size := _has_reference_size(parent_size)
		var mode := _get_layout_mode()
		if _reference_warning_label != null:
			_reference_warning_label.visible = not has_reference_size
		if not has_reference_size:
			_update_mode_label(mode)
			_update_layout_visibility(mode, false)
			return

		var anchor_left_px := parent_size.x * _anchor_left_value
		var anchor_right_px := parent_size.x * _anchor_right_value
		var anchor_top_px := parent_size.y * _anchor_top_value
		var anchor_bottom_px := parent_size.y * _anchor_bottom_value

		var left := anchor_left_px + float(_control.offset_left)
		var right := anchor_right_px + float(_control.offset_right)
		var top := anchor_top_px + float(_control.offset_top)
		var bottom := anchor_bottom_px + float(_control.offset_bottom)
		var width := right - left
		var height := bottom - top

		_update_mode_label(mode)
		_update_layout_visibility(mode, true)

		match mode:
			LayoutMode.POINT:
				_set_spin_value(_pos_x_spin, ((left + right) * 0.5) - anchor_left_px)
				_set_spin_value(_pos_y_spin, ((top + bottom) * 0.5) - anchor_top_px)
				_set_spin_value(_width_spin, width)
				_set_spin_value(_height_spin, height)
			LayoutMode.H_STRETCH:
				_set_spin_value(_left_spin, float(_control.offset_left))
				_set_spin_value(_right_spin, -float(_control.offset_right))
				_set_spin_value(_pos_y_spin, ((top + bottom) * 0.5) - anchor_top_px)
				_set_spin_value(_height_spin, height)
			LayoutMode.V_STRETCH:
				_set_spin_value(_pos_x_spin, ((left + right) * 0.5) - anchor_left_px)
				_set_spin_value(_width_spin, width)
				_set_spin_value(_top_spin, float(_control.offset_top))
				_set_spin_value(_bottom_spin, -float(_control.offset_bottom))
			LayoutMode.FULL_STRETCH:
				_set_spin_value(_left_spin, float(_control.offset_left))
				_set_spin_value(_right_spin, -float(_control.offset_right))
				_set_spin_value(_top_spin, float(_control.offset_top))
				_set_spin_value(_bottom_spin, -float(_control.offset_bottom))

	func _build_ui() -> void:
		add_theme_constant_override("margin_left", 0)

		var outer := MarginContainer.new()
		outer.add_theme_constant_override("margin_left", 10)
		outer.add_theme_constant_override("margin_top", 10)
		outer.add_theme_constant_override("margin_right", 10)
		outer.add_theme_constant_override("margin_bottom", 10)
		add_child(outer)

		_root = VBoxContainer.new()
		_root.add_theme_constant_override("separation", 8)
		outer.add_child(_root)

		_root.add_child(_create_title_bar())
		_root.add_child(_make_section_label("Anchors"))
		_root.add_child(_create_anchor_vector_fields())
		_root.add_child(_create_anchor_preset_grid())
		_root.add_child(_make_separator())
		_root.add_child(_make_section_label("Pivot"))
		_root.add_child(_create_pivot_fields())
		_root.add_child(_create_pivot_preset_grid())
		_root.add_child(_create_pivot_note())
		_root.add_child(_make_separator())
		_root.add_child(_make_section_label("Layout"))
		_layout_mode_label = Label.new()
		_layout_mode_label.text = "Mode: -"
		_layout_mode_label.add_theme_font_size_override("font_size", 11)
		_layout_mode_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
		_root.add_child(_layout_mode_label)
		_reference_warning_label = Label.new()
		_reference_warning_label.text = "Reference size is unavailable. RectTransform layout editing is temporarily disabled."
		_reference_warning_label.visible = false
		_reference_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_reference_warning_label.add_theme_font_size_override("font_size", 11)
		_reference_warning_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42))
		_root.add_child(_reference_warning_label)
		_root.add_child(_create_layout_fields())

	func _create_title_bar() -> Control:
		var bar := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.17, 0.18, 0.22, 1.0)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		bar.add_theme_stylebox_override("panel", style)

		var row := HBoxContainer.new()
		bar.add_child(row)

		var label := Label.new()
		label.text = "RectTransform"
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(label)
		return bar

	func _make_section_label(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
		return label

	func _make_separator() -> HSeparator:
		return HSeparator.new()

	func _create_anchor_vector_fields() -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_anchor_min_x_spin = _make_anchor_spinbox()
		_anchor_min_y_spin = _make_anchor_spinbox()
		_anchor_max_x_spin = _make_anchor_spinbox()
		_anchor_max_y_spin = _make_anchor_spinbox()
		box.add_child(_create_vector_row(
			"Anchor Min",
			_anchor_min_x_spin,
			_anchor_min_y_spin,
			Callable(self, "_on_anchor_min_x_changed"),
			Callable(self, "_on_anchor_min_y_changed")
		))
		box.add_child(_create_vector_row(
			"Anchor Max",
			_anchor_max_x_spin,
			_anchor_max_y_spin,
			Callable(self, "_on_anchor_max_x_changed"),
			Callable(self, "_on_anchor_max_y_changed")
		))
		return box

	func _create_anchor_preset_grid() -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_child(_create_preset_button("↖", "Top Left", Vector2(0.0, 0.0), Vector2(0.0, 0.0)))
		grid.add_child(_create_preset_button("↑", "Top Middle", Vector2(0.5, 0.0), Vector2(0.5, 0.0)))
		grid.add_child(_create_preset_button("↗", "Top Right", Vector2(1.0, 0.0), Vector2(1.0, 0.0)))
		grid.add_child(_create_preset_button("H↑", "Horizontal Stretch Top", Vector2(0.0, 0.0), Vector2(1.0, 0.0)))
		grid.add_child(_create_preset_button("←", "Middle Left", Vector2(0.0, 0.5), Vector2(0.0, 0.5)))
		grid.add_child(_create_preset_button("•", "Middle Center", Vector2(0.5, 0.5), Vector2(0.5, 0.5)))
		grid.add_child(_create_preset_button("→", "Middle Right", Vector2(1.0, 0.5), Vector2(1.0, 0.5)))
		grid.add_child(_create_preset_button("H•", "Horizontal Stretch Middle", Vector2(0.0, 0.5), Vector2(1.0, 0.5)))
		grid.add_child(_create_preset_button("↙", "Bottom Left", Vector2(0.0, 1.0), Vector2(0.0, 1.0)))
		grid.add_child(_create_preset_button("↓", "Bottom Middle", Vector2(0.5, 1.0), Vector2(0.5, 1.0)))
		grid.add_child(_create_preset_button("↘", "Bottom Right", Vector2(1.0, 1.0), Vector2(1.0, 1.0)))
		grid.add_child(_create_preset_button("H↓", "Horizontal Stretch Bottom", Vector2(0.0, 1.0), Vector2(1.0, 1.0)))
		grid.add_child(_create_preset_button("V←", "Vertical Stretch Left", Vector2(0.0, 0.0), Vector2(0.0, 1.0)))
		grid.add_child(_create_preset_button("V•", "Vertical Stretch Middle", Vector2(0.5, 0.0), Vector2(0.5, 1.0)))
		grid.add_child(_create_preset_button("V→", "Vertical Stretch Right", Vector2(1.0, 0.0), Vector2(1.0, 1.0)))
		grid.add_child(_create_preset_button("□", "Full Stretch", Vector2(0.0, 0.0), Vector2(1.0, 1.0)))
		return grid

	func _create_pivot_fields() -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_pivot_x_spin = _make_anchor_spinbox()
		_pivot_y_spin = _make_anchor_spinbox()
		box.add_child(_create_vector_row(
			"Pivot",
			_pivot_x_spin,
			_pivot_y_spin,
			Callable(self, "_on_pivot_x_changed"),
			Callable(self, "_on_pivot_y_changed")
		))
		return box

	func _create_pivot_preset_grid() -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_child(_create_pivot_button("↖", Vector2(0.0, 0.0)))
		grid.add_child(_create_pivot_button("↑", Vector2(0.5, 0.0)))
		grid.add_child(_create_pivot_button("↗", Vector2(1.0, 0.0)))
		grid.add_child(_create_pivot_button("←", Vector2(0.0, 0.5)))
		grid.add_child(_create_pivot_button("•", Vector2(0.5, 0.5)))
		grid.add_child(_create_pivot_button("→", Vector2(1.0, 0.5)))
		grid.add_child(_create_pivot_button("↙", Vector2(0.0, 1.0)))
		grid.add_child(_create_pivot_button("↓", Vector2(0.5, 1.0)))
		grid.add_child(_create_pivot_button("↘", Vector2(1.0, 1.0)))
		return grid

	func _create_pivot_note() -> Label:
		var label := Label.new()
		label.text = "Pivot is edited as a normalized 0..1 value. The plugin converts it to pivot_offset and keeps it aligned when the Control size changes."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
		return label

	func _create_layout_fields() -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_pos_x_spin = _make_value_spinbox()
		_pos_y_spin = _make_value_spinbox()
		_width_spin = _make_value_spinbox()
		_height_spin = _make_value_spinbox()
		_left_spin = _make_value_spinbox()
		_right_spin = _make_value_spinbox()
		_top_spin = _make_value_spinbox()
		_bottom_spin = _make_value_spinbox()

		var layout_changed := Callable(self, "_on_layout_field_changed")
		_pos_x_row = _create_spin_row("Pos X", _pos_x_spin, layout_changed)
		_pos_y_row = _create_spin_row("Pos Y", _pos_y_spin, layout_changed)
		_width_row = _create_spin_row("Width", _width_spin, layout_changed)
		_height_row = _create_spin_row("Height", _height_spin, layout_changed)
		_left_row = _create_spin_row("Left", _left_spin, layout_changed)
		_right_row = _create_spin_row("Right", _right_spin, layout_changed)
		_top_row = _create_spin_row("Top", _top_spin, layout_changed)
		_bottom_row = _create_spin_row("Bottom", _bottom_spin, layout_changed)

		box.add_child(_pos_x_row)
		box.add_child(_pos_y_row)
		box.add_child(_width_row)
		box.add_child(_height_row)
		box.add_child(_left_row)
		box.add_child(_right_row)
		box.add_child(_top_row)
		box.add_child(_bottom_row)
		return box

	func _create_spin_row(label_text: String, spin_box: SpinBox, changed_handler: Callable) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size = Vector2(96, 0)
		row.add_child(label)

		spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin_box.value_changed.connect(changed_handler)
		row.add_child(spin_box)
		return row

	func _create_vector_row(label_text: String, x_spin: SpinBox, y_spin: SpinBox, x_handler: Callable, y_handler: Callable) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size = Vector2(96, 0)
		row.add_child(label)

		var vec_box := HBoxContainer.new()
		vec_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vec_box.add_theme_constant_override("separation", 6)

		vec_box.add_child(_create_axis_label("X"))
		x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x_spin.value_changed.connect(x_handler)
		vec_box.add_child(x_spin)

		vec_box.add_child(_create_axis_label("Y"))
		y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		y_spin.value_changed.connect(y_handler)
		vec_box.add_child(y_spin)

		row.add_child(vec_box)
		return row

	func _create_axis_label(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size = Vector2(12, 0)
		label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84))
		return label

	func _make_anchor_spinbox() -> SpinBox:
		var spin_box := SpinBox.new()
		spin_box.min_value = 0.0
		spin_box.max_value = 1.0
		spin_box.step = ANCHOR_STEP
		spin_box.allow_lesser = false
		spin_box.allow_greater = false
		spin_box.custom_minimum_size = Vector2(0, 24)
		return spin_box

	func _make_value_spinbox() -> SpinBox:
		var spin_box := SpinBox.new()
		spin_box.min_value = -100000.0
		spin_box.max_value = 100000.0
		spin_box.step = VALUE_STEP
		spin_box.allow_lesser = true
		spin_box.allow_greater = true
		spin_box.custom_minimum_size = Vector2(0, 24)
		return spin_box

	func _create_preset_button(text: String, tooltip: String, anchor_min: Vector2, anchor_max: Vector2) -> Button:
		var button := Button.new()
		button.text = text
		button.tooltip_text = tooltip
		button.custom_minimum_size = Vector2(42, 28)
		button.pressed.connect(Callable(self, "_apply_anchor_preset").bind(anchor_min, anchor_max))
		return button

	func _create_pivot_button(text: String, normalized_pivot: Vector2) -> Button:
		var button := Button.new()
		button.text = text
		button.tooltip_text = "%s, %s" % [normalized_pivot.x, normalized_pivot.y]
		button.custom_minimum_size = Vector2(42, 28)
		button.pressed.connect(Callable(self, "_apply_pivot_preset").bind(normalized_pivot))
		return button

	func _update_mode_label(mode: int) -> void:
		if _layout_mode_label == null:
			return
		match mode:
			LayoutMode.POINT:
				_layout_mode_label.text = "Mode: Pos / Size"
			LayoutMode.H_STRETCH:
				_layout_mode_label.text = "Mode: Left / Right / Pos Y / Height"
			LayoutMode.V_STRETCH:
				_layout_mode_label.text = "Mode: Pos X / Width / Top / Bottom"
			LayoutMode.FULL_STRETCH:
				_layout_mode_label.text = "Mode: Left / Right / Top / Bottom"

	func _update_layout_visibility(mode: int, editable: bool) -> void:
		_set_all_rows_visible(false)
		match mode:
			LayoutMode.POINT:
				_set_layout_row_state(_pos_x_row, _pos_x_spin, true, editable)
				_set_layout_row_state(_pos_y_row, _pos_y_spin, true, editable)
				_set_layout_row_state(_width_row, _width_spin, true, editable)
				_set_layout_row_state(_height_row, _height_spin, true, editable)
			LayoutMode.H_STRETCH:
				_set_layout_row_state(_left_row, _left_spin, true, editable)
				_set_layout_row_state(_right_row, _right_spin, true, editable)
				_set_layout_row_state(_pos_y_row, _pos_y_spin, true, editable)
				_set_layout_row_state(_height_row, _height_spin, true, editable)
			LayoutMode.V_STRETCH:
				_set_layout_row_state(_pos_x_row, _pos_x_spin, true, editable)
				_set_layout_row_state(_width_row, _width_spin, true, editable)
				_set_layout_row_state(_top_row, _top_spin, true, editable)
				_set_layout_row_state(_bottom_row, _bottom_spin, true, editable)
			LayoutMode.FULL_STRETCH:
				_set_layout_row_state(_left_row, _left_spin, true, editable)
				_set_layout_row_state(_right_row, _right_spin, true, editable)
				_set_layout_row_state(_top_row, _top_spin, true, editable)
				_set_layout_row_state(_bottom_row, _bottom_spin, true, editable)

	func _set_all_rows_visible(visible: bool) -> void:
		_set_row_visible(_pos_x_row, visible)
		_set_row_visible(_pos_y_row, visible)
		_set_row_visible(_width_row, visible)
		_set_row_visible(_height_row, visible)
		_set_row_visible(_left_row, visible)
		_set_row_visible(_right_row, visible)
		_set_row_visible(_top_row, visible)
		_set_row_visible(_bottom_row, visible)

	func _set_row_visible(row: Control, visible: bool) -> void:
		if row != null:
			row.visible = visible

	func _set_layout_row_state(row: Control, spin_box: SpinBox, visible: bool, editable: bool) -> void:
		if row != null:
			row.visible = visible
			row.modulate = Color(1, 1, 1, 1) if editable else Color(1, 1, 1, 0.45)
		if spin_box != null:
			spin_box.editable = visible and editable

	func _set_spin_value(spin_box: SpinBox, value: float) -> void:
		if spin_box == null:
			return
		spin_box.set_block_signals(true)
		spin_box.value = value
		spin_box.set_block_signals(false)

	func _clear_control_binding() -> void:
		if _control != null and is_instance_valid(_control):
			if _control.tree_exited.is_connected(_on_control_tree_exited):
				_control.tree_exited.disconnect(_on_control_tree_exited)
			if _control.resized.is_connected(_on_control_resized):
				_control.resized.disconnect(_on_control_resized)
		_control = null
		_last_control_size = Vector2.ZERO
		_has_pivot_snapshot = false

	func _on_control_tree_exited() -> void:
		_clear_control_binding()
		refresh_from_control()

	func _on_control_resized() -> void:
		refresh_from_control()

	func _on_anchor_min_x_changed(value: float) -> void:
		_anchor_left_value = clampf(value, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Min")

	func _on_anchor_min_y_changed(value: float) -> void:
		_anchor_top_value = clampf(value, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Min")

	func _on_anchor_max_x_changed(value: float) -> void:
		_anchor_right_value = clampf(value, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Max")

	func _on_anchor_max_y_changed(value: float) -> void:
		_anchor_bottom_value = clampf(value, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Max")

	func _apply_anchor_preset(anchor_min: Vector2, anchor_max: Vector2) -> void:
		if _control == null or not is_instance_valid(_control):
			return

		var rect := Rect2(_control.position, _control.size)
		var parent_size := _get_reference_size()
		if not _has_reference_size(parent_size):
			refresh_from_control()
			return

		var changes := {
			"anchor_left": anchor_min.x,
			"anchor_top": anchor_min.y,
			"anchor_right": anchor_max.x,
			"anchor_bottom": anchor_max.y,
			"offset_left": rect.position.x - parent_size.x * anchor_min.x,
			"offset_top": rect.position.y - parent_size.y * anchor_min.y,
			"offset_right": rect.position.x + rect.size.x - parent_size.x * anchor_max.x,
			"offset_bottom": rect.position.y + rect.size.y - parent_size.y * anchor_max.y,
		}
		_commit_properties("Apply Anchor Preset", changes)

	func _commit_anchor_values(preserve_rect: bool, action_name: String) -> void:
		if _control == null or not is_instance_valid(_control):
			return

		var changes := {
			"anchor_left": _anchor_left_value,
			"anchor_top": _anchor_top_value,
			"anchor_right": _anchor_right_value,
			"anchor_bottom": _anchor_bottom_value,
		}

		if preserve_rect:
			var rect := Rect2(_control.position, _control.size)
			var parent_size := _get_reference_size()
			if not _has_reference_size(parent_size):
				refresh_from_control()
				return
			changes["offset_left"] = rect.position.x - parent_size.x * _anchor_left_value
			changes["offset_top"] = rect.position.y - parent_size.y * _anchor_top_value
			changes["offset_right"] = rect.position.x + rect.size.x - parent_size.x * _anchor_right_value
			changes["offset_bottom"] = rect.position.y + rect.size.y - parent_size.y * _anchor_bottom_value

		_commit_properties(action_name, changes)

	func _on_pivot_x_changed(value: float) -> void:
		_pivot_normalized_value.x = clampf(value, 0.0, 1.0)
		_apply_normalized_pivot("Change Pivot")

	func _on_pivot_y_changed(value: float) -> void:
		_pivot_normalized_value.y = clampf(value, 0.0, 1.0)
		_apply_normalized_pivot("Change Pivot")

	func _apply_pivot_preset(normalized_pivot: Vector2) -> void:
		if _control == null or not is_instance_valid(_control):
			return
		_pivot_normalized_value = Vector2(
			clampf(normalized_pivot.x, 0.0, 1.0),
			clampf(normalized_pivot.y, 0.0, 1.0)
		)
		_apply_normalized_pivot("Apply Pivot Preset")

	func _apply_normalized_pivot(action_name: String) -> void:
		if _control == null or not is_instance_valid(_control):
			return
		_commit_properties(action_name, {
			"pivot_offset": _get_pivot_offset_from_normalized(_control.size),
		})

	func _sync_pivot_state_from_control() -> void:
		if _control == null or not is_instance_valid(_control):
			return

		var control_size := _control.size
		if _has_pivot_snapshot and not _vector2_approx_equal(control_size, _last_control_size):
			var desired_pivot := _get_pivot_offset_from_normalized(control_size)
			if not _vector2_approx_equal(_control.pivot_offset, desired_pivot):
				_control.pivot_offset = desired_pivot
		else:
			_pivot_normalized_value = Vector2(
				_get_normalized_axis_value(float(_control.pivot_offset.x), control_size.x, _pivot_normalized_value.x),
				_get_normalized_axis_value(float(_control.pivot_offset.y), control_size.y, _pivot_normalized_value.y)
			)

		_last_control_size = control_size
		_has_pivot_snapshot = true

	func _get_pivot_offset_from_normalized(control_size: Vector2) -> Vector2:
		return Vector2(
			control_size.x * _pivot_normalized_value.x,
			control_size.y * _pivot_normalized_value.y
		)

	func _get_normalized_axis_value(offset: float, axis_size: float, fallback: float) -> float:
		if axis_size <= 0.0:
			return clampf(fallback, 0.0, 1.0)
		return clampf(offset / axis_size, 0.0, 1.0)

	func _vector2_approx_equal(left: Vector2, right: Vector2) -> bool:
		return is_equal_approx(left.x, right.x) and is_equal_approx(left.y, right.y)

	func _on_layout_field_changed(_value: float) -> void:
		if _control == null or not is_instance_valid(_control):
			return

		var parent_size := _get_reference_size()
		if not _has_reference_size(parent_size):
			refresh_from_control()
			return

		var mode := _get_layout_mode()
		var anchor_left_px := parent_size.x * _anchor_left_value
		var anchor_right_px := parent_size.x * _anchor_right_value
		var anchor_top_px := parent_size.y * _anchor_top_value
		var anchor_bottom_px := parent_size.y * _anchor_bottom_value

		var left := anchor_left_px + float(_control.offset_left)
		var right := anchor_right_px + float(_control.offset_right)
		var top := anchor_top_px + float(_control.offset_top)
		var bottom := anchor_bottom_px + float(_control.offset_bottom)
		var width := _width_spin.value
		var height := _height_spin.value

		match mode:
			LayoutMode.POINT:
				var pos_x := _pos_x_spin.value
				var pos_y := _pos_y_spin.value
				left = anchor_left_px + pos_x - width * 0.5
				right = left + width
				top = anchor_top_px + pos_y - height * 0.5
				bottom = top + height
			LayoutMode.H_STRETCH:
				left = anchor_left_px + _left_spin.value
				right = anchor_right_px - _right_spin.value
				var pos_y := _pos_y_spin.value
				top = anchor_top_px + pos_y - height * 0.5
				bottom = top + height
			LayoutMode.V_STRETCH:
				var pos_x := _pos_x_spin.value
				left = anchor_left_px + pos_x - width * 0.5
				right = left + width
				top = anchor_top_px + _top_spin.value
				bottom = anchor_bottom_px - _bottom_spin.value
			LayoutMode.FULL_STRETCH:
				left = anchor_left_px + _left_spin.value
				right = anchor_right_px - _right_spin.value
				top = anchor_top_px + _top_spin.value
				bottom = anchor_bottom_px - _bottom_spin.value

		_commit_properties("Change RectTransform Layout", {
			"offset_left": left - anchor_left_px,
			"offset_top": top - anchor_top_px,
			"offset_right": right - anchor_right_px,
			"offset_bottom": bottom - anchor_bottom_px,
		})

	func _commit_properties(action_name: String, changes: Dictionary) -> void:
		if _control == null or not is_instance_valid(_control):
			return

		if changes.is_empty():
			return

		if _undo_redo == null:
			for key in changes.keys():
				_control.set(StringName(str(key)), changes[key])
			refresh_from_control()
			return

		var old_values: Dictionary = {}
		for key in changes.keys():
			old_values[key] = _control.get(StringName(str(key)))

		_undo_redo.create_action(action_name)
		for key in changes.keys():
			var property_name := StringName(str(key))
			_undo_redo.add_do_property(_control, property_name, changes[key])
			_undo_redo.add_undo_property(_control, property_name, old_values[key])
		_undo_redo.commit_action()
		refresh_from_control()

	func _get_layout_mode() -> int:
		var horizontal_equal := is_equal_approx(_anchor_left_value, _anchor_right_value)
		var vertical_equal := is_equal_approx(_anchor_top_value, _anchor_bottom_value)

		if horizontal_equal and vertical_equal:
			return LayoutMode.POINT
		if not horizontal_equal and vertical_equal:
			return LayoutMode.H_STRETCH
		if horizontal_equal and not vertical_equal:
			return LayoutMode.V_STRETCH
		return LayoutMode.FULL_STRETCH

	func _get_reference_size() -> Vector2:
		if _control == null or not is_instance_valid(_control):
			return Vector2.ZERO

		var parent: Node = _control.get_parent()
		if parent is Control:
			var parent_control := parent as Control
			if parent_control.size.x > 0.0 and parent_control.size.y > 0.0:
				return parent_control.size

		var viewport: Viewport = _control.get_viewport()
		if viewport != null:
			return viewport.get_visible_rect().size

		return Vector2.ZERO

	func _has_reference_size(parent_size: Vector2) -> bool:
		return parent_size.x > 0.0 and parent_size.y > 0.0

var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager
var _selection: EditorSelection
var _panels_by_object_id: Dictionary = {}

func setup(editor_interface: EditorInterface, undo_redo: EditorUndoRedoManager) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	if _editor_interface != null:
		_selection = _editor_interface.get_selection()
		if _selection != null and not _selection.selection_changed.is_connected(_on_selection_changed):
			_selection.selection_changed.connect(_on_selection_changed)

func dispose() -> void:
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	for panel in _panels_by_object_id.values():
		if panel != null and is_instance_valid(panel) and panel.has_method("clear_control_binding"):
			panel.clear_control_binding()
	_panels_by_object_id.clear()

func _can_handle(object: Object) -> bool:
	return object is Control

func _parse_begin(object: Object) -> void:
	if not (object is Control):
		return

	var object_id: int = object.get_instance_id()
	var existing_panel: RectTransformPanel = _panels_by_object_id.get(object_id) as RectTransformPanel
	if existing_panel != null and is_instance_valid(existing_panel):
		if existing_panel.has_method("clear_control_binding"):
			existing_panel.clear_control_binding()
		var panel_parent: Node = existing_panel.get_parent()
		if panel_parent != null:
			panel_parent.remove_child(existing_panel)
		existing_panel.queue_free()
	_panels_by_object_id.erase(object_id)

	var panel: RectTransformPanel = RectTransformPanel.new(_editor_interface, _undo_redo)
	panel.bind_control(object as Control)
	panel.tree_exited.connect(_on_panel_tree_exited.bind(object_id, panel), CONNECT_ONE_SHOT)
	_panels_by_object_id[object_id] = panel
	add_custom_control(panel)

func _on_selection_changed() -> void:
	var object_ids := _panels_by_object_id.keys()
	for object_id in object_ids:
		var panel: RectTransformPanel = _panels_by_object_id.get(object_id) as RectTransformPanel
		if panel == null or not is_instance_valid(panel):
			_panels_by_object_id.erase(object_id)
			continue
		if panel.has_method("refresh_from_control"):
			panel.refresh_from_control()

func _on_panel_tree_exited(object_id: int, panel: RectTransformPanel) -> void:
	var current_panel: RectTransformPanel = _panels_by_object_id.get(object_id) as RectTransformPanel
	if current_panel == panel:
		_panels_by_object_id.erase(object_id)
