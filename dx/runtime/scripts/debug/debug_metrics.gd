class_name DX_DebugMetrics
extends RefCounted

const TYPE_READONLY := "readonly"

func get_system_descriptors() -> Array[Dictionary]:
	return [
		{
			"id": "System",
			"items": [
				_readonly("System", "FPS", Callable(self, "_get_fps")),
				_readonly("System", "平台", Callable(self, "_get_platform")),
				_readonly("System", "Godot版本", Callable(self, "_get_godot_version")),
				_readonly("System", "Debug构建", Callable(self, "_get_debug_build")),
				_readonly("System", "窗口尺寸", Callable(self, "_get_window_size")),
				_readonly("System", "当前场景", Callable(self, "_get_current_scene")),
			],
		}
	]

func get_profiler_descriptors() -> Array[Dictionary]:
	return [
		{
			"id": "Profiler",
			"items": [
				_readonly("Time", "处理耗时(ms)", Callable(self, "_get_process_ms")),
				_readonly("Time", "物理耗时(ms)", Callable(self, "_get_physics_process_ms")),
				_readonly("Memory", "静态内存(MB)", Callable(self, "_get_static_memory_mb")),
				_readonly("Objects", "对象数量", Callable(self, "_get_object_count")),
				_readonly("Objects", "节点数量", Callable(self, "_get_node_count")),
				_readonly("Objects", "资源数量", Callable(self, "_get_resource_count")),
				_readonly("Objects", "孤儿节点", Callable(self, "_get_orphan_node_count")),
				_readonly("Render", "Draw Calls", Callable(self, "_get_draw_calls")),
			],
		}
	]

func _readonly(group: String, name: String, getter: Callable) -> Dictionary:
	return {
		"target_id": "Runtime",
		"type": TYPE_READONLY,
		"group": group,
		"name": name,
		"member_name": "",
		"is_method": false,
		"getter": getter,
	}

func _get_fps() -> String:
	return "%.1f" % Performance.get_monitor(Performance.TIME_FPS)

func _get_platform() -> String:
	return OS.get_name()

func _get_godot_version() -> String:
	var info := Engine.get_version_info()
	return "%s.%s.%s %s" % [
		str(info.get("major", "")),
		str(info.get("minor", "")),
		str(info.get("patch", "")),
		str(info.get("status", "")),
	]

func _get_debug_build() -> String:
	return "是" if OS.is_debug_build() else "否"

func _get_window_size() -> String:
	var size := DisplayServer.window_get_size()
	return "%d x %d" % [size.x, size.y]

func _get_current_scene() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return ""
	return tree.current_scene.scene_file_path

func _get_process_ms() -> String:
	return "%.3f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)

func _get_physics_process_ms() -> String:
	return "%.3f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

func _get_static_memory_mb() -> String:
	return "%.2f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)

func _get_object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

func _get_node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _get_resource_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))

func _get_orphan_node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _get_draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
