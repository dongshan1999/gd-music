class_name MusicAppVoxelCity
extends MultiMeshInstance3D

const LOW_GRID_SIZE := 16
const MEDIUM_GRID_SIZE := 24
const HIGH_GRID_SIZE := 32
const CELL_SPACING := 0.34
const MIN_HEIGHT := 0.08
const MAX_HEIGHT := 4.2
const SMOOTH_SPEED := 9.0

var _grid_size := MEDIUM_GRID_SIZE
var _heights: PackedFloat32Array = []
var _distances: PackedFloat32Array = []
var _positions: PackedVector2Array = []
var _elapsed := 0.0
var _configured_quality := ""

func _ready() -> void:
	_ensure_multimesh()
	configure_quality("medium")

func configure_quality(quality: String) -> void:
	var next_grid_size := _grid_size_for_quality(quality)
	if next_grid_size == _grid_size and _configured_quality == quality:
		return
	_grid_size = next_grid_size
	_configured_quality = quality
	_rebuild_grid()

func update_city(
	delta: float,
	bass: float,
	mid: float,
	treble: float,
	activity: float,
	beat_flash: float,
	track_transition: float,
	bloom_scale: float
) -> void:
	if multimesh == null or multimesh.instance_count <= 0:
		return

	_elapsed += delta
	var alpha := clampf(1.0 - exp(-SMOOTH_SPEED * delta), 0.0, 1.0)
	var max_distance := maxf(0.001, float(_grid_size) * CELL_SPACING * 0.62)
	var pulse := clampf(beat_flash + track_transition, 0.0, 1.0)

	for index in multimesh.instance_count:
		var distance := _distances[index]
		var center_weight := clampf(1.0 - distance / max_distance, 0.0, 1.0)
		var edge_weight := clampf(distance / max_distance, 0.0, 1.0)
		var band_value := clampf(
			(bass * center_weight)
			+ (mid * 0.45)
			+ (treble * edge_weight * 0.55),
			0.0,
			1.0
		)
		band_value *= activity

		var wave := sin(_elapsed * lerpf(0.65, 2.15, activity) + distance * 1.18) * lerpf(0.018, 0.09, activity)
		var target_height := lerpf(
			MIN_HEIGHT,
			MAX_HEIGHT,
			clampf(band_value + wave + pulse * center_weight * 0.38, 0.0, 1.0)
		)
		_heights[index] = lerpf(_heights[index], target_height, alpha)

		var xz := _positions[index]
		var height := _heights[index]
		var pillar_basis := Basis.IDENTITY.scaled(Vector3(1.0, height, 1.0))
		multimesh.set_instance_transform(index, Transform3D(pillar_basis, Vector3(xz.x, height * 0.5, xz.y)))

		var glow := clampf((band_value + pulse * 0.55) * bloom_scale, 0.0, 1.5)
		multimesh.set_instance_color(
			index,
			Color(
				lerpf(0.04, 0.20, center_weight + pulse * 0.25),
				lerpf(0.28, 0.82, glow),
				lerpf(0.38, 1.00, clampf(treble + pulse, 0.0, 1.0)),
				1.0
			)
		)

func _ensure_multimesh() -> void:
	if multimesh != null:
		if multimesh.instance_count > 0:
			multimesh.instance_count = 0
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		if multimesh.mesh == null:
			multimesh.mesh = _make_city_mesh()
		return

	var next_multimesh := MultiMesh.new()
	next_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	next_multimesh.use_colors = true
	next_multimesh.mesh = _make_city_mesh()
	multimesh = next_multimesh

func _make_city_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, 1.0, 0.24)
	return mesh

func _rebuild_grid() -> void:
	_ensure_multimesh()
	var instance_count := _grid_size * _grid_size
	multimesh.instance_count = instance_count
	_heights.resize(instance_count)
	_distances.resize(instance_count)
	_positions.resize(instance_count)

	var half := float(_grid_size - 1) * 0.5
	for z in _grid_size:
		for x in _grid_size:
			var index := z * _grid_size + x
			var grid_position := Vector2((float(x) - half) * CELL_SPACING, (float(z) - half) * CELL_SPACING)
			_positions[index] = grid_position
			_distances[index] = grid_position.length()
			_heights[index] = MIN_HEIGHT
			multimesh.set_instance_transform(
				index,
				Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, MIN_HEIGHT, 1.0)), Vector3(grid_position.x, MIN_HEIGHT * 0.5, grid_position.y))
			)
			multimesh.set_instance_color(index, Color(0.05, 0.32, 0.45, 1.0))

func _grid_size_for_quality(quality: String) -> int:
	match quality:
		"low":
			return LOW_GRID_SIZE
		"high":
			return HIGH_GRID_SIZE
		"off":
			return LOW_GRID_SIZE
		_:
			return MEDIUM_GRID_SIZE
