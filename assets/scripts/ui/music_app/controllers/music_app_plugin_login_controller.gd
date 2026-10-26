class_name MusicAppPluginLoginController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

## B 站扫码登录与手动 Cookie 登录的公共入口。
## 只负责“拿到一份可用的 cookie 并落盘”，不关心弹窗长什么样。

const PLUGIN_ID := "bilibili"
const GENERATE_URL := "https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
const POLL_URL := "https://passport.bilibili.com/x/passport-login/web/qrcode/poll"
const LOGIN_SOURCE := "main-fe-header"
const REQUEST_TIMEOUT_SECONDS := 8.0

## 轮询状态，取值与界面文案一一对应。
const STATE_WAITING := "waiting"      # 未扫码
const STATE_SCANNED := "scanned"      # 已扫码待确认
const STATE_EXPIRED := "expired"      # 二维码失效
const STATE_SUCCESS := "success"      # 登录成功
const STATE_FAILED := "failed"        # 网络或响应异常

## 只保留这些字段，避免把网关塞过来的杂项 cookie 一起存下来。
const COOKIE_WHITELIST := [
	"SESSDATA",
	"bili_jct",
	"DedeUserID",
	"DedeUserID__ckMd5",
	"sid",
	"buvid3",
	"buvid4",
	"b_nut",
]

const LOGIN_HEADERS := {
	"user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
	"accept": "application/json, text/plain, */*",
	"referer": "https://www.bilibili.com/",
}

var last_error := ""

## 申请一个登录二维码；返回 {"url": String, "qrcode_key": String}，失败返回 {}。
func generate_qrcode() -> Dictionary:
	last_error = ""
	var response := await _request(GENERATE_URL, {"source": LOGIN_SOURCE})
	if response.is_empty():
		return {}
	var body: Dictionary = response.get("body", {}) if response.get("body") is Dictionary else {}
	var data: Dictionary = body.get("data", {}) if body.get("data") is Dictionary else {}
	var url := str(data.get("url", "")).strip_edges()
	var qrcode_key := str(data.get("qrcode_key", "")).strip_edges()
	if url.is_empty() or qrcode_key.is_empty():
		last_error = "二维码申请失败，请稍后重试。"
		return {}
	return {"url": url, "qrcode_key": qrcode_key}

## 轮询扫码结果；返回 {"state": String, "cookie": String}。
func poll_qrcode(qrcode_key: String) -> Dictionary:
	var normalized_key := qrcode_key.strip_edges()
	if normalized_key.is_empty():
		return {"state": STATE_FAILED, "cookie": ""}
	var response := await _request(
		POLL_URL,
		{"qrcode_key": normalized_key, "source": LOGIN_SOURCE}
	)
	if response.is_empty():
		return {"state": STATE_FAILED, "cookie": ""}
	var body: Dictionary = response.get("body", {}) if response.get("body") is Dictionary else {}
	var data: Dictionary = body.get("data", {}) if body.get("data") is Dictionary else {}
	var state_code := int(data.get("code", -1))
	if state_code == 0:
		var cookie := _extract_cookie_header(response.get("headers"))
		if cookie.is_empty():
			last_error = "登录成功但未拿到登录凭据，请重试。"
			return {"state": STATE_FAILED, "cookie": ""}
		return {"state": STATE_SUCCESS, "cookie": cookie}
	if state_code == 86101:
		return {"state": STATE_WAITING, "cookie": ""}
	if state_code == 86090:
		return {"state": STATE_SCANNED, "cookie": ""}
	if state_code == 86038:
		return {"state": STATE_EXPIRED, "cookie": ""}
	last_error = str(data.get("message", "登录状态未知。"))
	return {"state": STATE_FAILED, "cookie": ""}

## 保存并校验一份 cookie；返回 {"ok": bool, "uname": String, "message": String}。
## 校验失败的 cookie 会回滚，避免把无效凭据写进存档。
func apply_cookie(cookie_header: String) -> Dictionary:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		last_error = "插件控制器未就绪。"
		return {"ok": false, "uname": "", "message": last_error}

	var previous_cookie: String = plugin_controller.get_plugin_cookie(PLUGIN_ID)
	var normalized_cookie := cookie_header.strip_edges()
	if normalized_cookie.is_empty():
		plugin_controller.set_plugin_cookie(PLUGIN_ID, "")
		return {"ok": true, "uname": "", "message": "已退出登录。"}

	plugin_controller.set_plugin_cookie(PLUGIN_ID, normalized_cookie)
	var status: Dictionary = await plugin_controller.fetch_plugin_login_status(PLUGIN_ID)
	if bool(status.get("is_login", false)):
		return {"ok": true, "uname": str(status.get("uname", "")), "message": ""}

	plugin_controller.set_plugin_cookie(PLUGIN_ID, previous_cookie)
	return {"ok": false, "uname": "", "message": "Cookie 无效或已过期，请重新获取。"}

## 查询当前已保存的登录态，供弹窗打开时展示。
func fetch_current_login() -> Dictionary:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return {"logged_in": false, "uname": "", "has_cookie": false}
	var has_cookie := not str(plugin_controller.get_plugin_cookie(PLUGIN_ID)).is_empty()
	if not has_cookie:
		return {"logged_in": false, "uname": "", "has_cookie": false}
	var status: Dictionary = await plugin_controller.fetch_plugin_login_status(PLUGIN_ID)
	return {
		"logged_in": bool(status.get("is_login", false)),
		"uname": str(status.get("uname", "")),
		"has_cookie": true,
	}

