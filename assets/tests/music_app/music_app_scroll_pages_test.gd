extends Node

## 真实页面级别的滚动测试：确认每个页面的列表都挂上了滚动组件、
## 而且触摸拖动在手感上 1:1 跟手且不会把行按钮按下去。

const SceneRegistry = preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const HomeRowScene := preload("res://assets/scenes/ui/music_app/home/home_playlist_row.tscn")
const BASE_SCROLL_SCRIPT := "res://dx/runtime/scripts/component/scroll/scroll_interaction_comp.gd"
const MUSIC_SCROLL_SCRIPT := "res://assets/scripts/ui/music_app/music_app_scroll.gd"

var failures: Array[String] = []
var viewport: SubViewport

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	viewport = SubViewport.new()
	viewport.size = Vector2i(430, 932)
	add_child(viewport)
	await _test_every_page_has_scroll_interaction()
	await _test_home_list_touch_drag()
	print("Music app scroll page tests: %d failures" % failures.size())
	viewport.queue_free()
	get_tree().quit(OK if failures.is_empty() else FAILED)

func _test_every_page_has_scroll_interaction() -> void:
	var found_pages := 0
	for id in SceneRegistry.POPUP_SCENES:
		if id == SceneRegistry.PopupId.DX_DEBUG:
			continue
		var page: Control = SceneRegistry.get_scene(id).instantiate()
		viewport.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for frame in 3:
			await get_tree().process_frame
		var interactions: Array[Node] = []
		_collect_scroll_interactions(page, interactions)
		if not interactions.is_empty():
			found_pages += 1
		for interaction in interactions:
			_check(
				interaction._scroll != null,
				"%s scroll interaction resolves its ScrollContainer" % page.name
			)
			if interaction.name == "LyricsScrollInteraction":
				_check(
					not interaction.touch_fling_enabled,
					"Lyrics list keeps fling disabled so centering on release works"
				)
		page.queue_free()
		await get_tree().process_frame
	_check(found_pages >= 8, "Every list page wires a scroll interaction (%d pages)" % found_pages)

func _collect_scroll_interactions(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null:
			var path := String(script.resource_path)
			if path == BASE_SCROLL_SCRIPT or path == MUSIC_SCROLL_SCRIPT:
				out.append(child)
		_collect_scroll_interactions(child, out)

func _test_home_list_touch_drag() -> void:
	var page: Control = SceneRegistry.get_scene(SceneRegistry.PopupId.MUSIC_APP_HOME).instantiate()
	viewport.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var opened := [0]
	for index in 12:
		var row: Control = HomeRowScene.instantiate()
		page.home_list.add_child(row)
		row.configure(
			index,
			"",
			"我喜欢" if index == 0 else "夜晚的旋律 · %d" % index,
			24 + index,
			index > 0
		)
		row.open_requested.connect(func(_index: int) -> void: opened[0] += 1)
	for frame in 6:
		await get_tree().process_frame
	var scroll := page.home_list.get_parent() as ScrollContainer
	var target_row: Control = page.home_list.get_child(3)
	var button: Button = target_row.get_node("OpenButton")
	var start := button.get_global_rect().get_center()

	_push(_touch_press(start))
	_push(_mouse_press(start))
	_check(button.get_draw_mode() == BaseButton.DRAW_PRESSED, "Pressing a real row shows the press style")
	_push(_touch_drag(start - Vector2(0, 12), Vector2(0, -12)))
	_check(button.get_draw_mode() != BaseButton.DRAW_PRESSED, "Dragging clears the real row press style")
	_push(_touch_drag(start - Vector2(0, 30), Vector2(0, -18)))
	var scrolled := scroll.scroll_vertical
	_push(_mouse_release(start - Vector2(0, 30)))
	_push(_touch_release(start - Vector2(0, 30)))
	_check(
		scrolled >= 29 and scrolled <= 31,
		"Home list scrolls with the finger, not twice (%d px for 30 px)" % scrolled
	)
	_check(opened[0] == 0, "Scrolling a home row does not activate it")
	page.queue_free()
	await get_tree().process_frame

func _touch_press(position: Vector2) -> InputEvent:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	return event

func _touch_release(position: Vector2) -> InputEvent:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = false
	return event

func _touch_drag(position: Vector2, relative: Vector2) -> InputEvent:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = relative
	event.velocity = relative * 20.0
	return event

func _mouse_press(position: Vector2) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event

func _mouse_release(position: Vector2) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = position
	return event

func _push(event: InputEvent) -> void:
	viewport.push_input(event, true)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error(message)
