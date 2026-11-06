extends "res://dx/runtime/scripts/component/scroll/scroll_interaction_comp.gd"

## 音乐应用统一的滚动手感：滚轮平滑、隐藏滚动条（滚动时短暂显示）。
## 触摸拖拽 / 惯性 / 按压高亮取消都沿用基类，改基类即对所有列表生效。

const INDICATOR_ALPHA := 0.8
const INDICATOR_HOLD_SEC := 0.9
const INDICATOR_FADE_SEC := 0.25

var _indicator_alpha := 0.0
var _indicator_hold := 0.0
var _indicator_bar: VScrollBar

func _ready() -> void:
	configure_scroll_modes = false
	enable_horizontal_scroll = false
	wheel_scroll_step = 72
	super._ready()
	if _scroll == null:
		return
	_scroll.follow_focus = true
	_indicator_bar = _scroll.get_v_scroll_bar()
	if _indicator_bar == null:
		return
	_indicator_bar.modulate.a = 0.0
	_indicator_bar.value_changed.connect(_show_indicator)
	_indicator_bar.mouse_entered.connect(_show_indicator.bind(0.0))

func _process(delta: float) -> void:
	super._process(delta)
	_update_indicator(delta)

## 只在指针确实落在本滚动容器上时才响应，避免叠放页面里的列表同时滚动。
func _is_pointer_inside_scroll(pointer: Vector2) -> bool:
	if not super._is_pointer_inside_scroll(pointer) or not _scroll.is_visible_in_tree():
		return false
	var viewport := get_viewport()
	if viewport == null:
		return true
	var hovered := viewport.gui_get_hovered_control()
	if hovered == null:
		return true
	return hovered == _scroll or _scroll.is_ancestor_of(hovered)

func _show_indicator(_value: float) -> void:
	if _indicator_bar == null:
		return
	_indicator_alpha = INDICATOR_ALPHA
	_indicator_hold = INDICATOR_HOLD_SEC
	_indicator_bar.modulate.a = INDICATOR_ALPHA

func _update_indicator(delta: float) -> void:
	if _indicator_alpha <= 0.0 or _indicator_bar == null:
		return
	if _indicator_hold > 0.0:
		_indicator_hold = maxf(0.0, _indicator_hold - delta)
		return
	_indicator_alpha = maxf(0.0, _indicator_alpha - delta * (INDICATOR_ALPHA / INDICATOR_FADE_SEC))
	_indicator_bar.modulate.a = _indicator_alpha
