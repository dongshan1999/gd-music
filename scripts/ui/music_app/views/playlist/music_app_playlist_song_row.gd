class_name MusicAppPlaylistSongRow
extends Panel

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")

signal play_requested(index: int)
signal more_requested(index: int)

var _is_bound := false
var _slot_index := -1

var _index_label: Label
var _title_label: Label
var _subtitle_label: Label
var _vip_label: Label
var _more_button: Button
var _play_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_index_label = $Margin/Row/SongIndexLabel
	_title_label = $Margin/Row/SongInfo/SongTitleLabel
	_subtitle_label = $Margin/Row/SongInfo/SongSubtitleLabel
	_vip_label = $Margin/Row/SongVipLabel
	_more_button = $Margin/Row/SongMoreButton
	_play_button = $SongButton

	_more_button.pressed.connect(_on_more_pressed)
	_play_button.pressed.connect(_on_play_pressed)

func configure(slot_index: int, track: TrackData) -> void:
	setup()
	_slot_index = slot_index
	_index_label.text = str(slot_index + 1)
	_title_label.text = track.title
	_subtitle_label.text = track.subtitle
	_vip_label.text = "[%s]" % track.source

func _on_play_pressed() -> void:
	if _slot_index < 0:
		return
	play_requested.emit(_slot_index)

func _on_more_pressed() -> void:
	if _slot_index < 0:
		return
	more_requested.emit(_slot_index)
