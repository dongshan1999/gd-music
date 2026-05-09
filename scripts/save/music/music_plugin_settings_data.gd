class_name MusicPluginSettingsData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const DEFAULT_HOST_URL := "http://127.0.0.1:31840"
const DEFAULT_REQUEST_TIMEOUT_SECONDS := 10.0

var host_url: String = DEFAULT_HOST_URL
var auto_start_local_host: bool = true
var local_host_command: String = ""
var local_host_args: Array[String] = []
var request_timeout_seconds: float = DEFAULT_REQUEST_TIMEOUT_SECONDS

func normalize() -> void:
	host_url = host_url.strip_edges()
	if host_url.is_empty():
		host_url = DEFAULT_HOST_URL
	host_url = host_url.trim_suffix("/")

	local_host_command = local_host_command.strip_edges()

	var normalized_args: Array[String] = []
	for arg in local_host_args:
		normalized_args.append(str(arg))
	local_host_args = normalized_args

	request_timeout_seconds = clampf(request_timeout_seconds, 1.0, 120.0)
