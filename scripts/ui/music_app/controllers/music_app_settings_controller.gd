class_name MusicAppSettingsController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const VISUALIZER_QUALITY_LABELS := {
	MusicAppStateDataType.VISUALIZER_QUALITY_OFF: "关闭",
	MusicAppStateDataType.VISUALIZER_QUALITY_LOW: "低",
	MusicAppStateDataType.VISUALIZER_QUALITY_MEDIUM: "中",
	MusicAppStateDataType.VISUALIZER_QUALITY_HIGH: "高"
}

func get_visualizer_settings() -> Dictionary:
	return get_app_state().visualizer_settings.duplicate(true)

func set_visualizer_enabled(enabled: bool) -> void:
	var settings := get_visualizer_settings()
	settings["enabled"] = enabled
	_apply_visualizer_settings(settings)

func set_visualizer_quality(quality: String) -> void:
	var settings := get_visualizer_settings()
	settings["quality"] = quality
	settings["enabled"] = quality != MusicAppStateDataType.VISUALIZER_QUALITY_OFF
	_apply_visualizer_settings(settings)

func set_visualizer_mode(mode: String) -> void:
	var settings := get_visualizer_settings()
	settings["mode"] = mode
	_apply_visualizer_settings(settings)

func set_visualizer_particles(value: float) -> void:
	var settings := get_visualizer_settings()
	settings["particles"] = value
	_apply_visualizer_settings(settings)

func set_visualizer_bloom(value: float) -> void:
	var settings := get_visualizer_settings()
	settings["bloom"] = value
	_apply_visualizer_settings(settings)

func _apply_visualizer_settings(settings: Dictionary) -> void:
	get_app_state().visualizer_settings = settings
	get_app_state().normalize()
	var showcase = get_showcase()
	if showcase != null and showcase.has_method("apply_visualizer_settings"):
		showcase.apply_visualizer_settings()
	var save_manager = get_save_manager()
	if save_manager != null:
		save_manager.save(false)

func open_plugin_management() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLUGIN_MANAGEMENT)

func show_basic_settings_placeholder() -> void:
	show_toast("基础设置暂未接入。")

func show_theme_settings_placeholder() -> void:
	show_toast("主题设置暂未接入。")

func show_language_settings_placeholder() -> void:
	show_toast("语言设置暂未接入。")

func show_sleep_timer_placeholder() -> void:
	show_toast("定时关闭暂未接入。")

func show_backup_placeholder() -> void:
	show_toast("备份与恢复暂未接入。")

func show_permission_placeholder() -> void:
	show_toast("权限管理暂未接入。")

func show_update_placeholder() -> void:
	show_toast("检查更新暂未接入。")

func show_about_placeholder() -> void:
	show_toast("关于页面暂未接入。")

func close_to_home() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_HOME)
