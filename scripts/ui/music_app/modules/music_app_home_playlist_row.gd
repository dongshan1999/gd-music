class_name MusicAppHomePlaylistRow
extends Panel

signal open_requested(index: int)
signal delete_requested(index: int)

var _is_bound := false
var _playlist_index := -1

var _mark_label: Label
var _title_label: Label
var _count_label: Label
var _delete_button: Button
var _open_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_mark_label = $Margin/Row/CoverPanel/MarkLabel
	_title_label = $Margin/Row/Info/TitleLabel
	_count_label = $Margin/Row/Info/CountLabel
	_delete_button = $Margin/Row/DeleteButton
	_open_button = $OpenButton

	_open_button.pressed.connect(_on_open_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)

func configure(index: int, display_mark: String, display_title: String, count: int, deletable: bool) -> void:
	setup()
	_playlist_index = index
	_mark_label.text = display_mark
	_title_label.text = display_title
	_count_label.text = tr("music_app.common.song_count").format({"count": count})
	_delete_button.text = tr("music_app.action.delete_short")
	_delete_button.visible = deletable

func _on_open_pressed() -> void:
	if _playlist_index < 0:
		return
	open_requested.emit(_playlist_index)

func _on_delete_pressed() -> void:
	if _playlist_index < 0:
		return
	delete_requested.emit(_playlist_index)
