class_name MusicAppSettingsView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const SettingsControllerScript := preload(MusicAppScriptPathsType.MUSIC_APP_SETTINGS_CONTROLLER)
const BUILD_INFO_PATH := "res://build_info.cfg"
const DEFAULT_APP_VERSION := "0.0.0"
const QUALITY_OFF := "off"
const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"
const MODE_MINERADIO := "mineradio"
const MODE_CITY := "city"

var _controller: MusicAppShowcaseController
var _settings_controller
var _is_bound := false

@onready var back_button: Button = %SettingsBackButton
@onready var basic_settings_button: Button = %BasicSettingsButton
@onready var plugin_management_button: Button = %PluginManagementButton
@onready var theme_settings_button: Button = %ThemeSettingsButton
@onready var language_settings_button: Button = %LanguageSettingsButton
@onready var visualizer_enabled_check_box: CheckBox = %VisualizerEnabledCheckBox
@onready var visualizer_mode_mineradio_button: Button = %VisualizerModeMineradioButton
@onready var visualizer_mode_city_button: Button = %VisualizerModeCityButton
@onready var visualizer_quality_off_button: Button = %VisualizerQualityOffButton
@onready var visualizer_quality_low_button: Button = %VisualizerQualityLowButton
@onready var visualizer_quality_medium_button: Button = %VisualizerQualityMediumButton
@onready var visualizer_quality_high_button: Button = %VisualizerQualityHighButton
@onready var visualizer_particles_slider: HSlider = %VisualizerParticlesSlider
@onready var visualizer_particles_value_label: Label = %VisualizerParticlesValueLabel
@onready var visualizer_bloom_slider: HSlider = %VisualizerBloomSlider
@onready var visualizer_bloom_value_label: Label = %VisualizerBloomValueLabel
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
	visualizer_enabled_check_box.toggled.connect(_on_visualizer_enabled_toggled)
	visualizer_mode_mineradio_button.pressed.connect(_on_visualizer_mode_mineradio_pressed)
	visualizer_mode_city_button.pressed.connect(_on_visualizer_mode_city_pressed)
	visualizer_quality_off_button.pressed.connect(_on_visualizer_quality_off_pressed)
	visualizer_quality_low_button.pressed.connect(_on_visualizer_quality_low_pressed)
	visualizer_quality_medium_button.pressed.connect(_on_visualizer_quality_medium_pressed)
	visualizer_quality_high_button.pressed.connect(_on_visualizer_quality_high_pressed)
	visualizer_particles_slider.value_changed.connect(_on_visualizer_particles_changed)
	visualizer_bloom_slider.value_changed.connect(_on_visualizer_bloom_changed)
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
	_refresh_visualizer_settings()

func _refresh_visualizer_settings() -> void:
	if _settings_controller == null:
		return
	var settings: Dictionary = _settings_controller.get_visualizer_settings()
	var enabled := bool(settings.get("enabled", true))
	var mode := str(settings.get("mode", MODE_MINERADIO))
	var quality := str(settings.get("quality", QUALITY_MEDIUM))
	visualizer_enabled_check_box.set_pressed_no_signal(enabled)
	_set_mode_button_state(mode)
	_set_quality_button_state(quality)
	var particles_value := float(settings.get("particles", 1.0))
	var bloom_value := float(settings.get("bloom", 1.0))
	visualizer_particles_slider.set_value_no_signal(particles_value)
	visualizer_bloom_slider.set_value_no_signal(bloom_value)
	_update_visualizer_value_labels(particles_value, bloom_value)

func _set_mode_button_state(mode: String) -> void:
	visualizer_mode_mineradio_button.set_pressed_no_signal(mode == MODE_MINERADIO)
	visualizer_mode_city_button.set_pressed_no_signal(mode == MODE_CITY)

func _set_quality_button_state(quality: String) -> void:
	visualizer_quality_off_button.set_pressed_no_signal(quality == QUALITY_OFF)
	visualizer_quality_low_button.set_pressed_no_signal(quality == QUALITY_LOW)
	visualizer_quality_medium_button.set_pressed_no_signal(quality == QUALITY_MEDIUM)
	visualizer_quality_high_button.set_pressed_no_signal(quality == QUALITY_HIGH)

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

func _on_basic_settings_pressed() -> void:
	_settings_controller.show_basic_settings_placeholder()

func _on_plugin_management_pressed() -> void:
	_settings_controller.open_plugin_management()

func _on_theme_settings_pressed() -> void:
	_settings_controller.show_theme_settings_placeholder()

func _on_language_settings_pressed() -> void:
	_settings_controller.show_language_settings_placeholder()

func _on_visualizer_enabled_toggled(enabled: bool) -> void:
	_settings_controller.set_visualizer_enabled(enabled)
	_refresh_visualizer_settings()

func _on_visualizer_mode_mineradio_pressed() -> void:
	_settings_controller.set_visualizer_mode(MODE_MINERADIO)
	_refresh_visualizer_settings()

func _on_visualizer_mode_city_pressed() -> void:
	_settings_controller.set_visualizer_mode(MODE_CITY)
	_refresh_visualizer_settings()

func _on_visualizer_quality_off_pressed() -> void:
	_settings_controller.set_visualizer_quality(QUALITY_OFF)
	_refresh_visualizer_settings()

func _on_visualizer_quality_low_pressed() -> void:
	_settings_controller.set_visualizer_quality(QUALITY_LOW)
	_refresh_visualizer_settings()

func _on_visualizer_quality_medium_pressed() -> void:
	_settings_controller.set_visualizer_quality(QUALITY_MEDIUM)
	_refresh_visualizer_settings()

func _on_visualizer_quality_high_pressed() -> void:
	_settings_controller.set_visualizer_quality(QUALITY_HIGH)
	_refresh_visualizer_settings()

func _on_visualizer_particles_changed(value: float) -> void:
	_settings_controller.set_visualizer_particles(value)
	_update_visualizer_value_labels(value, visualizer_bloom_slider.value)

func _on_visualizer_bloom_changed(value: float) -> void:
	_settings_controller.set_visualizer_bloom(value)
	_update_visualizer_value_labels(visualizer_particles_slider.value, value)

func _update_visualizer_value_labels(particles_value: float, bloom_value: float) -> void:
	visualizer_particles_value_label.text = _format_visualizer_percent(particles_value)
	visualizer_bloom_value_label.text = _format_visualizer_percent(bloom_value)

func _format_visualizer_percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)

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
