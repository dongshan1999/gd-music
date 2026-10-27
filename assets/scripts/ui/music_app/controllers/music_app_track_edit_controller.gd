class_name MusicAppTrackEditController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 编辑当前播放曲目的歌名 / 创作者，只改本机曲库与下载记录，不回写音源平台。

## 返回当前播放中的曲目，没有则返回 null。
func get_target_track() -> TrackData:
	return get_current_track()

## 弹窗里的说明文案，按音源区分「UP 主」和「艺人」。
func get_hint_text(track: TrackData) -> String:
	if track == null:
		return ""
	if track.plugin_id == "bilibili":
		return "B 站视频里的「作者」其实是 UP 主；这里只改本机显示，不会改动视频本身。"
	return "只修改本机曲库里的显示名称，不会改动音源平台的原始信息。"

## 保存曲目信息，成功返回 {"ok": true}，失败返回 {"ok": false, "error": 文案}。
func save_track_info(next_title: String, next_artist: String) -> Dictionary:
	var track := get_target_track()
	if track == null:
		return {"ok": false, "error": "当前没有播放中的曲目。"}

	var title := next_title.strip_edges()
	if title.is_empty():
		return {"ok": false, "error": "歌名不能为空。"}

	track.title = title
	track.artist = next_artist.strip_edges()
	track.normalize()
	_sync_download_record(track)

	var save_manager = get_save_manager()
	if save_manager != null:
		save_manager.save(false)
	return {"ok": true}

## 已下载的曲目同步更新下载记录，避免列表里还是旧名字。
func _sync_download_record(track: TrackData) -> void:
	var downloads = get_download_controller()
	if downloads == null:
		return
	var record: MusicDownloadRecordData = downloads.get_download_record(track.id)
	if record == null:
		return
	record.title = track.title
	record.artist = track.artist
	record.normalize()
