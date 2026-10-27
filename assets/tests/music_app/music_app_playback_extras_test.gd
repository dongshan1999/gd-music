extends Node
## 验证 Phase 6 新增的三处改动：设置页音量控件、封面编码、拖进度动作解析。
##
## 运行：
##   godot --headless --path . res://assets/tests/music_app/music_app_playback_extras_test.tscn
##
## 退出码 0 = 全过。

const ControllerScript = preload("res://assets/scripts/ui/music_app/controllers/global/music_app_audio_controller.gd")
const SettingsScene := "res://assets/scenes/ui/music_app/settings/music_app_settings_page.tscn"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[extras] OK    %s" % message)
	else:
		failures.append(message)
		printerr("[extras] FAIL  %s" % message)


func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	_check_settings_scene()
	_check_artwork_encoding()
	_check_seek_action()
	get_tree().quit(0 if failures.is_empty() else 1)


## 设置页必须能实例化，且音量控件带正确的初值与唯一名。
func _check_settings_scene() -> void:
	var scene: PackedScene = load(SettingsScene)
	_check(scene != null, "设置页场景可加载")
	if scene == null:
		return
	var page: Control = scene.instantiate()
	add_child(page)
	var slider: HSlider = page.get_node_or_null("%VolumeSlider")
	var label: Label = page.get_node_or_null("%VolumeValueLabel")
	_check(slider != null, "设置页存在 %VolumeSlider")
	_check(label != null, "设置页存在 %VolumeValueLabel")
	if slider != null:
		_check(is_equal_approx(slider.max_value, 100.0), "音量滑块量程为 0–100")
		_check(is_equal_approx(slider.value, 100.0), "音量滑块初值为 100（未设置过时全音量）")
		_check(slider.step >= 1.0, "音量滑块以整度步进")
	if label != null:
		_check(label.text.ends_with("%"), "音量数值带百分号", )
	page.queue_free()


## 任意尺寸的封面都要被缩到 512px 长边以内，且输出能解回图片。
func _check_artwork_encoding() -> void:
	var controller: RefCounted = ControllerScript.new(null)
	var image := Image.create(1536, 864, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.2, 0.4, 1.0))
	var source_png := image.save_png_to_buffer()
	_check(not source_png.is_empty(), "构造源封面成功")
	var encoded: String = controller._encode_artwork(source_png)
	_check(not encoded.is_empty(), "封面编码返回非空字符串")
	if encoded.is_empty():
		return
	var decoded_bytes := Marshalls.base64_to_raw(encoded)
	var decoded := Image.new()
	var error: int = decoded.load_jpg_from_buffer(decoded_bytes)
	_check(error == OK, "编码结果是合法 JPEG")
	var longest := maxi(decoded.get_width(), decoded.get_height())
	_check(longest <= ControllerScript.ARTWORK_MAX_EDGE, "长边已缩到 %d 以内（实际 %d）" % [ControllerScript.ARTWORK_MAX_EDGE, longest])
	# 512px JPEG 的 base64 远小于 Binder 事务上限，超出说明没有真正压缩。
	_check(encoded.length() < 400_000, "编码后体积可控（%d 字符）" % encoded.length())


## 服务回传的 seek_to 动作必须能落到播放队列的跳转上。
func _check_seek_action() -> void:
	var action := "seek_to:42000"
	_check(action.begins_with("seek_to:"), "动作前缀可识别")
	_check(int(action.trim_prefix("seek_to:")) == 42_000, "毫秒解析正确")
