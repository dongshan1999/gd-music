class_name MusicAppSettingsView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const SettingsControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_SETTINGS_CONTROLLER)
const BuildNumberStoreScript := preload("res://addons/dx_build_number/dx_build_number_store.gd")
const APP_VERSION := "0.0.1"

var _controller: MusicAppShowcaseController
var _settings_controller
var _is_bound := false
var _build_number_store := BuildNumberStoreScript.new()

@onready var back_button: Button = %SettingsBackButton
@onready var basic_settings_button: Button = %BasicSettingsButton
@onready var plugin_management_button: Button = %PluginManagementButton
@onready var theme_settings_button: Button = %ThemeSettingsButton
@onready var language_settings_button: Button = %LanguageSettingsButton
@onready var sleep_timer_button: Button = %SleepTimerButton
@onready var backup_restore_button: Button = %BackupRestoreButton
@onready var permission_management_button: Button = %PermissionManagementButton
@onready var check_update_button: Button = %CheckUpdateButton
@onready var about_button: Button = %AboutButton
@onready var version_label: Label = %VersionLabel
@onready var back_home_button: Button = %BackHomeButton
@onready var exit_app_button: Button = %ExitAppButton

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_settings_controller = SettingsControllerScript.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	back_button.pressed.connect(close_popup)
	basic_settings_button.pressed.connect(_on_basic_settings_pressed)
	plugin_management_button.pressed.connect(_on_plugin_management_pressed)
	theme_settings_button.pressed.connect(_on_theme_settings_pressed)
	language_settings_button.pressed.connect(_on_language_settings_pressed)
	sleep_timer_button.pressed.connect(_on_sleep_timer_pressed)
	backup_restore_button.pressed.connect(_on_backup_restore_pressed)
	permission_management_button.pressed.connect(_on_permission_management_pressed)
	check_update_button.pressed.connect(_on_check_update_pressed)
	about_button.pressed.connect(_on_about_pressed)
	back_home_button.pressed.connect(_on_back_home_pressed)
	exit_app_button.pressed.connect(_on_exit_app_pressed)

func on_popup_shown() -> void:
	refresh()

func refresh() -> void:
	_refresh_version_label()
	if _controller == null:
		return

func _refresh_version_label() -> void:
	if version_label == null:
		return

	var build_number := _build_number_store.read_build_number(OS.get_name())
	version_label.text = "%s.%d" % [APP_VERSION, build_number]

func _on_basic_settings_pressed() -> void:
	_settings_controller.show_basic_settings_placeholder()

func _on_plugin_management_pressed() -> void:
	_settings_controller.open_plugin_management()

func _on_theme_settings_pressed() -> void:
	_settings_controller.show_theme_settings_placeholder()

func _on_language_settings_pressed() -> void:
	_settings_controller.show_language_settings_placeholder()

func _on_sleep_timer_pressed() -> void:
	_settings_controller.show_sleep_timer_placeholder()

func _on_backup_restore_pressed() -> void:
	_settings_controller.show_backup_placeholder()

func _on_permission_management_pressed() -> void:
	_settings_controller.show_permission_placeholder()

func _on_check_update_pressed() -> void:
	_settings_controller.show_update_placeholder()

func _on_about_pressed() -> void:
	_settings_controller.show_about_placeholder()

func _on_back_home_pressed() -> void:
	close_popup()

func _on_exit_app_pressed() -> void:
	get_tree().quit()
