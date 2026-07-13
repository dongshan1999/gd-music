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
	if body.is_empty():
		result["error"] = "Path body is empty."
		return result

	result["ok"] = true
	result["scheme"] = scheme
	result["body"] = body

	if scheme == SCHEME_SAF_TREE:
		var fragment_index := body.find("#")
		if fragment_index >= 0:
			result["body"] = body.substr(0, fragment_index)
			result["relative_path"] = body.substr(fragment_index + 1).strip_edges().trim_prefix("/")

	return result

static func is_virtual_path(value: String) -> bool:
	var scheme_end := value.find("://")
	return scheme_end > 0

static func normalize_app_path(relative_path: String) -> String:
	return "app://%s" % _clean_relative_path(relative_path)

static func normalize_local_path(native_path: String) -> String:
	return "local://%s" % native_path.strip_edges()

static func normalize_saf_file_path(uri: String) -> String:
	return "saf-file://%s" % uri.strip_edges()

static func normalize_saf_tree_path(uri: String, relative_path: String = "") -> String:
	var normalized_uri := uri.strip_edges()
	var normalized_relative := _clean_relative_path(relative_path)
	if normalized_relative.is_empty():
		return "saf-tree://%s" % normalized_uri
	return "saf-tree://%s#%s" % [normalized_uri, normalized_relative]

static func _clean_relative_path(value: String) -> String:
	return value.strip_edges().replace("\\", "/").trim_prefix("/")
