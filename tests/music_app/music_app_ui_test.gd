extends Node
## Exercise responsive layouts and navigation lifecycle without starting plugin hosts.

const PageScript = preload("res://scripts/ui/music_app/music_app_page.gd")
const SceneRegistry = preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
var failures: Array[String] = []
var viewport: SubViewport

class FakeManager:
	extends RefCounted
	var close_count := 0
	func hide_popup(popup: Control) -> void:
		close_count += 1
		popup._popup_close()
		popup.queue_free()

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	viewport = SubViewport.new()
	viewport.size = Vector2i(430, 932)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	DirAccess.make_dir_recursive_absolute("/tmp/gdmusic-ui")
	for dimensions in [Vector2i(430, 932), Vector2i(320, 568)]:
		viewport.size = dimensions
		for id in SceneRegistry.POPUP_SCENES:
			if id == SceneRegistry.PopupId.DX_DEBUG:
				continue
			var page: Control = SceneRegistry.get_scene(id).instantiate()
			viewport.add_child(page)
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await get_tree().process_frame
			if id == SceneRegistry.PopupId.COMMON_DIALOG:
				page.show_confirm("移除这首歌曲？", "歌曲将从当前播放队列中移除。你可以随时从资料库重新添加。")
			elif id == SceneRegistry.PopupId.COMMON_TOAST:
				page.show_message("已添加到资料库")
			elif id == SceneRegistry.PopupId.MUSIC_APP_HOME:
				var labels := ["推荐歌单", "榜单", "播放历史", "本地音乐"]
				for index in 4:
					page.feature_cards[index].configure(index, MusicAppHomeView.FEATURE_CARD_ICONS[index], labels[index])
				for index in 12:
					var row = preload("res://scenes/ui/music_app/home/home_playlist_row.tscn").instantiate()
					page.home_list.add_child(row)
					row.configure(index, "", "我喜欢" if index == 0 else "夜晚的旋律 · %d" % index, 24 + index, index > 0)
			elif id == SceneRegistry.PopupId.MUSIC_APP_PLAYBACK_QUEUE:
				for index in 12:
					var row = preload("res://scenes/ui/music_app/playback_queue/playback_queue_row.tscn").instantiate()
					page.queue_list.add_child(row)
					row.configure(index, "漫长的旅途 · 第 %d 首" % index, "陈粒 · 如也", "本地音乐", index == 0)
			elif id == SceneRegistry.PopupId.MUSIC_APP_PLUGIN_BROWSER:
				for index in 3:
					var row = preload("res://scenes/ui/music_app/plugin_browser/plugin_history_tag.tscn").instantiate()
					page.get_node("%HistoryTagsContainer").add_child(row)
					row.configure(["陈粒", "周杰伦", "适合夜晚的音乐"][index])
			elif id == SceneRegistry.PopupId.MUSIC_APP_PLUGIN_MANAGEMENT:
				page.empty_label.hide()
				var card = preload("res://scenes/ui/music_app/settings/music_app_plugin_management_item.tscn").instantiate()
				page.plugin_list.add_child(card)
				card.configure({"id": "preview", "name": "音乐插件", "version": "1.0.0", "author": "GDMusic"}, true)
			for frame in 6:
				await get_tree().process_frame
			if id == SceneRegistry.PopupId.MUSIC_APP_HOME:
				await _test_home_feedback(page, dimensions)
			_check(page.size.x <= dimensions.x + 1, "%s exceeds viewport width %d" % [page.name, dimensions.x])
			var body: Control = page.get_node_or_null("Margin")
			if body != null:
				_check(body.size.x <= dimensions.x, "%s body exceeds width" % page.name)
			if id == SceneRegistry.PopupId.MUSIC_APP_PLAYER:
				var cover: Control = page.get_node("%CoverPanel")
				_check(cover.size.y <= page.album_stage.size.y + 1, "Artwork must fit stage on short screens")
				_check(page.get_node("%PlayerPlayButton").get_global_rect().end.y < dimensions.y, "Transport controls must remain on screen")
			if id == SceneRegistry.PopupId.MUSIC_APP_PLAYBACK_QUEUE:
				var sheet: Control = page.get_node("Sheet")
				_check(sheet.position.y >= 0 and sheet.get_rect().end.y <= dimensions.y + 1, "Queue must fit screen")
			if id == SceneRegistry.PopupId.COMMON_DIALOG:
				var panel: Control = page.get_node("%Panel")
				_check(panel.size.y > 100 and panel.size.x <= dimensions.x, "Dialog must size to its content")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("/tmp/gdmusic-ui/%s-%d.png" % [page.name, dimensions.x])
			page.queue_free()
			await get_tree().process_frame
	await _test_navigation()
	await _test_mini_feedback()
	print("Music app UI tests: %d failures" % failures.size())
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_navigation() -> void:
	var manager := FakeManager.new()
	var parent := Control.new()
	viewport.add_child(parent)
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button := Button.new()
	parent.add_child(button)
	button.grab_focus()
	var page = PageScript.new()
	parent.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page._popup_open(manager)
	await get_tree().create_timer(0.4).timeout
	_check(page.position.is_zero_approx() and is_equal_approx(page.modulate.a, 1), "Navigation must finish at resting position")
	page.close_popup()
	page.close_popup()
	_check(manager.close_count == 0, "Popup must survive until dismissal animation ends")
	await get_tree().create_timer(0.3).timeout
	_check(manager.close_count == 1, "Repeated back must dismiss exactly once")
	_check(viewport.gui_get_focus_owner() == button, "Dismissal restores previous keyboard focus")
	var early_page = PageScript.new()
	parent.add_child(early_page)
	early_page._popup_open(manager)
	early_page.close_popup()
	await get_tree().process_frame
	_check(manager.close_count == 2, "Immediate back during presentation must close safely")
	parent.queue_free()

