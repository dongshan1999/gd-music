class_name MusicAppCoverParticleStage
extends Node3D

signal stage_tint_changed(tint: Color)

const LOW_GRID := 75
const MEDIUM_GRID := 119
const HIGH_GRID := 183
const PLANE_SIZE := 2.86
const BASE_DOT_SIZE := 0.008
const RIPPLE_DURATION := 1.25
const TEXTURE_SIZE := 128
const REMOTE_ARTWORK_TIMEOUT_SECONDS := 10.0
const REMOTE_ARTWORK_CACHE_DIR := "user://music_app/visualizer_artwork"
const MODE_MINERADIO := "mineradio"

@onready var cover_particle_mesh: MeshInstance3D = %CoverParticleMesh
@onready var cover_bloom_mesh: MeshInstance3D = %CoverBloomMesh
@onready var cover_artwork_request: HTTPRequest = %CoverArtworkRequest

var _quality := "medium"
var _grid := 0
var _elapsed := 0.0
var _bass := 0.0
var _mid := 0.0
var _treble := 0.0
var _volume := 0.0
var _kick := 0.0
var _vocal := 0.0
var _instrument_mid := 0.0
var _treble_air := 0.0
var _rms := 0.0
var _energy_onset := 0.0
var _beat := 0.0
var _burst := 0.0
var _activity := 1.0
var _bloom_scale := 1.0
var _particle_scale := 1.0
var _ripple_cursor := 0
var _ripples: Array[Vector4] = [
	Vector4(0.0, 0.0, RIPPLE_DURATION + 1.0, 0.0),
	Vector4(0.0, 0.0, RIPPLE_DURATION + 1.0, 0.0),
	Vector4(0.0, 0.0, RIPPLE_DURATION + 1.0, 0.0),
	Vector4(0.0, 0.0, RIPPLE_DURATION + 1.0, 0.0)
]
var _cover_texture: Texture2D
var _previous_cover_texture: Texture2D
var _edge_texture: Texture2D
var _depth_texture: Texture2D
var _has_real_cover := false
var _main_material: ShaderMaterial
var _bloom_material: ShaderMaterial
var _last_track_key := ""
var _color_mix := 1.0
var _shape_preset := 0.0
var _artwork_source := ""
var _artwork_request_id := 0
var _requested_artwork_source := ""
var _requested_artwork_id := 0
var _artwork_texture_cache := {}
var _tint_color := Color(0.44, 0.92, 1.0, 1.0)
var _current_track = null

func _ready() -> void:
	_duplicate_materials()
	_setup_artwork_request()
	_cover_texture = _make_default_cover_texture("Mineradio", "Godot", "M")
	_previous_cover_texture = _cover_texture
	_tint_color = _make_source_tint(null)
	_update_support_textures_from_cover()
	configure_quality(_quality)
	_apply_all_shader_parameters()

func configure_quality(quality: String) -> void:
	_quality = quality
	var next_grid := MEDIUM_GRID
	match quality:
		"low":
			next_grid = LOW_GRID
		"high":
			next_grid = HIGH_GRID
		"off":
			next_grid = LOW_GRID
		_:
			next_grid = MEDIUM_GRID
	if next_grid == _grid and cover_particle_mesh.mesh != null:
		return
	_grid = next_grid
	_build_particle_mesh(_grid)

func apply_visualizer_settings(settings: Dictionary) -> void:
	var enabled := bool(settings.get("enabled", true))
	var mode := str(settings.get("mode", MODE_MINERADIO))
	var quality := str(settings.get("quality", "medium"))
	visible = enabled and quality != "off" and mode == MODE_MINERADIO
	if not visible:
		release_visualizer_resources()
	configure_quality(quality)
	_particle_scale = clampf(float(settings.get("particles", 1.0)), 0.25, 1.5)
	_bloom_scale = clampf(float(settings.get("bloom", 1.0)), 0.0, 0.88)
	_apply_all_shader_parameters()

