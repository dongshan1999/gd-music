class_name DX_AndroidSafTree
extends RefCounted

static func is_supported() -> bool:
	return OS.get_name() == "Android" and Engine.get_singleton("AndroidRuntime") != null

static func persist_uri_permission(uri: String, persist: bool = true) -> bool:
	var normalized_uri := uri.strip_edges()
	if normalized_uri.is_empty():
		return false
	var android_runtime: Variant = Engine.get_singleton("AndroidRuntime")
	if android_runtime == null:
		return false
	android_runtime.updatePersistableUriPermission(normalized_uri, persist)
	return true

static func collect_gd_files_from_tree(tree_uri: String) -> Array[Dictionary]:
	var normalized_tree_uri := tree_uri.strip_edges()
	var results: Array[Dictionary] = []
	if normalized_tree_uri.is_empty():
		return results
	if not is_supported():
		return results

	var android_runtime: Variant = Engine.get_singleton("AndroidRuntime")
	var application_context: Variant = android_runtime.getApplicationContext()
	var Uri: Variant = JavaClassWrapper.wrap("android.net.Uri")
	var DocumentFile: Variant = JavaClassWrapper.wrap("androidx.documentfile.provider.DocumentFile")
	if Uri == null or DocumentFile == null:
		return results

	var root_uri: Variant = Uri.parse(normalized_tree_uri)
	var root: Variant = DocumentFile.fromTreeUri(application_context, root_uri)
	if root == null or not root.exists() or not root.isDirectory():
		return results

	_collect_gd_files_recursive(root, "", normalized_tree_uri, results)
	return results

static func list_entries(tree_uri: String, relative_dir: String = "") -> Array[Dictionary]:
	var result := list_entries_result(tree_uri, relative_dir)
	return result.get("entries", []) if bool(result.get("ok", false)) else []

static func list_entries_result(tree_uri: String, relative_dir: String = "") -> Dictionary:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_relative_dir := relative_dir.strip_edges().replace("\\", "/").trim_prefix("/")
	var results: Array[Dictionary] = []
	if normalized_tree_uri.is_empty():
		return _fail("Android SAF tree URI is empty.")
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", normalized_tree_uri)
	if _contains_parent_segment(normalized_relative_dir):
		return _fail("Parent path segments are not allowed.", _build_tree_file_path(normalized_tree_uri, normalized_relative_dir))

	var root: Variant = _get_tree_root(normalized_tree_uri)
	if root == null:
		return _fail("Android SAF tree is unavailable or permission has expired.", normalized_tree_uri)

	var directory: Variant = _find_directory(root, normalized_relative_dir)
	if directory == null:
		return _fail("Android SAF directory does not exist.", _build_tree_file_path(normalized_tree_uri, normalized_relative_dir))

	var children: Variant = directory.listFiles()
	if children == null:
		return _fail("Failed to list Android SAF directory.", _build_tree_file_path(normalized_tree_uri, normalized_relative_dir))

	for child in children:
		if child == null:
			continue
		var child_name := str(child.getName()).strip_edges()
		if child_name.is_empty():
			continue
		var relative_path := child_name if normalized_relative_dir.is_empty() else normalized_relative_dir.path_join(child_name)
		var document_uri := str(child.getUri().toString())
		results.append({
			"name": child_name,
			"relative_path": relative_path,
			"tree_path": _build_tree_file_path(normalized_tree_uri, relative_path),
			"document_uri": document_uri,
			"is_dir": child.isDirectory(),
			"is_file": child.isFile()
		})
	return _ok(_build_tree_file_path(normalized_tree_uri, normalized_relative_dir), {"entries": results})

static func tree_path_exists(tree_uri: String, relative_path: String = "") -> bool:
	var root: Variant = _get_tree_root(tree_uri)
	if root == null:
		return false
	if relative_path.strip_edges().is_empty():
		return root.exists()
	return _find_document(root, relative_path) != null

static func path_is_directory(tree_uri: String, relative_path: String = "") -> bool:
	var root: Variant = _get_tree_root(tree_uri)
	if root == null:
		return false
	var document: Variant = _find_document(root, relative_path)
	return document != null and document.exists() and document.isDirectory()

static func path_is_file(tree_uri: String, relative_path: String = "") -> bool:
	var root: Variant = _get_tree_root(tree_uri)
	if root == null:
		return false
	var document: Variant = _find_document(root, relative_path)
	return document != null and document.exists() and document.isFile()

