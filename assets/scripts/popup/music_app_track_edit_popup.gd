class_name MusicAppTrackEditPopup
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

## 编辑当前播放曲目的歌名 / 创作者，用于修正 UP 主被当成艺人、标题带序号等情况。

const TrackEditControllerScript := preload(
	"res://assets/scripts/ui/music_app/controllers/music_app_track_edit_controller.gd"
)

@onready var title_input: LineEdit = %TrackEditTitleInput
@onready var artist_input: LineEdit = %TrackEditArtistInput
@onready var cancel_button: Button = %TrackEditCancelButton
@onready var save_button: Button = %TrackEditSaveButton
@onready var hint_label: Label = %TrackEditHintLabel

var _controller
var _edit_controller
var _is_bound := false

func setup(controller) -> void:
	_controller = controller
	_edit_controller = TrackEditControllerScript.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	cancel_button.pressed.connect(close_popup)
	save_button.pressed.connect(_on_save_pressed)
	title_input.text_submitted.connect(_on_title_submitted)
	artist_input.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())

func on_popup_shown() -> void:
	refresh()

func refresh() -> void:
	if _edit_controller == null:
		return

	var track: TrackData = _edit_controller.get_target_track()
	if track == null:
		title_input.text = ""
		artist_input.text = ""
		title_input.editable = false
		artist_input.editable = false
		save_button.disabled = true
		hint_label.text = "当前没有播放中的曲目。"
		return

	title_input.editable = true
	artist_input.editable = true
	save_button.disabled = false
	title_input.text = track.title
	artist_input.text = track.artist
	hint_label.text = _edit_controller.get_hint_text(track)
	title_input.caret_column = title_input.text.length()

func _on_title_submitted(_text: String) -> void:
	artist_input.grab_focus()
	artist_input.caret_column = artist_input.text.length()

func _on_save_pressed() -> void:
	if _edit_controller == null:
		return

	var result: Dictionary = _edit_controller.save_track_info(title_input.text, artist_input.text)
	if not bool(result.get("ok", false)):
		_edit_controller.show_toast(str(result.get("error", "保存失败。")))
		return

	_edit_controller.show_toast("已更新曲目信息")
	close_popup()
