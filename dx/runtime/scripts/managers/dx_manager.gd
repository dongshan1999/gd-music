class_name DXManager
extends RefCounted

var framework: Node

func setup(owner: Node) -> void:
	framework = owner

func in_ready() -> void:
	pass

func in_process(_delta: float) -> void:
	pass

func in_exit_tree() -> void:
	pass

func in_quit() -> void:
	pass

func in_pause(_paused: bool) -> void:
	pass

func in_focus(_has_focus: bool) -> void:
	pass
