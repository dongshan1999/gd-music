extends Node

const PlayerPageScene := preload("res://scenes/ui/music_app/player/music_app_player_page.tscn")
const ShowcaseControllerScript := preload("res://scripts/ui/music_app/music_app_showcase.gd")

var _failures := PackedStringArray()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Control.new()
	host.size = Vector2(430, 932)
	add_child(host)
	var player_page: MusicAppPlayerView = PlayerPageScene.instantiate() as MusicAppPlayerView
	var controller := ShowcaseControllerScript.new()
	player_page.on_popup_shown()
	player_page.setup(controller)
	host.add_child(player_page)
	player_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame

	var album_stage := player_page.get_node("PlayerMargin/PlayerVBox/CoverStage/AlbumStage") as Control
	var lyrics_stage := player_page.get_node("PlayerMargin/PlayerVBox/CoverStage/LyricsStage") as Control
	_check(album_stage != null and album_stage.visible, "album stage should be visible after deferred setup")
	_check(lyrics_stage != null and not lyrics_stage.visible, "lyrics stage should be hidden after deferred setup")

	player_page._lyrics = [
		{"time": 0, "text": "First line"},
		{"time": 30, "text": "Middle line"},
		{"time": 60, "text": "Last line"},
	]
	player_page._is_lyrics_visible = true
	player_page._apply_content_view_visibility()
	player_page._rebuild_lyric_lines()
	await get_tree().process_frame
	await get_tree().process_frame

	var lyrics_scroll := player_page.get_node("PlayerMargin/PlayerVBox/CoverStage/LyricsStage/LyricsMargin/LyricsScroll") as ScrollContainer
	var lyrics_time_cursor := player_page.get_node("PlayerMargin/PlayerVBox/CoverStage/LyricsStage/LyricsTimeCursor") as Control
	var line_labels: Array[Label] = player_page._lyric_line_labels
	var scroll_center_y := lyrics_scroll.get_global_rect().get_center().y
	_check(not lyrics_time_cursor.visible, "time cursor should stay hidden outside content dragging")
	_check(
		is_equal_approx(line_labels[0].get_global_rect().get_center().y, scroll_center_y),
		"first lyric should align with the center marker at the top scroll boundary"
	)
	var max_scroll := roundi(maxf(0.0, lyrics_scroll.get_v_scroll_bar().max_value - lyrics_scroll.get_v_scroll_bar().page))
	lyrics_scroll.scroll_vertical = max_scroll
	await get_tree().process_frame
	_check(
		is_equal_approx(line_labels[line_labels.size() - 1].get_global_rect().get_center().y, scroll_center_y),
		"last lyric should align with the center marker at the bottom scroll boundary"
	)

	for failure in _failures:
		push_error(failure)
	print("Music app player lifecycle tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
