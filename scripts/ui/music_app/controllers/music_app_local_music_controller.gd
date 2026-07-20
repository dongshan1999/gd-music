class_name MusicAppLocalMusicController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const DEBUG_TAG := "MusicLocalImport"

var _is_native_import_open := false

## 返回已保存的本地扫描文件夹列表。
func get_local_folder_paths() -> Array[String]:
	var result: Array[String] = []
	for path in get_app_state().local_music_folders:
		result.append(_normalize_local_path(path))
	return result

## 返回文件夹在本地音乐页上的短名称。
func get_folder_display_name(path: String) -> String:
	var normalized_path := _normalize_local_path(path)
	if normalized_path.is_empty():
		return tr("music_app.local.folder_unknown")
	var folder_name := _display_name_from_path(normalized_path)
	if folder_name.is_empty():
		return normalized_path
	return folder_name

## 返回全部本地曲目的 ID 列表。
func get_local_track_ids() -> Array[String]:
	var result: Array[String] = []
	var tracks: Array[TrackData] = get_tracks_ref()
	for track in tracks:
		if track == null:
			continue
		if not track.file_path.is_empty() or track.source == "LOCAL":
			result.append(track.id)
	return result

## 根据曲目 ID 返回对应曲目对象。
func get_track(track_id: String):
	return get_track_by_id(track_id)

## 以本地音乐页当前可见顺序构建播放队列并打开播放器。
func play_local_track_list(track_ids: Array[String], slot_index: int) -> bool:
	if not _play_track_list(track_ids, slot_index, true):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true

## 通过 DX 文件系统选择目录并导入本地音乐。
func open_native_import(finished_callback: Callable = Callable()) -> void:
	if _is_native_import_open:
		_debug_import("skip native import because picker is already open")
		return

	_is_native_import_open = true
	var start_directory := _get_native_import_start_directory()
	_debug_import("open DX directory picker", {
		"start_directory": start_directory,
		"os": OS.get_name(),
		"native_dialog": DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	})
	var picker_result: Dictionary = DX.files.pick_directory(
		tr("music_app.scan.select_folder_title"),
		Callable(self, "_on_native_import_directory_picked").bind(finished_callback),
		start_directory
	)
	_debug_import("DX directory picker open result", picker_result)
	if not bool(picker_result.get("ok", false)):
		_is_native_import_open = false
		var error_message := str(picker_result.get("error", ""))
		if not error_message.is_empty():
			show_common_alert(tr("music_app.scan.select_folder_title"), error_message)
		_notify_native_import_finished(finished_callback)

## 打开内置本地扫描页。
func open_scan_page(finished_callback: Callable = Callable()) -> void:
	var popup = show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_LOCAL_SCAN)
	if popup == null:
		_debug_import("failed to open built-in scan page")
		_notify_native_import_finished(finished_callback)
		return
	_debug_import("built-in scan page opened")
	if popup.has_method("set_finished_callback"):
		popup.call("set_finished_callback", finished_callback)

## 打开插件音乐浏览页。
func open_plugin_browser() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLUGIN_BROWSER)

## 删除一个本地扫描文件夹，并移除该文件夹下已导入的本地曲目。
func remove_local_folder(path: String) -> void:
	var normalized_path := _normalize_local_path(path)
	if normalized_path.is_empty():
		_debug_import("skip removing empty local folder", path)
		return

	_debug_import("remove local folder", normalized_path)
	var next_folders: Array[String] = []
	for folder_path in get_local_folder_paths():
		if folder_path == normalized_path:
			continue
		next_folders.append(folder_path)
	get_app_state().local_music_folders = next_folders
	_remove_local_tracks_under_paths([normalized_path])
	_rescan_saved_local_folders()
	_save_music_state()
	_debug_import("local folder removed", {
		"folders": get_local_folder_paths(),
		"track_count": get_local_track_ids().size()
	})

## 用指定曲目顺序替换播放队列，并切到目标槽位播放。
func _play_track_list(track_ids: Array[String], start_slot_index: int, autoplay: bool = true) -> bool:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_ids, start_slot_index):
		return false
	return playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), autoplay)

