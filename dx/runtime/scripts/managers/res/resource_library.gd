class_name DX_ResourceLibrary
extends Resource

const ResourceEntryScript := preload("res://dx/runtime/scripts/managers/res/resource_entry.gd")

@export var library_id: StringName = &""
@export var entries: Array[ResourceEntryScript] = []

func normalize() -> void:
	library_id = StringName(library_id)
	if entries == null:
		entries = []
	for entry in entries:
		if entry != null:
			entry.normalize()
