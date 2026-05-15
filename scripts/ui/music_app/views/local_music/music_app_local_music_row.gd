class_name MusicAppLocalMusicRow
extends Panel

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

signal play_requested(index: int)
signal more_requested(index: int)

var _is_bound := false
var _track_index := -1

var _index_label: Label
var _title_label: Label
var _subtitle_label: Label
var _source_label: Label
var _more_button: Button
var _open_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_index_label = $Margin/Row/IndexLabel
	_title_label = $Margin/Row/Info/TitleLabel
	_subtitle_label = $Margin/Row/Info/SubtitleLabel
	_source_label = $Margin/Row/SourceChip/Margin/SourceLabel
	_more_button = $Margin/Row/MoreButton
	_open_button = $OpenButton

	_more_button.pressed.connect(_on_more_pressed)
	_open_button.pressed.connect(_on_open_pressed)

func configure(track_index: int, track: TrackData) -> void:
	setup()
	_track_index = track_index
	_index_label.text = str(track_index + 1)
	_title_label.text = track.title if not track.title.is_empty() else track.file_path.get_file().get_basename()
	_subtitle_label.text = _build_subtitle(track)
	_source_label.text = track.source if not track.source.is_empty() else "LOCAL"

func _build_subtitle(track: TrackData) -> String:
	var subtitle := track.artist
	if not track.subtitle.is_empty() and track.subtitle != track.artist:
		subtitle = "%s - %s" % [subtitle, track.subtitle] if not subtitle.is_empty() else track.subtitle
	if subtitle.is_empty():
		subtitle = tr("music_app.track.local_file")
	return subtitle

func _on_open_pressed() -> void:
	if _track_index < 0:
		return
	play_requested.emit(_track_index)

func _on_more_pressed() -> void:
	if _track_index < 0:
		return
	more_requested.emit(_track_index)
