class_name MusicAppLocalMusicController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

var _is_native_import_open := false

## 返回全部本地曲目在全量曲目数组中的索引列表。
func get_local_track_indices() -> Array[int]:
	var result: Array[int] = []
	var tracks: Array[TrackData] = get_tracks_ref()
	for index in tracks.size():
		var track = tracks[index]
		if track == null:
			continue
		if not track.file_path.is_empty() or track.source == "LOCAL":
			result.append(index)
	return result

## 根据全量曲目索引返回对应曲目对象。
func get_track(track_index: int):
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 以本地音乐页当前可见顺序构建播放队列并打开播放器。
func play_local_track_list(track_indices: Array[int], slot_index: int) -> bool:
	if not _play_track_list(track_indices, slot_index, true):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true

## 调用 DX 原生目录选择器导入本地音乐。
func open_native_import(finished_callback: Callable = Callable()) -> void:
	if _is_native_import_open:
		return

	_is_native_import_open = true
	var picker_result: Dictionary = DX.files.pick_directory(
		tr("music_app.scan.select_folder_title"),
		Callable(self, "_on_native_import_directory_picked").bind(finished_callback),
		_get_native_import_start_directory()
	)
	if not bool(picker_result.get("ok", false)):
		_is_native_import_open = false
		var error_message := str(picker_result.get("error", ""))
		if not error_message.is_empty():
			show_common_alert(tr("music_app.scan.select_folder_title"), error_message)
		_notify_native_import_finished(finished_callback)

## 打开插件音乐浏览页。
func open_plugin_browser() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLUGIN_BROWSER)

## 弹出编辑功能占位提示。
func show_edit_placeholder() -> void:
	show_common_alert(
		tr("music_app.local.edit_title"),
		tr("music_app.local.edit_message")
	)

## 弹出下载列表功能占位提示。
func show_download_placeholder() -> void:
	show_common_alert(
		tr("music_app.local.download_title"),
		tr("music_app.local.download_message")
	)

## 用指定曲目顺序替换播放队列，并切到目标槽位播放。
func _play_track_list(track_indices: Array[int], start_slot_index: int, autoplay: bool = true) -> bool:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_indices, start_slot_index):
		return false
	return playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), autoplay)

func _on_native_import_directory_picked(result: Dictionary, finished_callback: Callable) -> void:
	_is_native_import_open = false
	if bool(result.get("cancelled", false)):
		_notify_native_import_finished(finished_callback)
		return
	if not bool(result.get("ok", false)):
		var error_message := str(result.get("error", ""))
		if not error_message.is_empty():
			show_common_alert(tr("music_app.scan.select_folder_title"), error_message)
		_notify_native_import_finished(finished_callback)
		return

	var target_paths := _get_native_import_target_paths(result)
	if target_paths.is_empty():
		show_common_alert(
			tr("music_app.scan.not_found_title"),
			tr("music_app.scan.not_found_message")
		)
		_notify_native_import_finished(finished_callback)
		return

	var scan_controller := MusicAppLocalScanController.new(controller)
	var imported_count := scan_controller.scan_local_music_directories(target_paths)
	if imported_count <= 0:
		show_common_alert(
			tr("music_app.scan.not_found_title"),
			tr("music_app.scan.not_found_message")
		)
		_notify_native_import_finished(finished_callback)
		return

	get_save_manager().save(false)
	show_common_alert(
		tr("music_app.scan.complete_title"),
		tr("music_app.scan.complete_message").format({"count": imported_count})
	)
	_notify_native_import_finished(finished_callback)

func _get_native_import_target_paths(result: Dictionary) -> Array[String]:
	var target_paths: Array[String] = []
	var unique_paths := {}
	var raw_paths: Array[String] = []
	var selected_paths = result.get("paths", PackedStringArray())
	if selected_paths is PackedStringArray or selected_paths is Array:
		for selected_path in selected_paths:
			raw_paths.append(str(selected_path))
	var primary_path := str(result.get("path", ""))
	if raw_paths.is_empty() and not primary_path.is_empty():
		raw_paths.append(primary_path)

	for raw_path in raw_paths:
		var target_path := _to_native_scan_path(str(raw_path))
		if target_path.is_empty() or unique_paths.has(target_path):
			continue
		unique_paths[target_path] = true
		target_paths.append(target_path)
	return target_paths

func _to_native_scan_path(path: String) -> String:
	var native_path: String = DX.files.globalize(path)
	native_path = native_path.strip_edges().replace("\\", "/")
	if not DirAccess.dir_exists_absolute(native_path):
		return ""
	return native_path

func _get_native_import_start_directory() -> String:
	var documents_path := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not documents_path.is_empty():
		return documents_path
	return ProjectSettings.globalize_path("user://")

func _notify_native_import_finished(finished_callback: Callable) -> void:
	if finished_callback.is_valid():
		finished_callback.call()
