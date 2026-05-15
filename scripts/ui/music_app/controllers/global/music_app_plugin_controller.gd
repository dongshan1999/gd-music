class_name MusicAppPluginController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const BUNDLED_SERVER_PATH := "res://plugin_host/src/server.js"
const BUNDLED_NODE_MODULES_PATH := "res://plugin_host/node_modules"

var _local_host_pid: int = -1

## 控制器进入运行期时预热插件设置对象。
func in_ready() -> void:
	get_settings()

## 控制器退出运行期时关闭本地插件宿主进程。
func in_quit() -> void:
	_stop_local_host()

## 读取并规范化音乐插件设置数据，不存在时返回默认值。
func get_settings() -> MusicPluginSettingsData:
	var save_manager = get_save_manager()
	if save_manager == null or save_manager.data == null:
		return MusicPluginSettingsData.new()
	if save_manager.data.music_plugins == null:
		save_manager.data.music_plugins = MusicPluginSettingsData.new()
	save_manager.data.music_plugins.normalize()
	return save_manager.data.music_plugins

## 将当前插件设置写回存档。
func save_settings() -> void:
	var save_manager = get_save_manager()
	if save_manager != null:
		save_manager.save_data()

func get_base_url() -> String:
	return get_settings().host_url

func get_last_started_pid() -> int:
	return _local_host_pid

func is_local_host_configured() -> bool:
	return _build_local_host_launch_config().get("ok", false)

## 按设置在首帧后尝试自动启动本地插件宿主。
func auto_start_local_host() -> void:
	var resolved_controller = get_showcase()
	if resolved_controller == null:
		return
	if not get_settings().auto_start_local_host:
		return
	await resolved_controller.get_tree().process_frame
	var result: Dictionary = await start_local_host()
	if not bool(result.get("ok", false)):
		push_warning("Music plugin host auto-start failed: %s" % str(result.get("error", "Unknown error.")))

## 启动本地插件宿主进程，并轮询直到健康检查通过。
func start_local_host() -> Dictionary:
	if not _is_desktop_platform():
		return _error_result("Local plugin host startup is only supported on desktop platforms.")

	var launch_config = _build_local_host_launch_config()
	if not bool(launch_config.get("ok", false)):
		return _error_result(str(launch_config.get("error", "Local plugin host command is not configured.")))

	var health_result: Dictionary = await ping()
	if bool(health_result.get("ok", false)):
		return health_result

	var command = str(launch_config.get("command", ""))
	var args: PackedStringArray = launch_config.get("args", PackedStringArray())
	var pid = OS.create_process(command, args, false)
	if pid <= 0:
		return _error_result(
			"Failed to start local plugin host process.",
			{
				"command": command,
				"args": Array(args)
			}
		)

	_local_host_pid = pid

	var attempts = 10
	while attempts > 0:
		await _delay_seconds(0.35)
		health_result = await ping()
		if bool(health_result.get("ok", false)):
			health_result["pid"] = pid
			return health_result
		attempts -= 1

	return _error_result(
		"Plugin host process started but did not become ready in time. Please make sure plugin_host dependencies are installed.",
		{
			"pid": pid,
			"command": command,
			"args": Array(args)
		}
	)

func ping() -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, "/health")

func list_plugins() -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, "/plugins")

func get_plugin_user_variables(plugin_id: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/plugin_vars?plugin_id=%s" % plugin_id.uri_encode()
	)

func set_plugin_user_variables(plugin_id: String, values: Dictionary) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/plugin_vars",
		{
			"plugin_id": plugin_id,
			"values": values
		}
	)

func install_plugin_from_url(plugin_url: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/install",
		{"url": plugin_url.strip_edges()}
	)

func install_plugin_from_file(plugin_path: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/install",
		{"path": _resolve_command_path(plugin_path.strip_edges())}
	)

func search(plugin_id: String, query: String, page: int = 1, media_type: String = "music") -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/search",
		{
			"plugin_id": plugin_id,
			"query": query,
			"page": maxi(1, page),
			"type": media_type
		}
	)

func get_media_source(track, quality: String = "standard") -> Dictionary:
	if track == null or not track.has_method("to_plugin_media_item"):
		return _error_result("Track does not provide plugin media payload.")
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/source",
		{
			"plugin_id": str(track.platform),
			"music_item": track.to_plugin_media_item(),
			"quality": quality
		}
	)