func release_visualizer_resources() -> void:
	if cover_artwork_request != null:
		cover_artwork_request.cancel_request()
	_requested_artwork_source = ""
	_requested_artwork_id = 0
	_beat = 0.0
	_burst = 0.0
	_activity = 0.0
	for index in _ripples.size():
		_ripples[index] = Vector4(0.0, 0.0, RIPPLE_DURATION + 1.0, 0.0)
	_apply_motion_parameters()

func set_playback_active(active: bool) -> void:
	_activity = 1.0 if active else 0.24

func apply_track(track) -> void:
	var key := _track_key(track)
	if key == _last_track_key:
		return
	_last_track_key = key
	_current_track = track
	_previous_cover_texture = _cover_texture if _cover_texture != null else _make_default_cover_texture("", "", "")
	_cover_texture = _make_texture_for_track(track)
	_shape_preset = _shape_preset_for_track(track)
	_set_tint_color(_derive_track_tint(track, _cover_texture, _has_real_cover))
	_update_support_textures_from_cover()
	_color_mix = 0.0
	trigger_burst(0.72)
	_apply_texture_parameters()

func get_stage_tint() -> Color:
	return _tint_color

func trigger_burst(strength: float) -> void:
	_burst = maxf(_burst, clampf(strength, 0.0, 1.0))
	trigger_ripple(strength)

func trigger_favorite_feedback(liked: bool) -> void:
	var strength := 0.58 if liked else 0.28
	_burst = maxf(_burst, strength)
	trigger_ripple(strength, Vector2(0.42, -0.34))

func trigger_ripple(strength: float, ripple_position := Vector2.ZERO) -> void:
	_ripples[_ripple_cursor] = Vector4(
		clampf(ripple_position.x, -1.0, 1.0),
		clampf(ripple_position.y, -1.0, 1.0),
		0.0,
		clampf(strength, 0.08, 1.0)
	)
	_ripple_cursor = (_ripple_cursor + 1) % _ripples.size()

func update_stage(
	delta: float,
	bass: float,
	mid: float,
	treble: float,
	volume: float,
	beat_flash: float,
	track_transition: float,
	activity: float,
	bloom_scale: float,
	particle_scale: float,
	kick: float = -1.0,
	vocal: float = -1.0,
	instrument_mid: float = -1.0,
	treble_air: float = -1.0,
	rms: float = -1.0,
	energy_onset: float = -1.0
) -> void:
	if not visible:
		return
	_elapsed += delta
	_bass = bass
	_mid = mid
	_treble = treble
	_volume = volume
	_kick = kick if kick >= 0.0 else bass
	_vocal = vocal if vocal >= 0.0 else mid
	_instrument_mid = instrument_mid if instrument_mid >= 0.0 else mid
	_treble_air = treble_air if treble_air >= 0.0 else treble
	_rms = rms if rms >= 0.0 else volume
	_energy_onset = energy_onset if energy_onset >= 0.0 else 0.0
	_beat = maxf(beat_flash, _beat)
	_burst = maxf(_burst, track_transition)
	_activity = activity
	_bloom_scale = bloom_scale
	_particle_scale = particle_scale
	_color_mix = lerpf(_color_mix, 1.0, clampf(1.0 - exp(-3.4 * delta), 0.0, 1.0))

	for index in _ripples.size():
		var ripple := _ripples[index]
		if ripple.z <= RIPPLE_DURATION:
			ripple.z += delta
			ripple.w *= pow(0.50, delta)
			_ripples[index] = ripple

	_apply_motion_parameters()
	_beat = lerpf(_beat, 0.0, clampf(1.0 - exp(-7.5 * delta), 0.0, 1.0))
	_burst = lerpf(_burst, 0.0, clampf(1.0 - exp(-4.8 * delta), 0.0, 1.0))

func _duplicate_materials() -> void:
	if cover_particle_mesh.material_override is ShaderMaterial:
		cover_particle_mesh.material_override = cover_particle_mesh.material_override.duplicate()
		_main_material = cover_particle_mesh.material_override as ShaderMaterial
	if cover_bloom_mesh.material_override is ShaderMaterial:
		cover_bloom_mesh.material_override = cover_bloom_mesh.material_override.duplicate()
		_bloom_material = cover_bloom_mesh.material_override as ShaderMaterial

