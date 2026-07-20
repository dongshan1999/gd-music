class_name MusicAppLocalScanController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const DEBUG_TAG := "MusicLocalImport"
const WINDOWS_SCAN_ROOT := "windows://drives"
const AUDIO_EXTENSIONS := {
	"mp3": true,
	"wav": true,
	"ogg": true
}
const LYRIC_EXTENSIONS := [
	"lrc",
	"LRC",
	"txt",
	"TXT"
]

## 返回本地扫描的起始目录。
func get_scan_root_path() -> String:
	var os_name := OS.get_name()
	if os_name == "Android":
		for candidate in ["/storage/emulated/0", "/sdcard", "/storage/self/primary"]:
			if DirAccess.dir_exists_absolute(candidate):
				return candidate
		return "/"
	if os_name == "Windows":
		return WINDOWS_SCAN_ROOT

	var base_path := OS.get_environment("USERPROFILE")
	if base_path.is_empty():
		base_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if base_path.is_empty():
		base_path = ProjectSettings.globalize_path("res://")
	return path_root(base_path)

## 返回当前扫描路径用于界面展示的文案。
func get_scan_display_path(path: String) -> String:
	var normalized_path := normalize_path(path)
	if is_scan_virtual_root(normalized_path):
		return tr("music_app.scan.windows_root")
	return normalized_path

## 计算当前路径的上一级目录，并保证不会退回到扫描根目录之外。
func get_scan_parent_path(current_path: String, root_path: String) -> String:
	var normalized_current := normalize_path(current_path)
	var normalized_root := normalize_path(root_path)
	if normalized_current == normalized_root:
		return normalized_root
	if is_scan_virtual_root(normalized_root) and is_windows_drive_root(normalized_current):
		return normalized_root

	var parent := normalize_path(normalized_current.get_base_dir())
	if parent.is_empty():
		return normalized_root
	if parent.ends_with(":"):
		parent += "/"
	if parent.length() < normalized_root.length():
		return normalized_root
	return parent

## 列出指定目录下可供扫描选择的子目录。
func list_scan_directories(path: String) -> Array[Dictionary]:
	var normalized_path := normalize_path(path)
	if is_scan_virtual_root(normalized_path):
		return list_windows_drive_entries()
	if not DirAccess.dir_exists_absolute(normalized_path):
		return []

	var result: Array[Dictionary] = []
	var directory_names := DirAccess.get_directories_at(normalized_path)
	directory_names.sort()
	for directory_name in directory_names:
		if _should_skip_file_system_entry(directory_name):
			continue
		result.append(
			{
				"name": directory_name,
				"path": normalize_path(normalized_path.path_join(directory_name))
			}
		)
	return result

## 返回 Windows 盘符根目录列表。
func list_windows_drive_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for index in letters.length():
		var drive_letter := letters.substr(index, 1)
		var drive_path := "%s:/" % drive_letter
		if not DirAccess.dir_exists_absolute(drive_path):
			continue
		result.append(
			{
				"name": "%s:" % drive_letter,
				"path": drive_path
			}
		)
	return result

## 递归扫描所选目录并导入新的本地音乐曲目。
func scan_local_music_directories(paths: Array[String]) -> int:
	_debug_import("scan directories requested", paths)
	var tracks: Array[TrackData] = get_tracks_ref()
	var existing_paths := {}
	for track in tracks:
		if track == null or track.file_path.is_empty():
			continue
		existing_paths[normalize_path(track.file_path)] = true

	var imported_tracks: Array[TrackData] = []
	var stats := {
		"targets": 0,
		"invalid_targets": 0,
		"directories": 0,
		"files": 0,
		"audio_files": 0,
		"duplicates": 0,
		"unsupported_files": 0,
		"imported": 0
	}
	var unique_targets := {}
	for raw_path in paths:
		var target_path := normalize_path(str(raw_path))
		if target_path.is_empty() or unique_targets.has(target_path):
			_debug_import("skip scan target", {
				"raw": raw_path,
				"target": target_path,
				"already_seen": unique_targets.has(target_path)
			})
			continue
		unique_targets[target_path] = true
		stats["targets"] = int(stats["targets"]) + 1
		_collect_audio_tracks(target_path, existing_paths, imported_tracks, stats, {})

	for track in imported_tracks:
		tracks.append(track)
	stats["imported"] = imported_tracks.size()
	_debug_import("scan directories completed", stats)

	return imported_tracks.size()

