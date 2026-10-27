## 播放后端工厂。
##
## 选择规则（优先级从高到低）：
##   1. 项目设置 `audio/backend/use_mpv` 显式为 true/false —— 人工强制
##   2. 移动端（Android / iOS）且 gdmpv 扩展已编译加载 —— 自动启用 mpv
##   3. 其余情况 —— 沿用 Godot 原生播放器
##
## 任何时候 `GDMPVPlayer` 不可用都会安静回退，不会让 App 无法播放。
class_name AudioBackendFactory
extends RefCounted

const SETTING_USE_MPV := "audio/backend/use_mpv"
const GDMPV_CLASS := "GDMPVPlayer"

const MOBILE_PLATFORMS := ["Android", "iOS"]


## gdmpv 扩展是否已经在编辑器/运行时注册。
static func is_mpv_built() -> bool:
	return ClassDB.class_exists(GDMPV_CLASS)


## 是否应该走 mpv 后端（不考虑构建是否就绪）。
static func should_use_mpv() -> bool:
	var forced: Variant = ProjectSettings.get_setting(SETTING_USE_MPV, null)
	if forced is bool:
		return forced
	return OS.get_name() in MOBILE_PLATFORMS


## 创建后端。返回 null 表示「沿用现有 Godot 播放器路径」。
##
## @param host  用于挂载 GDMPVPlayer 节点的宿主（通常是 showcase）
static func try_create(host: Node) -> AudioBackend:
	# 扩展没编译时静默回退；只有用户显式要求 mpv 才提醒一次。
	if not is_mpv_built():
		if ProjectSettings.get_setting(SETTING_USE_MPV, null) == true:
			push_warning(
				"audio/backend/use_mpv 已开启，但 GDMPVPlayer 未注册："
				+ "addons/gdmpv 未编译或未加载，已回退到 Godot 原生播放器。"
			)
		return null
	if not should_use_mpv():
		return null

	var backend := LibMpvAudioBackend.new(host)
	if not backend.is_available():
		push_warning("libmpv 后端不可用，已回退：%s" % backend.get_init_error())
		backend.shutdown()
		return null
	return backend


## 把已有播放器节点包成后端，用于「Godot 原生路径」的显式封装。
static func wrap_node(player: Node) -> AudioBackend:
	if player == null:
		return null
	return NodeAudioBackend.new(player)