func _build_particle_mesh(grid: int) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var half := PLANE_SIZE * 0.5
	var step := PLANE_SIZE / float(maxi(1, grid - 1))
	var dot_size := minf(BASE_DOT_SIZE, step * 0.42)
	var vertex_index := 0

	for y in grid:
		for x in grid:
			var u := (float(x) + 0.5) / float(grid)
			var v := (float(y) + 0.5) / float(grid)
			var center := Vector3(
				lerpf(-half, half, float(x) / float(maxi(1, grid - 1))),
				lerpf(half, -half, float(y) / float(maxi(1, grid - 1))),
				0.0
			)
			var random_value := _random_from_uv(u, v)
			var color := Color(1.0, 1.0, 1.0, random_value)

			vertices.append(center + Vector3(-dot_size, -dot_size, 0.0))
			vertices.append(center + Vector3(dot_size, -dot_size, 0.0))
			vertices.append(center + Vector3(dot_size, dot_size, 0.0))
			vertices.append(center + Vector3(-dot_size, dot_size, 0.0))

			for _corner_index in 4:
				uvs.append(Vector2(u, v))
				colors.append(color)
			uv2s.append(Vector2(0.0, 0.0))
			uv2s.append(Vector2(1.0, 0.0))
			uv2s.append(Vector2(1.0, 1.0))
			uv2s.append(Vector2(0.0, 1.0))

			indices.append(vertex_index)
			indices.append(vertex_index + 1)
			indices.append(vertex_index + 2)
			indices.append(vertex_index)
			indices.append(vertex_index + 2)
			indices.append(vertex_index + 3)
			vertex_index += 4

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	cover_particle_mesh.mesh = mesh
	cover_bloom_mesh.mesh = mesh

func _apply_all_shader_parameters() -> void:
	_apply_texture_parameters()
	_apply_motion_parameters()

func _apply_texture_parameters() -> void:
	_set_shader_parameter("cover_texture", _cover_texture)
	_set_shader_parameter("previous_cover_texture", _previous_cover_texture)
	_set_shader_parameter("edge_texture", _edge_texture)
	_set_shader_parameter("depth_texture", _depth_texture)
	_set_shader_parameter("has_cover", 1.0 if _has_real_cover else 0.0)
	_set_shader_parameter("color_mix", _color_mix)
	_set_shader_parameter("shape_preset", _shape_preset)
	_set_shader_parameter("tint_color", _tint_color)

func _apply_motion_parameters() -> void:
	var point_scale := clampf(_particle_scale, 0.25, 1.5)
	_set_shader_parameter("time", _elapsed)
	_set_shader_parameter("bass", _bass)
	_set_shader_parameter("mid", _mid)
	_set_shader_parameter("treble", _treble)
	_set_shader_parameter("kick", _kick)
	_set_shader_parameter("vocal", _vocal)
	_set_shader_parameter("instrument_mid", _instrument_mid)
	_set_shader_parameter("treble_air", _treble_air)
	_set_shader_parameter("rms", _rms)
	_set_shader_parameter("energy_onset", _energy_onset)
	_set_shader_parameter("beat", _beat)
	_set_shader_parameter("energy", _volume)
	_set_shader_parameter("burst", _burst)
	_set_shader_parameter("activity", _activity)
	_set_shader_parameter("point_scale", point_scale)
	_set_shader_parameter("bloom_strength", _bloom_scale)
	_set_shader_parameter("color_mix", _color_mix)
	for index in _ripples.size():
		_set_shader_parameter("ripple%s" % index, _ripples[index])

func _set_shader_parameter(parameter_name: StringName, value: Variant) -> void:
	if _main_material != null:
		_main_material.set_shader_parameter(parameter_name, value)
	if _bloom_material != null:
		_bloom_material.set_shader_parameter(parameter_name, value)

