class_name MusicAppLayout
extends RefCounted

static func show_page(controller, page: int) -> void:
	controller.home_page.visible = page == controller._page_home()
	controller.playlist_page.visible = page == controller._page_playlist()
	controller.player_page.visible = page == controller._page_player()
	if controller.local_music_page != null:
		controller.local_music_page.visible = page == controller._page_local_music()
	if controller.local_scan_page != null:
		controller.local_scan_page.visible = page == controller._page_local_scan()
	controller.mini_player.visible = page != controller._page_player() and page != controller._page_local_scan()

static func layout_preview(scene_size: Vector2, controller, home_ui, outer_margin: float) -> void:
	if controller.preview_root == null:
		return

	controller.preview_root.offset_left = outer_margin
	controller.preview_root.offset_top = outer_margin
	controller.preview_root.offset_right = -outer_margin
	controller.preview_root.offset_bottom = -outer_margin

	var preview_size := Vector2(
		maxf(0.0, scene_size.x - outer_margin * 2.0),
		maxf(0.0, scene_size.y - outer_margin * 2.0)
	)
	_update_feature_grid_layout(preview_size, home_ui)

static func _update_feature_grid_layout(preview_size: Vector2, home_ui) -> void:
	if home_ui.feature_grid == null:
		return

	var available_width: float = preview_size.x - 28.0
	var use_two_columns: bool = available_width < 390.0
	home_ui.feature_grid.columns = 2 if use_two_columns else 4

	var card_height: float = 108.0 if use_two_columns else 120.0
	for card in home_ui.feature_cards:
		card.custom_minimum_size = Vector2(86, card_height)
