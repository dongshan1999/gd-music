class_name MusicAppPlaylistShelf3D
extends Control

signal previous_requested
signal next_requested
signal play_requested
signal playlist_selected(index: int)

const EMPTY_TITLE := "未创建歌单"
const EMPTY_COUNT := "0 首"
const NORMAL_COLOR := Color(0.05, 0.09, 0.13, 1.0)
const SELECTED_COLOR := Color(0.08, 0.28, 0.34, 1.0)
const PLAYING_COLOR := Color(0.18, 0.34, 0.16, 1.0)
const NORMAL_MARK_COLOR := Color(0.72, 0.96, 1.0, 1.0)
const PLAYING_MARK_COLOR := Color(0.78, 1.0, 0.62, 1.0)
const SLOT_OFFSETS := [-2, -1, 0, 1, 2]
const COVER_TEXTURE_SIZE := 128
const REMOTE_ARTWORK_TIMEOUT_SECONDS := 10.0
const REMOTE_ARTWORK_CACHE_DIR := "user://music_app/playlist_shelf_artwork"
const SLOT_NODE_PATHS := [
	"PlaylistShelfContainer/PlaylistShelfViewport/ShelfRoot/CardSlots/CardFarLeft",
	"PlaylistShelfContainer/PlaylistShelfViewport/ShelfRoot/CardSlots/CardLeft",
	"PlaylistShelfContainer/PlaylistShelfViewport/ShelfRoot/CardSlots/CardCenter",
	"PlaylistShelfContainer/PlaylistShelfViewport/ShelfRoot/CardSlots/CardRight",
	"PlaylistShelfContainer/PlaylistShelfViewport/ShelfRoot/CardSlots/CardFarRight"
]

@onready var shelf_viewport: SubViewport = %PlaylistShelfViewport
@onready var playlist_artwork_request: HTTPRequest = %PlaylistArtworkRequest
@onready var shelf_stage: Node3D = %ShelfStage
@onready var shelf_glow_light: OmniLight3D = %ShelfGlowLight
@onready var left_button: Button = %ShelfPreviousButton
@onready var right_button: Button = %ShelfNextButton
@onready var play_button: Button = %ShelfPlayButton
@onready var slot_hit_buttons: Array[Button] = [
	%ShelfFarLeftHitButton,
	%ShelfLeftHitButton,
	%ShelfCenterHitButton,
	%ShelfRightHitButton,
	%ShelfFarRightHitButton
]

var _slots: Array[Node3D] = []
var _slot_base_positions: Array[Vector3] = []
var _slot_base_rotations: Array[Vector3] = []
var _slot_target_scales: Array[Vector3] = []
var _slot_playlist_indices: Array[int] = []
var _selected_index := 0
var _playlist_count := 0
var _playing_playlist_index := -1
var _is_bound := false
var _enabled := true
var _artwork_texture_cache := {}
var _pending_artwork_queue: Array[Dictionary] = []
var _active_artwork_request := {}
var _stage_nodes: Array[MeshInstance3D] = []
var _stage_materials: Array[Material] = []
var _stage_base_positions: Array[Vector3] = []
var _stage_base_rotations: Array[Vector3] = []
var _stage_base_scales: Array[Vector3] = []
var _stage_tint := Color(0.24, 0.92, 1.0, 1.0)
var _target_stage_tint := Color(0.24, 0.92, 1.0, 1.0)
var _selection_pulse := 0.0
var _elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	shelf_viewport.transparent_bg = true
	_cache_stage()
	_cache_slots()
	_bind()