func _make_texture_for_track(track) -> Texture2D:
	if track != null:
		var artwork_url := str(track.artwork_url).strip_edges()
		_artwork_source = artwork_url
		_artwork_request_id += 1
		var artwork_texture := _resolve_cached_artwork_texture(artwork_url)
		if artwork_texture != null:
			_has_real_cover = true
			return artwork_texture
		_has_real_cover = false
		if _is_remote_artwork(artwork_url):
			call_deferred("_request_remote_artwork", artwork_url, _artwork_request_id)
		return _make_default_cover_texture(str(track.title), str(track.artist), str(track.mark))
	_has_real_cover = false
	_artwork_source = ""
	_artwork_request_id += 1
	return _make_default_cover_texture("", "", "")

func _try_load_artwork_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not (path.begins_with("res://") or path.begins_with("user://")):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _setup_artwork_request() -> void:
	if cover_artwork_request == null:
		return
	cover_artwork_request.timeout = REMOTE_ARTWORK_TIMEOUT_SECONDS
	if not cover_artwork_request.request_completed.is_connected(_on_cover_artwork_request_completed):
		cover_artwork_request.request_completed.connect(_on_cover_artwork_request_completed)

func _resolve_cached_artwork_texture(source: String) -> Texture2D:
	if source.is_empty():
		return null
	if _artwork_texture_cache.has(source):
		return _artwork_texture_cache[source] as Texture2D
	if _is_remote_artwork(source):
		var cached_texture := _try_load_artwork_texture(_get_remote_cache_path(source))
		if cached_texture != null:
			_artwork_texture_cache[source] = cached_texture
			return cached_texture
		return null
	var local_texture := _try_load_artwork_texture(source)
	if local_texture != null:
		_artwork_texture_cache[source] = local_texture
	return local_texture

func _request_remote_artwork(source: String, request_id: int) -> void:
	if cover_artwork_request == null:
		return
	if source != _artwork_source or request_id != _artwork_request_id:
		return
	if _artwork_texture_cache.has(source):
		_apply_remote_artwork_texture(source, _artwork_texture_cache[source] as Texture2D, request_id)
		return

	cover_artwork_request.cancel_request()
	_requested_artwork_source = source
	_requested_artwork_id = request_id
	var err := cover_artwork_request.request(source)
	if err != OK:
		_requested_artwork_source = ""
		_requested_artwork_id = 0

func _on_cover_artwork_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var source := _requested_artwork_source
	var request_id := _requested_artwork_id
	_requested_artwork_source = ""
	_requested_artwork_id = 0
	if source.is_empty() or source != _artwork_source or request_id != _artwork_request_id:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if response_code < 200 or response_code >= 300:
		return
	if body.is_empty():
		return

	var image := _load_image_from_buffer(body, source)
	if image == null or image.is_empty():
		return

	_ensure_remote_cache_dir()
	var cache_path := _get_remote_cache_path(source)
	image.save_png(cache_path)
	var texture := ImageTexture.create_from_image(image)
	_artwork_texture_cache[source] = texture
	_apply_remote_artwork_texture(source, texture, request_id)

func _apply_remote_artwork_texture(source: String, texture: Texture2D, request_id: int) -> void:
	if texture == null:
		return
	if source != _artwork_source or request_id != _artwork_request_id:
		return
	_previous_cover_texture = _cover_texture if _cover_texture != null else _make_default_cover_texture("", "", "")
	_cover_texture = texture
	_has_real_cover = true
	_set_tint_color(_derive_track_tint(_current_track, _cover_texture, true))
	_update_support_textures_from_cover()
	_color_mix = 0.0
	trigger_burst(0.72)
	_apply_texture_parameters()

func _update_support_textures_from_cover() -> void:
	var image := _get_cover_image_for_support()
	if image == null or image.is_empty():
		image = _make_default_support_source()
	_edge_texture = ImageTexture.create_from_image(_make_edge_image(image))
	_depth_texture = ImageTexture.create_from_image(_make_depth_image(image))

