class_name GDMusicHttpJsonClient
extends RefCounted

const DEFAULT_TIMEOUT_SEC := 15.0

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
	var response = await request(_build_url(url, query), headers, method, body, timeout_sec)
	if not bool(response.get("ok", false)):
		return null

	var response_body: PackedByteArray = response.get("body", PackedByteArray())
	if response_body.is_empty():
		return null

	return JSON.parse_string(response_body.get_string_from_utf8())

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
	tree.root.add_child(request_host)

	var error = http_request.request(url, _build_header_array(headers), method, body)
	if error != OK:
		request_host.queue_free()
		return {
			"ok": false,
			"error": "HTTPRequest.request failed.",
			"error_code": error,
			"url": url,
		}

	var result: Array = await http_request.request_completed
	request_host.queue_free()
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
