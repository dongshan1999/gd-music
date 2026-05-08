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

	enum PivotEditMode {
		NORMALIZED,
		PIXELS,
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
	var _last_valid_reference_size := Vector2.ZERO
	var _has_pivot_snapshot := false
	var _pivot_mode := PivotEditMode.NORMALIZED
	var _refresh_pending := false

	var _root: VBoxContainer
	var _layout_mode_label: Label
	var _reference_warning_label: Label
	var _pivot_mode_option: OptionButton
	var _pivot_note_label: Label
	var _anchor_min_x_spin: SpinBox
	var _anchor_min_y_spin: SpinBox
	var _anchor_max_x_spin: SpinBox
	var _anchor_max_y_spin: SpinBox
	var _pivot_x_spin: SpinBox
	var _pivot_y_spin: SpinBox
	# 所有布局行始终保留引用，以便控制灰显
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
		# 不再使用 _process 轮询，完全依靠信号和延迟刷新
		_request_refresh()

	func _exit_tree() -> void:
		clear_control_binding()

	func bind_control(control: Control) -> void:
		_clear_control_binding()
		_control = control
		_pivot_normalized_value = Vector2(0.5, 0.5)
		_last_control_size = Vector2.ZERO
		_last_valid_reference_size = Vector2.ZERO
		_has_pivot_snapshot = false
		if _control == null or not is_instance_valid(_control):
			return
		if _control.has_signal("tree_exited") and not _control.tree_exited.is_connected(_on_control_tree_exited):
			_control.tree_exited.connect(_on_control_tree_exited, CONNECT_ONE_SHOT)
		if _control.has_signal("resized") and not _control.resized.is_connected(_on_control_resized):
			_control.resized.connect(_on_control_resized)
		if _control.has_signal("item_rect_changed") and not _control.item_rect_changed.is_connected(_on_control_rect_changed):
			_control.item_rect_changed.connect(_on_control_rect_changed)
		if _ui_ready:
			_request_refresh()

	func clear_control_binding() -> void:
		_clear_control_binding()
		_request_refresh()

	func refresh_from_control() -> void:
		if not _ui_ready:
			return
		if _control == null or not is_instance_valid(_control):
			_set_all_rows_greyed(true)
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
		_update_pivot_controls()

		var parent_size := _get_reference_size()
		var has_reference_size := _has_reference_size(parent_size)
		if has_reference_size:
			_last_valid_reference_size = parent_size
		_reference_warning_label.visible = not has_reference_size

		# 始终使用有效参考尺寸，若无则使用控件自身尺寸作为退化
		var layout_ref := parent_size if has_reference_size else _control.size
		if not _has_reference_size(layout_ref):
			layout_ref = _last_valid_reference_size
		if not _has_reference_size(layout_ref):
			layout_ref = _control.get_combined_minimum_size()
		if not _has_reference_size(layout_ref):
			layout_ref = Vector2(1, 1)

		var anchor_left_px := layout_ref.x * _anchor_left_value
		var anchor_right_px := layout_ref.x * _anchor_right_value
		var anchor_top_px := layout_ref.y * _anchor_top_value
		var anchor_bottom_px := layout_ref.y * _anchor_bottom_value

		var left := anchor_left_px + float(_control.offset_left)
		var right := anchor_right_px + float(_control.offset_right)
		var top := anchor_top_px + float(_control.offset_top)
		var bottom := anchor_bottom_px + float(_control.offset_bottom)
		var width := right - left
		var height := bottom - top

		var mode := _get_layout_mode()
		_update_mode_label(mode)

		# 刷新所有行的可见性和灰显状态（不隐藏，只灰显）
		_set_rows_state_by_mode(mode, has_reference_size)

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
				_set_spin_value(_height_spin, height)
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
		_root.add_child(_create_pivot_mode_row())
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
		_reference_warning_label.text = "Reference size unavailable. Values show raw offsets."
		_reference_warning_label.visible = false
		_reference_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_reference_warning_label.add_theme_font_size_override("font_size", 11)
		_reference_warning_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42))
		_root.add_child(_reference_warning_label)
		_root.add_child(_create_layout_fields())

	# [其余UI创建函数与之前基本相同，仅微调了按钮最小尺寸和居中对齐]
	func _create_title_bar() -> Control:
		var bar := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.17, 0.18, 0.22)
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
		box.add_child(_create_vector_row("Anchor Min", _anchor_min_x_spin, _anchor_min_y_spin,
			Callable(self, "_on_anchor_min_x_changed"), Callable(self, "_on_anchor_min_y_changed")))
		box.add_child(_create_vector_row("Anchor Max", _anchor_max_x_spin, _anchor_max_y_spin,
			Callable(self, "_on_anchor_max_x_changed"), Callable(self, "_on_anchor_max_y_changed")))
		return box

	func _create_anchor_preset_grid() -> Control:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var grid := GridContainer.new()
		grid.columns = 4
		var presets = [
			["↖", Vector2(0,0), Vector2(0,0)], ["↑", Vector2(0.5,0), Vector2(0.5,0)], ["↗", Vector2(1,0), Vector2(1,0)], ["H↑", Vector2(0,0), Vector2(1,0)],
			["←", Vector2(0,0.5), Vector2(0,0.5)], ["•", Vector2(0.5,0.5), Vector2(0.5,0.5)], ["→", Vector2(1,0.5), Vector2(1,0.5)], ["H•", Vector2(0,0.5), Vector2(1,0.5)],
			["↙", Vector2(0,1), Vector2(0,1)], ["↓", Vector2(0.5,1), Vector2(0.5,1)], ["↘", Vector2(1,1), Vector2(1,1)], ["H↓", Vector2(0,1), Vector2(1,1)],
			["V←", Vector2(0,0), Vector2(0,1)], ["V•", Vector2(0.5,0), Vector2(0.5,1)], ["V→", Vector2(1,0), Vector2(1,1)], ["□", Vector2(0,0), Vector2(1,1)]
		]
		for p in presets:
			var btn := Button.new()
			btn.text = p[0]
			btn.custom_minimum_size = Vector2(48, 28)
			btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.pressed.connect(Callable(self, "_apply_anchor_preset").bind(p[1], p[2]))
			grid.add_child(btn)
		box.add_child(grid)
		return box

	func _create_pivot_fields() -> VBoxContainer:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_pivot_x_spin = _make_dynamic_spinbox()
		_pivot_y_spin = _make_dynamic_spinbox()
		box.add_child(_create_vector_row("Pivot", _pivot_x_spin, _pivot_y_spin,
			Callable(self, "_on_pivot_x_changed"), Callable(self, "_on_pivot_y_changed")))
		return box

	func _create_pivot_preset_grid() -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = 3
		var pivots = [
			["↖", Vector2(0,0)], ["↑", Vector2(0.5,0)], ["↗", Vector2(1,0)],
			["←", Vector2(0,0.5)], ["•", Vector2(0.5,0.5)], ["→", Vector2(1,0.5)],
			["↙", Vector2(0,1)], ["↓", Vector2(0.5,1)], ["↘", Vector2(1,1)]
		]
		for p in pivots:
			var btn := Button.new()
			btn.text = p[0]
			btn.custom_minimum_size = Vector2(42, 28)
			btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.pressed.connect(Callable(self, "_apply_pivot_preset").bind(p[1]))
			grid.add_child(btn)
		return grid

	func _create_pivot_note() -> Label:
		_pivot_note_label = Label.new()
		_pivot_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pivot_note_label.add_theme_font_size_override("font_size", 11)
		_pivot_note_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
		return _pivot_note_label

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
		_pos_x_row = _create_spin_row("Pos X", _pos_x_spin, layout_changed.bind("pos_x"))
		_pos_y_row = _create_spin_row("Pos Y", _pos_y_spin, layout_changed.bind("pos_y"))
		_width_row = _create_spin_row("Width", _width_spin, layout_changed.bind("width"))
		_height_row = _create_spin_row("Height", _height_spin, layout_changed.bind("height"))
		_left_row = _create_spin_row("Left", _left_spin, layout_changed.bind("left"))
		_right_row = _create_spin_row("Right", _right_spin, layout_changed.bind("right"))
		_top_row = _create_spin_row("Top", _top_spin, layout_changed.bind("top"))
		_bottom_row = _create_spin_row("Bottom", _bottom_spin, layout_changed.bind("bottom"))

		# 提示 right/bottom 是正边距
		_right_row.tooltip_text = "Positive pixel distance from right edge (internal negative offset)."
		_right_spin.tooltip_text = _right_row.tooltip_text
		_bottom_row.tooltip_text = "Positive pixel distance from bottom edge (internal negative offset)."
		_bottom_spin.tooltip_text = _bottom_row.tooltip_text

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
		label.custom_minimum_size = Vector2(72, 0)
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
		label.custom_minimum_size = Vector2(72, 0)
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

	func _create_pivot_mode_row() -> HBoxContainer:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "Mode"
		label.custom_minimum_size = Vector2(72, 0)
		row.add_child(label)
		_pivot_mode_option = OptionButton.new()
		_pivot_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pivot_mode_option.add_item("Normalized")
		_pivot_mode_option.add_item("Pixels")
		_pivot_mode_option.item_selected.connect(_on_pivot_mode_selected)
		row.add_child(_pivot_mode_option)
		return row

	func _make_anchor_spinbox() -> SpinBox:
		var sb := SpinBox.new()
		sb.min_value = 0.0
		sb.max_value = 1.0
		sb.step = ANCHOR_STEP
		sb.custom_minimum_size = Vector2(0, 24)
		return sb

	func _make_dynamic_spinbox() -> SpinBox:
		var sb := SpinBox.new()
		sb.custom_minimum_size = Vector2(0, 24)
		return sb

	func _make_value_spinbox() -> SpinBox:
		var sb := SpinBox.new()
		sb.min_value = -100000.0
		sb.max_value = 100000.0
		sb.step = VALUE_STEP
		sb.suffix = " px"
		sb.custom_minimum_size = Vector2(0, 24)
		return sb

	func _set_rows_state_by_mode(mode: int, has_ref: bool) -> void:
		var all_rows = [_pos_x_row, _pos_y_row, _width_row, _height_row, _left_row, _right_row, _top_row, _bottom_row]
		var all_spins = [_pos_x_spin, _pos_y_spin, _width_spin, _height_spin, _left_spin, _right_spin, _top_spin, _bottom_spin]

		# 全部设为灰显不可编辑
		for i in all_rows.size():
			if all_rows[i] != null:
				all_rows[i].modulate = Color(1,1,1,0.45)
			if all_spins[i] != null:
				all_spins[i].editable = false

		# 根据模式激活需要的行
		var active_indices := []
		match mode:
			LayoutMode.POINT: active_indices = [0,1,2,3]
			LayoutMode.H_STRETCH: active_indices = [4,5,1,3]
			LayoutMode.V_STRETCH: active_indices = [0,2,3,6,7]
			LayoutMode.FULL_STRETCH: active_indices = [4,5,6,7]

		for idx in active_indices:
			if all_rows[idx] != null:
				all_rows[idx].modulate = Color(1,1,1,1) if has_ref else Color(1,1,1,0.7)
			if all_spins[idx] != null:
				all_spins[idx].editable = true

	func _set_all_rows_greyed(grey: bool) -> void:
		var rows = [_pos_x_row, _pos_y_row, _width_row, _height_row, _left_row, _right_row, _top_row, _bottom_row]
		var spins = [_pos_x_spin, _pos_y_spin, _width_spin, _height_spin, _left_spin, _right_spin, _top_spin, _bottom_spin]
		for i in rows.size():
			if rows[i] != null:
				rows[i].modulate = Color(1,1,1,0.45) if grey else Color(1,1,1,1)
			if spins[i] != null:
				spins[i].editable = not grey

	func _update_mode_label(mode: int) -> void:
		if _layout_mode_label == null: return
		match mode:
			LayoutMode.POINT: _layout_mode_label.text = "Mode: Pos / Size"
			LayoutMode.H_STRETCH: _layout_mode_label.text = "Mode: Left / Right / Pos Y / Height"
			LayoutMode.V_STRETCH: _layout_mode_label.text = "Mode: Pos X / Width / Height / Top / Bottom"
			LayoutMode.FULL_STRETCH: _layout_mode_label.text = "Mode: Left / Right / Top / Bottom"

	func _update_pivot_controls() -> void:
		if _pivot_mode_option != null:
			_pivot_mode_option.select(_pivot_mode)
		if _pivot_mode == PivotEditMode.NORMALIZED:
			_configure_spinbox(_pivot_x_spin, 0.0, 1.0, ANCHOR_STEP, false, false, "")
			_configure_spinbox(_pivot_y_spin, 0.0, 1.0, ANCHOR_STEP, false, false, "")
			_set_spin_value(_pivot_x_spin, _pivot_normalized_value.x)
			_set_spin_value(_pivot_y_spin, _pivot_normalized_value.y)
			_pivot_note_label.text = "Normalized (0-1), scales with size."
		else:
			_configure_spinbox(_pivot_x_spin, -100000.0, 100000.0, VALUE_STEP, true, true, " px")
			_configure_spinbox(_pivot_y_spin, -100000.0, 100000.0, VALUE_STEP, true, true, " px")
			if _control != null and is_instance_valid(_control):
				_set_spin_value(_pivot_x_spin, float(_control.pivot_offset.x))
				_set_spin_value(_pivot_y_spin, float(_control.pivot_offset.y))
			_pivot_note_label.text = "Pixels (pivot_offset). No auto-rescale."

	func _configure_spinbox(sb: SpinBox, minv, maxv, step, lesser, greater, suffix: String) -> void:
		if sb == null: return
		sb.min_value = minv
		sb.max_value = maxv
		sb.step = step
		sb.allow_lesser = lesser
		sb.allow_greater = greater
		sb.suffix = suffix

	func _set_spin_value(sb: SpinBox, value: float) -> void:
		if sb == null: return
		sb.set_block_signals(true)
		sb.value = value
		sb.set_block_signals(false)

	func _clear_control_binding() -> void:
		if _control != null and is_instance_valid(_control):
			if _control.tree_exited.is_connected(_on_control_tree_exited):
				_control.tree_exited.disconnect(_on_control_tree_exited)
			if _control.resized.is_connected(_on_control_resized):
				_control.resized.disconnect(_on_control_resized)
			if _control.has_signal("item_rect_changed") and _control.item_rect_changed.is_connected(_on_control_rect_changed):
				_control.item_rect_changed.disconnect(_on_control_rect_changed)
		_control = null

	func _on_control_tree_exited() -> void:
		_clear_control_binding()
		_request_refresh()

	func _on_control_resized() -> void:
		_request_refresh()

	func _on_control_rect_changed() -> void:
		_request_refresh()

	func _on_pivot_mode_selected(index: int) -> void:
		_pivot_mode = PivotEditMode.NORMALIZED if index == 0 else PivotEditMode.PIXELS
		if _control != null and is_instance_valid(_control):
			_pivot_normalized_value = Vector2(
				_get_normalized_axis_value(float(_control.pivot_offset.x), _control.size.x, _pivot_normalized_value.x),
				_get_normalized_axis_value(float(_control.pivot_offset.y), _control.size.y, _pivot_normalized_value.y)
			)
		_update_pivot_controls()

	func _on_anchor_min_x_changed(v: float) -> void:
		_anchor_left_value = clampf(v, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Min")

	func _on_anchor_min_y_changed(v: float) -> void:
		_anchor_top_value = clampf(v, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Min")

	func _on_anchor_max_x_changed(v: float) -> void:
		_anchor_right_value = clampf(v, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Max")

	func _on_anchor_max_y_changed(v: float) -> void:
		_anchor_bottom_value = clampf(v, 0.0, 1.0)
		_commit_anchor_values(true, "Change Anchor Max")

	func _apply_anchor_preset(amin: Vector2, amax: Vector2) -> void:
		if _control == null: return
		var ref := _get_anchor_compensation_reference_size()
		var rect := _get_current_rect(ref)
		var changes := {
			"anchor_left": amin.x, "anchor_top": amin.y,
			"anchor_right": amax.x, "anchor_bottom": amax.y,
			"offset_left": rect.position.x - ref.x * amin.x,
			"offset_top": rect.position.y - ref.y * amin.y,
			"offset_right": rect.position.x + rect.size.x - ref.x * amax.x,
			"offset_bottom": rect.position.y + rect.size.y - ref.y * amax.y,
		}
		_commit_properties("Apply Anchor Preset", changes)

	func _commit_anchor_values(preserve_rect: bool, action_name: String) -> void:
		if _control == null: return
		var changes := {
			"anchor_left": _anchor_left_value, "anchor_top": _anchor_top_value,
			"anchor_right": _anchor_right_value, "anchor_bottom": _anchor_bottom_value,
		}
		if preserve_rect:
			var ref := _get_anchor_compensation_reference_size()
			var rect := _get_current_rect(ref)
			changes["offset_left"] = rect.position.x - ref.x * _anchor_left_value
			changes["offset_top"] = rect.position.y - ref.y * _anchor_top_value
			changes["offset_right"] = rect.position.x + rect.size.x - ref.x * _anchor_right_value
			changes["offset_bottom"] = rect.position.y + rect.size.y - ref.y * _anchor_bottom_value
		_commit_properties(action_name, changes)

	func _on_pivot_x_changed(v: float) -> void:
		if _pivot_mode == PivotEditMode.NORMALIZED:
			_pivot_normalized_value.x = clampf(v, 0.0, 1.0)
			_apply_normalized_pivot("Change Pivot")
		else:
			_apply_pixel_pivot(v, _pivot_y_spin.value, "Change Pivot Offset")

	func _on_pivot_y_changed(v: float) -> void:
		if _pivot_mode == PivotEditMode.NORMALIZED:
			_pivot_normalized_value.y = clampf(v, 0.0, 1.0)
			_apply_normalized_pivot("Change Pivot")
		else:
			_apply_pixel_pivot(_pivot_x_spin.value, v, "Change Pivot Offset")

	func _apply_pivot_preset(np: Vector2) -> void:
		if _control == null: return
		_pivot_normalized_value = Vector2(clampf(np.x, 0, 1), clampf(np.y, 0, 1))
		_apply_normalized_pivot("Apply Pivot Preset")

	func _apply_normalized_pivot(action: String) -> void:
		if _control == null: return
		_commit_properties(action, {"pivot_offset": _get_pivot_offset_from_normalized(_control.size)})

	func _apply_pixel_pivot(px, py, action: String) -> void:
		if _control == null: return
		_commit_properties(action, {"pivot_offset": Vector2(px, py)})

	func _sync_pivot_state_from_control() -> void:
		if _control == null: return
		var sz := _control.size
		if _pivot_mode == PivotEditMode.NORMALIZED and _has_pivot_snapshot and not _vector2_approx_equal(sz, _last_control_size):
			var desired := _get_pivot_offset_from_normalized(sz)
			if not _vector2_approx_equal(_control.pivot_offset, desired):
				_control.pivot_offset = desired
				_sync_editor_after_property_change()
		_pivot_normalized_value = Vector2(
			_get_normalized_axis_value(float(_control.pivot_offset.x), sz.x, _pivot_normalized_value.x),
			_get_normalized_axis_value(float(_control.pivot_offset.y), sz.y, _pivot_normalized_value.y)
		)
		_last_control_size = sz
		_has_pivot_snapshot = true

	func _get_pivot_offset_from_normalized(sz: Vector2) -> Vector2:
		return Vector2(sz.x * _pivot_normalized_value.x, sz.y * _pivot_normalized_value.y)

	func _get_normalized_axis_value(offset, axis, fallback) -> float:
		if axis <= 0.0: return clampf(fallback, 0.0, 1.0)
		return clampf(offset / axis, 0.0, 1.0)

	func _vector2_approx_equal(a: Vector2, b: Vector2) -> bool:
		return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y)

	func _on_layout_field_changed(_value: float, field_name: StringName) -> void:
		if _control == null: return
		var parent_size := _get_reference_size()
		var has_ref := _has_reference_size(parent_size)
		var layout_ref := parent_size if has_ref else _control.size
		if not _has_reference_size(layout_ref): layout_ref = _last_valid_reference_size
		if not _has_reference_size(layout_ref): layout_ref = _control.get_combined_minimum_size()
		if not _has_reference_size(layout_ref): layout_ref = Vector2(1,1)

		var mode := _get_layout_mode()
		var al := layout_ref.x * _anchor_left_value
		var ar := layout_ref.x * _anchor_right_value
		var at := layout_ref.y * _anchor_top_value
		var ab := layout_ref.y * _anchor_bottom_value

		var left := al + float(_control.offset_left)
		var right := ar + float(_control.offset_right)
		var top := at + float(_control.offset_top)
		var bottom := ab + float(_control.offset_bottom)
		var w := _width_spin.value
		var h := _height_spin.value

		match mode:
			LayoutMode.POINT:
				var px = _pos_x_spin.value
				var py = _pos_y_spin.value
				left = al + px - w * 0.5
				right = left + w
				top = at + py - h * 0.5
				bottom = top + h
			LayoutMode.H_STRETCH:
				left = al + _left_spin.value
				right = ar - _right_spin.value
				top = at + _pos_y_spin.value - h * 0.5
				bottom = top + h
			LayoutMode.V_STRETCH:
				left = al + _pos_x_spin.value - w * 0.5
				right = left + w
				top = at + _top_spin.value
				bottom = ab - _bottom_spin.value
				if field_name == &"height":
					var center_y := (top + bottom) * 0.5
					top = center_y - h * 0.5
					bottom = center_y + h * 0.5
			LayoutMode.FULL_STRETCH:
				left = al + _left_spin.value
				right = ar - _right_spin.value
				top = at + _top_spin.value
				bottom = ab - _bottom_spin.value

		_commit_properties("Change RectTransform Layout", {
			"offset_left": left - al,
			"offset_top": top - at,
			"offset_right": right - ar,
			"offset_bottom": bottom - ab,
		})

	func _get_anchor_compensation_reference_size() -> Vector2:
		var ps := _get_reference_size()
		if _has_reference_size(ps): return ps
		if _has_reference_size(_last_valid_reference_size): return _last_valid_reference_size
		if _control != null and is_instance_valid(_control):
			if _has_reference_size(_control.size): return _control.size
			var minsz := _control.get_combined_minimum_size()
			if _has_reference_size(minsz): return minsz
		return Vector2(1,1)

	func _get_current_rect(ref: Vector2) -> Rect2:
		var al := ref.x * float(_control.anchor_left) + float(_control.offset_left)
		var at := ref.y * float(_control.anchor_top) + float(_control.offset_top)
		var ar := ref.x * float(_control.anchor_right) + float(_control.offset_right)
		var ab := ref.y * float(_control.anchor_bottom) + float(_control.offset_bottom)
		return Rect2(al, at, ar - al, ab - at)

	func _commit_properties(action: String, changes: Dictionary) -> void:
		if _control == null: return
		if changes.is_empty(): return
		var ordered := _get_ordered_property_names(changes)
		if _undo_redo == null:
			for prop in ordered:
				_control.set(prop, changes[String(prop)])
			_sync_editor_after_property_change()
			_request_refresh()
			return
		var old_vals := {}
		for prop in ordered:
			old_vals[String(prop)] = _control.get(prop)
		_undo_redo.create_action(action)
		for prop in ordered:
			var key := String(prop)
			_undo_redo.add_do_property(_control, prop, changes[key])
			_undo_redo.add_undo_property(_control, prop, old_vals[key])
		_undo_redo.add_do_method(_control, "notify_property_list_changed")
		_undo_redo.add_undo_method(_control, "notify_property_list_changed")
		_undo_redo.add_do_method(_control, "queue_redraw")
		_undo_redo.add_undo_method(_control, "queue_redraw")
		_undo_redo.commit_action()
		_sync_editor_after_property_change()
		_request_refresh()

	func _sync_editor_after_property_change() -> void:
		if _control == null or not is_instance_valid(_control):
			return
		_control.notify_property_list_changed()
		_control.queue_redraw()
		if _editor_interface != null:
			_editor_interface.set_object_edited(_control, true)

	func _get_ordered_property_names(changes: Dictionary) -> Array[StringName]:
		var order := ["anchor_left","anchor_top","anchor_right","anchor_bottom","offset_left","offset_top","offset_right","offset_bottom","pivot_offset"]
		var res: Array[StringName] = []
		for k in order:
			if changes.has(k):
				res.append(StringName(k))
		for raw_key in changes.keys():
			var sn := StringName(str(raw_key))
			if not res.has(sn):
				res.append(sn)
		return res

	func _get_layout_mode() -> int:
		if _control == null:
			return _fallback_mode()
		var he := is_equal_approx(float(_control.anchor_left), float(_control.anchor_right))
		var ve := is_equal_approx(float(_control.anchor_top), float(_control.anchor_bottom))
		if he and ve: return LayoutMode.POINT
		if not he and ve: return LayoutMode.H_STRETCH
		if he and not ve: return LayoutMode.V_STRETCH
		return LayoutMode.FULL_STRETCH

	func _fallback_mode() -> int:
		var he := is_equal_approx(_anchor_left_value, _anchor_right_value)
		var ve := is_equal_approx(_anchor_top_value, _anchor_bottom_value)
		if he and ve: return LayoutMode.POINT
		if not he and ve: return LayoutMode.H_STRETCH
		if he and not ve: return LayoutMode.V_STRETCH
		return LayoutMode.FULL_STRETCH

	func _request_refresh() -> void:
		if _refresh_pending: return
		_refresh_pending = true
		call_deferred("_flush_refresh")

	func _flush_refresh() -> void:
		_refresh_pending = false
		refresh_from_control()

	func _get_reference_size() -> Vector2:
		if _control == null: return Vector2.ZERO
		var parent := _control.get_parent()
		if parent is Control:
			var pc := parent as Control
			if pc.size.x > 0 and pc.size.y > 0:
				return pc.size
		var vp := _control.get_viewport()
		if vp != null:
			return vp.get_visible_rect().size
		return Vector2.ZERO

	func _has_reference_size(sz: Vector2) -> bool:
		return sz.x > 0 and sz.y > 0

# ========== 外部 Inspector Plugin 类 ==========
var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager
var _selection: EditorSelection
var _panels_by_object_id: Dictionary = {}

func setup(ei: EditorInterface, ur: EditorUndoRedoManager) -> void:
	_editor_interface = ei
	_undo_redo = ur
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
	if not (object is Control): return
	var oid := object.get_instance_id()
	var existing := _panels_by_object_id.get(oid) as RectTransformPanel
	if existing != null and is_instance_valid(existing):
		if existing.has_method("clear_control_binding"):
			existing.clear_control_binding()
		var p := existing.get_parent()
		if p != null: p.remove_child(existing)
		existing.queue_free()
	_panels_by_object_id.erase(oid)

	var panel := RectTransformPanel.new(_editor_interface, _undo_redo)
	panel.bind_control(object as Control)
	panel.tree_exited.connect(_on_panel_tree_exited.bind(oid, panel), CONNECT_ONE_SHOT)
	_panels_by_object_id[oid] = panel
	add_custom_control(panel)

func _on_selection_changed() -> void:
	for oid in _panels_by_object_id.keys():
		var p := _panels_by_object_id.get(oid) as RectTransformPanel
		if p == null or not is_instance_valid(p):
			_panels_by_object_id.erase(oid)
			continue
		if p.has_method("refresh_from_control"):
			p.refresh_from_control()

func _on_panel_tree_exited(oid: int, panel: RectTransformPanel) -> void:
	if _panels_by_object_id.get(oid) == panel:
		_panels_by_object_id.erase(oid)