func _get_cover_image_for_support() -> Image:
	if _cover_texture == null:
		return null
	var image := _cover_texture.get_image()
	if image == null or image.is_empty():
		return null
	var working := image.duplicate()
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	if working.get_width() != TEXTURE_SIZE or working.get_height() != TEXTURE_SIZE:
		working.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	return working

func _make_default_support_source() -> Image:
	var fallback_texture := _make_default_cover_texture("", "", "")
	var fallback_image := fallback_texture.get_image()
	if fallback_image.get_format() != Image.FORMAT_RGBA8:
		fallback_image.convert(Image.FORMAT_RGBA8)
	return fallback_image

func _make_edge_image(source: Image) -> Image:
	var width: int = source.get_width()
	var height: int = source.get_height()
	var edge_image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var center_luma: float = _pixel_luma(source.get_pixel(x, y))
			var left_luma: float = _pixel_luma(source.get_pixel(maxi(0, x - 1), y))
			var right_luma: float = _pixel_luma(source.get_pixel(mini(width - 1, x + 1), y))
			var up_luma: float = _pixel_luma(source.get_pixel(x, maxi(0, y - 1)))
			var down_luma: float = _pixel_luma(source.get_pixel(x, mini(height - 1, y + 1)))
			var edge: float = absf(right_luma - left_luma) + absf(down_luma - up_luma)
			var contrast: float = absf(center_luma - ((left_luma + right_luma + up_luma + down_luma) * 0.25))
			var edge_value: float = clampf(edge * 2.8 + contrast * 2.2, 0.0, 1.0)
			edge_value = smoothstep(0.055, 0.58, edge_value)
			edge_image.set_pixel(x, y, Color(edge_value, edge_value, edge_value, 1.0))
	return edge_image

func _make_depth_image(source: Image) -> Image:
	var width: int = source.get_width()
	var height: int = source.get_height()
	var depth_image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(width - 1) * 0.5, float(height - 1) * 0.5)
	var max_distance: float = maxf(1.0, center.length())
	for y in height:
		for x in width:
			var uv_pos := Vector2(float(x), float(y))
			var luma: float = _pixel_luma(source.get_pixel(x, y))
			var radial: float = 1.0 - clampf(center.distance_to(uv_pos) / max_distance, 0.0, 1.0)
			var horizontal_light: float = smoothstep(0.0, 1.0, float(x) / float(maxi(1, width - 1)))
			var depth: float = clampf(luma * 0.62 + radial * 0.30 + horizontal_light * 0.08, 0.0, 1.0)
			depth = smoothstep(0.10, 0.95, depth)
			depth_image.set_pixel(x, y, Color(depth, depth, depth, 1.0))
	return depth_image

func _pixel_luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114

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

func _is_remote_artwork(source: String) -> bool:
	return source.begins_with("http://") or source.begins_with("https://")

func _get_remote_cache_path(source: String) -> String:
	var cache_key: int = absi(int(hash(source)))
	return "%s/%s.png" % [REMOTE_ARTWORK_CACHE_DIR, str(cache_key)]

func _ensure_remote_cache_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("music_app/visualizer_artwork")

func _make_default_cover_texture(title: String, artist: String, mark: String) -> Texture2D:
	var seed_text := "%s|%s|%s" % [title, artist, mark]
	var seed_value: int = absi(int(hash(seed_text)))
	var color_a := Color.from_hsv(float(seed_value % 360) / 360.0, 0.76, 0.92)
	var color_b := Color.from_hsv(fposmod(float(seed_value) / 7.0, 360.0) / 360.0, 0.58, 0.66)
	var color_c := Color.from_hsv(fposmod(float(seed_value) / 17.0, 360.0) / 360.0, 0.42, 0.98)
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(TEXTURE_SIZE * 0.5, TEXTURE_SIZE * 0.5)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var uv := Vector2(float(x) / float(TEXTURE_SIZE - 1), float(y) / float(TEXTURE_SIZE - 1))
			var diagonal := clampf((uv.x + uv.y) * 0.5, 0.0, 1.0)
			var dist := center.distance_to(Vector2(x, y)) / float(TEXTURE_SIZE) * 2.0
			var ring := 0.5 + 0.5 * sin(dist * 42.0 + float(seed_value % 31) * 0.17)
			var stripe := 0.5 + 0.5 * sin((uv.x - uv.y) * 24.0 + float(seed_value % 19))
			var color := color_a.lerp(color_b, diagonal).lerp(color_c, smoothstep(0.18, 0.88, ring) * 0.32)
			color = color.lerp(Color(0.02, 0.025, 0.035), smoothstep(0.45, 1.18, dist) * 0.54)
			color = color.lightened(stripe * 0.10)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _derive_track_tint(track, texture: Texture2D, has_real_cover: bool) -> Color:
	var fallback: Color = _make_source_tint(track)
	if not has_real_cover or texture == null:
		return fallback
	var image: Image = texture.get_image()
	return _extract_tint_from_image(image, fallback)

