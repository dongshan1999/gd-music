class_name MusicAppPlaylistSongRow
extends Panel

const SELECTED_ICON := preload("res://textures/check-circle.svg")
const UNSELECTED_ICON := preload("res://textures/check-circle-outline.svg")

const MODE_NORMAL := 0
const MODE_SORT := 1
const MODE_DELETE := 2

signal play_requested(index: int)
signal selection_toggled(index: int)
signal delete_requested(index: int)
signal sort_drag_started(index: int)
signal sort_drag_moved(pointer_position: Vector2)
signal sort_drag_ended(index: int)

var _is_bound := false
var _slot_index := -1
var _is_dragging := false

var _select_button: Button
var _index_label: Label
var _title_label: Label
var _subtitle_label: Label
var _vip_label: Label
var _delete_button: Button
var _drag_handle_button: Button
var _play_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_select_button = $Margin/Row/SongSelectButton
	_index_label = $Margin/Row/SongIndexLabel
	_title_label = $Margin/Row/SongInfo/SongTitleLabel
	_subtitle_label = $Margin/Row/SongInfo/SongSubtitleLabel
	_vip_label = $Margin/Row/SongVipLabel
	_delete_button = $Margin/Row/SongDeleteButton
	_drag_handle_button = $Margin/Row/SongDragHandleButton
	_play_button = $SongButton

	_select_button.pressed.connect(_on_select_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_drag_handle_button.gui_input.connect(_on_drag_handle_gui_input)
	_play_button.pressed.connect(_on_play_pressed)

func configure(slot_index: int, track: TrackData) -> void:
	setup()
	_slot_index = slot_index
	_index_label.text = str(slot_index + 1)
	if track == null:
		_title_label.text = "未知歌曲"
		_subtitle_label.text = ""
		_vip_label.visible = false
		return
	_title_label.text = _format_title(track)
	_subtitle_label.text = _format_subtitle(track)
	_vip_label.visible = false

func set_management_mode(mode: int, selected: bool) -> void:
	setup()
	var is_normal := mode == MODE_NORMAL
	var is_sort := mode == MODE_SORT
	var is_delete := mode == MODE_DELETE
	_play_button.visible = is_normal
	_drag_handle_button.visible = is_sort
	_select_button.visible = is_delete
	_delete_button.visible = is_delete
	_index_label.visible = not is_delete
	_select_button.icon = SELECTED_ICON if selected else UNSELECTED_ICON

func _on_play_pressed() -> void:
	if _slot_index < 0:
		return
	play_requested.emit(_slot_index)

func _on_select_pressed() -> void:
	if _slot_index < 0:
		return
	selection_toggled.emit(_slot_index)

func _on_delete_pressed() -> void:
	if _slot_index < 0:
		return
	delete_requested.emit(_slot_index)

func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if _slot_index < 0:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_begin_drag(mouse_button.global_position)
		else:
			_finish_drag()
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_drag(touch.position)
		else:
			_finish_drag()
		accept_event()

func _input(event: InputEvent) -> void:
	if not _is_dragging:
		return
	if event is InputEventMouseMotion:
		sort_drag_moved.emit((event as InputEventMouseMotion).global_position)
	elif event is InputEventScreenDrag:
		sort_drag_moved.emit((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			_finish_drag()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			_finish_drag()

func _begin_drag(pointer_position: Vector2) -> void:
	if _is_dragging:
		return
	_is_dragging = true
	sort_drag_started.emit(_slot_index)
	sort_drag_moved.emit(pointer_position)

func _finish_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	sort_drag_ended.emit(_slot_index)

func _format_title(track: TrackData) -> String:
	if not track.title.is_empty():
		return track.title
	if not track.file_path.is_empty():
		return track.file_path.get_file().get_basename()
	return "未知歌曲"

func _format_subtitle(track: TrackData) -> String:
	var parts: Array[String] = []
	var subtitle := track.subtitle.strip_edges()
	var artist := track.artist.strip_edges()
	var source := track.source.strip_edges()
	if not artist.is_empty():
		parts.append(artist)
	elif not subtitle.is_empty():
		parts.append(subtitle)
	if not source.is_empty():
		parts.append(source)
	return " - ".join(PackedStringArray(parts))
