class_name DXBackgroundStateManager
extends "res://dx/runtime/scripts/managers/dx_manager.gd"

const SIGNAL_APP_PAUSE := &"app/pause"
const SIGNAL_APP_FOCUS := &"app/focus"
const SIGNAL_APP_BACKGROUND := &"app/background"

var is_background := false
var has_focus := true

var _potential_background := false
var _potential_foreground := false

func in_pause(paused: bool) -> void:
	framework.signals.fire(SIGNAL_APP_PAUSE, paused)
	if paused:
		_set_background()
		framework.logger.log("BackgroundState", "应用进入后台")
	else:
		_set_foreground()
		framework.logger.log("BackgroundState", "应用返回前台")

func in_focus(focused: bool) -> void:
	has_focus = focused
	framework.signals.fire(SIGNAL_APP_FOCUS, focused)
	if focused:
		_set_foreground()
		framework.logger.log("BackgroundState", "应用获得焦点")
	else:
		_set_background()
		framework.logger.log("BackgroundState", "应用失去焦点")

func _set_background() -> void:
	if _potential_background:
		return
	_potential_background = true
	_potential_foreground = false
	is_background = true
	framework.signals.fire(SIGNAL_APP_BACKGROUND, true)

func _set_foreground() -> void:
	if _potential_foreground:
		return
	_potential_foreground = true
	_potential_background = false
	is_background = false
	framework.signals.fire(SIGNAL_APP_BACKGROUND, false)
