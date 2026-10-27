class_name MusicAppDownloadManagementView
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

## 下载管理页：展示下载目录、总占用与已下载列表。

const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const ManagementControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_DOWNLOAD_MANAGEMENT_CONTROLLER)
const DownloadRowScene := preload(MusicAppScriptPathsType.DOWNLOAD_ROW)

var _controller: MusicAppShowcaseController
var _management_controller
var _is_bound := false

@onready var back_button: Button = %DownloadManagementBackButton
@onready var path_label: Label = %DownloadPathLabel
@onready var summary_label: Label = %DownloadSummaryLabel
@onready var copy_path_button: Button = %CopyPathButton
@onready var open_directory_button: Button = %OpenDirectoryButton
@onready var list: VBoxContainer = %DownloadList
@onready var empty_label: Label = %DownloadEmptyLabel

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_management_controller = ManagementControllerScript.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true
	back_button.pressed.connect(close_popup)
	copy_path_button.pressed.connect(_on_copy_path_pressed)
	open_directory_button.pressed.connect(_on_open_directory_pressed)

func on_popup_shown() -> void:
	refresh()

func refresh() -> void:
	if path_label == null or summary_label == null or list == null:
		return
	var records: Array[MusicDownloadRecordData] = []
	if _management_controller != null:
		records = _management_controller.get_downloads()
		path_label.text = _management_controller.get_download_directory()
		summary_label.text = _management_controller.get_summary_text()
	else:
		path_label.text = ""
		summary_label.text = ""
	_sync_rows(records)

func _sync_rows(records: Array[MusicDownloadRecordData]) -> void:
	var wanted := {}
	for record in records:
		if record != null and not record.track_id.is_empty():
			wanted[record.track_id] = record

	# 先移除已不存在的曲目行。
	for child in list.get_children():
		if child == empty_label:
			continue
		var track_id := str(child.get_meta("track_id", ""))
		if not wanted.has(track_id):
			list.remove_child(child)
			child.queue_free()

	var ordered_rows: Array[Node] = []
	for track_id in wanted.keys():
		var row: Node = _find_row(track_id)
		if row == null:
			row = DownloadRowScene.instantiate()
			list.add_child(row)
			row.set_meta("track_id", track_id)
			row.delete_pressed.connect(_on_row_delete_pressed)
		row.configure(wanted[track_id])
		ordered_rows.append(row)

	for index in ordered_rows.size():
		list.move_child(ordered_rows[index], index)
	if empty_label != null:
		list.move_child(empty_label, list.get_child_count() - 1)
		empty_label.visible = records.is_empty()

func _find_row(track_id: String) -> Node:
	for child in list.get_children():
		if child == empty_label:
			continue
		if str(child.get_meta("track_id", "")) == track_id:
			return child
	return null

func _on_copy_path_pressed() -> void:
	if _management_controller != null:
		_management_controller.copy_download_directory()

func _on_open_directory_pressed() -> void:
	if _management_controller != null:
		_management_controller.open_download_directory()

func _on_row_delete_pressed(track_id: String) -> void:
	if _management_controller == null:
		return
	var result: Dictionary = _management_controller.remove_download(track_id)
	if bool(result.get("ok", false)):
		_management_controller.show_toast("已删除下载")
		refresh()
	else:
		_management_controller.show_toast(str(result.get("error", "删除失败")))
