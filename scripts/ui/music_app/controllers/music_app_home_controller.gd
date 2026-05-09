class_name MusicAppHomeController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 返回首页要展示的全部歌单。
func get_playlists() -> Array:
	return get_playlists_ref()

## 查找系统“我喜欢”歌单在当前歌单列表中的索引。
func find_favorite_playlist_index() -> int:
	var playlists := get_playlists_ref()
	for index in playlists.size():
		if MusicAppStateData.is_system_favorite_playlist(playlists[index]):
			return index
	return -1

## 返回歌单在首页卡片上的显示标题。
func get_playlist_display_title(playlist) -> String:
	if MusicAppStateData.is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_title")
	return playlist.title

## 返回歌单在首页卡片上的角标文字。
func get_playlist_display_mark(playlist) -> String:
	if MusicAppStateData.is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_mark")
	if not playlist.mark.is_empty():
		return playlist.mark
	var title := get_playlist_display_title(playlist)
	return title.left(1) if not title.is_empty() else ""

## 创建一个新的空歌单，并切换为当前选中歌单。
func create_playlist_from_current() -> bool:
	var playlists := get_playlists_ref()
	var title := _next_playlist_title()
	var playlist := PlaylistData.new()
	playlist.title = title
	playlist.count = 0
	playlist.mark = title.left(1)
	playlist.tracks = []
	playlist.deletable = true
	playlists.append(playlist)
	set_selected_playlist_index(playlists.size() - 1)
	notify_state_changed()
	save_app_state()
	return true

## 删除指定索引的歌单，并修正当前选中项。
func delete_playlist(index: int) -> bool:
	var playlists := get_playlists_ref()
	if index < 0 or index >= playlists.size():
		return false

	var playlist: PlaylistData = playlists[index]
	if not playlist.deletable:
		return false

	var selected_playlist_index := get_selected_playlist_index()
	if index < selected_playlist_index:
		selected_playlist_index -= 1

	playlists.remove_at(index)
	set_selected_playlist_index(clampi(selected_playlist_index, 0, maxi(playlists.size() - 1, 0)))
	notify_state_changed()
	save_app_state()
	return true

## 选中并打开指定歌单详情弹窗。
func open_playlist(index: int) -> bool:
	if not _select_playlist(index):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYLIST)
	return true

## 打开本地音乐页面。
func open_local_music() -> void:
	var popup = show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_LOCAL_MUSIC)
	if popup != null and popup.has_method("open_page"):
		popup.open_page()

## 打开插件音乐浏览页。
func open_plugin_browser() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLUGIN_BROWSER)

## 处理首页功能入口点击。
func open_feature_card(index: int) -> bool:
	if index == 3:
		open_local_music()
		return true
	show_toast("该入口暂未接入新页面。")
	return false

## 选中指定歌单并同步状态。
func _select_playlist(index: int) -> bool:
	var playlists := get_playlists_ref()
	if playlists.is_empty():
		return false
	set_selected_playlist_index(clampi(index, 0, playlists.size() - 1))
	notify_state_changed()
	save_app_state()
	return true

## 生成一个不与现有歌单重名的新歌单标题。
func _next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
	var suffix := 1
	var title := base_title
	while _playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

## 判断给定标题是否已被现有歌单使用。
func _playlist_title_exists(title: String) -> bool:
	for playlist in get_playlists_ref():
		if playlist.title == title:
			return true
	return false
