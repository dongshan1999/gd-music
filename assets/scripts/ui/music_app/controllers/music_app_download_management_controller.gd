class_name MusicAppDownloadManagementController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 下载管理页控制器：只做数据聚合与系统动作（复制路径、打开目录、打开链接、删除）。

var last_error := ""

func get_downloads() -> Array[MusicDownloadRecordData]:
	var downloads = get_download_controller()
	if downloads == null:
		last_error = "下载控制器不可用。"
		return []
	last_error = ""
	return downloads.get_records()

func has_downloads() -> bool:
	return not get_downloads().is_empty()

func get_total_bytes() -> int:
	var downloads = get_download_controller()
	if downloads == null:
		return 0
	return downloads.get_total_bytes()

func get_download_directory() -> String:
	var downloads = get_download_controller()
	if downloads == null:
		return ""
	return downloads.get_download_directory()

func get_summary_text() -> String:
	var downloads = get_download_controller()
	if downloads == null:
		return ""
	var count: int = downloads.get_records().size()
	var total_bytes: int = downloads.get_total_bytes()
	return "共 %d 首 / 占用 %s" % [count, _format_bytes(total_bytes)]

func copy_download_directory() -> void:
	var directory := get_download_directory()
	if directory.is_empty():
		last_error = "下载目录不可用。"
		return
	DisplayServer.clipboard_set(directory)
	show_toast("已复制下载目录路径")

func open_download_directory() -> void:
	var directory := get_download_directory()
	if directory.is_empty():
		last_error = "下载目录不可用。"
		return
	var result: Dictionary = DX.files.open_path(directory)
	if not bool(result.get("ok", false)):
		last_error = str(result.get("error", "无法打开下载目录。"))
		show_toast(last_error)

func remove_download(track_id: String) -> Dictionary:
	var downloads = get_download_controller()
	if downloads == null:
		last_error = "下载控制器不可用。"
		return {"ok": false, "error": last_error}
	var result: Dictionary = downloads.remove_download(track_id)
	last_error = str(result.get("error", ""))
	return result

static func _format_bytes(bytes: int) -> String:
	if bytes <= 0:
		return "0 B"
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