func configure(playlists: Array, selected_index: int, controller, playing_playlist_index: int = -1) -> void:
	var previous_selected_index := _selected_index
	_playlist_count = playlists.size()
	_selected_index = clampi(selected_index, 0, max(0, _playlist_count - 1))
	_playing_playlist_index = playing_playlist_index
	if previous_selected_index != _selected_index:
		_selection_pulse = 1.0

	for slot_index in _slots.size():
		var playlist_index := _selected_index + int(SLOT_OFFSETS[slot_index])
		var slot := _slots[slot_index]
		var hit_button := slot_hit_buttons[slot_index]
		var is_valid := playlist_index >= 0 and playlist_index < playlists.size()
		slot.visible = is_valid
		hit_button.visible = is_valid
		hit_button.disabled = not is_valid
		if not is_valid:
			_set_slot_text(slot, EMPTY_TITLE, EMPTY_COUNT, "")
			continue

		var playlist = playlists[playlist_index]
		var title: String = controller.get_playlist_display_title(playlist) if controller != null else playlist.title
		var count_text: String = controller.format_total_track_count(playlist.count) if controller != null else "%d 首" % playlist.count
		var mark: String = controller.get_playlist_display_mark(playlist) if controller != null else playlist.mark
		_set_slot_text(slot, title, count_text, mark)
		_apply_slot_cover(slot, playlist, controller, playlist_index, title, mark)
		if slot_index == 2:
			_target_stage_tint = _derive_playlist_tint(playlist, controller, title, mark, playlist_index)
		_apply_slot_emphasis(slot, slot_index == 2, playlist_index == _playing_playlist_index)

	left_button.disabled = _playlist_count <= 1 or _selected_index <= 0
	right_button.disabled = _playlist_count <= 1 or _selected_index >= _playlist_count - 1
	play_button.disabled = _playlist_count <= 0

func apply_visualizer_settings(settings: Dictionary) -> void:
	_enabled = bool(settings.get("enabled", true)) and str(settings.get("quality", "medium")) != "off"
	visible = _enabled
	set_process(_enabled)
	if not _enabled:
		release_visualizer_resources()

func release_visualizer_resources() -> void:
	if playlist_artwork_request != null:
		playlist_artwork_request.cancel_request()
	_pending_artwork_queue.clear()
	_active_artwork_request = {}
	_selection_pulse = 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	_selection_pulse = lerpf(_selection_pulse, 0.0, clampf(1.0 - exp(-5.8 * delta), 0.0, 1.0))
	_stage_tint = _stage_tint.lerp(_target_stage_tint, clampf(1.0 - exp(-3.2 * delta), 0.0, 1.0))
	var alpha := clampf(1.0 - exp(-8.0 * delta), 0.0, 1.0)
	for index in _slots.size():
		var slot := _slots[index]
		slot.position = slot.position.lerp(_slot_base_positions[index], alpha)
		slot.rotation = slot.rotation.lerp(_slot_base_rotations[index], alpha)
		slot.scale = slot.scale.lerp(_slot_target_scales[index], alpha)
	_update_stage(delta)

func _bind() -> void:
	if _is_bound:
		return
	_is_bound = true
	left_button.pressed.connect(func(): previous_requested.emit())
	right_button.pressed.connect(func(): next_requested.emit())
	play_button.pressed.connect(func(): play_requested.emit())
	if playlist_artwork_request != null:
		playlist_artwork_request.timeout = REMOTE_ARTWORK_TIMEOUT_SECONDS
		if not playlist_artwork_request.request_completed.is_connected(_on_playlist_artwork_request_completed):
			playlist_artwork_request.request_completed.connect(_on_playlist_artwork_request_completed)
	for index in slot_hit_buttons.size():
		var slot_index := index
		slot_hit_buttons[index].pressed.connect(func(): _on_slot_pressed(slot_index))

func _on_slot_pressed(slot_index: int) -> void:
	var playlist_index := _selected_index + int(SLOT_OFFSETS[slot_index])
	if playlist_index < 0 or playlist_index >= _playlist_count:
		return
	if slot_index == 2:
		play_requested.emit()
		return
	playlist_selected.emit(playlist_index)

func _cache_slots() -> void:
	_slots.clear()
	_slot_base_positions.clear()
	_slot_base_rotations.clear()
	_slot_target_scales.clear()
	_slot_playlist_indices.clear()

	for path in SLOT_NODE_PATHS:
		var slot := get_node(path) as Node3D
		var cover := slot.get_node("Cover") as MeshInstance3D
		if cover != null and cover.material_override is StandardMaterial3D:
			cover.material_override = cover.material_override.duplicate()
		var card_glass := slot.get_node("CardGlass") as MeshInstance3D
		if card_glass != null and card_glass.material_override is StandardMaterial3D:
			card_glass.material_override = card_glass.material_override.duplicate()
		var accent_rail := slot.get_node("CardAccentRail") as MeshInstance3D
		if accent_rail != null and accent_rail.material_override is StandardMaterial3D:
			accent_rail.material_override = accent_rail.material_override.duplicate()
		_slots.append(slot)
		_slot_base_positions.append(slot.position)
		_slot_base_rotations.append(slot.rotation)
		_slot_target_scales.append(slot.scale)
		_slot_playlist_indices.append(-1)