func _test_home_feedback(page: Control, dimensions: Vector2i) -> void:
	var buttons: Array[Button] = [page.get_node("%HomeMenuButton"), page.get_node("%SearchButton"), page.get_node("%NewPlaylistButton"), page.get_node("%ImportButton"), page.feature_cards[0].get_node("OpenButton")]
	for button in buttons:
		await _check_button_feedback(button, dimensions.x)
	var row: Control = page.home_list.get_child(3)
	# First generated row is a favorite and has no delete action.
	_check(row.get_node("OpenButton").size.x == row.size.x, "Favorite highlight must cover its full row")
	var scroll := page.home_list.get_parent() as ScrollContainer
	for index in [3, 4]:
		row = page.home_list.get_child(index)
		scroll.ensure_control_visible(row)
		await get_tree().process_frame
		await _check_button_feedback(row.get_node("OpenButton"))
		if index == 4:
			await _check_button_feedback(row.get_node("Margin/Row/DeleteButton"))
	scroll.scroll_vertical = 0

func _check_button_feedback(button: Button, screenshot_width: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	viewport.push_input(motion, true)
	await get_tree().process_frame
	_check(button.is_hovered(), "%s must receive hover at its visual center" % button.name)
	_check(not button.flat, "%s must draw its hover style instead of suppressing it in flat mode" % button.name)
	if screenshot_width > 0 and DisplayServer.get_name() != "headless":
		# Allow the viewport's queued redraw to reach the rendered texture.
		for frame in 3:
			viewport.push_input(motion, true)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(button.get_draw_mode() == BaseButton.DRAW_HOVER, "%s must render the hover state" % button.name)
		viewport.get_texture().get_image().save_png("/tmp/gdmusic-ui/Hover-%s-%d.png" % [button.name, screenshot_width])
	var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
	var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
	_check(hover != null and hover.bg_color.a > 0, "%s must have a visible hover fill" % button.name)
	_check(pressed != null and pressed.bg_color != hover.bg_color, "%s must distinguish press from hover" % button.name)
	var clicks := [0]
	var record_click := func(): clicks[0] += 1
	button.pressed.connect(record_click)
	var click := InputEventMouseButton.new()
	click.position = motion.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	viewport.push_input(click, true)
	_check(button.is_pressed(), "%s must press at its highlighted center" % button.name)
	click = click.duplicate()
	click.pressed = false
	viewport.push_input(click, true)
	_check(clicks[0] == 1, "%s must activate exactly once" % button.name)
	button.pressed.disconnect(record_click)
	button.release_focus()

func _test_mini_feedback() -> void:
	for width in [320, 430]:
		viewport.size = Vector2i(width, 932)
		var mini: Control = preload("res://scenes/ui/music_app/mini_player/music_app_mini_player.tscn").instantiate()
		viewport.add_child(mini)
		for frame in 3:
			await get_tree().process_frame
		mini._update_open_hit_area()
		var open: Button = mini.get_node("%MiniOpenButton")
		var play: Button = mini.get_node("%MiniPlayButton")
		_check(open.get_global_rect().end.x <= play.get_global_rect().position.x, "Mini player open target must not overlap playback")
		for button in [open, play, mini.get_node("%MiniListButton")]:
			await _check_button_feedback(button)
		mini.queue_free()
		await get_tree().process_frame
