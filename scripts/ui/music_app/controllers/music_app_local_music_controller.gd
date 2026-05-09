class_name MusicAppLocalMusicController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")

var _playback_controller: MusicAppPlaybackController = MusicAppPlaybackController.new()

## 返回全部本地曲目在全量曲目数组中的索引列表。
func get_local_track_indices() -> Array[int]:
	var result: Array[int] = []
	var tracks := get_tracks_ref()
	for index in tracks.size():
		var track = tracks[index]
		if track == null:
			continue
		if not track.file_path.is_empty() or track.source == "LOCAL":
			result.append(index)
	return result

## 根据全量曲目索引返回对应曲目对象。
func get_track(track_index: int):
	var tracks := get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 以本地音乐页当前可见顺序构建播放队列并打开播放器。
func play_local_track_list(track_indices: Array[int], slot_index: int) -> bool:
	if not _play_track_list(track_indices, slot_index, true):
		return false
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
	return true

## 打开本地扫描页面。
func open_scan_page() -> void:
	var popup = show_popup(PopupRegistryType.PopupId.MUSIC_APP_LOCAL_SCAN)
	if popup != null and popup.has_method("open_page"):
		popup.open_page()

## 打开插件音乐浏览页。
func open_plugin_browser() -> void:
	show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLUGIN_BROWSER)

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
	if not _playback_controller.set_playback_queue(track_indices, start_slot_index):
		return false
	return _playback_controller.play_queue_index(_playback_controller.get_playback_queue_index(), autoplay)
