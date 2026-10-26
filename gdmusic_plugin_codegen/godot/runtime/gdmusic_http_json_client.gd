class_name GDMusicHttpJsonClient
extends RefCounted

const DEFAULT_TIMEOUT_SEC := 15.0
var last_error := ""

func get_json(
	url: String,
	query: Dictionary = {},
	headers: Dictionary = {},
	timeout_sec: float = DEFAULT_TIMEOUT_SEC
) -> Variant:
	return await request_json(url, query, headers, HTTPClient.METHOD_GET, "", timeout_sec)

func request_json(
	url: String,
	query: Dictionary = {},
	headers: Dictionary = {},
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	body: String = "",
	timeout_sec: float = DEFAULT_TIMEOUT_SEC
) -> Variant:
	last_error = ""
	var response = await request(_build_url(url, query), headers, method, body, timeout_sec)
	if not bool(response.get("ok", false)):
		last_error = "%s (HTTP %s)" % [str(response.get("error", "Network request failed.")), str(response.get("response_code", 0))]
		return null

	var response_body: PackedByteArray = response.get("body", PackedByteArray())
	if response_body.is_empty():
		last_error = "Empty HTTP response."
		return null

	var parsed = JSON.parse_string(response_body.get_string_from_utf8())
	if parsed == null:
		last_error = "HTTP response is not valid JSON."
	return parsed

func build_url(base_url: String, query: Dictionary = {}) -> String:
	return _build_url(base_url, query)

func build_form_body(query: Dictionary = {}) -> String:
	return _build_query_string(query)

func get_text(
	url: String,
	query: Dictionary = {},
	headers: Dictionary = {},
	timeout_sec: float = DEFAULT_TIMEOUT_SEC
) -> String:
	var response = await request(
		_build_url(url, query),
		headers,
		HTTPClient.METHOD_GET,
		"",
		timeout_sec
	)
	if not bool(response.get("ok", false)):
		return ""

	var response_body: PackedByteArray = response.get("body", PackedByteArray())
	return response_body.get_string_from_utf8()

func request(
	url: String,
	headers: Dictionary = {},
	method: HTTPClient.Method = HTTPClient.METHOD_GET,
	body: String = "",
	timeout_sec: float = DEFAULT_TIMEOUT_SEC
) -> Dictionary:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {"ok": false, "error": "SceneTree is not available for HTTP requests."}

	var request_host = Node.new()
	request_host.name = "GDMusicHttpRequestHost"
	var http_request = HTTPRequest.new()
	http_request.timeout = timeout_sec
	request_host.add_child(http_request)
	# 挂在 SceneTree.root（Window）下时 HTTPRequest 会返回 ERR_UNCONFIGURED，
	# 因此优先挂到当前场景这个普通节点上。
	var host: Node = tree.current_scene
	if host == null or not host.is_inside_tree():
		host = tree.root
	host.add_child(request_host)

	var error = http_request.request(url, _build_header_array(headers), method, body)
	if error != OK:
		request_host.queue_free()
		return {
			"ok": false,
			"error": "HTTPRequest.request failed.",
			"error_code": error,
			"url": url,
		}

	var state := {"done": false, "result": null}
	http_request.request_completed.connect(
		func(req_result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
			state["done"] = true
			state["result"] = [req_result, response_code, response_headers, response_body]
	)

	# 自己计时：部分环境下 request_completed 不会回调，只能靠帧计数兜底。
	var frames := 0
	var max_frames := int((timeout_sec + 3.0) * 60.0)
	while not bool(state["done"]) and frames < max_frames:
		await tree.process_frame
		frames += 1

	if not bool(state["done"]):
		http_request.cancel_request()
		request_host.queue_free()
		var fallback := _request_via_curl(url, headers, method, body, timeout_sec)
		if not fallback.is_empty():
			return fallback
		return {"ok": false, "error": "HTTP request timed out.", "url": url}

	request_host.queue_free()
	var result: Array = state["result"]
	if result.size() < 4:
		return {"ok": false, "error": "HTTPRequest returned an incomplete result.", "url": url}

	var request_result: int = int(result[0])
	var response_code: int = int(result[1])
	var response_headers: PackedStringArray = result[2]
	var response_body: PackedByteArray = result[3]
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "HTTPRequest failed.",
			"request_result": request_result,
			"response_code": response_code,
			"url": url,
			"headers": response_headers,
			"body": response_body,
		}

	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": "HTTP status is not successful.",
			"request_result": request_result,
			"response_code": response_code,
			"url": url,
			"headers": response_headers,
			"body": response_body,
		}

	return {
		"ok": true,
		"request_result": request_result,
		"response_code": response_code,
		"url": url,
		"headers": response_headers,
		"body": response_body,
	}

## 桌面平台兜底：HTTPRequest 卡死时改用系统 curl，避免整条插件链路挂住。
func _request_via_curl(
	url: String,
	headers: Dictionary,
	method: HTTPClient.Method,
	body: String,
	timeout_sec: float
) -> Dictionary:
	var platform := OS.get_name()
	if platform != "macOS" and platform != "Linux" and platform != "Windows":
		return {}

	var curl_path := "curl.exe" if platform == "Windows" else "/usr/bin/curl"
	var args := PackedStringArray(["-s", "-i", "--max-time", str(int(timeout_sec))])
	for key in headers.keys():
		args.append("-H")
		args.append("%s: %s" % [str(key), str(headers[key])])
	if method == HTTPClient.METHOD_POST:
		args.append("-X")
		args.append("POST")
		if not body.is_empty():
			args.append("--data-binary")
			args.append(body)
	args.append(url)

	var output: Array = []
	var exit_code := OS.execute(curl_path, args, output, true)
	if exit_code != 0 or output.is_empty():
		return {}

	var text := str(output[0]).replace("\r\n", "\n")
	var parts := text.split("\n\n")
	if parts.size() < 2:
		return {}

	var header_block := parts[parts.size() - 2]
	var body_text := parts[parts.size() - 1]
	var header_lines := header_block.split("\n")
	var response_code := 0
	var response_headers := PackedStringArray()
	for index in header_lines.size():
		var line := header_lines[index]
		if index == 0 and line.begins_with("HTTP/"):
			var pieces := line.split(" ")
			if pieces.size() > 1:
				response_code = int(pieces[1])
			continue
		if not line.strip_edges().is_empty():
			response_headers.append(line)

	return {
		"ok": response_code >= 200 and response_code < 300,
		"response_code": response_code,
		"url": url,
		"headers": response_headers,
		"body": body_text.to_utf8_buffer(),
		"via": "curl",
	}

func _build_url(base_url: String, query: Dictionary) -> String:
	if query.is_empty():
		return base_url

	var separator = "&" if base_url.contains("?") else "?"
	return "%s%s%s" % [base_url, separator, _build_query_string(query)]

func _build_header_array(headers: Dictionary) -> PackedStringArray:
	var result = PackedStringArray()
	for key in headers.keys():
		result.append("%s: %s" % [str(key), str(headers[key])])
	return result

func _format_query_value(value: Variant) -> String:
	if value is bool:
		return "true" if value else "false"
	return str(value)

func _build_query_string(query: Dictionary) -> String:
	var parts: Array[String] = []
	for key in query.keys():
		parts.append("%s=%s" % [
			str(key).uri_encode(),
			_format_query_value(query[key]).uri_encode(),
		])
	return "&".join(parts)
