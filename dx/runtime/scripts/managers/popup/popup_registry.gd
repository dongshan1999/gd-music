extends RefCounted

enum PopupId {
	COMMON_DIALOG,
	COMMON_TOAST,
	MUSIC_APP_HOME,
	MUSIC_APP_PLAYLIST,
	MUSIC_APP_PLAYER,
	MUSIC_APP_LOCAL_MUSIC,
	MUSIC_APP_LOCAL_SCAN,
	MUSIC_APP_PLUGIN_BROWSER,
}

const POPUP_SCENES := {
	PopupId.COMMON_DIALOG: preload("res://scenes/popup/common_dialog_popup.tscn"),
	PopupId.COMMON_TOAST: preload("res://scenes/popup/common_toast_popup.tscn"),
	PopupId.MUSIC_APP_HOME: preload("res://scenes/ui/music_app/music_app_home_page.tscn"),
	PopupId.MUSIC_APP_PLAYLIST: preload("res://scenes/ui/music_app/music_app_playlist_page.tscn"),
	PopupId.MUSIC_APP_PLAYER: preload("res://scenes/ui/music_app/music_app_player_page.tscn"),
	PopupId.MUSIC_APP_LOCAL_MUSIC: preload("res://scenes/ui/music_app/music_app_local_music_page.tscn"),
	PopupId.MUSIC_APP_LOCAL_SCAN: preload("res://scenes/ui/music_app/music_app_local_scan_page.tscn"),
	PopupId.MUSIC_APP_PLUGIN_BROWSER: preload("res://scenes/ui/music_app/music_app_plugin_browser_page.tscn"),
}

static func has_popup(popup_id: int) -> bool:
	return POPUP_SCENES.has(popup_id)

static func get_scene(popup_id: int) -> PackedScene:
	if not POPUP_SCENES.has(popup_id):
		return null
	return POPUP_SCENES[popup_id] as PackedScene