func _on_native_import_directory_picked(result: Dictionary, finished_callback: Callable) -> void:
	_is_native_import_open = false
	_debug_import("native directory picker callback", result)
	if bool(result.get("cancelled", false)):
		_debug_import("native directory picker cancelled")
		_notify_native_import_finished(finished_callback)
		return
	if not bool(result.get("ok", false)):
		var error_message := str(result.get("error", ""))
		_debug_import("native directory picker returned error", error_message)
		if not error_message.is_empty():
			show_common_alert(tr("music_app.scan.select_folder_title"), error_message)
		_notify_native_import_finished(finished_callback)
		return

	var target_paths := _get_native_import_target_paths(result)
	_debug_import("native import target paths", target_paths)
	if target_paths.is_empty():
		_debug_import("native import has no valid target paths")
		show_common_alert(
			tr("music_app.scan.not_found_title"),
			tr("music_app.scan.not_found_message")
		)
		_notify_native_import_finished(finished_callback)
		return

	var imported_count := import_local_folders(target_paths)
	_debug_import("native import finished scanning", {
		"target_paths": target_paths,
		"imported_count": imported_count,
		"saved_folders": get_local_folder_paths(),
		"local_track_count": get_local_track_ids().size()
	})
	if imported_count <= 0:
		show_common_alert(
			tr("music_app.scan.not_found_title"),
			tr("music_app.scan.not_found_message")
		)
		_notify_native_import_finished(finished_callback)
		return

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

	_debug_import("native import raw paths", raw_paths)
	for raw_path in raw_paths:
		var target_path := _to_dx_scan_path(str(raw_path))
		_debug_import("native import path converted", {
			"raw": raw_path,
			"target": target_path,
			"exists": not target_path.is_empty()
		})
		if target_path.is_empty() or unique_paths.has(target_path):
			continue
		unique_paths[target_path] = true
		target_paths.append(target_path)
	return target_paths

func _to_dx_scan_path(path: String) -> String:
	var raw_path := str(path).strip_edges().replace("\\", "/")
	var dx_path: String = DX.files.to_virtual_path(raw_path)
	dx_path = _normalize_local_path(dx_path)
	if dx_path.is_empty() or not DX.files.exists(dx_path):
		_debug_import("DX scan path does not exist", {
			"raw": raw_path,
			"converted": dx_path
		})
		return ""
	return dx_path

func _to_native_scan_path(path: String) -> String:
	var native_path := str(path).strip_edges().replace("\\", "/")
	var original_path := native_path
	if native_path.begins_with("file://"):
		native_path = _file_uri_to_native_path(native_path)
	else:
		native_path = DX.files.globalize(native_path)
	native_path = native_path.strip_edges().replace("\\", "/")
	if not DirAccess.dir_exists_absolute(native_path):
		_debug_import("native scan path does not exist", {
			"raw": original_path,
			"converted": native_path
		})
		return ""
	return native_path

func _file_uri_to_native_path(uri: String) -> String:
	var path := uri.strip_edges().replace("\\", "/").trim_prefix("file://").uri_decode()
	if path.begins_with("localhost/"):
		path = path.substr("localhost".length())
	if path.length() >= 3 and path.begins_with("/") and path.substr(2, 1) == ":":
		path = path.substr(1)
	return path

func _get_native_import_start_directory() -> String:
	var documents_path := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not documents_path.is_empty():
		return documents_path
	return ProjectSettings.globalize_path("user://")

func _notify_native_import_finished(finished_callback: Callable) -> void:
	_debug_import("notify import finished", {"has_callback": finished_callback.is_valid()})
	if finished_callback.is_valid():
		finished_callback.call()

