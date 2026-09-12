class_name MusicAppHomePlaylistRow
extends Panel

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

signal open_requested(index: int)
signal delete_requested(index: int)

var _is_bound := false
var _playlist_index := -1

var _cover_icon_rect: TextureRect
var _title_label: Label
var _count_label: Label
var _delete_button: Button
var _open_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_cover_icon_rect = $Margin/Row/CoverSlot/CoverPanel/CoverIconRect
	_title_label = $Margin/Row/Info/TitleLabel
	_count_label = $Margin/Row/Info/CountLabel
	_delete_button = $Margin/Row/DeleteButton
	_open_button = $OpenButton

	_open_button.pressed.connect(_on_open_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)

func configure(index: int, display_mark: String, display_title: String, count: int, deletable: bool) -> void:
	setup()
	_playlist_index = index
	_cover_icon_rect.texture = (
		MusicAppIconsType.HEART_FILLED
		if display_mark == tr("music_app.playlist.favorites_mark")
		else MusicAppIconsType.MUSICAL_NOTE
	)
	_title_label.text = display_title
	_count_label.text = tr("music_app.common.song_count").format({"count": count})
	MusicAppIconsType.apply_icon_button(_delete_button, MusicAppIconsType.TRASH, false, false)
	_delete_button.visible = deletable
	# Favorites have no trailing action: highlight their entire clickable row.
	_open_button.offset_right = -56.0 if deletable else 0.0

func _on_open_pressed() -> void:
	if _playlist_index < 0:
		return
	open_requested.emit(_playlist_index)

func _on_delete_pressed() -> void:
	if _playlist_index < 0:
		return
	delete_requested.emit(_playlist_index)
