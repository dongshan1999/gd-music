class_name MusicAppMiniPlayerView
extends Panel

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const REMOTE_ARTWORK_TIMEOUT_SECONDS := 10.0
const DEFAULT_COVER_BG := Color(0.203922, 0.215686, 0.247059, 1)
const DEFAULT_COVER_FG := Color(0.968627, 0.968627, 0.972549, 1)

var _controller: MusicAppShowcaseController
var _mini_player_controller: MusicAppMiniPlayerController
var _is_bound := false
var _artwork_source := ""
var _artwork_request_id := 0
var _artwork_texture_cache := {}

@onready var mini_cover_panel: Panel = %MiniCoverPanel
@onready var mini_cover_texture_rect: TextureRect = %MiniCoverTextureRect
@onready var mini_cover_mark_label: Label = %MiniCoverMarkLabel
@onready var mini_track_label: Label = %MiniTrackLabel
@onready var mini_play_ring: Control = %MiniPlayRing
@onready var mini_play_button: Button = %MiniPlayButton
@onready var mini_list_button: Button = %MiniListButton
@onready var mini_open_button: Button = %MiniOpenButton

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_mini_player_controller = MusicAppMiniPlayerController.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	mini_play_button.pressed.connect(_toggle_playback)
	mini_list_button.pressed.connect(_show_playback_queue)
	mini_open_button.pressed.connect(_open_player_from_current)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	if not _mini_player_controller.has_tracks():
		_reset_cover_state()
		mini_track_label.text = tr("music_app.mini_player.empty")
		mini_play_ring.progress = 0.0
		MusicAppIconsType.apply_icon_button(mini_play_button, MusicAppIconsType.PLAY)
		MusicAppIconsType.apply_icon_button(mini_list_button, MusicAppIconsType.PLAYLIST)
		return

	var track: TrackData = _mini_player_controller.get_current_track()
	_refresh_cover(track)
	mini_track_label.text = "%s - %s" % [track.title, _mini_player_controller.get_track_display_artist(track)]
	mini_play_ring.progress = _mini_player_controller.get_playback_progress_ratio()
	MusicAppIconsType.apply_icon_button(
		mini_play_button,
		MusicAppIconsType.PAUSE
		if _mini_player_controller.is_playing()
		else MusicAppIconsType.PLAY
	)
	MusicAppIconsType.apply_icon_button(mini_list_button, MusicAppIconsType.PLAYLIST)

func _toggle_playback() -> void:
	if not _mini_player_controller.has_tracks():
		return
	_mini_player_controller.toggle_playback()

func _show_playback_queue() -> void:
	if not _mini_player_controller.has_tracks():
		return
	_mini_player_controller.show_playback_queue()

func _open_player_from_current() -> void:
	_mini_player_controller.open_player_page()

func _refresh_cover(track: TrackData) -> void:
	if track == null:
		_reset_cover_state()
		return

	_apply_cover_placeholder(track)
	var next_artwork_source := track.artwork_url.strip_edges()
	if next_artwork_source.is_empty():
		_artwork_source = ""
		mini_cover_texture_rect.texture = null
		mini_cover_texture_rect.visible = false
		return

	if next_artwork_source == _artwork_source and mini_cover_texture_rect.texture != null:
		mini_cover_texture_rect.visible = true
		mini_cover_mark_label.visible = false
		return

	_artwork_source = next_artwork_source
	_artwork_request_id += 1
	mini_cover_texture_rect.texture = null
	mini_cover_texture_rect.visible = false
	mini_cover_mark_label.visible = true

	if _artwork_texture_cache.has(next_artwork_source):
		_display_cover_texture(_artwork_texture_cache[next_artwork_source] as Texture2D)
		return

	call_deferred("_load_cover_artwork", next_artwork_source, _artwork_request_id)

func _reset_cover_state() -> void:
	_artwork_source = ""
	mini_cover_texture_rect.texture = null
	mini_cover_texture_rect.visible = false
	mini_cover_mark_label.visible = true
	mini_cover_mark_label.text = ""
	_apply_cover_colors(DEFAULT_COVER_BG, DEFAULT_COVER_FG)

func _apply_cover_placeholder(track: TrackData) -> void:
	mini_cover_mark_label.visible = true
	mini_cover_mark_label.text = track.mark if not track.mark.is_empty() else track.title.left(1)
	_apply_cover_colors(track.tertiary, track.secondary)

func _apply_cover_colors(background_color: Color, foreground_color: Color) -> void:
	var panel_style := mini_cover_panel.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		var style_copy := (panel_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		style_copy.bg_color = background_color
		mini_cover_panel.add_theme_stylebox_override("panel", style_copy)
	mini_cover_mark_label.add_theme_color_override("font_color", foreground_color)

func _display_cover_texture(texture: Texture2D) -> void:
	if texture == null:
		mini_cover_texture_rect.texture = null
		mini_cover_texture_rect.visible = false
		mini_cover_mark_label.visible = true
		return

	mini_cover_texture_rect.texture = texture
	mini_cover_texture_rect.visible = true
	mini_cover_mark_label.visible = false

func _load_cover_artwork(source: String, request_id: int) -> void:
	var texture := await _resolve_cover_texture(source, request_id)
	if request_id != _artwork_request_id or source != _artwork_source:
		return
	if texture == null:
		return
	_artwork_texture_cache[source] = texture
	_display_cover_texture(texture)

func _resolve_cover_texture(source: String, request_id: int) -> Texture2D:
	if source.begins_with("http://") or source.begins_with("https://"):
		return await _load_remote_cover_texture(source, request_id)
	return _load_local_cover_texture(source)

func _load_local_cover_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _load_remote_cover_texture(url: String, request_id: int) -> Texture2D:
	if _controller == null:
		return null

	var request := HTTPRequest.new()
	request.timeout = REMOTE_ARTWORK_TIMEOUT_SECONDS
	_controller.add_child(request)

	var err := request.request(url)
	if err != OK:
		request.queue_free()
		return null

	var signal_result: Array = await request.request_completed
	request.queue_free()
	if request_id != _artwork_request_id or url != _artwork_source:
		return null

	var result_code := int(signal_result[0])
	var response_code := int(signal_result[1])
	var body: PackedByteArray = signal_result[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return null
	if response_code < 200 or response_code >= 300:
		return null
	if body.is_empty():
		return null

	return _load_texture_from_buffer(body, url)

func _load_texture_from_buffer(buffer: PackedByteArray, source: String) -> Texture2D:
	var image := Image.new()
	var lower_source := source.to_lower()
	var err := ERR_FILE_UNRECOGNIZED

	if lower_source.ends_with(".png"):
		err = image.load_png_from_buffer(buffer)
	elif lower_source.ends_with(".jpg") or lower_source.ends_with(".jpeg"):
		err = image.load_jpg_from_buffer(buffer)
	elif lower_source.ends_with(".webp"):
		err = image.load_webp_from_buffer(buffer)
	else:
		for loader in [
			func() -> int: return image.load_png_from_buffer(buffer),
			func() -> int: return image.load_jpg_from_buffer(buffer),
			func() -> int: return image.load_webp_from_buffer(buffer),
		]:
			err = loader.call()
			if err == OK:
				break

	if err != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
