class_name MusicAppJavaHttpBridge
extends RefCounted

## Android 上引擎自带的 HTTPRequest 在部分机型上连 request_completed / timeout 都不触发，
## 表现为「请求发出去、永远没有回调」。这里统一改由 Android 插件用系统网络栈代发 GET，
## 再通过 `media_control` 信号把结果回传到 GDScript。
##
## 登录（B 站扫码）与封面下载原本各写了一套一模一样的通道，合并到这里只留一份。

const RESULT_PREFIX := "http_result:"
const ERROR_PREFIX := "http_error:"
const POLL_INTERVAL_SECONDS := 0.05

var _seq := 0
var _pending: Dictionary = {}
var _signal_plugin: Variant = null

## 发一次 GET。返回 {"ok": bool, "bytes": PackedByteArray, "error": String}。
## error 取值：plugin_unavailable / method_missing / signal_missing / timeout / <Java 异常类名>。
func request_bytes(host: Node, url: String, timeout_seconds: float, prefix: String) -> Dictionary:
	var failed := {"ok": false, "bytes": PackedByteArray(), "error": ""}
	var target := url.strip_edges()
	if target.is_empty():
		failed["error"] = "empty_url"
		return failed
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		failed["error"] = "host_unavailable"
		return failed
	var plugin: Variant = Engine.get_singleton("GDMusicBackgroundAudio")
	if plugin == null:
		failed["error"] = "plugin_unavailable"
		return failed
	# JNISingleton 暴露的 Java 方法不进 ClassDB，has_method() 恒为 false，必须用 has_java_method()。
	if plugin.has_method("has_java_method") and not bool(plugin.has_java_method("httpGet")):
		failed["error"] = "method_missing"
		return failed
	if _signal_plugin == null:
		if not plugin.has_signal("media_control"):
			failed["error"] = "signal_missing"
			return failed
		plugin.connect("media_control", _on_media_control)
		_signal_plugin = plugin

	_seq += 1
	var request_id := "%s-%d" % [prefix, _seq]
	_pending[request_id] = {"done": false, "payload": PackedByteArray(), "error": ""}
	plugin.httpGet(target, request_id)

	var tree: SceneTree = host.get_tree()
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var snapshot: Dictionary = _pending.get(request_id, {})
		if snapshot.is_empty() or bool(snapshot.get("done", false)):
			break
		var tick: SceneTreeTimer = tree.create_timer(POLL_INTERVAL_SECONDS)
		await tick.timeout

	var finished: Dictionary = _pending.get(request_id, {})
	_pending.erase(request_id)
	if finished.is_empty() or not bool(finished.get("done", false)):
		failed["error"] = "timeout"
		return failed
	var error_text := String(finished.get("error", ""))
	if not error_text.is_empty():
		failed["error"] = error_text
		return failed
	return {"ok": true, "bytes": finished.get("payload", PackedByteArray()), "error": ""}

func _on_media_control(action: String) -> void:
	var is_result := action.begins_with(RESULT_PREFIX)
	var is_error := action.begins_with(ERROR_PREFIX)
	if not is_result and not is_error:
		return
	var rest := action.substr(RESULT_PREFIX.length())
	var split_at := rest.find(":")
	if split_at <= 0:
		return
	var request_id := rest.substr(0, split_at)
	if not _pending.has(request_id):
		return
	if is_result:
		_pending[request_id] = {
			"done": true,
			"payload": Marshalls.base64_to_raw(rest.substr(split_at + 1)),
			"error": "",
		}
		return
	_pending[request_id] = {
		"done": true,
		"payload": PackedByteArray(),
		"error": rest.substr(split_at + 1),
	}
