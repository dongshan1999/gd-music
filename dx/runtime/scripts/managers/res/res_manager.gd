class_name DX_ResManager
extends RefCounted

const ResourceLibraryScript := preload("res://dx/runtime/scripts/managers/res/resource_library.gd")

const DEFAULT_LIBRARY_DIR := "res://dx/data/resources"

var dx: Node
var library_dir: String = DEFAULT_LIBRARY_DIR

var _path_cache: Dictionary = {}
var _entries_by_key: Dictionary = {}

func in_ready() -> void:
	_load_libraries()

func get_by_id(library_id: StringName, id: StringName):
	var key := _make_entry_key(library_id, id)
	if not _entries_by_key.has(key):
		push_error("DX_ResManager cannot find resource id '%s'." % String(key))
		return null
	var entry = _entries_by_key[key] as DX_ResourceEntry
	return _resolve_entry_value(entry)

func get_scene(id: StringName) -> PackedScene:
	return get_by_id(&"scene", id) as PackedScene

func get_texture(id: StringName) -> Texture2D:
	return get_by_id(&"texture", id) as Texture2D

# Dictionary | Array | JSON
func get_json(id: StringName):
	return get_by_id(&"json", id)

func _load_libraries(path: String = DEFAULT_LIBRARY_DIR) -> void:
	library_dir = path
	_entries_by_key.clear()

	var dir := DirAccess.open(library_dir)
	if dir == null:
		push_warning("DX_ResManager cannot open resource library dir '%s'." % library_dir)
		return

	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		_load_library(library_dir.path_join(file_name))
	dir.list_dir_end()

func _load_library(path: String) -> void:
	var library := ResourceLoader.load(path) as ResourceLibraryScript
	if library == null:
		push_warning("DX_ResManager skipped non-library resource '%s'." % path)
		return
	library.normalize()
	if library.library_id == &"":
		push_warning("DX_ResManager skipped resource library without library_id: '%s'." % path)
		return

	for entry in library.entries:
		if entry == null or entry.id == &"":
			continue
		_register_entry(library.library_id, entry)

func _register_entry(library_id: StringName, entry: DX_ResourceEntry) -> void:
	var key := _make_entry_key(library_id, entry.id)
	if _entries_by_key.has(key):
		push_warning("DX_ResManager replaced duplicate resource id '%s'." % key)
	_entries_by_key[key] = entry

func _resolve_entry_value(entry: DX_ResourceEntry):
	if entry.value != null:
		return entry.value
	if entry.path.is_empty():
		return null
	entry.value = _load_path_resource(entry.path)
	return entry.value

func _load_path_resource(path: String):
	if _path_cache.has(path):
		return _path_cache[path]
	if not ResourceLoader.exists(path):
		push_error("DX_ResManager cannot find resource path '%s'." % path)
		return null
	var resource := ResourceLoader.load(path)
	if resource == null:
		push_error("DX_ResManager failed to load resource path '%s'." % path)
		return null
	_path_cache[path] = resource
	return resource

func _make_entry_key(library_id: StringName, id: StringName) -> StringName:
	return StringName("%s/%s" % [String(library_id), String(id)])
