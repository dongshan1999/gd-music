extends RefCounted

const SIGNAL_APP_PAUSE := &"app/pause"
const SIGNAL_APP_FOCUS := &"app/focus"
const SIGNAL_APP_BACKGROUND := &"app/background"

var dx: Node
var is_background := false
var has_focus := true

var _potential_background := false
var _potential_foreground := false

func in_pause(paused: bool) -> void:
	dx.signals.fire(SIGNAL_APP_PAUSE, paused)
	if paused:
		_set_background()
		dx.logger.log("BackgroundState", "应用进入后台")
	else:
		_set_foreground()
		dx.logger.log("BackgroundState", "应用返回前台")

func in_focus(focused: bool) -> void:
	has_focus = focused
	dx.signals.fire(SIGNAL_APP_FOCUS, focused)
	if focused:
		_set_foreground()
		dx.logger.log("BackgroundState", "应用获得焦点")
	else:
		_set_background()
		dx.logger.log("BackgroundState", "应用失去焦点")

func _set_background() -> void:
	if _potential_background:
		return
	_potential_background = true
	_potential_foreground = false
	is_background = true
	dx.signals.fire(SIGNAL_APP_BACKGROUND, true)

func _set_foreground() -> void:
	if _potential_foreground:
		return
	_potential_foreground = true
	_potential_background = false
	is_background = false
	dx.signals.fire(SIGNAL_APP_BACKGROUND, false)
