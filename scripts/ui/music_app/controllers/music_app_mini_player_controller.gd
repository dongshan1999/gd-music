class_name MusicAppMiniPlayerController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

var _playback_controller: MusicAppPlaybackController = MusicAppPlaybackController.new()

## 判断迷你播放器当前是否有可播放队列。
func has_tracks() -> bool:
	return _playback_controller.has_playback_queue()

## 返回迷你播放器当前对应的曲目对象。
func get_current_track() -> TrackData:
	return _playback_controller.get_current_playback_track()

## 返回曲目在迷你播放器上的展示歌手名。
func get_track_display_artist(track: TrackData) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

## 切换播放或暂停状态。
func toggle_playback() -> void:
	var resolved_controller = get_showcase()
	if resolved_controller != null:
		resolved_controller.toggle_playback()

## 打开完整播放器页面。
func open_player_page() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)

## 展示当前播放队列对话框。
func show_playback_queue() -> void:
	_playback_controller.show_playback_queue_dialog()
