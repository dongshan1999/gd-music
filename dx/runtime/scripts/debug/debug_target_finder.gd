class_name DX_DebugTargetFinder
extends RefCounted

static func get_current_scene() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree != null else null

static func get_root_node(path: NodePath) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path)

static func find_child_by_script(root: Object, script_path: String) -> Object:
	var normalized_path := script_path.strip_edges()
	if root == null or normalized_path.is_empty():
		return null

	var result := {"target": null}
	_walk_object(
		root,
		func(target: Object) -> bool:
			if has_script_path(target, normalized_path):
				result["target"] = target
				return true
			return false,
		{}
	)
	return result["target"]

static func find_in_current_scene_by_script(script_path: String) -> Object:
	return find_child_by_script(get_current_scene(), script_path)

static func has_script_path(target: Object, script_path: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var script := target.get_script() as Script
	return script != null and script.resource_path == script_path

static func _walk_object(target: Object, visitor: Callable, visited: Dictionary) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var instance_id := target.get_instance_id()
	if visited.has(instance_id):
		return false
	visited[instance_id] = true

	var visitor_result = visitor.call(target)
	if visitor_result is bool and visitor_result:
		return true

	var node := target as Node
	if node != null:
		for child in node.get_children():
			if _walk_object(child, visitor, visited):
				return true

	return false
