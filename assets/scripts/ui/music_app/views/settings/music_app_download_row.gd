class_name MusicAppDownloadRow
extends PanelContainer

## 下载列表行：标题 + 格式/大小/创作者/下载时间 + 删除。

signal delete_pressed(track_id: String)

@onready var title_label: Label = %TitleLabel
@onready var meta_label: Label = %MetaLabel
@onready var delete_button: Button = %DeleteButton

var _track_id := ""

## UP 主常在视频标题前加「001.」「01、」这类序号，展示时剥掉，便于阅读与比对。
static var _order_prefix_regex: RegEx = RegEx.create_from_string("^\\s*\\d{1,3}\\s*[.、．]\\s*")

func _ready() -> void:
	delete_button.pressed.connect(_on_delete_pressed)
	MusicAppIcons.apply_icon_button(delete_button, MusicAppIcons.TRASH)

func configure(record: MusicDownloadRecordData) -> void:
	_track_id = record.track_id if record != null else ""
	title_label.text = _format_title(record)
	meta_label.text = _format_meta(record)

func _format_title(record: MusicDownloadRecordData) -> String:
	if record == null:
		return ""
	var title := record.title.strip_edges()
	if title.is_empty():
		title = record.get_file_name()
	return strip_order_prefix(title)

## 去掉「001.」「01、」这类标题序号前缀；留空时保留原值。清理只用于展示，不改存档。
static func strip_order_prefix(value: String) -> String:
	if _order_prefix_regex == null:
		return value
	var match_result := _order_prefix_regex.search(value)
	if match_result == null or match_result.get_start() != 0:
		return value
	var stripped := value.substr(match_result.get_end()).strip_edges()
	return stripped if not stripped.is_empty() else value

func _format_meta(record: MusicDownloadRecordData) -> String:
	if record == null:
		return ""
	var parts: Array[String] = []
	var format := record.format.strip_edges().to_upper()
	parts.append(format if not format.is_empty() else "音频")
	parts.append(record.get_size_text())
	var creator := record.artist.strip_edges()
	if not creator.is_empty():
		parts.append("%s %s" % [_get_creator_label(record), creator])
	var created_at := _format_time(record.created_at)
	parts.append("下载于 %s" % created_at if not created_at.is_empty() else "下载时间未知")
	return " · ".join(parts)

## B 站搜索把视频 UP 主放在 artist 位，展示时标为「UP主」而不是「艺人」。
func _get_creator_label(record: MusicDownloadRecordData) -> String:
	return "UP主" if record.plugin_id.strip_edges() == "bilibili" else "艺人"

func _format_time(value: String) -> String:
	var text := value.strip_edges().replace("T", " ")
	return text.substr(0, 16) if text.length() >= 16 else text

func _on_delete_pressed() -> void:
	delete_pressed.emit(_track_id)
