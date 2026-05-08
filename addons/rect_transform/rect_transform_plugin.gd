@tool
class_name RectTransformPlugin
extends EditorPlugin

var _inspector_plugin: RectTransformInspectorPlugin

func _enter_tree() -> void:
	var editor_interface := get_editor_interface()
	_inspector_plugin = RectTransformInspectorPlugin.new()
	_inspector_plugin.setup(editor_interface, get_undo_redo())
	add_inspector_plugin(_inspector_plugin)

func _exit_tree() -> void:
	if _inspector_plugin != null:
		if _inspector_plugin.has_method("dispose"):
			_inspector_plugin.dispose()
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