static func get_path_info(tree_uri: String, relative_path: String = "") -> Dictionary:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_relative_path := relative_path.strip_edges().replace("\\", "/").trim_prefix("/")
	var root: Variant = _get_tree_root(normalized_tree_uri)
	if root == null:
		return _fail("Android SAF tree is not available.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	var document: Variant = _find_document(root, normalized_relative_path)
	return _document_info(document, _build_tree_file_path(normalized_tree_uri, normalized_relative_path), normalized_relative_path)

static func get_uri_info(uri: String) -> Dictionary:
	var document: Variant = _get_single_uri_document(uri)
	return _document_info(document, uri, "")

static func make_dir_recursive(tree_uri: String, relative_path: String = "") -> Dictionary:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_relative_path := relative_path.strip_edges().replace("\\", "/").trim_prefix("/")
	if _contains_parent_segment(normalized_relative_path):
		return _fail("Parent path segments are not allowed.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	var root: Variant = _get_tree_root(normalized_tree_uri)
	if root == null:
		return _fail("Android SAF tree is not available.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	if normalized_relative_path.is_empty():
		return _ok(_build_tree_file_path(normalized_tree_uri, normalized_relative_path))

	var current: Variant = root
	for segment in normalized_relative_path.split("/", false):
		var child_name := str(segment).strip_edges()
		if child_name.is_empty():
			continue
		var child: Variant = current.findFile(child_name)
		if child == null:
			child = current.createDirectory(child_name)
		if child == null or not child.exists():
			return _fail("Failed to create Android SAF directory.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
		if not child.isDirectory():
			return _fail("Android SAF path segment is not a directory.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
		current = child
	return _ok(_build_tree_file_path(normalized_tree_uri, normalized_relative_path))

static func delete_path(tree_uri: String, relative_path: String = "") -> Dictionary:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_relative_path := relative_path.strip_edges().replace("\\", "/").trim_prefix("/")
	if normalized_relative_path.is_empty():
		return _fail("Deleting the root SAF tree is not allowed.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	var root: Variant = _get_tree_root(normalized_tree_uri)
	if root == null:
		return _fail("Android SAF tree is not available.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	var document: Variant = _find_document(root, normalized_relative_path)
	if document == null or not document.exists():
		return _fail("Android SAF path does not exist.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))
	return _ok(_build_tree_file_path(normalized_tree_uri, normalized_relative_path)) if document.delete() else _fail("Failed to delete Android SAF path.", _build_tree_file_path(normalized_tree_uri, normalized_relative_path))

static func delete_uri(uri: String) -> Dictionary:
	var normalized_uri := uri.strip_edges()
	var document: Variant = _get_single_uri_document(normalized_uri)
	if document == null or not document.exists():
		return _fail("Android SAF URI does not exist.", normalized_uri)
	return _ok(normalized_uri) if document.delete() else _fail("Failed to delete Android SAF URI.", normalized_uri)

static func move_path(tree_uri: String, source_path: String, target_path: String, overwrite: bool = true) -> Dictionary:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_source := source_path.strip_edges().replace("\\", "/").trim_prefix("/")
	var normalized_target := target_path.strip_edges().replace("\\", "/").trim_prefix("/")
	if normalized_tree_uri.is_empty() or normalized_source.is_empty() or normalized_target.is_empty():
		return _fail("Android SAF move requires non-empty source and target paths.", normalized_tree_uri)
	if _contains_parent_segment(normalized_source) or _contains_parent_segment(normalized_target):
		return _fail("Parent path segments are not allowed.", _build_tree_file_path(normalized_tree_uri, normalized_target))
	if normalized_source == normalized_target:
		return _ok(_build_tree_file_path(normalized_tree_uri, normalized_target))

	var source_parent := normalized_source.get_base_dir()
	var target_parent := normalized_target.get_base_dir()
	if source_parent == ".":
		source_parent = ""
	if target_parent == ".":
		target_parent = ""
	if source_parent != target_parent:
		return {
			"ok": false,
			"path": _build_tree_file_path(normalized_tree_uri, normalized_target),
			"error": "Android SAF native move only supports the same parent directory.",
			"unsupported": true
		}

	var root: Variant = _get_tree_root(normalized_tree_uri)
	if root == null:
		return _fail("Android SAF tree is unavailable or permission has expired.", normalized_tree_uri)
	var parent: Variant = _find_directory(root, source_parent)
	if parent == null:
		return _fail("Android SAF parent directory does not exist.", _build_tree_file_path(normalized_tree_uri, source_parent))
	var source_name := normalized_source.get_file()
	var target_name := normalized_target.get_file()
	var source_document: Variant = parent.findFile(source_name)
	if source_document == null or not source_document.exists():
		return _fail("Android SAF source path does not exist.", _build_tree_file_path(normalized_tree_uri, normalized_source))
	var target_document: Variant = parent.findFile(target_name)
	if target_document != null and target_document.exists() and not overwrite:
		return _fail("Android SAF target path already exists.", _build_tree_file_path(normalized_tree_uri, normalized_target))

	var backup_name := ""
	if target_document != null and target_document.exists():
		backup_name = ".%s.dx-backup-%s-%s" % [target_name, Time.get_ticks_usec(), randi()]
		if not target_document.renameTo(backup_name):
			return _fail("Failed to preserve existing Android SAF target.", _build_tree_file_path(normalized_tree_uri, normalized_target))
	if not source_document.renameTo(target_name):
		var rollback_succeeded := backup_name.is_empty()
		if not backup_name.is_empty():
			rollback_succeeded = target_document.renameTo(target_name)
		var failure := _fail("Failed to rename Android SAF source path.", _build_tree_file_path(normalized_tree_uri, normalized_target))
		failure["rollback_succeeded"] = rollback_succeeded
		failure["rollback_error"] = "" if rollback_succeeded else "Failed to restore the previous Android SAF target."
		failure["backup_path"] = "" if rollback_succeeded else _build_tree_file_path(normalized_tree_uri, source_parent.path_join(backup_name) if not source_parent.is_empty() else backup_name)
		return failure

	var cleanup_error := ""
	if not backup_name.is_empty() and not target_document.delete():
		cleanup_error = "Failed to delete Android SAF backup path: %s" % backup_name
	return _ok(_build_tree_file_path(normalized_tree_uri, normalized_target), {
		"cleanup_error": cleanup_error,
		"backup_path": _build_tree_file_path(normalized_tree_uri, source_parent.path_join(backup_name) if not source_parent.is_empty() else backup_name) if not cleanup_error.is_empty() else ""
	})

static func _collect_gd_files_recursive(directory, relative_prefix: String, tree_uri: String, results: Array[Dictionary]) -> void:
	if directory == null:
		return
	var children: Variant = directory.listFiles()
	if children == null:
		return

	for child in children:
		if child == null:
			continue
		var child_name := str(child.getName()).strip_edges()
		if child_name.is_empty():
			continue
		var relative_path := child_name if relative_prefix.is_empty() else relative_prefix.path_join(child_name)
		if child.isDirectory():
			_collect_gd_files_recursive(child, relative_path, tree_uri, results)
			continue
		if not child.isFile():
			continue
		if child_name.get_extension().to_lower() != "gd":
			continue
		results.append(
			{
				"name": child_name,
				"relative_path": relative_path,
				"tree_path": _build_tree_file_path(tree_uri, relative_path),
				"document_uri": str(child.getUri().toString())
			}
		)

static func _build_tree_file_path(tree_uri: String, relative_path: String) -> String:
	var normalized_tree_uri := tree_uri.strip_edges()
	var normalized_relative_path := relative_path.strip_edges().trim_prefix("/")
	if normalized_tree_uri.is_empty():
		return ""
	if normalized_relative_path.is_empty():
		return normalized_tree_uri
	return "%s#%s" % [normalized_tree_uri, normalized_relative_path]

static func _get_tree_root(tree_uri: String):
	if not is_supported():
		return null
	var android_runtime: Variant = Engine.get_singleton("AndroidRuntime")
	var application_context: Variant = android_runtime.getApplicationContext()
	var Uri: Variant = JavaClassWrapper.wrap("android.net.Uri")
	var DocumentFile: Variant = JavaClassWrapper.wrap("androidx.documentfile.provider.DocumentFile")
	if Uri == null or DocumentFile == null:
		return null

	var root_uri: Variant = Uri.parse(tree_uri.strip_edges())
	var root: Variant = DocumentFile.fromTreeUri(application_context, root_uri)
	if root == null or not root.exists() or not root.isDirectory():
		return null
	return root

static func _find_directory(root, relative_dir: String):
	var document: Variant = _find_document(root, relative_dir)
	if document == null or not document.isDirectory():
		return null
	return document

static func _find_document(root, relative_path: String):
	if root == null:
		return null
	var normalized_relative := relative_path.strip_edges().replace("\\", "/").trim_prefix("/")
	if normalized_relative.is_empty():
		return root

	var current: Variant = root
	for segment in normalized_relative.split("/", false):
		var child_name := str(segment).strip_edges()
		if child_name.is_empty():
			continue
		current = current.findFile(child_name)
		if current == null or not current.exists():
			return null
	return current

static func _contains_parent_segment(path: String) -> bool:
	for segment in path.replace("\\", "/").split("/", false):
		if str(segment).strip_edges() == "..":
			return true
	return false

static func _get_single_uri_document(uri: String):
	if not is_supported():
		return null
	var android_runtime: Variant = Engine.get_singleton("AndroidRuntime")
	var application_context: Variant = android_runtime.getApplicationContext()
	var Uri: Variant = JavaClassWrapper.wrap("android.net.Uri")
	var DocumentFile: Variant = JavaClassWrapper.wrap("androidx.documentfile.provider.DocumentFile")
	if Uri == null or DocumentFile == null:
		return null
	return DocumentFile.fromSingleUri(application_context, Uri.parse(uri.strip_edges()))

static func _document_info(document: Variant, path: String, relative_path: String) -> Dictionary:
	if document == null or not document.exists():
		return _fail("Android SAF path does not exist.", path)
	var name := str(document.getName()).strip_edges()
	return {
		"ok": true,
		"path": path,
		"native_path": str(document.getUri().toString()),
		"name": name,
		"relative_path": relative_path,
		"is_dir": document.isDirectory(),
		"is_file": document.isFile(),
		"size": int(document.length()) if document.isFile() else 0,
		"modified_time": int(document.lastModified() / 1000),
		"extension": name.get_extension().to_lower(),
		"error": ""
	}

static func _ok(path: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"path": path,
		"error": ""
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result

static func _fail(message: String, path: String = "") -> Dictionary:
	return {
		"ok": false,
		"path": path,
		"error": message
	}
