class_name DX_PoolManager
extends Node

const DEFAULT_MAX_CAPACITY := 100
const DEFAULT_EXPIRATION_SECONDS := 300.0

var dx: Node
@onready var _active_root: Node = %PoolActive
@onready var _inactive_root: Node = %PoolInactive
var _pools: Dictionary = {}
var _cleanup_timer := 0.0

func in_process(delta: float) -> void:
	_cleanup_timer += delta
	if _cleanup_timer < 5.0:
		return
	_cleanup_timer = 0.0
	_cleanup_expired_objects()

func init(
	pool_name: StringName,
	source,
	max_capacity: int = DEFAULT_MAX_CAPACITY,
	expiration_seconds: float = DEFAULT_EXPIRATION_SECONDS
) -> bool:
	if pool_name == &"":
		dx.logger.error("Pool", "初始化对象池失败，pool_name 不能为空.")
		return false
	if _pools.has(pool_name):
		return true

	var template := _make_template(source)
	if template == null:
		dx.logger.error("Pool", "初始化对象池失败，source 必须是 PackedScene 或 Node: %s" % String(pool_name))
		return false

	_clear_pool_entries(pool_name)

	template.name = _make_template_name(pool_name)
	if template.get_parent() != null:
		template.reparent(_inactive_root)
	else:
		_inactive_root.add_child(template)
	_notify_pool_push(template)
	_set_node_visible(template, false)

	_pools[pool_name] = {
		"template": template,
		"items": [],
		"max_capacity": maxi(1, max_capacity),
		"expiration_seconds": maxf(0.0, expiration_seconds),
		"next_index": 1,
	}
	return true

func contains(pool_name: StringName) -> bool:
	return _pools.has(pool_name)

func pop(pool_name: StringName, parent: Node = null) -> Node:
	if not _pools.has(pool_name):
		dx.logger.warning("Pool", "未找到对象池: %s" % String(pool_name))
		return null

	_cleanup_pool(pool_name)

	var pool: Dictionary = _pools[pool_name]
	var items: Array = pool["items"]
	var instance: Node = null
	while not items.is_empty() and instance == null:
		var entry: Dictionary = items.pop_back()
		var candidate = entry.get("node")
		if is_instance_valid(candidate) and candidate is Node:
			instance = candidate as Node

	if instance == null:
		var template = pool.get("template")
		if not is_instance_valid(template) or not template is Node:
			dx.logger.error("Pool", "对象池模板无效: %s" % String(pool_name))
			pool["items"] = items
			_pools[pool_name] = pool
			return null
		instance = (template as Node).duplicate()
		instance.name = _make_instance_name(pool_name, int(pool.get("next_index", 1)))
		pool["next_index"] = int(pool.get("next_index", 1)) + 1

	pool["items"] = items
	_pools[pool_name] = pool

	var target_parent := parent if parent != null else _active_root
	if instance.get_parent() != null:
		instance.reparent(target_parent)
	else:
		target_parent.add_child(instance, true)
	_set_node_visible(instance, true)
	_notify_pool_pop(instance)
	return instance

func push(pool_name: StringName, node: Node, parent: Node = null) -> bool:
	if node == null:
		return false
	if not _pools.has(pool_name):
		dx.logger.warning("Pool", "未找到对象池，已直接释放节点: %s" % String(pool_name))
		node.queue_free()
		return false

	var pool: Dictionary = _pools[pool_name]
	var items: Array = pool["items"]
	var max_capacity: int = int(pool["max_capacity"])

	if items.size() >= max_capacity:
		node.queue_free()
		return false

	var target_parent := parent if parent != null else _inactive_root
	if node.get_parent() != null:
		node.reparent(target_parent)
	else:
		target_parent.add_child(node, true)
	_notify_pool_push(node)
	_set_node_visible(node, false)

	items.append({
		"node": node,
		"returned_at": dx.time.now_unix(),
	})
	pool["items"] = items
	_pools[pool_name] = pool
	return true

func clear(pool_name: StringName = &"") -> void:
	if pool_name.is_empty():
		for key in _pools.keys():
			_clear_pool_entries(key)
		_pools.clear()
		_clear_children(_active_root)
		_clear_children(_inactive_root)
		return

	_clear_pool_entries(pool_name)
	_pools.erase(pool_name)

func _make_template(source) -> Node:
	if source is PackedScene:
		return (source as PackedScene).instantiate()
	if source is Node:
		return (source as Node).duplicate()
	return null

func _make_instance_name(pool_name: StringName, index: int) -> String:
	return "%s_%d" % [String(pool_name), index]

func _make_template_name(pool_name: StringName) -> String:
	return "%s_Template" % String(pool_name)

func _cleanup_expired_objects() -> void:
	for key in _pools.keys():
		_cleanup_pool(key)

func _cleanup_pool(pool_name: StringName) -> void:
	if not _pools.has(pool_name):
		return

	var pool: Dictionary = _pools[pool_name]
	var expiration_seconds: float = float(pool["expiration_seconds"])
	if expiration_seconds <= 0.0:
		return

	var now: int = dx.time.now_unix()
	var items: Array = pool["items"]
	for index in range(items.size() - 1, -1, -1):
		var entry: Dictionary = items[index]
		var candidate = entry.get("node")
		var returned_at := float(entry.get("returned_at", 0.0))
		if not is_instance_valid(candidate) or not candidate is Node:
			items.remove_at(index)
			continue
		if now - returned_at < expiration_seconds:
			continue
		items.remove_at(index)
		(candidate as Node).queue_free()

	pool["items"] = items
	_pools[pool_name] = pool

func _clear_pool_entries(pool_name: StringName) -> void:
	if not _pools.has(pool_name):
		return

	var pool: Dictionary = _pools[pool_name]
	var items: Array = pool.get("items", [])
	for entry in items:
		var candidate = (entry as Dictionary).get("node")
		if is_instance_valid(candidate) and candidate is Node:
			(candidate as Node).queue_free()
	var template = pool.get("template")
	if is_instance_valid(template) and template is Node:
		(template as Node).queue_free()

func _notify_pool_pop(node: Node) -> void:
	if node != null and node.has_method("on_pool_pop"):
		node.call("on_pool_pop")

func _notify_pool_push(node: Node) -> void:
	if node != null and node.has_method("on_pool_push"):
		node.call("on_pool_push")

func _set_node_visible(node: Node, visible: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = visible
	elif node is Node3D:
		(node as Node3D).visible = visible

func _clear_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()
