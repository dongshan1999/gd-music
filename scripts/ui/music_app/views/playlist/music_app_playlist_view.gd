class_name MusicAppPlaylistView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const PLAYLIST_SONG_ROW_SCENE := preload(MusicAppScriptPathsType.PLAYLIST_SONG_ROW)

const MODE_NORMAL := MusicAppPlaylistSongRow.MODE_NORMAL
const MODE_SORT := MusicAppPlaylistSongRow.MODE_SORT
const MODE_DELETE := MusicAppPlaylistSongRow.MODE_DELETE

var _controller: MusicAppShowcaseController
var _playlist_controller: MusicAppPlaylistController
var _is_bound := false
var _management_mode := MODE_NORMAL
var _selected_slots := {}
var _visible_track_ids: Array[String] = []
var _dragging_slot_index := -1

@onready var playlist_back_button: Button = %PlaylistBackButton
@onready var playlist_search_button: Button = %PlaylistSearchButton
@onready var playlist_more_button: Button = %PlaylistMoreButton
@onready var playlist_hero_mark_label: Label = %PlaylistHeroMarkLabel
@onready var playlist_hero_title_label: Label = %PlaylistHeroTitleLabel
@onready var playlist_hero_count_label: Label = %PlaylistHeroCountLabel
@onready var play_all_button: Button = %PlayAllButton
@onready var play_all_icon_rect: TextureRect = %PlayAllIconRect
@onready var play_all_label: Label = %PlayAllLabel
@onready var delete_selected_button: Button = %DeleteSelectedButton
@onready var playlist_scroll: ScrollContainer = %PlaylistScroll
@onready var playlist_empty_label: Label = %PlaylistEmptyLabel
@onready var playlist_more_menu_scrim: Button = %PlaylistMoreMenuScrim
@onready var playlist_more_menu_panel: Panel = %PlaylistMoreMenuPanel
@onready var sort_mode_button: Button = %SortModeButton
@onready var delete_mode_button: Button = %DeleteModeButton
@onready var song_list: VBoxContainer = $Margin/PlaylistVBox/PlaylistScroll/SongList
@onready var song_bottom_space: Control = $Margin/PlaylistVBox/PlaylistScroll/SongList/SongBottomSpace

var song_rows: Array[MusicAppPlaylistSongRow] = []

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_playlist_controller = MusicAppPlaylistController.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	playlist_back_button.pressed.connect(close_page)
	playlist_search_button.pressed.connect(_show_search_placeholder)
	playlist_more_button.pressed.connect(_toggle_more_menu)
	play_all_button.pressed.connect(_on_primary_action_pressed)
	delete_selected_button.pressed.connect(_delete_selected_slots)
	playlist_more_menu_scrim.pressed.connect(_hide_more_menu)
	sort_mode_button.pressed.connect(_enter_sort_mode)
	delete_mode_button.pressed.connect(_enter_delete_mode)

func refresh() -> void:
	if _controller == null:
		return

	if _playlist_controller.get_playlists().is_empty():
		_visible_track_ids = []
		playlist_hero_mark_label.text = tr("music_app.playlist.favorites_mark")
		playlist_hero_title_label.text = tr("music_app.playlist.favorites_title")
		playlist_hero_count_label.text = _playlist_controller.format_total_track_count(0)
		_sync_song_rows(0)
		_sync_empty_state(false)
		_set_management_mode(MODE_NORMAL)
		return

	var playlist: PlaylistData = _playlist_controller.get_selected_playlist()
	_visible_track_ids = _playlist_controller.get_selected_playlist_track_ids()

	_sync_song_rows(_visible_track_ids.size())
	_sync_empty_state(not _visible_track_ids.is_empty())
	if _visible_track_ids.is_empty():
		_set_management_mode(MODE_NORMAL)
	playlist_hero_title_label.text = _playlist_controller.get_playlist_display_title(playlist)
	playlist_hero_count_label.text = _playlist_controller.format_total_track_count(playlist.count)
	playlist_hero_mark_label.text = _playlist_controller.get_playlist_display_mark(playlist)

	for index in song_rows.size():
		var track_id: String = _visible_track_ids[index]
		var track: TrackData = _playlist_controller.get_track(track_id)
		song_rows[index].configure(index, track)
		song_rows[index].set_management_mode(_management_mode, _is_slot_selected(index))

	_prune_selected_slots()
	_update_action_buttons()

func close_page() -> void:
	_hide_more_menu()
	close_popup()

func _on_primary_action_pressed() -> void:
	if _management_mode == MODE_SORT:
		_set_management_mode(MODE_NORMAL)
		return
	if _management_mode == MODE_DELETE:
		_toggle_select_all()
		return
	if not _playlist_controller.play_selected_playlist_from_start():
		_playlist_controller.show_empty_playlist_placeholder()

func _select_song_from_playlist(slot_index: int) -> void:
	if _management_mode != MODE_NORMAL:
		return
	_playlist_controller.play_selected_playlist_track(slot_index)

func _show_search_placeholder() -> void:
	_playlist_controller.show_search_placeholder()

func _sync_empty_state(has_tracks: bool) -> void:
	playlist_scroll.visible = has_tracks
	playlist_empty_label.visible = not has_tracks
	playlist_empty_label.text = "这个歌单里还没有歌曲"

