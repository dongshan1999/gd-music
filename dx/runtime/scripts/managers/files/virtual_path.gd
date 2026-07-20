class_name DX_VirtualPath
extends RefCounted

const SCHEME_APP := "app"
const SCHEME_LOCAL := "local"
const SCHEME_SAF_FILE := "saf-file"
const SCHEME_SAF_TREE := "saf-tree"

static func parse(value: String) -> Dictionary:
	var raw := value.strip_edges()
	var result := {
		"ok": false,
		"raw": raw,
		"scheme": "",
		"body": "",
		"relative_path": "",
		"error": ""
	}
	if raw.is_empty():
		result["error"] = "Path is empty."
		return result

	var scheme_end := raw.find("://")
	if scheme_end <= 0:
		result["error"] = "Path must use a virtual scheme, for example app://exports/file.csv."
		return result

	var scheme := raw.substr(0, scheme_end).to_lower()
	var body := raw.substr(scheme_end + 3)
	if body.is_empty() and scheme != SCHEME_APP:
		result["error"] = "Path body is empty."
		return result

	result["scheme"] = scheme
	match scheme:
		SCHEME_APP:
			var app_path := normalize_relative_path(body)
			if not bool(app_path.get("ok", false)):
				result["error"] = str(app_path.get("error", "Invalid app path."))
				return result
			result["body"] = str(app_path.get("path", ""))
		SCHEME_LOCAL:
			var local_body := body.replace("\\", "/").simplify_path()
			if local_body.is_empty():
				result["error"] = "Local path body is empty."
				return result
			result["body"] = local_body
		SCHEME_SAF_FILE:
			result["body"] = body.strip_edges()
		SCHEME_SAF_TREE:
			var fragment_index := body.find("#")
			var tree_uri := body.substr(0, fragment_index) if fragment_index >= 0 else body
			if tree_uri.strip_edges().is_empty():
				result["error"] = "SAF tree URI is empty."
				return result
			result["body"] = tree_uri.strip_edges()
			if fragment_index >= 0:
				var relative_path := normalize_relative_path(body.substr(fragment_index + 1))
				if not bool(relative_path.get("ok", false)):
					result["error"] = str(relative_path.get("error", "Invalid SAF relative path."))
					return result
				result["relative_path"] = str(relative_path.get("path", ""))
		_:
			result["body"] = body

	result["ok"] = true
	return result

static func is_virtual_path(value: String) -> bool:
	var scheme_end := value.find("://")
	return scheme_end > 0

static func normalize_app_path(relative_path: String) -> String:
	var normalized := normalize_relative_path(relative_path)
	if not bool(normalized.get("ok", false)):
		return ""
	return "app://%s" % str(normalized.get("path", ""))

static func normalize_local_path(native_path: String) -> String:
	var normalized := native_path.strip_edges().replace("\\", "/").simplify_path()
	return "local://%s" % normalized if not normalized.is_empty() else ""

static func normalize_saf_file_path(uri: String) -> String:
	return "saf-file://%s" % uri.strip_edges()

static func normalize_saf_tree_path(uri: String, relative_path: String = "") -> String:
	var normalized_uri := uri.strip_edges()
	if normalized_uri.is_empty():
		return ""
	var relative_result := normalize_relative_path(relative_path)
	if not bool(relative_result.get("ok", false)):
		return ""
	var normalized_relative := str(relative_result.get("path", ""))
	if normalized_relative.is_empty():
		return "saf-tree://%s" % normalized_uri
	return "saf-tree://%s#%s" % [normalized_uri, normalized_relative]

static func normalize_relative_path(value: String) -> Dictionary:
	var normalized := value.strip_edges().replace("\\", "/")
	while normalized.begins_with("/"):
		normalized = normalized.trim_prefix("/")
	var segments := PackedStringArray()
	for segment_value in normalized.split("/", false):
		var segment := str(segment_value).strip_edges()
		if segment.is_empty() or segment == ".":
			continue
		if segment == "..":
			return {
				"ok": false,
				"path": "",
				"error": "Parent path segments are not allowed."
			}
		segments.append(segment)
	return {
		"ok": true,
		"path": "/".join(segments),
		"error": ""
	}