func _extract_tint_from_image(image: Image, fallback: Color) -> Color:
	if image == null or image.is_empty():
		return fallback
	var working: Image = image.duplicate()
	if working.get_format() != Image.FORMAT_RGBA8:
		working.convert(Image.FORMAT_RGBA8)
	if working.get_width() > 48 or working.get_height() > 48:
		working.resize(48, 48, Image.INTERPOLATE_LANCZOS)

	var total := Vector3.ZERO
	var weight_total := 0.0
	var width: int = working.get_width()
	var height: int = working.get_height()
	for y in height:
		for x in width:
			var color: Color = working.get_pixel(x, y)
			var max_channel: float = maxf(color.r, maxf(color.g, color.b))
			var min_channel: float = minf(color.r, minf(color.g, color.b))
			var saturation: float = max_channel - min_channel
			var luma: float = _pixel_luma(color)
			var mid_luma_weight: float = smoothstep(0.10, 0.56, luma) * (1.0 - smoothstep(0.78, 1.0, luma))
			var weight: float = color.a * clampf(0.16 + saturation * 2.4, 0.16, 1.0) * (0.38 + mid_luma_weight * 0.72)
			total += Vector3(color.r, color.g, color.b) * weight
			weight_total += weight

	if weight_total <= 0.001:
		return fallback
	var averaged := Color(total.x / weight_total, total.y / weight_total, total.z / weight_total, 1.0)
	return Color.from_hsv(
		averaged.h,
		clampf(averaged.s + 0.20, 0.46, 0.88),
		clampf(maxf(averaged.v, 0.72), 0.62, 0.98),
		1.0
	)

func _make_source_tint(track) -> Color:
	var key := "music-app-default"
	if track != null:
		key = "%s|%s|%s|%s" % [
			str(track.platform),
			str(track.source),
			str(track.artist),
			str(track.title)
		]
	var lower_key := key.to_lower()
	var hue := fposmod(float(absi(int(hash(key)))) / 11.0, 360.0) / 360.0
	if lower_key.contains("local") or lower_key.contains("file"):
		hue = 0.52
	elif lower_key.contains("netease") or lower_key.contains("cloud"):
		hue = 0.98
	elif lower_key.contains("qq"):
		hue = 0.12
	elif lower_key.contains("spotify"):
		hue = 0.38
	return Color.from_hsv(hue, 0.74, 0.90, 1.0)

func _set_tint_color(tint: Color) -> void:
	_tint_color = tint
	_set_shader_parameter("tint_color", _tint_color)
	stage_tint_changed.emit(_tint_color)

func _track_key(track) -> String:
	if track == null:
		return ""
	return "%s|%s|%s|%s|%s" % [
		str(track.source),
		str(track.platform),
		str(track.remote_id),
		str(track.file_path),
		str(track.title)
	]

func _shape_preset_for_track(track) -> float:
	var key := _track_key(track)
	if key.is_empty():
		return 0.0
	return float(absi(int(hash(key))) % 4)

func _random_from_uv(u: float, v: float) -> float:
	return fposmod(sin(u * 127.1 + v * 311.7) * 43758.5453123, 1.0)