func _sync_song_rows(target_size: int) -> void:
	while song_rows.size() < target_size:
		var row := PLAYLIST_SONG_ROW_SCENE.instantiate() as MusicAppPlaylistSongRow
		song_list.add_child(row)
		song_list.move_child(row, song_bottom_space.get_index())
		row.play_requested.connect(_select_song_from_playlist)
		row.selection_toggled.connect(_toggle_slot_selection)
		row.delete_requested.connect(_delete_single_slot)
		row.sort_drag_started.connect(_begin_sort_drag)
		row.sort_drag_moved.connect(_move_sort_drag)
		row.sort_drag_ended.connect(_finish_sort_drag)
		song_rows.append(row)

	while song_rows.size() > target_size:
		var row: MusicAppPlaylistSongRow = song_rows.pop_back()
		row.queue_free()

func _toggle_more_menu() -> void:
	if playlist_more_menu_panel.visible:
		_hide_more_menu()
		return
	playlist_more_menu_panel.visible = true
	playlist_more_menu_scrim.visible = true

func _hide_more_menu() -> void:
	playlist_more_menu_panel.visible = false
	playlist_more_menu_scrim.visible = false

func _enter_sort_mode() -> void:
	_hide_more_menu()
	if _visible_track_ids.is_empty():
		_playlist_controller.show_sort_empty_placeholder()
		return
	_set_management_mode(MODE_SORT)

func _enter_delete_mode() -> void:
	_hide_more_menu()
	if _visible_track_ids.is_empty():
		_playlist_controller.show_delete_empty_placeholder()
		return
	_set_management_mode(MODE_DELETE)

func _set_management_mode(mode: int) -> void:
	if _management_mode == mode and mode != MODE_DELETE:
		return
	_management_mode = mode
	_dragging_slot_index = -1
	if mode != MODE_DELETE:
		_selected_slots.clear()
	_refresh_row_modes()
	_update_action_buttons()

func _refresh_row_modes() -> void:
	for index in song_rows.size():
		song_rows[index].set_management_mode(_management_mode, _is_slot_selected(index))

func _update_action_buttons() -> void:
	delete_selected_button.visible = _management_mode == MODE_DELETE
	play_all_icon_rect.visible = _management_mode == MODE_NORMAL
	if _management_mode == MODE_SORT:
		play_all_label.text = "完成排序"
	elif _management_mode == MODE_DELETE:
		play_all_label.text = "取消全选" if _is_all_selected() else "全选"
		var selected_count := _selected_slots.size()
		delete_selected_button.text = "删除选择" if selected_count == 0 else "删除选择 %d" % selected_count
	else:
		play_all_label.text = tr("music_app.playlist.play_all")
		delete_selected_button.text = "删除选择"

func _toggle_slot_selection(slot_index: int) -> void:
	if _management_mode != MODE_DELETE:
		return
	if _is_slot_selected(slot_index):
		_selected_slots.erase(slot_index)
	else:
		_selected_slots[slot_index] = true
	_refresh_row_modes()
	_update_action_buttons()

func _toggle_select_all() -> void:
	if _visible_track_ids.is_empty():
		return
	if _is_all_selected():
		_selected_slots.clear()
	else:
		_selected_slots.clear()
		for index in _visible_track_ids.size():
			_selected_slots[index] = true
	_refresh_row_modes()
	_update_action_buttons()

func _delete_single_slot(slot_index: int) -> void:
	if _management_mode != MODE_DELETE:
		return
	if _playlist_controller.delete_selected_playlist_track(slot_index):
		_selected_slots.clear()
		refresh()

func _delete_selected_slots() -> void:
	if _management_mode != MODE_DELETE:
		return
	if _selected_slots.is_empty():
		_playlist_controller.show_delete_selection_empty_placeholder()
		return
	if _playlist_controller.delete_selected_playlist_tracks(_selected_slots.keys()) > 0:
		_selected_slots.clear()
		refresh()

func _begin_sort_drag(slot_index: int) -> void:
	if _management_mode != MODE_SORT:
		return
	_dragging_slot_index = slot_index

func _move_sort_drag(pointer_position: Vector2) -> void:
	if _management_mode != MODE_SORT or _dragging_slot_index < 0:
		return
	var target_slot := _find_sort_target_slot(pointer_position.y)
	if target_slot == _dragging_slot_index:
		return
	if _playlist_controller.move_selected_playlist_track(_dragging_slot_index, target_slot):
		_dragging_slot_index = target_slot
		refresh()

func _finish_sort_drag(_slot_index: int) -> void:
	_dragging_slot_index = -1

func _find_sort_target_slot(global_y: float) -> int:
	if song_rows.is_empty():
		return 0
	for index in song_rows.size():
		var row_rect := song_rows[index].get_global_rect()
		if global_y < row_rect.position.y + row_rect.size.y * 0.5:
			return index
	return song_rows.size() - 1

func _is_slot_selected(slot_index: int) -> bool:
	return bool(_selected_slots.get(slot_index, false))

func _is_all_selected() -> bool:
	return not _visible_track_ids.is_empty() and _selected_slots.size() == _visible_track_ids.size()

func _prune_selected_slots() -> void:
	for slot_index in _selected_slots.keys():
		if int(slot_index) < 0 or int(slot_index) >= _visible_track_ids.size():
			_selected_slots.erase(slot_index)
