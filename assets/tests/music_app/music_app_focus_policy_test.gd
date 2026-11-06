extends Control
## 验证「应用内按钮不参与焦点」：主场景按钮全部关闭焦点、运行时新增按钮同样生效、点击仍能触发、输入框仍可聚焦。

const SHOWCASE_SCENE := "res://assets/scenes/music_app_showcase_scene.tscn"

var _failures: Array[String] = []
var _presses := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SHOWCASE_SCENE)
	if packed == null:
		_check(false, "主场景加载失败")
		_finish()
		return
	var app := packed.instantiate()
	add_child(app)
	# 等首页弹出动画结束，导航遮罩（NavigationInputGuard）会让位。
	await get_tree().create_timer(0.6).timeout
	for i in 2:
		await get_tree().process_frame

	var buttons: Array[BaseButton] = []
	_collect_buttons(app, buttons)
	_check(buttons.size() >= 5, "主场景里应能找到多个按钮，实际 %d 个" % buttons.size())
	var focusable := 0
	for button in buttons:
		if button.focus_mode != Control.FOCUS_NONE:
			focusable += 1
	_check(focusable == 0, "按钮都应关闭焦点，实际仍有 %d 个可聚焦" % focusable)

	# 运行时新增的按钮（列表行就是这样挂上来的）同样不能抢焦点。
	var late_button := Button.new()
	late_button.text = "late"
	late_button.position = Vector2(40, size.y * 0.5)
	late_button.size = Vector2(160, 56)
	add_child(late_button)
	await get_tree().process_frame
	_check(late_button.focus_mode == Control.FOCUS_NONE, "运行时新增的按钮也应关闭焦点")

	# GDScript 的 lambda 按值捕获局部变量，计数用成员变量。
	_presses = 0
	late_button.pressed.connect(_on_late_pressed)
	_click(late_button.get_global_rect().get_center())
	await get_tree().process_frame
	_check(_presses == 1, "点击仍应触发一次 pressed，实际 %d 次" % _presses)
	var owner := get_viewport().gui_get_focus_owner()
	_check(not (owner is BaseButton), "点击后按钮不应抢走焦点，实际焦点 %s" % str(owner))

	# 输入框不在此列，仍然可以聚焦。
	var input := LineEdit.new()
	add_child(input)
	await get_tree().process_frame
	input.grab_focus()
	await get_tree().process_frame
	_check(get_viewport().gui_get_focus_owner() == input, "输入框仍应能获得焦点")

	# 触摸端会把 hover 样式换成 normal，避免点过的行一直亮着；用副本验证，不改全局主题。
	var probe_theme := probe_source_theme()
	app._strip_hover_styles(probe_theme)
	_check(
		probe_theme.get_stylebox("hover", "RowHit") == probe_theme.get_stylebox("normal", "RowHit"),
		"触摸端应把 RowHit 的 hover 样式换成 normal"
	)
	_check(
		probe_theme.get_stylebox("hover", "CardHit") == probe_theme.get_stylebox("normal", "CardHit"),
		"触摸端应把 CardHit 的 hover 样式换成 normal"
	)

	late_button.queue_free()
	input.queue_free()
	app.queue_free()
	for i in 3:
		await get_tree().process_frame
	_finish()

func _on_late_pressed() -> void:
	_presses += 1

## 取一份项目主题的副本，避免测试改到全局共享的那份。
func probe_source_theme() -> Theme:
	var source: Theme = load("res://assets/themes/gd_music_theme.tres")
	return source.duplicate() as Theme

## 递归收集场景里的按钮。
func _collect_buttons(node: Node, out: Array[BaseButton]) -> void:
	if node is BaseButton:
		out.append(node as BaseButton)
	for child in node.get_children():
		_collect_buttons(child, out)

## 用 GUI 事件点击指定坐标，模拟真实指针点击。
func _click(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	get_viewport().push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = position
	release.global_position = position
	get_viewport().push_input(release, true)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Music app focus policy tests: 0 failures")
		get_tree().quit(OK)
		return
	print("Music app focus policy tests: %d failures" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	get_tree().quit(FAILED)
