class_name DX_PoolManager
extends RefCounted

const DEFAULT_MAX_CAPACITY := 100
const DEFAULT_EXPIRATION_SECONDS := 300.0
const ACTIVE_ROOT_NAME := "PoolActive"
const INACTIVE_ROOT_NAME := "PoolInactive"

var dx: Node
var _active_root: Node
var _inactive_root: Node
var _pools: Dictionary = {}
var _cleanup_timer := 0.0

func in_ready() -> void:
	_ensure_roots()

func in_process(delta: float) -> void:
	_cleanup_timer += delta
	if _cleanup_timer < 5.0:
		return
	_cleanup_timer = 0.0
	_cleanup_expired_objects()

func init(
	name: StringName,
	template: Node,
	max_capacity: int = DEFAULT_MAX_CAPACITY,
	expiration_seconds: float = DEFAULT_EXPIRATION_SECONDS
) -> bool:
	if template == null:
		dx.logger.error("Pool", "初始化对象池失败，template 不能为空: %s" % String(name))
		return false

	_ensure_roots()
	_clear_pool_entries(name)

	if template.get_parent() != null:
		template.reparent(_inactive_root)
	else:
		_inactive_root.add_child(template)
	_set_node_active_state(template, false)

	_pools[name] = {
		"template": template,
		"items": [],
		"max_capacity": maxi(1, max_capacity),
		"expiration_seconds": maxf(0.0, expiration_seconds),
	}
	return true

func contains(name: StringName) -> bool:
	return _pools.has(name)

func pop(name: StringName, parent: Node = null) -> Node:
	if not _pools.has(name):
		dx.logger.warning("Pool", "未找到对象池: %s" % String(name))
		return null

	_ensure_roots()
	_cleanup_pool(name)

	var pool: Dictionary = _pools[name]
	var items: Array = pool["items"]
	var instance: Node = null
	while not items.is_empty() and instance == null:
		var entry: Dictionary = items.pop_back()
		var candidate := entry.get("node") as Node
		if is_instance_valid(candidate):
			instance = candidate

	if instance == null:
		var template: Node = pool.get("template") as Node
		if not is_instance_valid(template):
			dx.logger.error("Pool", "对象池模板无效: %s" % String(name))
			pool["items"] = items
			_pools[name] = pool
			return null
		instance = template.duplicate()

	pool["items"] = items
	_pools[name] = pool

	var target_parent := parent if parent != null else _active_root
	if instance.get_parent() != null:
		instance.reparent(target_parent)
	else:
		target_parent.add_child(instance)
	_set_node_active_state(instance, true)
	if instance.has_method("on_pool_pop"):
		instance.call("on_pool_pop")
	return instance

func push(name: StringName, node: Node, parent: Node = null) -> bool:
	if node == null:
		return false
	if not _pools.has(name):
		dx.logger.warning("Pool", "未找到对象池，已直接释放节点: %s" % String(name))
		node.queue_free()
		return false

	_ensure_roots()
	var pool: Dictionary = _pools[name]
	var items: Array = pool["items"]
	var max_capacity: int = int(pool["max_capacity"])

	if items.size() >= max_capacity:
		node.queue_free()
		return false

	var target_parent := parent if parent != null else _inactive_root
	if node.get_parent() != null:
		node.reparent(target_parent)
	else:
		target_parent.add_child(node)
	_set_node_active_state(node, false)
	if node.has_method("on_pool_push"):
		node.call("on_pool_push")

	items.append({
		"node": node,
		"returned_at": dx.time.now_unix(),
	})
	pool["items"] = items
	_pools[name] = pool
	return true

func clear(name: StringName = &"") -> void:
	if name.is_empty():
		for key in _pools.keys():
			_clear_pool_entries(key)
		_pools.clear()
		if is_instance_valid(_active_root):
			_active_root.queue_free()
			_active_root = null
		if is_instance_valid(_inactive_root):
			_inactive_root.queue_free()
			_inactive_root = null
		return

	_clear_pool_entries(name)
	_pools.erase(name)

func _ensure_roots() -> void:
	if _active_root == null:
		_active_root = Node.new()
		_active_root.name = ACTIVE_ROOT_NAME
		dx.add_child(_active_root)
	if _inactive_root == null:
		_inactive_root = Node.new()
		_inactive_root.name = INACTIVE_ROOT_NAME
		dx.add_child(_inactive_root)

func _cleanup_expired_objects() -> void:
	for key in _pools.keys():
		_cleanup_pool(key)

func _cleanup_pool(name: StringName) -> void:
	if not _pools.has(name):
		return

	var pool: Dictionary = _pools[name]
	var expiration_seconds: float = float(pool["expiration_seconds"])
	if expiration_seconds <= 0.0:
		return

	var now := dx.time.now_unix()
	var items: Array = pool["items"]
	for index in range(items.size() - 1, -1, -1):
		var entry: Dictionary = items[index]
		var candidate := entry.get("node") as Node
		var returned_at := float(entry.get("returned_at", 0.0))
		if not is_instance_valid(candidate):
			items.remove_at(index)
			continue
		if now - returned_at < expiration_seconds:
			continue
		items.remove_at(index)
		candidate.queue_free()

	pool["items"] = items
	_pools[name] = pool

func _clear_pool_entries(name: StringName) -> void:
	if not _pools.has(name):
		return

	var pool: Dictionary = _pools[name]
	var items: Array = pool.get("items", [])
	for entry in items:
		var candidate := (entry as Dictionary).get("node") as Node
		if is_instance_valid(candidate):
			candidate.queue_free()
	var template := pool.get("template") as Node
	if is_instance_valid(template):
		template.queue_free()

func _set_node_active_state(node: Node, visible: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = visible
	elif node is Node3D:
		(node as Node3D).visible = visible