func _cache_stage() -> void:
	_stage_nodes.clear()
	_stage_materials.clear()
	_stage_base_positions.clear()
	_stage_base_rotations.clear()
	_stage_base_scales.clear()
	if shelf_stage == null:
		return

	for child in shelf_stage.get_children():
		if not (child is MeshInstance3D):
			continue
		var stage_node := child as MeshInstance3D
		_stage_nodes.append(stage_node)
		_stage_base_positions.append(stage_node.position)
		_stage_base_rotations.append(stage_node.rotation)
		_stage_base_scales.append(stage_node.scale)
		if stage_node.material_override != null:
			stage_node.material_override = stage_node.material_override.duplicate()
			_stage_materials.append(stage_node.material_override)
		else:
			_stage_materials.append(null)

func _update_stage(delta: float) -> void:
	if shelf_stage == null:
		return
	var playing_pulse := 0.35 if _playing_playlist_index == _selected_index and _selected_index >= 0 else 0.0
	var pulse := clampf(_selection_pulse + playing_pulse, 0.0, 1.0)
	var alpha := clampf(1.0 - exp(-5.5 * delta), 0.0, 1.0)
	shelf_stage.rotation.z = lerpf(shelf_stage.rotation.z, sin(_elapsed * 0.28) * 0.012 + pulse * 0.018, alpha)
	if shelf_glow_light != null:
		shelf_glow_light.light_color = _stage_tint.lerp(PLAYING_MARK_COLOR, playing_pulse)
		shelf_glow_light.light_energy = lerpf(0.85, 1.85, pulse)

	for index in _stage_nodes.size():
		var stage_node := _stage_nodes[index]
		var base_position := _stage_base_positions[index]
		var base_rotation := _stage_base_rotations[index]
		var base_scale := _stage_base_scales[index]
		var phase := float(index) * 0.91
		var wave := sin(_elapsed * (0.34 + float(index) * 0.05) + phase)
		var local_pulse := clampf(pulse * (1.0 - float(index) * 0.08), 0.0, 1.0)
		stage_node.position = stage_node.position.lerp(base_position + Vector3(0.0, local_pulse * 0.025 + wave * 0.006, 0.0), alpha)
		stage_node.rotation = stage_node.rotation.lerp(base_rotation + Vector3(0.0, 0.0, wave * 0.018 + local_pulse * 0.028), alpha)
		stage_node.scale = stage_node.scale.lerp(base_scale * (1.0 + local_pulse * 0.035 + wave * 0.006), alpha)

		var stage_material := _stage_materials[index]
		if stage_material is ShaderMaterial:
			var shader_material := stage_material as ShaderMaterial
			shader_material.set_shader_parameter("tint", _stage_tint)
			shader_material.set_shader_parameter("pulse", local_pulse)
			shader_material.set_shader_parameter("bass", local_pulse * 0.85)
			shader_material.set_shader_parameter("mid", 0.35 + playing_pulse)
			shader_material.set_shader_parameter("treble", 0.45 + _selection_pulse * 0.55)
			shader_material.set_shader_parameter("alpha", lerpf(0.12, 0.34, local_pulse + playing_pulse))
		elif stage_material is StandardMaterial3D:
			var standard_material := stage_material as StandardMaterial3D
			var tint := _stage_tint.lerp(Color(1.0, 0.72, 0.28, 1.0), 0.28 + playing_pulse * 0.34)
			var color := standard_material.albedo_color
			color.r = tint.r
			color.g = tint.g
			color.b = tint.b
			color.a = lerpf(0.12, 0.32, local_pulse + playing_pulse)
			standard_material.albedo_color = color
			standard_material.emission = tint
			standard_material.emission_energy_multiplier = lerpf(0.30, 1.15, local_pulse + playing_pulse)

