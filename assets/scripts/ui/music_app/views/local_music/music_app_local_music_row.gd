class_name MusicAppLocalMusicRow
extends Panel

signal play_requested(index: int)

var _is_bound := false
var _slot_index := -1

var _index_label: Label
var _title_label: Label
var _subtitle_label: Label
var _source_label: Label
var _open_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_index_label = $Margin/Row/IndexLabel
	_title_label = $Margin/Row/Info/TitleLabel
	_subtitle_label = $Margin/Row/Info/SubtitleLabel
	_source_label = $Margin/Row/SourceChip/Margin/SourceLabel
	_open_button = $OpenButton

	_open_button.pressed.connect(_on_open_pressed)

func configure(slot_index: int, track: TrackData) -> void:
	setup()
	_slot_index = slot_index
	_index_label.text = str(slot_index + 1)
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
	if _slot_index < 0:
		return
	play_requested.emit(_slot_index)
