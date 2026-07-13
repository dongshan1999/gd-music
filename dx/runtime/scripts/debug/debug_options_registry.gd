class_name DX_DebugOptionsRegistry
extends RefCounted

var debug
var _options_scripts: Array[Script] = []
var _options_list: Array = []
var _bound_instance_ids: Dictionary = {}

func setup(debug_manager) -> void:
	debug = debug_manager
	_rebuild_options()

func set_options_scripts(options_scripts: Array[Script]) -> void:
	_options_scripts = options_scripts.duplicate()
	_rebuild_options()

func discover_current_scene() -> void:
	if debug == null or not OS.is_debug_build():
		return

	_bound_instance_ids.clear()
	debug.clear_runtime_targets()
	for options in _options_list:
		if not options.has_method("get_targets"):
			continue
		var targets = options.get_targets()
		if not targets is Array:
			continue
		for target in targets:
			_bind_option_target(options, target)

func _rebuild_options() -> void:
	_options_list.clear()
	if debug == null:
		return

	for options_script in _options_scripts:
		var options = options_script.new()
		if not _is_valid_options(options):
			continue
		options.setup(debug)
		if options.has_method("register_options"):
			options.register_options()
		_options_list.append(options)

func _bind_option_target(options, target: Object) -> void:
	if target == null or not is_instance_valid(target):
		return

	var bind_key := "%s:%d" % [str(options.get_instance_id()), target.get_instance_id()]
	if _bound_instance_ids.has(bind_key):
		return
	_bound_instance_ids[bind_key] = true
	options.bind(target)

func _is_valid_options(options) -> bool:
	return options != null \
		and options.has_method("setup") \
		and options.has_method("get_targets") \
		and options.has_method("bind")
