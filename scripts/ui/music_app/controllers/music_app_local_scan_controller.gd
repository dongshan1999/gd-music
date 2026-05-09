class_name MusicAppLocalScanController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const WINDOWS_SCAN_ROOT := "windows://drives"
const AUDIO_EXTENSIONS := {
	"mp3": true,
	"wav": true,
	"ogg": true
}

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
		if directory_name in [".", ".."]:
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
	var tracks: Array[TrackData] = get_tracks_ref()
	var existing_paths := {}
	for track in tracks:
		if track == null or track.file_path.is_empty():
			continue
		existing_paths[normalize_path(track.file_path)] = true

	var imported_tracks: Array[TrackData] = []
	var unique_targets := {}
	for raw_path in paths:
		var target_path := normalize_path(str(raw_path))
		if target_path.is_empty() or unique_targets.has(target_path):
			continue
		unique_targets[target_path] = true
		_collect_audio_tracks(target_path, existing_paths, imported_tracks)

	for track in imported_tracks:
		tracks.append(track)

	if not imported_tracks.is_empty():
		notify_state_changed()
		save_app_state()

	return imported_tracks.size()

## 递归收集目录下符合条件的音频文件并转成曲目数据。
func _collect_audio_tracks(
	root_path: String,
	existing_paths: Dictionary,
	imported_tracks: Array[TrackData]
) -> void:
	var normalized_root := normalize_path(root_path)
	if not DirAccess.dir_exists_absolute(normalized_root):
		return

	var directory := DirAccess.open(normalized_root)
	if directory == null:
		return

	directory.list_dir_begin()
	while true:
		var item_name := directory.get_next()
		if item_name.is_empty():
			break
		if item_name in [".", ".."]:
			continue

		var item_path := normalize_path(normalized_root.path_join(item_name))
		if directory.current_is_dir():
			_collect_audio_tracks(item_path, existing_paths, imported_tracks)
			continue

		if not is_audio_file(item_path) or existing_paths.has(item_path):
			continue

		existing_paths[item_path] = true
		imported_tracks.append(make_local_track_from_path(item_path))
	directory.list_dir_end()

## 判断指定路径是否为支持导入的音频文件。
func is_audio_file(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return AUDIO_EXTENSIONS.has(extension)

## 根据文件路径构造一条本地曲目数据。
func make_local_track_from_path(path: String) -> TrackData:
	var normalized_path := normalize_path(path)
	var file_stem := normalized_path.get_file().get_basename()
	var title := file_stem
	var artist := ""
	var separator := " - "
	var separator_index := file_stem.find(separator)
	if separator_index >= 0:
		artist = file_stem.substr(0, separator_index).strip_edges()
		title = file_stem.substr(separator_index + separator.length()).strip_edges()
		if title.is_empty():
			title = file_stem

	var subtitle := normalized_path.get_base_dir().get_file()

	var track := TrackData.new()
	track.title = title
	track.artist = artist
	track.subtitle = subtitle
	track.duration = 180
	track.preview_start = 0
	track.mark = title.left(1) if not title.is_empty() else "L"
	track.source = "LOCAL"
	track.file_path = normalized_path
	track.normalize()
	return track

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
