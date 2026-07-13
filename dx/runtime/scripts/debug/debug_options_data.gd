class_name DX_DebugOptionsData
extends RefCounted

const OptionsScripts: Array[Script] = [

]

func get_options_scripts() -> Array[Script]:
	return OptionsScripts.duplicate()
