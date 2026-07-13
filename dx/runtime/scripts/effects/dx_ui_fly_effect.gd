class_name DX_UiFlyEffect
extends RefCounted

const DEFAULT_POOL_NAME := &"DX_UiFlyEffect"
const DEFAULT_POOL_CAPACITY := 64
const DEFAULT_DURATION := 0.45
const UI_NODE_PATH := ^"UI"

var dx: Node
var _host_layer: CanvasLayer

func in_ready() -> void:
	_ensure_host_layer()

func fly(
	start_position: Vector2,
	end_position: Vector2,
	fly_source,
	size: Vector2 = Vector2.ZERO,
	pool_name: StringName = DEFAULT_POOL_NAME
) -> void:
	_ensure_host_layer()
	if not _ensure_pool(pool_name, fly_source):
		return

	var fly_node: Node = dx.pool.pop(pool_name, _host_layer)
	if fly_node == null:
		return

	_prepare_fly_node(fly_node, start_position, size)

	var tween := dx.create_tween()
	tween.tween_property(fly_node, "global_position", end_position, DEFAULT_DURATION)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(fly_node, "modulate:a", 0.0, DEFAULT_DURATION)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)

	await tween.finished
	_return_fly_node(pool_name, fly_node)

func _ensure_host_layer() -> void:
	if is_instance_valid(_host_layer):
		return
	_host_layer = dx.get_node(UI_NODE_PATH) as CanvasLayer

func _ensure_pool(pool_name: StringName, fly_source) -> bool:
	if dx.pool.contains(pool_name):
		return true
	return dx.pool.init(pool_name, fly_source, DEFAULT_POOL_CAPACITY, 0.0)

func _prepare_fly_node(fly_node: Node, start_position: Vector2, size: Vector2) -> void:
	if fly_node is Control:
		var control := fly_node as Control
		if size != Vector2.ZERO:
			control.size = size
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.modulate = Color.WHITE
		control.global_position = start_position
	elif fly_node is Node2D:
		var node_2d := fly_node as Node2D
		node_2d.modulate = Color.WHITE
		node_2d.global_position = start_position

func _return_fly_node(pool_name: StringName, fly_node: Node) -> void:
	if not is_instance_valid(fly_node):
		return
	if fly_node is CanvasItem:
		(fly_node as CanvasItem).modulate = Color.WHITE
	dx.pool.push(pool_name, fly_node)