## 保存扫描目录，只扫描本次选择的目录，并返回真正新增的曲目数量。
func import_local_folders(paths: Array[String]) -> int:
	_debug_import("import local folders requested", paths)
	var next_folders := get_local_folder_paths()
	var scan_targets: Array[String] = []
	for raw_path in paths:
		var normalized_path := _normalize_local_path(raw_path)
		if normalized_path.is_empty() or scan_targets.has(normalized_path):
			_debug_import("skip local folder path", {
				"raw": raw_path,
				"normalized": normalized_path,
				"already_selected": scan_targets.has(normalized_path)
			})
			continue
		scan_targets.append(normalized_path)
		if not next_folders.has(normalized_path):
			next_folders.append(normalized_path)
	get_app_state().local_music_folders = next_folders
	_debug_import("saved local folders before selected scan", {
		"folders": next_folders,
		"scan_targets": scan_targets
	})
	var scan_controller := MusicAppLocalScanController.new(controller)
	var imported_count := scan_controller.scan_local_music_directories(scan_targets)
	get_app_state().normalize()
	_save_music_state()
	_debug_import("import local folders completed", {
		"imported_count": imported_count,
		"saved_folders": get_local_folder_paths(),
		"local_track_count": get_local_track_ids().size()
	})
	return imported_count

func _rescan_saved_local_folders() -> int:
	var folder_paths := get_local_folder_paths()
	if folder_paths.is_empty():
		_debug_import("rescan skipped because no saved local folders")
		return 0
	var before_count := get_tracks_ref().size()
	_debug_import("rescan saved local folders start", {
		"folders": folder_paths,
		"track_count_before": before_count
	})
	_remove_local_tracks_under_paths(folder_paths)
	var after_remove_count := get_tracks_ref().size()
	var scan_controller := MusicAppLocalScanController.new(controller)
	var imported_count := scan_controller.scan_local_music_directories(folder_paths)
	get_app_state().normalize()
	_debug_import("rescan saved local folders end", {
		"track_count_before": before_count,
		"track_count_after_remove": after_remove_count,
		"imported_count": imported_count,
		"track_count_after": get_tracks_ref().size()
	})
	return imported_count

func _remove_local_tracks_under_paths(folder_paths: Array[String]) -> void:
	var normalized_folders: Array[String] = []
	for folder_path in folder_paths:
		var normalized_path := _normalize_local_path(folder_path)
		if normalized_path.is_empty():
			continue
		normalized_folders.append(normalized_path)

	var tracks: Array[TrackData] = get_tracks_ref()
	var removed_count := 0
	var index := tracks.size() - 1
	while index >= 0:
		var track: TrackData = tracks[index]
		if track != null and _is_track_under_any_folder(track, normalized_folders):
			tracks.remove_at(index)
			removed_count += 1
		index -= 1
	get_app_state().normalize()
	_debug_import("removed local tracks under folders", {
		"folders": normalized_folders,
		"removed_count": removed_count
	})

func _is_track_under_any_folder(track: TrackData, folder_paths: Array[String]) -> bool:
	if track.file_path.is_empty():
		return false
	var track_path := _normalize_local_path(track.file_path)
	for folder_path in folder_paths:
		if track_path == folder_path or track_path.begins_with("%s/" % folder_path):
			return true
		if track_path.begins_with("%s#" % folder_path):
			return true
	return false

func _normalize_local_path(path: String) -> String:
	var normalized_path := str(path).strip_edges().replace("\\", "/")
	if DX != null and DX.files != null:
		normalized_path = str(DX.files.to_virtual_path(normalized_path))
	if normalized_path.ends_with("/") and normalized_path.length() > 1 and not normalized_path.ends_with(":/"):
		normalized_path = normalized_path.left(normalized_path.length() - 1)
	return normalized_path

func _display_name_from_path(path: String) -> String:
	var candidate := str(path).strip_edges().replace("\\", "/").uri_decode()
	var fragment_index := candidate.find("#")
	if fragment_index >= 0:
		candidate = candidate.substr(fragment_index + 1)
	var display_name := candidate.get_file()
	var colon_index := display_name.rfind(":")
	if colon_index >= 0 and colon_index < display_name.length() - 1:
		display_name = display_name.substr(colon_index + 1)
	return display_name.strip_edges()

func _save_music_state() -> void:
	var save_manager := get_save_manager()
	if save_manager != null:
		save_manager.save(false)
		_debug_import("music state marked dirty for save")

func _debug_import(message: String, payload: Variant = null) -> void:
	var text := message if payload == null else "%s | %s" % [message, str(payload)]
	if DX != null and DX.logger != null:
		DX.logger.log(DEBUG_TAG, text)
	else:
		print("[%s] %s" % [DEBUG_TAG, text])
