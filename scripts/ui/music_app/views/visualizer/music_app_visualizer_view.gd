class_name MusicAppVisualizerView
extends Control

const PILLAR_MIN_HEIGHT := 0.15
const PILLAR_MAX_HEIGHT := 4.5
const PILLAR_SMOOTH_SPEED := 9.0
const PARTICLE_MIN_AMOUNT := 180
const PARTICLE_MAX_AMOUNT := 900
const CAMERA_BASE_POSITION := Vector3(0.0, 7.2, 13.0)
const CAMERA_BEAT_OFFSET := Vector3(0.0, 0.35, -0.45)
const RING_DURATION := 0.95
const RING_MAX_SCALE := 8.0
const RING_MIN_SCALE := 0.25
const IDLE_FLOW_SPEED := 0.35
const IDLE_ACTIVITY := 0.18
const ACTIVE_ACTIVITY := 1.0
const TRACK_TRANSITION_PULSE := 0.82
const STARDUST_MIN_AMOUNT := 260
const STARDUST_MAX_AMOUNT := 760
const RIBBON_DRIFT_SPEED := 0.18
const MODE_MINERADIO := "mineradio"
const MODE_CITY := "city"

@onready var visualizer_viewport: SubViewport = %VisualizerViewport
@onready var camera: Camera3D = %VisualizerCamera
@onready var beat_light: OmniLight3D = %BeatLight
@onready var mineradio_backdrop: Node3D = %MineradioBackdrop
@onready var star_dust_particles: GPUParticles3D = %StarDustParticles
@onready var light_ribbons_root: Node3D = %LightRibbons
@onready var scanline_overlay: ColorRect = %VisualizerScanlineOverlay
@onready var cover_particle_stage: Node3D = %CoverParticleStage3D
@onready var mineradio_stage_frame: Node3D = %MineradioStageFrame
@onready var rhythm_particles: GPUParticles3D = %RhythmParticles
@onready var voxel_city: MultiMeshInstance3D = %MultiMeshCity
@onready var city_scene_layers: Node3D = %CitySceneLayers
@onready var pillars_root: Node3D = %Pillars
@onready var rings_root: Node3D = %ShockwaveRings