## 递归收集目录下符合条件的音频文件并转成曲目数据。
func _collect_audio_tracks(
	root_path: String,
	existing_paths: Dictionary,
	imported_tracks: Array[TrackData],
	stats: Dictionary,
	visited_dirs: Dictionary
) -> void:
	var normalized_root := normalize_path(root_path)
	if normalized_root.is_empty() or visited_dirs.has(normalized_root):
		return
	visited_dirs[normalized_root] = true

	var list_result: Dictionary = DX.files.list_dir(normalized_root)
	if not bool(list_result.get("ok", false)):
		stats["invalid_targets"] = int(stats["invalid_targets"]) + 1
		_debug_import("scan directory list failed", {
			"path": normalized_root,
			"error": str(list_result.get("error", ""))
		})
		return

	stats["directories"] = int(stats["directories"]) + 1
	var entries: Array = list_result.get("entries", [])
	var lyric_paths_by_stem := {}
	var file_entries: Array[Dictionary] = []
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var item_name := str(entry.get("name", ""))
		if _should_skip_file_system_entry(item_name):
			continue

		var item_path := normalize_path(str(entry.get("path", "")))
		if item_path.is_empty():
			item_path = normalize_path(str(entry.get("native_path", "")))
		if bool(entry.get("is_dir", false)):
			_collect_audio_tracks(item_path, existing_paths, imported_tracks, stats, visited_dirs)
			continue

		stats["files"] = int(stats["files"]) + 1
		var file_stem := item_name.get_basename().to_lower()
		if _is_lyric_file_name(item_name):
			if not lyric_paths_by_stem.has(file_stem):
				lyric_paths_by_stem[file_stem] = item_path
			continue
		file_entries.append({
			"name": item_name,
			"path": item_path,
			"stem": file_stem
		})

	for file_entry in file_entries:
		var item_name := str(file_entry.get("name", ""))
		var item_path := str(file_entry.get("path", ""))
		if not is_audio_file(item_path):
			stats["unsupported_files"] = int(stats["unsupported_files"]) + 1
			continue
		stats["audio_files"] = int(stats["audio_files"]) + 1
		if existing_paths.has(item_path):
			stats["duplicates"] = int(stats["duplicates"]) + 1
			continue

		existing_paths[item_path] = true
		var lyric_path := str(lyric_paths_by_stem.get(str(file_entry.get("stem", "")), ""))
		imported_tracks.append(
			make_local_track_from_path(
				item_path,
				item_name,
				_display_name_from_path(normalized_root),
				lyric_path
			)
		)

## 判断指定路径是否为支持导入的音频文件。
func is_audio_file(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return AUDIO_EXTENSIONS.has(extension)

## 根据文件路径构造一条本地曲目数据。
func make_local_track_from_path(
	path: String,
	display_file_name: String = "",
	folder_display_name: String = "",
	lyric_path: String = ""
) -> TrackData:
	var normalized_path := normalize_path(path)
	var file_name := display_file_name.strip_edges()
	if file_name.is_empty():
		file_name = _display_name_from_path(normalized_path)
	var file_stem := file_name.get_basename()
	var title := file_stem
	var artist := ""
	var separator := " - "
	var separator_index := file_stem.find(separator)
	if separator_index >= 0:
		artist = file_stem.substr(0, separator_index).strip_edges()
		title = file_stem.substr(separator_index + separator.length()).strip_edges()
		if title.is_empty():
			title = file_stem

	var subtitle := folder_display_name.strip_edges()
	if subtitle.is_empty():
		subtitle = _display_name_from_path(normalized_path.get_base_dir())

	var track := TrackData.new()
	track.title = title
	track.artist = artist
	track.subtitle = subtitle
	track.duration = 180
	track.preview_start = 0
	track.mark = title.left(1) if not title.is_empty() else "L"
	track.source = "LOCAL"
	track.file_path = normalized_path
	track.lyric_path = lyric_path if not lyric_path.is_empty() else find_lyric_path_for_audio(normalized_path)
	track.normalize()
	return track

## 查找与音频同名的旁挂歌词文件。
func find_lyric_path_for_audio(path: String) -> String:
	var normalized_path := normalize_path(path)
	var base_path := normalized_path.get_basename()
	for extension in LYRIC_EXTENSIONS:
		var lyric_path := "%s.%s" % [base_path, extension]
		if DX.files.exists(lyric_path):
			return lyric_path
	return ""

func _is_lyric_file_name(file_name: String) -> bool:
	return file_name.get_extension().to_lower() in ["lrc", "txt"]

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

## 解析给定路径所属的根目录。
func path_root(path: String) -> String:
	var normalized := normalize_path(path)
	var drive_index := normalized.find(":/")
	if drive_index >= 0:
		return normalized.substr(0, drive_index + 2) + "/"
	if normalized.begins_with("/"):
		return "/"
	return normalized

## 统一路径分隔符并移除多余尾部斜杠。
func normalize_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.ends_with("/") and normalized.length() > 1 and not normalized.ends_with(":/"):
		normalized = normalized.left(normalized.length() - 1)
	return normalized

## 判断路径是否为虚拟的 Windows 盘符根入口。
func is_scan_virtual_root(path: String) -> bool:
	return normalize_path(path) == WINDOWS_SCAN_ROOT

## 判断路径是否是 Windows 单个盘符根目录。
func is_windows_drive_root(path: String) -> bool:
	return path.length() == 3 and path.substr(1, 1) == ":" and path.ends_with("/")

func _should_skip_file_system_entry(entry_name: String) -> bool:
	if entry_name in [".", "..", ".DS_Store", "__MACOSX", "System Volume Information", "$RECYCLE.BIN"]:
		return true
	return entry_name.begins_with(".")

func _debug_import(message: String, payload: Variant = null) -> void:
	var text := message if payload == null else "%s | %s" % [message, str(payload)]
	if DX != null and DX.logger != null:
		DX.logger.log(DEBUG_TAG, text)
	else:
		print("[%s] %s" % [DEBUG_TAG, text])
