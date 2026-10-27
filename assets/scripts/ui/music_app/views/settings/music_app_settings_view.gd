class_name MusicAppSettingsView
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const SettingsControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_SETTINGS_CONTROLLER)
const BUILD_INFO_PATH := "res://build_info.cfg"
const DEFAULT_APP_VERSION := "0.0.0"

var _controller: MusicAppShowcaseController
var _settings_controller
var _is_bound := false

@onready var back_button: Button = %SettingsBackButton
@onready var plugin_management_button: Button = %PluginManagementButton
@onready var download_management_button: Button = %DownloadManagementButton
@onready var language_settings_button: Button = %LanguageSettingsButton
@onready var version_label: Label = %VersionLabel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel

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
	plugin_management_button.pressed.connect(_on_plugin_management_pressed)
	download_management_button.pressed.connect(_on_download_management_pressed)
	language_settings_button.pressed.connect(_on_language_settings_pressed)
	volume_slider.value_changed.connect(_on_volume_slider_changed)
	$Margin/RootVBox/TopRow/TitleLabel.text = tr("music_app.ui.settings")

func on_popup_shown() -> void:
	refresh()

func refresh() -> void:
	_refresh_version_label()
	_refresh_volume_slider()
	if _controller == null:
		return

## 让滑块反映当前音量，并同步一次播放端状态。
func _refresh_volume_slider() -> void:
	if _controller == null or volume_slider == null:
		return
	_controller.sync_playback_volume()
	var percent := int(round(_controller.get_playback_volume() * 100.0))
	volume_slider.set_value_no_signal(percent)
	volume_value_label.text = "%d%%" % percent

## 拖动滑块时实时改音量。
func _on_volume_slider_changed(value: float) -> void:
	volume_value_label.text = "%d%%" % int(round(value))
	if _controller == null:
		return
	_controller.set_playback_volume(clampf(value / 100.0, 0.0, 1.0))

func _refresh_version_label() -> void:
	if version_label == null:
		return

	var version := str(ProjectSettings.get_setting("application/config/version", DEFAULT_APP_VERSION))
	var build_number := _read_exported_build_number()
	version_label.text = "%s.%d" % [version, build_number]

func _read_exported_build_number() -> int:
	var config := ConfigFile.new()
	if config.load(BUILD_INFO_PATH) == OK:
		return maxi(0, int(config.get_value("build", "number", 0)))
	return 0

func _on_plugin_management_pressed() -> void:
	_settings_controller.open_plugin_management()

func _on_download_management_pressed() -> void:
	_settings_controller.open_download_management()

func _on_language_settings_pressed() -> void:
	_settings_controller.show_language_settings_placeholder()