## 退出登录：清空存档里的 cookie。
func logout() -> void:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return
	plugin_controller.set_plugin_cookie(PLUGIN_ID, "")

func _request(url: String, query: Dictionary) -> Dictionary:
	var full_url := url
	if not query.is_empty():
		var pairs := PackedStringArray()
		for key in query.keys():
			pairs.append("%s=%s" % [str(key).uri_encode(), str(query[key]).uri_encode()])
		full_url = "%s?%s" % [url, "&".join(pairs)]

	# 桌面平台优先用系统 curl：这类请求量极小，curl 比 HTTPRequest 稳得多。
	var curl_result := _request_via_curl(full_url)
	if not curl_result.is_empty():
		return curl_result

	var host = get_showcase()
	if host == null:
		last_error = "应用窗口未就绪。"
		return {}
	var tree: SceneTree = host.get_tree()
	if tree == null:
		last_error = "应用窗口未就绪。"
		return {}

	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	host.add_child(request)

	var state := {
		"done": false,
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"code": 0,
		"headers": PackedStringArray(),
		"body": PackedByteArray(),
	}
	request.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			state["done"] = true
			state["result"] = result
			state["code"] = code
			state["headers"] = headers
			state["body"] = body
	)

	var err := request.request(full_url, _build_header_lines(LOGIN_HEADERS), HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		last_error = "无法发起登录请求（%d）。" % err
		return {}

	# 自己计时：HTTPRequest 的 timeout 只管建连，卡住时必须靠这里兜底。
	# 用 process_frame 而不是 SceneTreeTimer：前者每帧必发，最不容易被卡住。
	var frames := 0
	var max_frames := int((REQUEST_TIMEOUT_SECONDS + 5.0) * 60.0)
	while not bool(state["done"]) and frames < max_frames:
		await tree.process_frame
		frames += 1

	if not bool(state["done"]):
		request.cancel_request()
		request.queue_free()
		var fallback := _request_via_curl(full_url)
		if not fallback.is_empty():
			return fallback
		last_error = "连接 B 站超时，请检查网络后重试。"
		return {}

	request.queue_free()
	var result_code := int(state["result"])
	var response_code := int(state["code"])
	if result_code != HTTPRequest.RESULT_SUCCESS:
		last_error = "网络请求失败（%d），请检查网络后重试。" % result_code
		return {}

	var body_text := (state["body"] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	return {
		"body": parsed if parsed is Dictionary else {},
		"headers": state["headers"],
		"response_code": response_code,
	}

## HTTPRequest 在部分桌面环境下会卡死（TLS/代理层不回调），此时用系统 curl 兜底。
func _request_via_curl(full_url: String) -> Dictionary:
	var platform := OS.get_name()
	if platform != "macOS" and platform != "Linux" and platform != "Windows":
		return {}
	var curl_path := "curl.exe" if platform == "Windows" else "/usr/bin/curl"
	var output: Array = []
	var args := PackedStringArray([
		"-s", "-i", "--max-time", "8",
		"-H", "User-Agent: " + str(LOGIN_HEADERS.get("user-agent", "")),
		"-H", "Referer: https://www.bilibili.com/",
		full_url,
	])
	var exit_code := OS.execute(curl_path, args, output, true)
	var raw := str(output[0]) if output.size() > 0 else ""
	if exit_code != 0 or raw.strip_edges().is_empty():
		return {}

	var headers := PackedStringArray()
	var body_lines := PackedStringArray()
	var in_body := false
	for line in raw.replace("\r\n", "\n").split("\n"):
		if in_body:
			body_lines.append(line)
			continue
		if line.strip_edges().is_empty():
			in_body = true
			continue
		if line.begins_with("HTTP/"):
			continue
		headers.append(line)
	var body_text := "\n".join(body_lines)
	var parsed: Variant = JSON.parse_string(body_text)
	return {
		"body": parsed if parsed is Dictionary else {},
		"headers": headers,
		"response_code": 200,
	}

func _build_header_lines(headers: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key in headers.keys():
		lines.append("%s: %s" % [str(key), str(headers[key])])
	return lines

## 从 Set-Cookie 响应头里拣出白名单字段，拼成 "k=v; k=v"。
func _extract_cookie_header(headers: Variant) -> String:
	if not (headers is PackedStringArray):
		return ""

	var collected := {}
	for header_line in headers:
		var line := str(header_line)
		var separator := line.find(":")
		if separator <= 0:
			continue
		if line.substr(0, separator).strip_edges().to_lower() != "set-cookie":
			continue
		var raw_value := line.substr(separator + 1).strip_edges()
		# 上游可能把多条 Set-Cookie 合并进一行，按逗号再切一次。
		for fragment in raw_value.split(",", false):
			var pair := fragment.split(";")[0].strip_edges()
			var equals := pair.find("=")
			if equals <= 0:
				continue
			var name := pair.substr(0, equals).strip_edges()
			if not COOKIE_WHITELIST.has(name):
				continue
			collected[name] = pair

	var ordered := PackedStringArray()
	for name in COOKIE_WHITELIST:
		if collected.has(name):
			ordered.append(str(collected[name]))
	return "; ".join(ordered)
