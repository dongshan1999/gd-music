class_name MusicAppSettingsController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

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
