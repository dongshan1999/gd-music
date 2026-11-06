class_name MusicAppHistoryRow
extends Panel

## 播放历史列表行：只负责渲染，标题/副标题/右侧信息都由页面控制器格式化好再传进来。
## 这样排序口径（次数、相对时间）全部留在控制器里，行节点不持有业务状态。

signal play_requested(index: int)

var _is_bound := false
var _slot_index := -1

var _index_label: Label
var _title_label: Label
var _subtitle_label: Label
var _side_chip: Panel
var _side_label: Label
var _open_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_index_label = $Margin/Row/IndexLabel
	_title_label = $Margin/Row/Info/TitleLabel
	_subtitle_label = $Margin/Row/Info/SubtitleLabel
	_side_chip = $Margin/Row/SideChip
	_side_label = $Margin/Row/SideChip/Margin/SideLabel
	_open_button = $OpenButton

	_open_button.pressed.connect(_on_open_pressed)

func configure(slot_index: int, title: String, subtitle: String, side_text: String) -> void:
	setup()
	_slot_index = slot_index
	_index_label.text = str(slot_index + 1)
	_title_label.text = title
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()
	_side_chip.visible = not side_text.is_empty()
	_side_label.text = side_text

func _on_open_pressed() -> void:
	if _slot_index < 0:
		return
	play_requested.emit(_slot_index)
