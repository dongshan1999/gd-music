@tool
class_name DX_ResourceEntry
extends Resource

@export var id: StringName = &""
@export var value: Variant
@export var path: String = ""
@export_tool_button("Value 转路径并清空", "Callable") var convert_value_to_path_action := _convert_value_to_path

func normalize() -> void:
	id = StringName(id)

func _convert_value_to_path() -> void:
	if not value is Resource:
		push_warning("DX_ResourceEntry value is not a Resource, cannot read resource_path.")
		return

	var resource := value as Resource
	if resource.resource_path.is_empty():
		push_warning("DX_ResourceEntry value has no resource_path.")
		return

	path = resource.resource_path
	value = null
	emit_changed()
