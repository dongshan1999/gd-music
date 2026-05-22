class_name DX_AndroidSafTree
extends RefCounted

static func is_supported() -> bool:
	return OS.get_name() == "Android" and Engine.get_singleton("AndroidRuntime") != null

static func persist_uri_permission(uri: String, persist: bool = true) -> bool:
	var normalized_uri := uri.strip_edges()
	if normalized_uri.is_empty():
		return false
	var android_runtime = Engine.get_singleton("AndroidRuntime")
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

	var android_runtime = Engine.get_singleton("AndroidRuntime")
	var application_context = android_runtime.getApplicationContext()
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var DocumentFile = JavaClassWrapper.wrap("androidx.documentfile.provider.DocumentFile")
	if Uri == null or DocumentFile == null:
		return results

	var root_uri = Uri.parse(normalized_tree_uri)
	var root = DocumentFile.fromTreeUri(application_context, root_uri)
	if root == null or not root.exists() or not root.isDirectory():
		return results

	_collect_gd_files_recursive(root, "", normalized_tree_uri, results)
	return results

static func _collect_gd_files_recursive(directory, relative_prefix: String, tree_uri: String, results: Array[Dictionary]) -> void:
	if directory == null:
		return
	var children = directory.listFiles()
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