func get_lyric(track) -> Dictionary:
	if track == null or not track.has_method("to_plugin_media_item"):
		return _error_result("Track does not provide plugin media payload.")
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/lyric",
		{
			"plugin_id": str(track.platform),
			"music_item": track.to_plugin_media_item()
		}
	)

func get_toplists(plugin_id: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/toplists",
		{"plugin_id": plugin_id}
	)

## 向插件宿主发起统一 JSON 请求，并解析标准响应结构。
func _request_json(method: HTTPClient.Method, endpoint: String, payload: Variant = null) -> Dictionary:
	var request_host = get_showcase()
	if request_host == null:
		return _error_result("Music app showcase is not available.")

	var request = HTTPRequest.new()
	request.timeout = get_settings().request_timeout_seconds
	request_host.add_child(request)

	var url = "%s%s" % [get_base_url(), endpoint]
	var body = ""
	if payload != null:
		body = JSON.stringify(payload)

	var err = request.request(url, _get_default_headers(), method, body)
	if err != OK:
		request.queue_free()
		return _error_result("Failed to dispatch HTTP request.", {"code": err, "url": url})

	var signal_result: Array = await request.request_completed
	request.queue_free()

	var result_code = int(signal_result[0])
	var response_code = int(signal_result[1])
	var raw_headers: Array = signal_result[2]
	var raw_body: PackedByteArray = signal_result[3]
	var response_text = raw_body.get_string_from_utf8()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _error_result(
			"Plugin host request failed.",
			{
				"result_code": result_code,
				"status_code": response_code,
				"url": url
			}
		)

	var parsed_body: Variant = {}
	if not response_text.is_empty():
		var json = JSON.new()
		if json.parse(response_text) == OK:
			parsed_body = json.data
		else:
			parsed_body = {"raw": response_text}

	if response_code < 200 or response_code >= 300:
		return _error_result(
			"Plugin host returned an error response.",
			{
				"status_code": response_code,
				"headers": raw_headers,
				"body": parsed_body
			}
		)

	return {
		"ok": true,
		"status_code": response_code,
		"headers": raw_headers,
		"data": parsed_body
	}

## 将 Godot 资源路径解析为实际系统路径。
func _resolve_command_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

## 组装本地插件宿主的启动命令，优先使用用户配置，其次回退到内置 host。
func _build_local_host_launch_config() -> Dictionary:
	var settings = get_settings()
	if not settings.local_host_command.is_empty():
		return {
			"ok": true,
			"command": _resolve_command_path(settings.local_host_command),
			"args": PackedStringArray(settings.local_host_args)
		}

	var bundled_server = ProjectSettings.globalize_path(BUNDLED_SERVER_PATH)
	if FileAccess.file_exists(bundled_server):
		var bundled_node_modules = ProjectSettings.globalize_path(BUNDLED_NODE_MODULES_PATH)
		if not DirAccess.dir_exists_absolute(bundled_node_modules):
			return _error_result("Bundled plugin_host dependencies are missing. Run `npm install` in `plugin_host/` first.")
		return {
			"ok": true,
			"command": "node",
			"args": PackedStringArray([bundled_server])
		}

	return _error_result("Local plugin host command is not configured.")

## 返回插件宿主 HTTP 请求默认头部。
func _get_default_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

func _is_desktop_platform() -> bool:
	return OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")

## 在 showcase 所在场景树上等待指定秒数。
func _delay_seconds(seconds: float) -> void:
	var request_host = get_showcase()
	if request_host == null:
		return
	var timer = request_host.get_tree().create_timer(seconds)
	await timer.timeout

## 结束当前记录的本地插件宿主进程。
func _stop_local_host() -> void:
	if _local_host_pid <= 0:
		return
	if OS.has_method("is_process_running") and OS.is_process_running(_local_host_pid):
		OS.kill(_local_host_pid)
	_local_host_pid = -1

## 构造统一格式的插件控制器错误返回。
func _error_result(message: String, extra: Dictionary = {}) -> Dictionary:
	var result = {"ok": false, "error": message}
	for key in extra.keys():
		result[key] = extra[key]
	return result