func _set_slot_text(slot: Node3D, title: String, count_text: String, mark: String) -> void:
	var title_label := slot.get_node("TitleLabel") as Label3D
	var count_label := slot.get_node("CountLabel") as Label3D
	var mark_label := slot.get_node("MarkLabel") as Label3D
	title_label.text = title
	count_label.text = count_text
	mark_label.text = mark.left(2) if not mark.is_empty() else title.left(1)

func _apply_slot_emphasis(slot: Node3D, selected: bool, playing: bool) -> void:
	var cover := slot.get_node("Cover") as MeshInstance3D
	var cover_material := cover.material_override as StandardMaterial3D
	if cover_material == null:
		return
	var card_glass := slot.get_node("CardGlass") as MeshInstance3D
	var card_glass_material := card_glass.material_override as StandardMaterial3D
	var accent_rail := slot.get_node("CardAccentRail") as MeshInstance3D
	var accent_rail_material := accent_rail.material_override as StandardMaterial3D
	var mark_label := slot.get_node("MarkLabel") as Label3D
	var title_label := slot.get_node("TitleLabel") as Label3D
	var count_label := slot.get_node("CountLabel") as Label3D
	var base_tint := _stage_tint
	var rail_tint := base_tint.lerp(Color(1.0, 0.72, 0.28, 1.0), 0.32)
	if playing:
		cover_material.emission_energy_multiplier = 1.35
		cover_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		cover_material.emission = base_tint.lerp(PLAYING_MARK_COLOR, 0.55)
		if card_glass_material != null:
			card_glass_material.albedo_color = Color(0.018, 0.028, 0.022, 0.94)
			card_glass_material.emission = base_tint.lerp(PLAYING_MARK_COLOR, 0.58)
			card_glass_material.emission_energy_multiplier = 1.35
		if accent_rail_material != null:
			accent_rail_material.albedo_color = Color(rail_tint.r, rail_tint.g, rail_tint.b, 0.78)
			accent_rail_material.emission = rail_tint
			accent_rail_material.emission_energy_multiplier = 2.1
		mark_label.modulate = PLAYING_MARK_COLOR
		title_label.modulate = Color(1.0, 1.0, 0.92, 1.0)
		count_label.modulate = Color(0.82, 1.0, 0.70, 1.0)
		return
	if selected:
		cover_material.emission_energy_multiplier = 0.95
		cover_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		cover_material.emission = base_tint
		if card_glass_material != null:
			card_glass_material.albedo_color = Color(0.012, 0.020, 0.030, 0.92)
			card_glass_material.emission = base_tint
			card_glass_material.emission_energy_multiplier = 0.88
		if accent_rail_material != null:
			accent_rail_material.albedo_color = Color(base_tint.r, base_tint.g, base_tint.b, 0.62)
			accent_rail_material.emission = base_tint
			accent_rail_material.emission_energy_multiplier = 1.55
		mark_label.modulate = NORMAL_MARK_COLOR
		title_label.modulate = Color(0.96, 0.99, 1.0, 1.0)
		count_label.modulate = Color(0.66, 0.86, 0.94, 1.0)
		return
	cover_material.emission_energy_multiplier = 0.18
	cover_material.albedo_color = Color(0.86, 0.91, 0.94, 1.0)
	cover_material.emission = base_tint.darkened(0.35)
	if card_glass_material != null:
		card_glass_material.albedo_color = Color(0.006, 0.011, 0.017, 0.84)
		card_glass_material.emission = base_tint.darkened(0.34)
		card_glass_material.emission_energy_multiplier = 0.22
	if accent_rail_material != null:
		accent_rail_material.albedo_color = Color(base_tint.r, base_tint.g, base_tint.b, 0.22)
		accent_rail_material.emission = base_tint
		accent_rail_material.emission_energy_multiplier = 0.48
	mark_label.modulate = NORMAL_MARK_COLOR
	title_label.modulate = Color(0.88, 0.94, 0.98, 1.0)
	count_label.modulate = Color(0.52, 0.70, 0.78, 1.0)

