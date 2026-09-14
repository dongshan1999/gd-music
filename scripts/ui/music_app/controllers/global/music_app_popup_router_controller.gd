class_name MusicAppPopupRouterController
extends RefCounted

const MusicAppShowcaseControllerScript := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppControllerBaseScript := preload("res://scripts/ui/music_app/controllers/music_app_controller_base.gd")

var controller

func _init(owner = null) -> void:
	controller = owner

func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

func _get_base_controller() -> MusicAppControllerBase:
	return MusicAppControllerBaseScript.new(controller)

func get_tracks_ref() -> Array[TrackData]:
	return _get_base_controller().get_tracks_ref()

func get_playlists_ref() -> Array[PlaylistData]:
	return _get_base_controller().get_playlists_ref()

func get_selected_playlist_index() -> int:
	return _get_base_controller().get_selected_playlist_index()

func set_selected_playlist_index(value: int) -> void:
	_get_base_controller().set_selected_playlist_index(value)

## 绑定弹窗宿主节点，供全局弹窗管理器使用。
func attach_popup_hosts(normal_host: Control, fullscreen_host: Control) -> void:
	var popup_manager := get_popup_manager()
	if popup_manager == null:
		return
	popup_manager.set_normal_host(normal_host)
	popup_manager.set_fullscreen_host(fullscreen_host)

## 解绑弹窗宿主节点。
func detach_popup_hosts(normal_host: Control, fullscreen_host: Control) -> void:
	var popup_manager := get_popup_manager()
	if popup_manager == null:
		return
	popup_manager.clear_normal_host(normal_host)
	popup_manager.clear_fullscreen_host(fullscreen_host)


## 返回全局弹窗管理器。
func get_popup_manager() -> DX_PopupManager:
	return DX.popup as DX_PopupManager

## 按弹窗 ID 获取已创建的弹窗实例。
func get_popup(popup_id: int):
	var popup_manager := get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_popup"):
		return null
	return popup_manager.get_popup(popup_id)

## 返回当前显示中的弹窗实例。
func get_current_popup():
	var popup_manager := get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_current_popup"):
		return null
	return popup_manager.get_current_popup()

## 打开指定弹窗，并在支持时注入 showcase 控制器。
func show_popup(popup_id: int, layer_override: int = -1):
	var popup_manager := get_popup_manager()
	if popup_manager == null:
		return null

	var popup = popup_manager.show(popup_id, layer_override)
	if popup != null and popup.has_method("setup"):
		popup.setup(get_showcase())
	return popup

## 打开音乐应用首页弹窗。
func show_home_popup() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_HOME)

## 弹出通用提示对话框。
func show_common_alert(title: String, message: String) -> void:
	var popup_manager := get_popup_manager()
	if popup_manager == null:
		push_error("Popup autoload is not available.")
		return

	var popup: DX_PopupView = popup_manager.show(DX_PopupRegistry.PopupId.COMMON_DIALOG)
	if popup is CommonDialogPopup:
		var dialog: CommonDialogPopup = popup as CommonDialogPopup
		dialog.show_alert(title, message)

## 显示底部轻提示。
func show_toast(message: String) -> void:
	var resolved_controller = get_showcase()
	var popup_manager := get_popup_manager()
	if resolved_controller == null or popup_manager == null:
		return

	var popup: DX_PopupView = popup_manager.show(DX_PopupRegistry.PopupId.COMMON_TOAST)
	if popup is CommonToastPopup:
		var toast_popup := popup as CommonToastPopup
		toast_popup.show_message(message, 104.0 if resolved_controller.mini_player.visible else 28.0)

## 处理返回键，关闭当前非首页弹窗。
func handle_cancel_input(event: InputEvent) -> bool:
	if not event.is_action_pressed("ui_cancel"):
		return false

	var current_popup = get_current_popup()
	if current_popup == null or current_popup == get_popup(DX_PopupRegistry.PopupId.MUSIC_APP_HOME):
		return false

	var popup_manager := get_popup_manager()
	if popup_manager == null:
		return false

	current_popup.close_popup()
	return true