var _spectrum_controller
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
var _beat_flash := 0.0
var _elapsed := 0.0
var _ring_cursor := 0
var _rings: Array[MeshInstance3D] = []
var _ring_age: Array[float] = []
var _pillar_base_positions: Array[Vector3] = []
var _pillar_nodes: Array[MeshInstance3D] = []
var _pillar_materials: Array[StandardMaterial3D] = []
var _ribbon_nodes: Array[MeshInstance3D] = []
var _ribbon_base_positions: Array[Vector3] = []
var _ribbon_base_rotations: Array[Vector3] = []
var _ribbon_materials: Array[StandardMaterial3D] = []
var _city_layer_nodes: Array[MeshInstance3D] = []
var _city_layer_materials: Array[StandardMaterial3D] = []
var _city_layer_base_positions: Array[Vector3] = []
var _stage_frame_nodes: Array[MeshInstance3D] = []
var _stage_frame_materials: Array[ShaderMaterial] = []
var _stage_frame_base_positions: Array[Vector3] = []
var _stage_frame_base_rotations: Array[Vector3] = []
var _stage_frame_base_scales: Array[Vector3] = []
var _scanline_material: ShaderMaterial
var _quality_scale := 1.0
var _quality := "medium"
var _mode := MODE_MINERADIO
var _particle_scale := 1.0
var _bloom_scale := 1.0
var _target_activity := IDLE_ACTIVITY
var _activity := IDLE_ACTIVITY
var _track_transition := 0.0
var _favorite_flash := 0.0
var _favorite_liked := false
var _track_tint := Color(0.44, 0.92, 1.0, 1.0)
var _target_track_tint := Color(0.44, 0.92, 1.0, 1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visualizer_viewport.transparent_bg = true
	_connect_cover_particle_stage_tint()
	_cache_mineradio_backdrop()
	_cache_stage_frame()
	_cache_city_layers()
	_cache_pillars()
	_cache_rings()
	if voxel_city != null and voxel_city.has_method("configure_quality"):
		voxel_city.configure_quality(_quality)
		voxel_city.visible = false
	if city_scene_layers != null:
		city_scene_layers.visible = false
		pillars_root.visible = false
	_apply_spectrum(0.0, 0.0, 0.0, 0.0)

func setup(spectrum_controller) -> void:
	if _spectrum_controller != null:
		if _spectrum_controller.spectrum_changed.is_connected(_on_spectrum_changed):
			_spectrum_controller.spectrum_changed.disconnect(_on_spectrum_changed)
		if _spectrum_controller.beat_detected.is_connected(_on_beat_detected):
			_spectrum_controller.beat_detected.disconnect(_on_beat_detected)
		if _spectrum_controller.has_signal("detailed_spectrum_changed") and _spectrum_controller.detailed_spectrum_changed.is_connected(_on_detailed_spectrum_changed):
			_spectrum_controller.detailed_spectrum_changed.disconnect(_on_detailed_spectrum_changed)

	_spectrum_controller = spectrum_controller
	if _spectrum_controller == null:
		return
	_spectrum_controller.spectrum_changed.connect(_on_spectrum_changed)
	_spectrum_controller.beat_detected.connect(_on_beat_detected)
	if _spectrum_controller.has_signal("detailed_spectrum_changed"):
		_spectrum_controller.detailed_spectrum_changed.connect(_on_detailed_spectrum_changed)

func apply_visualizer_settings(settings: Dictionary) -> void:
	var enabled := bool(settings.get("enabled", true))
	var mode := str(settings.get("mode", MODE_MINERADIO))
	var quality := str(settings.get("quality", "medium"))
	var previous_mode := _mode
	_mode = mode
	_quality = quality
	visible = enabled and quality != "off"
	set_process(visible)
	if not visible or previous_mode != _mode:
		_release_visualizer_resources()
	if rhythm_particles != null:
		rhythm_particles.emitting = visible
	if mineradio_backdrop != null:
		mineradio_backdrop.visible = visible
	if star_dust_particles != null:
		star_dust_particles.emitting = visible
	if scanline_overlay != null:
		scanline_overlay.visible = visible
	if cover_particle_stage != null:
		if cover_particle_stage.has_method("apply_visualizer_settings"):
			cover_particle_stage.apply_visualizer_settings(settings)
		cover_particle_stage.visible = visible and _mode == MODE_MINERADIO
	if mineradio_stage_frame != null:
		mineradio_stage_frame.visible = visible and _mode == MODE_MINERADIO
	if voxel_city != null:
		voxel_city.visible = visible and _mode == MODE_CITY
		if voxel_city.has_method("configure_quality"):
			voxel_city.configure_quality(quality)
	if city_scene_layers != null:
		city_scene_layers.visible = visible and _mode == MODE_CITY
	if pillars_root != null:
		pillars_root.visible = false

	match quality:
		"low":
			_quality_scale = 0.55
		"high":
			_quality_scale = 1.25
		"off":
			_quality_scale = 0.0
		_:
			_quality_scale = 1.0
	_particle_scale = clampf(float(settings.get("particles", 1.0)), 0.25, 1.5)
	_bloom_scale = clampf(float(settings.get("bloom", 1.0)), 0.0, 1.5)

func _release_visualizer_resources() -> void:
	_beat_flash = 0.0
	_track_transition = 0.0
	_favorite_flash = 0.0
	_target_activity = IDLE_ACTIVITY
	_activity = IDLE_ACTIVITY
	if rhythm_particles != null:
		rhythm_particles.emitting = false
		rhythm_particles.amount = 0
	if star_dust_particles != null:
		star_dust_particles.emitting = false
		star_dust_particles.amount = 0
	if cover_particle_stage != null and cover_particle_stage.has_method("release_visualizer_resources"):
		cover_particle_stage.release_visualizer_resources()
	if mineradio_stage_frame != null:
		mineradio_stage_frame.visible = false
	for ring_index in _rings.size():
		_rings[ring_index].visible = false
		_ring_age[ring_index] = RING_DURATION
	if voxel_city != null:
		voxel_city.visible = false
	if city_scene_layers != null:
		city_scene_layers.visible = false
	if pillars_root != null:
		pillars_root.visible = false

func set_playback_active(active: bool) -> void:
	_target_activity = ACTIVE_ACTIVITY if active else IDLE_ACTIVITY
	if cover_particle_stage != null and cover_particle_stage.has_method("set_playback_active"):
		cover_particle_stage.set_playback_active(active)

func trigger_track_transition(track = null) -> void:
	_track_transition = TRACK_TRANSITION_PULSE
	_beat_flash = clampf(_beat_flash + TRACK_TRANSITION_PULSE, 0.0, 1.0)
	_trigger_ring(TRACK_TRANSITION_PULSE)
	if cover_particle_stage != null:
		if cover_particle_stage.has_method("apply_track"):
			cover_particle_stage.apply_track(track)
		if cover_particle_stage.has_method("get_stage_tint"):
			_target_track_tint = cover_particle_stage.get_stage_tint()
		if cover_particle_stage.has_method("trigger_burst"):
			cover_particle_stage.trigger_burst(TRACK_TRANSITION_PULSE)

func trigger_favorite_feedback(liked: bool, _track = null) -> void:
	_favorite_liked = liked
	_favorite_flash = maxf(_favorite_flash, 0.78 if liked else 0.42)
	_beat_flash = clampf(_beat_flash + (0.36 if liked else 0.16), 0.0, 1.0)
	if liked:
		_trigger_ring(0.55)
	if cover_particle_stage != null and cover_particle_stage.has_method("trigger_favorite_feedback"):
		cover_particle_stage.trigger_favorite_feedback(liked)

func _process(delta: float) -> void:
	_elapsed += delta
	_beat_flash = lerpf(_beat_flash, 0.0, clampf(1.0 - exp(-8.0 * delta), 0.0, 1.0))
	_track_transition = lerpf(_track_transition, 0.0, clampf(1.0 - exp(-5.5 * delta), 0.0, 1.0))
	_favorite_flash = lerpf(_favorite_flash, 0.0, clampf(1.0 - exp(-6.5 * delta), 0.0, 1.0))
	_activity = lerpf(_activity, _target_activity, clampf(1.0 - exp(-4.0 * delta), 0.0, 1.0))
	_track_tint = _track_tint.lerp(_target_track_tint, clampf(1.0 - exp(-2.8 * delta), 0.0, 1.0))
	_update_cover_particle_stage(delta)
	_update_stage_frame(delta)
	_update_mineradio_backdrop(delta)
	_update_particles()
	_update_camera(delta)
	_update_pillars(delta)
	_update_city_scene_layers(delta)
	_update_rings(delta)

func _on_spectrum_changed(bass: float, mid: float, treble: float, volume: float) -> void:
	_apply_spectrum(bass, mid, treble, volume)

func _on_detailed_spectrum_changed(
	kick: float,
	bass: float,
	vocal: float,
	instrument_mid: float,
	treble: float,
	treble_air: float,
	rms: float,
	energy_onset: float
) -> void:
	_kick = kick
	_bass = bass
	_vocal = vocal
	_instrument_mid = instrument_mid
	_mid = clampf((vocal * 0.55) + (instrument_mid * 0.45), 0.0, 1.0)
	_treble = treble
	_treble_air = treble_air
	_rms = rms
	_volume = maxf(_volume, rms)
	_energy_onset = energy_onset

func _on_beat_detected(strength: float) -> void:
	_beat_flash = clampf(_beat_flash + strength, 0.0, 1.0)
	_trigger_ring(strength)
	if cover_particle_stage != null and cover_particle_stage.has_method("trigger_ripple"):
		cover_particle_stage.trigger_ripple(strength)

func _apply_spectrum(bass: float, mid: float, treble: float, volume: float) -> void:
	_bass = bass
	_mid = mid
	_treble = treble
	_volume = volume

func _connect_cover_particle_stage_tint() -> void:
	if cover_particle_stage == null:
		return
	if cover_particle_stage.has_signal("stage_tint_changed"):
		var tint_callable := Callable(self, "_on_cover_stage_tint_changed")
		if not cover_particle_stage.is_connected("stage_tint_changed", tint_callable):
			cover_particle_stage.connect("stage_tint_changed", tint_callable)

func _on_cover_stage_tint_changed(tint: Color) -> void:
	_target_track_tint = tint

func _cache_mineradio_backdrop() -> void:
	_ribbon_nodes.clear()
	_ribbon_base_positions.clear()
	_ribbon_base_rotations.clear()
	_ribbon_materials.clear()

	for child in light_ribbons_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var ribbon := child as MeshInstance3D
		_ribbon_nodes.append(ribbon)
		_ribbon_base_positions.append(ribbon.position)
		_ribbon_base_rotations.append(ribbon.rotation)
		if ribbon.material_override is StandardMaterial3D:
			ribbon.material_override = ribbon.material_override.duplicate()
			_ribbon_materials.append(ribbon.material_override as StandardMaterial3D)
		else:
			_ribbon_materials.append(null)

	if scanline_overlay.material is ShaderMaterial:
		scanline_overlay.material = scanline_overlay.material.duplicate()
		_scanline_material = scanline_overlay.material as ShaderMaterial

func _cache_stage_frame() -> void:
	_stage_frame_nodes.clear()
	_stage_frame_materials.clear()
	_stage_frame_base_positions.clear()
	_stage_frame_base_rotations.clear()
	_stage_frame_base_scales.clear()
	if mineradio_stage_frame == null:
		return

	for child in mineradio_stage_frame.get_children():
		if not (child is MeshInstance3D):
			continue
		var frame_node := child as MeshInstance3D
		_stage_frame_nodes.append(frame_node)
		_stage_frame_base_positions.append(frame_node.position)
		_stage_frame_base_rotations.append(frame_node.rotation)
		_stage_frame_base_scales.append(frame_node.scale)
		if frame_node.material_override is ShaderMaterial:
			frame_node.material_override = frame_node.material_override.duplicate()
			_stage_frame_materials.append(frame_node.material_override as ShaderMaterial)
		else:
			_stage_frame_materials.append(null)

func _cache_pillars() -> void:
	_pillar_nodes.clear()
	_pillar_base_positions.clear()
	_pillar_materials.clear()

	for child in pillars_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var pillar := child as MeshInstance3D
		_pillar_nodes.append(pillar)
		_pillar_base_positions.append(pillar.position)
		if pillar.material_override is StandardMaterial3D:
			pillar.material_override = pillar.material_override.duplicate()
			_pillar_materials.append(pillar.material_override as StandardMaterial3D)
		else:
			_pillar_materials.append(null)

func _cache_city_layers() -> void:
	_city_layer_nodes.clear()
	_city_layer_materials.clear()
	_city_layer_base_positions.clear()
	if city_scene_layers == null:
		return

	for child in city_scene_layers.get_children():
		if not (child is MeshInstance3D):
			continue
		var layer := child as MeshInstance3D
		_city_layer_nodes.append(layer)
		_city_layer_base_positions.append(layer.position)
		if layer.material_override is StandardMaterial3D:
			layer.material_override = layer.material_override.duplicate()
			_city_layer_materials.append(layer.material_override as StandardMaterial3D)
		else:
			_city_layer_materials.append(null)

func _cache_rings() -> void:
	_rings.clear()
	_ring_age.clear()
	for child in rings_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var ring := child as MeshInstance3D
		if ring.material_override is StandardMaterial3D:
			ring.material_override = ring.material_override.duplicate()
		ring.visible = false
		_rings.append(ring)
		_ring_age.append(RING_DURATION)

func _update_mineradio_backdrop(delta: float) -> void:
	var pulse := clampf(_beat_flash * 0.65 + _track_transition * 0.55 + _favorite_flash * 0.38, 0.0, 1.0)
	var dust_intensity := clampf((_treble * 0.65 + _volume * 0.45 + pulse * 0.35) * _activity, 0.0, 1.0)

	if star_dust_particles != null:
		star_dust_particles.amount = int(lerpf(STARDUST_MIN_AMOUNT, STARDUST_MAX_AMOUNT, dust_intensity) * _quality_scale * _particle_scale * 0.72)
		star_dust_particles.speed_scale = lerpf(0.055, 0.45, clampf(_mid * 0.6 + _treble * 0.35 + pulse * 0.4, 0.0, 1.0))
		star_dust_particles.emitting = visible
		var dust_material := star_dust_particles.process_material as ParticleProcessMaterial
		if dust_material != null:
			var dust_tint := _track_tint.lerp(Color(0.95, 0.74, 0.34, 1.0), clampf(_treble * 0.28 + _favorite_flash * 0.22, 0.0, 0.52))
			dust_material.initial_velocity_max = lerpf(0.22, 1.05, clampf(_treble + pulse * 0.4, 0.0, 1.0))
			dust_material.scale_max = lerpf(0.018, 0.052, clampf(_mid + pulse, 0.0, 1.0))
			dust_material.color = Color(
				dust_tint.r,
				dust_tint.g,
				dust_tint.b,
				lerpf(0.28, 0.58, dust_intensity)
			)

	for index in _ribbon_nodes.size():
		var ribbon := _ribbon_nodes[index]
		var base_position := _ribbon_base_positions[index]
		var base_rotation := _ribbon_base_rotations[index]
		var offset_phase := float(index) * 1.37
		var drift := sin(_elapsed * RIBBON_DRIFT_SPEED + offset_phase) * 0.18
		var beat_lift := pulse * lerpf(0.08, 0.22, float(index % 2))
		ribbon.position = ribbon.position.lerp(
			base_position + Vector3(drift, beat_lift + sin(_elapsed * 0.12 + offset_phase) * 0.08, 0.0),
			clampf(1.0 - exp(-3.0 * delta), 0.0, 1.0)
		)
		ribbon.rotation = ribbon.rotation.lerp(
			base_rotation + Vector3(0.0, 0.0, sin(_elapsed * 0.1 + offset_phase) * 0.025 + pulse * 0.018),
			clampf(1.0 - exp(-2.5 * delta), 0.0, 1.0)
		)

		var ribbon_material := _ribbon_materials[index]
		if ribbon_material != null:
			var band_value := clampf(_bass * 0.42 + _mid * 0.28 + pulse * 0.65, 0.0, 1.0)
			var color := ribbon_material.albedo_color
			var ribbon_tint := _track_tint.lerp(Color(1.0, 0.74, 0.30, 1.0), 0.42 if index % 2 == 1 else 0.12)
			color.r = ribbon_tint.r
			color.g = ribbon_tint.g
			color.b = ribbon_tint.b
			color.a = lerpf(0.065, 0.24, band_value) * _bloom_scale
			ribbon_material.albedo_color = color
			ribbon_material.emission = ribbon_tint
			ribbon_material.emission_energy_multiplier = lerpf(0.28, 1.65, band_value) * _bloom_scale

	if _scanline_material != null:
		var overlay_energy := clampf(maxf(_rms, _volume) + pulse * 0.35, 0.0, 1.0)
		var air := clampf(_treble_air * 0.72 + _treble * 0.28, 0.0, 1.0)
		var onset := clampf(_energy_onset + pulse * 0.35, 0.0, 1.0)
		var quality_factor := clampf(_quality_scale, 0.45, 1.25)
		_scanline_material.set_shader_parameter("pulse", clampf(pulse + overlay_energy * 0.22, 0.0, 1.0))
		_scanline_material.set_shader_parameter("scanline_alpha", lerpf(0.026, 0.074, clampf(air + onset * 0.35, 0.0, 1.0)) * quality_factor)
		_scanline_material.set_shader_parameter("vignette_alpha", lerpf(0.48, 0.64, clampf(_bass + pulse * 0.3, 0.0, 1.0)))
		_scanline_material.set_shader_parameter("rgb_shift", lerpf(0.0025, 0.0095, clampf(air + onset * 0.48, 0.0, 1.0)) * quality_factor)
		_scanline_material.set_shader_parameter("flow_strength", lerpf(0.58, 1.18, clampf(overlay_energy + _activity * 0.2, 0.0, 1.0)) * quality_factor)
		_scanline_material.set_shader_parameter("line_density", lerpf(0.62, 1.22, quality_factor) + air * 0.18)
		_scanline_material.set_shader_parameter("grain_alpha", lerpf(0.006, 0.018, quality_factor) * lerpf(0.62, 1.25, overlay_energy))
		_scanline_material.set_shader_parameter("air", air)
		_scanline_material.set_shader_parameter("onset", onset)
		_scanline_material.set_shader_parameter("tint", _track_tint)

func _update_stage_frame(delta: float) -> void:
	if mineradio_stage_frame == null or _mode != MODE_MINERADIO or not mineradio_stage_frame.visible:
		return

	var pulse := clampf(_beat_flash * 0.62 + _track_transition * 0.48 + _energy_onset * 0.62 + _favorite_flash * 0.36, 0.0, 1.0)
	var body := clampf(_bass * 0.42 + _mid * 0.24 + _rms * 0.28 + pulse * 0.32, 0.0, 1.0)
	var alpha := clampf(1.0 - exp(-5.2 * delta), 0.0, 1.0)
	mineradio_stage_frame.position = mineradio_stage_frame.position.lerp(Vector3(0.0, 0.0, -0.18 - body * 0.045), alpha)
	mineradio_stage_frame.rotation.z = lerpf(mineradio_stage_frame.rotation.z, sin(_elapsed * 0.12) * 0.018 + pulse * 0.012, alpha)

	for index in _stage_frame_nodes.size():
		var frame_node := _stage_frame_nodes[index]
		var base_position := _stage_frame_base_positions[index]
		var base_rotation := _stage_frame_base_rotations[index]
		var base_scale := _stage_frame_base_scales[index]
		var phase := float(index) * 1.27
		var local_pulse := clampf(body + pulse * (0.9 - float(index) * 0.16), 0.0, 1.0)
		var breathing := sin(_elapsed * (0.20 + float(index) * 0.045) + phase) * 0.012
		var scale_boost := 1.0 + breathing + local_pulse * (0.035 + float(index) * 0.012)
		frame_node.position = frame_node.position.lerp(base_position + Vector3(0.0, 0.0, -local_pulse * 0.035), alpha)
		frame_node.rotation = frame_node.rotation.lerp(
			base_rotation + Vector3(0.0, 0.0, sin(_elapsed * (0.10 + float(index) * 0.04) + phase) * 0.035 + pulse * 0.022),
			alpha
		)
		frame_node.scale = frame_node.scale.lerp(base_scale * scale_boost, alpha)

		var frame_material := _stage_frame_materials[index]
		if frame_material == null:
			continue
		frame_material.set_shader_parameter("tint", _track_tint)
		frame_material.set_shader_parameter("pulse", pulse)
		frame_material.set_shader_parameter("bass", _bass)
		frame_material.set_shader_parameter("mid", _mid)
		frame_material.set_shader_parameter("treble", _treble_air)
		frame_material.set_shader_parameter("alpha", lerpf(0.14, 0.38, local_pulse) * _bloom_scale * _quality_scale)

func _update_cover_particle_stage(delta: float) -> void:
	if cover_particle_stage == null or not cover_particle_stage.has_method("update_stage"):
		return
	cover_particle_stage.update_stage(
		delta,
		_bass,
		_mid,
		_treble,
		_volume,
		_beat_flash,
		_track_transition,
		_activity,
		_bloom_scale,
		_particle_scale,
		_kick,
		_vocal,
		_instrument_mid,
		_treble_air,
		_rms,
		_energy_onset
	)

func _update_particles() -> void:
	var pulse := clampf(_beat_flash * 0.35 + _track_transition * 0.45 + _favorite_flash * 0.42, 0.0, 1.0)
	var particle_intensity := clampf((_volume + pulse) * _activity, 0.0, 1.0)
	rhythm_particles.amount = int(lerpf(PARTICLE_MIN_AMOUNT, PARTICLE_MAX_AMOUNT, particle_intensity) * _quality_scale * _particle_scale)
	rhythm_particles.speed_scale = lerpf(IDLE_FLOW_SPEED, 1.9, clampf((_bass + _volume * 0.45) * _activity + _track_transition * 0.35, 0.0, 1.0))
	rhythm_particles.emitting = true

	var process_material := rhythm_particles.process_material as ParticleProcessMaterial
	if process_material == null:
		return
	process_material.initial_velocity_min = lerpf(0.25, 2.8, _bass * _activity)
	process_material.initial_velocity_max = lerpf(1.0, 7.5, clampf((_treble + _beat_flash * 0.5 + _track_transition * 0.45) * _activity, 0.0, 1.0))
	process_material.scale_min = lerpf(0.025, 0.075, _mid * _activity)
	process_material.scale_max = lerpf(0.055, 0.22, clampf((_treble + _beat_flash + _track_transition * 0.6) * _activity, 0.0, 1.0))
	var particle_tint := _track_tint.lerp(Color(1.0, 0.72, 0.32, 1.0), clampf(_favorite_flash * 0.48 + _track_transition * 0.18, 0.0, 0.55))
	process_material.color = Color(
		lerpf(particle_tint.r * 0.46, 0.95 if _favorite_liked else particle_tint.r, clampf(_bass + _track_transition * 0.5 + _favorite_flash, 0.0, 1.0)),
		lerpf(particle_tint.g * 0.56, 0.74 if _favorite_liked else particle_tint.g, clampf(_treble + _activity * 0.3 + _favorite_flash * 0.45, 0.0, 1.0)),
		lerpf(particle_tint.b * 0.62, 0.34 if _favorite_liked else particle_tint.b, clampf(_mid + _track_transition * 0.35 + _favorite_flash, 0.0, 1.0)),
		0.92
	)

func _update_camera(delta: float) -> void:
	var beat_offset := CAMERA_BEAT_OFFSET * (_beat_flash + _track_transition * 0.65 + _favorite_flash * 0.18)
	var orbit := Vector3(sin(_elapsed * 0.22) * 0.18, sin(_elapsed * 0.31) * 0.08, 0.0)
	camera.position = camera.position.lerp(CAMERA_BASE_POSITION + beat_offset + orbit, clampf(1.0 - exp(-5.0 * delta), 0.0, 1.0))
	camera.look_at(Vector3(0.0, 1.4 + _bass * _activity * 0.6, 0.0), Vector3.UP)
	beat_light.light_color = _track_tint.lerp(Color(1.0, 0.74, 0.34, 1.0), clampf(_favorite_flash * 0.45 + _beat_flash * 0.18, 0.0, 0.55))
	beat_light.light_energy = lerpf(0.25, 3.4, clampf((_bass * 0.55 + _beat_flash + _track_transition * 0.6 + _favorite_flash * 0.45) * _activity, 0.0, 1.0)) * _bloom_scale

func _update_pillars(delta: float) -> void:
	if _mode != MODE_CITY:
		return
	if voxel_city != null and voxel_city.visible and voxel_city.has_method("update_city"):
		voxel_city.update_city(
			delta,
			_bass,
			_mid,
			_treble,
			_activity,
			_beat_flash,
			_track_transition,
			_bloom_scale
		)
		return

	var alpha := clampf(1.0 - exp(-PILLAR_SMOOTH_SPEED * delta), 0.0, 1.0)
	for index in _pillar_nodes.size():
		var pillar := _pillar_nodes[index]
		var base_position := _pillar_base_positions[index]
		var distance := Vector2(base_position.x, base_position.z).length()
		var center_weight := clampf(1.0 - distance / 6.0, 0.0, 1.0)
		var edge_weight := clampf(distance / 6.0, 0.0, 1.0)
		var band_value := clampf((_bass * center_weight + _mid * 0.55 + _treble * edge_weight * 0.55) * _activity, 0.0, 1.0)
		var wave := sin(_elapsed * lerpf(0.75, 1.8, _activity) + distance * 0.85) * lerpf(0.025, 0.08, _activity)
		var target_height := lerpf(PILLAR_MIN_HEIGHT, PILLAR_MAX_HEIGHT, clampf(band_value + wave + (_beat_flash + _track_transition) * center_weight * 0.35, 0.0, 1.0))

		pillar.scale.y = lerpf(pillar.scale.y, target_height, alpha)
		pillar.position.y = pillar.scale.y * 0.5

		var pillar_material := _pillar_materials[index]
		if pillar_material != null:
			pillar_material.emission_energy_multiplier = lerpf(0.25, 2.4, clampf(band_value + _beat_flash * 0.5, 0.0, 1.0)) * _bloom_scale

func _update_city_scene_layers(delta: float) -> void:
	if _mode != MODE_CITY or city_scene_layers == null or not city_scene_layers.visible:
		return

	var pulse := clampf(_beat_flash + _track_transition * 0.55 + _energy_onset * 0.65 + _favorite_flash * 0.32, 0.0, 1.0)
	var city_energy := clampf((_bass * 0.42 + _mid * 0.26 + _treble * 0.22 + pulse * 0.35) * _activity, 0.0, 1.0)
	var alpha := clampf(1.0 - exp(-4.8 * delta), 0.0, 1.0)

	for index in _city_layer_nodes.size():
		var layer := _city_layer_nodes[index]
		var layer_material := _city_layer_materials[index]
		var base_position := _city_layer_base_positions[index]
		if layer.name.begins_with("CityFog"):
			var phase := float(index) * 0.83
			var drift := Vector3(
				sin(_elapsed * 0.18 + phase) * 0.18,
				sin(_elapsed * 0.12 + phase) * 0.055 + pulse * 0.045,
				cos(_elapsed * 0.16 + phase) * 0.12
			)
			layer.position = layer.position.lerp(base_position + drift, alpha)
		elif layer.name.begins_with("CityRoad"):
			var road_shift := sin(_elapsed * 0.42 + float(index)) * 0.025
			layer.position = layer.position.lerp(base_position + Vector3(0.0, pulse * 0.018, road_shift), alpha)
		else:
			layer.position = layer.position.lerp(base_position, alpha)

		if layer_material == null:
			continue
		var color := layer_material.albedo_color
		if layer.name == "CityGround":
			color = color.lerp(_track_tint.darkened(0.28), 0.16)
			color.a = lerpf(0.52, 0.82, city_energy)
			layer_material.emission = _track_tint.darkened(0.18)
			layer_material.emission_energy_multiplier = lerpf(0.22, 0.58, city_energy) * _bloom_scale
		elif layer.name.begins_with("CityRoad"):
			var road_tint := _track_tint.lerp(Color(1.0, 0.72, 0.30, 1.0), 0.34)
			color.r = road_tint.r
			color.g = road_tint.g
			color.b = road_tint.b
			color.a = lerpf(0.08, 0.34, clampf(_treble + pulse, 0.0, 1.0))
			layer_material.emission = road_tint
			layer_material.emission_energy_multiplier = lerpf(0.45, 2.4, clampf(city_energy + pulse * 0.72, 0.0, 1.0)) * _bloom_scale
		elif layer.name.begins_with("CityFog"):
			var fog_tint := _track_tint.lerp(Color(0.12, 0.90, 1.0, 1.0), 0.46)
			color.r = fog_tint.r
			color.g = fog_tint.g
			color.b = fog_tint.b
			color.a = lerpf(0.035, 0.14, clampf(_mid * 0.55 + _rms * 0.35 + pulse * 0.25, 0.0, 1.0))
			layer_material.emission = fog_tint
			layer_material.emission_energy_multiplier = lerpf(0.18, 0.72, clampf(_treble_air + pulse * 0.35, 0.0, 1.0)) * _bloom_scale
		layer_material.albedo_color = color

func _trigger_ring(strength: float) -> void:
	if _rings.is_empty():
		return
	var ring := _rings[_ring_cursor]
	_ring_age[_ring_cursor] = 0.0
	ring.visible = true
	ring.scale = Vector3.ONE * lerpf(RING_MIN_SCALE, 0.8, clampf(strength, 0.0, 1.0))
	_ring_cursor = (_ring_cursor + 1) % _rings.size()

func _update_rings(delta: float) -> void:
	for index in _rings.size():
		if _ring_age[index] >= RING_DURATION:
			_rings[index].visible = false
			continue
		_ring_age[index] += delta
		var t := clampf(_ring_age[index] / RING_DURATION, 0.0, 1.0)
		var ring := _rings[index]
		ring.scale = Vector3.ONE * lerpf(RING_MIN_SCALE, RING_MAX_SCALE, t)
		var ring_material := ring.material_override as StandardMaterial3D
		if ring_material != null:
			var color := ring_material.albedo_color
			color.a = 1.0 - t
			ring_material.albedo_color = color
			ring_material.emission_energy_multiplier = lerpf(2.6, 0.0, t) * _bloom_scale