func _apply_slot_cover(
	slot: Node3D,
	playlist,
	controller,
	playlist_index: int,
	title: String,
	mark: String
) -> void:
	var slot_index := _slots.find(slot)
	if slot_index >= 0:
		_slot_playlist_indices[slot_index] = playlist_index

	var cover := slot.get_node("Cover") as MeshInstance3D
	var cover_material := cover.material_override as StandardMaterial3D
	var mark_label := slot.get_node("MarkLabel") as Label3D
	if cover_material == null:
		return

	var artwork_source := _get_playlist_artwork_source(playlist, controller)
	var texture := _resolve_cached_artwork_texture(artwork_source)
	var has_real_cover := texture != null
	if texture == null:
		texture = _make_playlist_placeholder_texture(title, mark, playlist_index)
	cover_material.albedo_texture = texture
	cover_material.roughness = 0.26 if has_real_cover else 0.34
	mark_label.visible = not has_real_cover

	if not has_real_cover and _is_remote_artwork(artwork_source):
		_queue_remote_artwork(slot_index, playlist_index, artwork_source)

func _get_playlist_artwork_source(playlist, controller) -> String:
	if playlist == null or controller == null:
		return ""
	for track_index in playlist.tracks:
		var track = controller.get_track(int(track_index))
		if track == null:
			continue
		var artwork_source := str(track.artwork_url).strip_edges()
		if not artwork_source.is_empty():
			return artwork_source
	return ""

func _resolve_cached_artwork_texture(source: String) -> Texture2D:
	if source.is_empty():
		return null
	if _artwork_texture_cache.has(source):
		return _artwork_texture_cache[source] as Texture2D
	if _is_remote_artwork(source):
		var cached_texture := _load_local_artwork_texture(_get_remote_cache_path(source))
		if cached_texture != null:
			_artwork_texture_cache[source] = cached_texture
			return cached_texture
		return null
	var local_texture := _load_local_artwork_texture(source)
	if local_texture != null:
		_artwork_texture_cache[source] = local_texture
	return local_texture

func _load_local_artwork_texture(path: String) -> Texture2D:
	if path.is_empty() or not (path.begins_with("res://") or path.begins_with("user://")):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _queue_remote_artwork(slot_index: int, playlist_index: int, source: String) -> void:
	if playlist_artwork_request == null or source.is_empty():
		return
	for request in _pending_artwork_queue:
		if str(request.get("source", "")) == source and int(request.get("playlist_index", -1)) == playlist_index:
			return
	if str(_active_artwork_request.get("source", "")) == source:
		return
	_pending_artwork_queue.append({
		"slot_index": slot_index,
		"playlist_index": playlist_index,
		"source": source
	})
	_process_next_artwork_request()

func _process_next_artwork_request() -> void:
	if playlist_artwork_request == null:
		return
	if not _active_artwork_request.is_empty():
		return
	if _pending_artwork_queue.is_empty():
		return
	_active_artwork_request = _pending_artwork_queue.pop_front()
	var source := str(_active_artwork_request.get("source", ""))
	var err := playlist_artwork_request.request(source)
	if err != OK:
		_active_artwork_request = {}
		_process_next_artwork_request()

func _on_playlist_artwork_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var request := _active_artwork_request.duplicate()
	_active_artwork_request = {}
	var source := str(request.get("source", ""))
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300 and not body.is_empty():
		var image := _load_image_from_buffer(body, source)
		if image != null and not image.is_empty():
			_ensure_remote_cache_dir()
			image.save_png(_get_remote_cache_path(source))
			var texture := ImageTexture.create_from_image(image)
			_artwork_texture_cache[source] = texture
			_apply_downloaded_artwork_to_visible_slot(
				int(request.get("slot_index", -1)),
				int(request.get("playlist_index", -1)),
				texture
			)
	_process_next_artwork_request()

func _apply_downloaded_artwork_to_visible_slot(slot_index: int, playlist_index: int, texture: Texture2D) -> void:
	if texture == null or slot_index < 0 or slot_index >= _slots.size():
		return
	if _slot_playlist_indices[slot_index] != playlist_index:
		return
	var slot := _slots[slot_index]
	var cover := slot.get_node("Cover") as MeshInstance3D
	var cover_material := cover.material_override as StandardMaterial3D
	var mark_label := slot.get_node("MarkLabel") as Label3D
	if cover_material == null:
		return
	cover_material.albedo_texture = texture
	cover_material.roughness = 0.26
	if slot_index == 2:
		_target_stage_tint = _extract_tint_from_texture(texture, _target_stage_tint)
	mark_label.visible = false

func _load_image_from_buffer(buffer: PackedByteArray, source: String) -> Image:
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
		err = image.load_png_from_buffer(buffer)
		if err != OK:
			err = image.load_jpg_from_buffer(buffer)
		if err != OK:
			err = image.load_webp_from_buffer(buffer)
	return image if err == OK else null

func _make_playlist_placeholder_texture(title: String, mark: String, playlist_index: int) -> Texture2D:
	var seed_text := "%s|%s|%s" % [title, mark, str(playlist_index)]
	var seed_value: int = absi(int(hash(seed_text)))
	var color_a := Color.from_hsv(float(seed_value % 360) / 360.0, 0.68, 0.72)
	var color_b := Color.from_hsv(fposmod(float(seed_value) / 9.0, 360.0) / 360.0, 0.50, 0.40)
	var image := Image.create_empty(COVER_TEXTURE_SIZE, COVER_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(COVER_TEXTURE_SIZE * 0.5, COVER_TEXTURE_SIZE * 0.5)
	for y in COVER_TEXTURE_SIZE:
		for x in COVER_TEXTURE_SIZE:
			var uv := Vector2(float(x) / float(COVER_TEXTURE_SIZE - 1), float(y) / float(COVER_TEXTURE_SIZE - 1))
			var dist := center.distance_to(Vector2(x, y)) / float(COVER_TEXTURE_SIZE)
			var ring := 0.5 + 0.5 * sin(dist * 56.0 + float(seed_value % 29) * 0.21)
			var diagonal := clampf((uv.x + uv.y) * 0.5, 0.0, 1.0)
			var color := color_a.lerp(color_b, diagonal)
			color = color.lerp(Color(0.01, 0.018, 0.026), smoothstep(0.20, 0.88, dist) * 0.42)
			color = color.lightened(ring * 0.10)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _derive_playlist_tint(playlist, controller, title: String, mark: String, playlist_index: int) -> Color:
	var artwork_source := _get_playlist_artwork_source(playlist, controller)
	var texture := _resolve_cached_artwork_texture(artwork_source)
	if texture != null:
		return _extract_tint_from_texture(texture, _make_stable_playlist_tint(title, mark, playlist_index))
	return _make_stable_playlist_tint(title, mark, playlist_index)

func _extract_tint_from_texture(texture: Texture2D, fallback: Color) -> Color:
	if texture == null:
		return fallback
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return fallback
	var working: Image = image.duplicate()
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	if working.get_width() > 42 or working.get_height() > 42:
		working.resize(42, 42, Image.INTERPOLATE_LANCZOS)

	var total := Vector3.ZERO
	var weight_total := 0.0
	for y in working.get_height():
		for x in working.get_width():
			var color: Color = working.get_pixel(x, y)
			var max_channel := maxf(color.r, maxf(color.g, color.b))
			var min_channel := minf(color.r, minf(color.g, color.b))
			var saturation := max_channel - min_channel
			var luma := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
			var weight := color.a * clampf(0.20 + saturation * 2.2, 0.20, 1.0) * (1.0 - smoothstep(0.82, 1.0, luma))
			total += Vector3(color.r, color.g, color.b) * weight
			weight_total += weight
	if weight_total <= 0.001:
		return fallback
	var averaged := Color(total.x / weight_total, total.y / weight_total, total.z / weight_total, 1.0)
	return Color.from_hsv(averaged.h, clampf(averaged.s + 0.18, 0.48, 0.88), clampf(maxf(averaged.v, 0.70), 0.62, 0.96), 1.0)

func _make_stable_playlist_tint(title: String, mark: String, playlist_index: int) -> Color:
	var seed_text := "%s|%s|%s" % [title, mark, str(playlist_index)]
	var seed_value: int = absi(int(hash(seed_text)))
	return Color.from_hsv(float(seed_value % 360) / 360.0, 0.72, 0.88, 1.0)

func _is_remote_artwork(source: String) -> bool:
	return source.begins_with("http://") or source.begins_with("https://")

func _get_remote_cache_path(source: String) -> String:
	var cache_key: int = absi(int(hash(source)))
	return "%s/%s.png" % [REMOTE_ARTWORK_CACHE_DIR, str(cache_key)]

func _ensure_remote_cache_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("music_app/playlist_shelf_artwork")
