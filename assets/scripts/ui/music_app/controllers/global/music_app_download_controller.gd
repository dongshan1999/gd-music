class_name MusicAppDownloadController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 音乐下载控制器：解析插件音频地址、下载到本地、维护下载索引。
##
## 生命周期与插件控制器一致：由 showcase 持有（RefCounted，不能 add_child），
## HTTPRequest 临时挂到 showcase 节点下，请求结束即释放。
## 串行下载（同一时刻 1 个），其余排队，避免同时占满带宽与插件风控。

const DOWNLOAD_ROOT_RELATIVE := "music_downloads"
const PART_SUFFIX := ".part"
const REMOTE_TIMEOUT_SECONDS := 60.0
const REMOTE_BODY_SIZE_LIMIT := 128 * 1024 * 1024
const PROGRESS_INTERVAL_SECONDS := 0.2
## 网络失败后的额外重试次数（总尝试次数 = 1 + MAX_RETRY_COUNT）。
const MAX_RETRY_COUNT := 2
const WEB_FORMAT_EXTENSIONS := ["m4a", "aac", "mp4"]

enum Status {
	IDLE,
	QUEUED,
	RESOLVING,
	DOWNLOADING,
	DONE,
	FAILED,
	CANCELLED,
}

signal download_state_changed(track_id: String)
signal download_progress_changed(track_id: String, received: int, total: int)
signal download_finished(track_id: String, record: MusicDownloadRecordData)
signal download_failed(track_id: String, message: String)

var last_error: String = ""

var _queue: Array[TrackData] = []
var _status: Dictionary = {}
var _progress: Dictionary = {}
var _cancelled: Dictionary = {}
var _busy: bool = false
var _active_request: HTTPRequest = null
var _active_track_id: String = ""

## 下载根目录（app:// 下的相对路径）；测试可改写到临时目录。
var download_root_relative: String = DOWNLOAD_ROOT_RELATIVE

func in_ready() -> void:
	last_error = ""
	_status.clear()
	_progress.clear()
	_cancelled.clear()
	_queue.clear()
	_busy = false
	_active_request = null
	_active_track_id = ""
	var root := get_download_root_virtual()
	if root.is_empty():
		return
	DX.files.make_dir_recursive(root)
	_cleanup_part_files(root)
	_verify_records()

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

## 返回可用的下载记录；索引里有记录但文件已不存在时顺手清理。
func get_download_record(track_id: String) -> MusicDownloadRecordData:
	var normalized_id := track_id.strip_edges()
	if normalized_id.is_empty():
		return null
	var app_state := get_app_state()
	var record := app_state.get_download_record(normalized_id)
	if record == null:
		return null
	if record.path.is_empty() or not DX.files.is_file(record.path):
		app_state.remove_download_record(normalized_id)
		_save_state()
		return null
	return record

func has_download(track_id: String) -> bool:
	return get_download_record(track_id) != null

func get_status(track_id: String) -> int:
	return int(_status.get(track_id, Status.IDLE))

func is_downloading(track_id: String) -> bool:
	var status := get_status(track_id)
	return status == Status.QUEUED or status == Status.RESOLVING or status == Status.DOWNLOADING

func get_progress(track_id: String) -> Dictionary:
	return _progress.get(track_id, {"received": 0, "total": 0})

func get_records() -> Array[MusicDownloadRecordData]:
	var result := get_app_state().get_download_records()
	result.sort_custom(func(left, right) -> bool:
		return left.created_at > right.created_at
	)
	return result

func get_total_bytes() -> int:
	var total := 0
	for record in get_app_state().get_download_records():
		if record != null:
			total += maxi(0, record.bytes)
	return total

func get_download_root_virtual() -> String:
	return DX.files.app_path(download_root_relative)

## 供设置页展示的系统真实路径。
func get_download_directory() -> String:
	var root := get_download_root_virtual()
	var native_path = DX.files.globalize(root)
	return native_path if not native_path.is_empty() else root

# ---------------------------------------------------------------------------
# 下载
# ---------------------------------------------------------------------------

## 下载一首曲目，等待结束后返回 `{ok, error, cached, record}`。
func download_track(track: TrackData) -> Dictionary:
	if track == null:
		return _failure("曲目为空，无法下载。")
	var track_id := track.id.strip_edges()
	if track_id.is_empty():
		return _failure("曲目缺少 ID，无法下载。")
	var existing := get_download_record(track_id)
	if existing != null:
		return {"ok": true, "error": "", "cached": true, "record": existing}
	if track.plugin_id.is_empty():
		return _failure("该曲目没有关联插件，无法下载。")
	if is_downloading(track_id):
		return _failure("正在下载中。")

	_cancelled.erase(track_id)
	_queue.append(track)
	_set_status(track_id, Status.QUEUED)
	_pump()

	while true:
		var status := get_status(track_id)
		match status:
			Status.DONE:
				var record := get_app_state().get_download_record(track_id)
				return {"ok": record != null, "error": "", "cached": false, "record": record}
			Status.FAILED:
				return _failure(last_error if not last_error.is_empty() else "下载失败。")
			Status.CANCELLED:
				return _failure("下载已取消。")
		var tree := _get_scene_tree()
		if tree == null:
			return _failure("下载已中断。")
		await tree.create_timer(0.1).timeout
	return _failure("下载失败。")

## 取消排队中/下载中的任务。
func cancel_download(track_id: String) -> void:
	var normalized_id := track_id.strip_edges()
	if normalized_id.is_empty():
		return
	_cancelled[normalized_id] = true
	for index in range(_queue.size() - 1, -1, -1):
		if _queue[index] != null and _queue[index].id == normalized_id:
			_queue.remove_at(index)
	if _active_track_id == normalized_id and _active_request != null and is_instance_valid(_active_request):
		_active_request.cancel_request()
	if not _busy or _active_track_id != normalized_id:
		_set_status(normalized_id, Status.CANCELLED)

func remove_download(track_id: String) -> Dictionary:
	var normalized_id := track_id.strip_edges()
	var record := get_app_state().remove_download_record(normalized_id)
	if record == null:
		return _failure("没有找到该下载记录。")
	if not record.path.is_empty() and DX.files.exists(record.path):
		var deleted = DX.files.delete_file(record.path)
		if not bool(deleted.get("ok", false)):
			last_error = str(deleted.get("error", "删除下载文件失败。"))
			# 记录已经移除，文件删除失败时把记录放回，避免出现看不见的残留。
			get_app_state().set_download_record(record)
			return _failure(last_error)
	_save_state()
	_status.erase(normalized_id)
	_progress.erase(normalized_id)
	return {"ok": true, "error": ""}

## 已下载曲目的来源页面链接；无法生成时返回空串。
static func build_source_url(track: TrackData) -> String:
	if track == null or track.plugin_data == null:
		return ""
	var plugin_data: Dictionary = track.plugin_data
	var bvid := str(plugin_data.get("bvid", "")).strip_edges()
	if not bvid.is_empty():
		return "https://www.bilibili.com/video/%s" % bvid
	var aid := str(plugin_data.get("aid", "")).strip_edges()
	if not aid.is_empty() and aid != "0":
		return "https://www.bilibili.com/video/av%s" % aid
	return ""

# ---------------------------------------------------------------------------
# 内部：队列与下载流程
# ---------------------------------------------------------------------------

func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var track: TrackData = _queue.pop_front()
	if track == null:
		_busy = false
		_pump()
		return
	await _do_download(track)
	_busy = false
	_active_request = null
	_active_track_id = ""
	_pump()

func _do_download(track: TrackData) -> void:
	var track_id := track.id
	_active_track_id = track_id
	last_error = ""
	_set_status(track_id, Status.RESOLVING)

	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		_fail(track, "插件控制器不可用。")
		return
	var source: Dictionary = await plugin_controller.get_media_source(track)
	if _consume_cancel(track_id):
		return
	if source.is_empty():
		_fail(track, _pick_error(plugin_controller.last_error, "解析音频地址失败。"))
		return

	var url := str(source.get("url", "")).strip_edges()
	if url.is_empty():
		_fail(track, "插件未返回可播放的音频地址。")
		return
	var headers: Dictionary = source.get("headers", {})
	var extension := _normalize_extension(str(source.get("format", "")), url)
	var target_path := _build_target_path(track, extension)
	var part_path := target_path + PART_SUFFIX

	var body := PackedByteArray()
	var download_error := ""
	for attempt in MAX_RETRY_COUNT + 1:
		var result: Dictionary = await _download_bytes(url, headers, track_id)
		if bool(result.get("ok", false)):
			body = result.get("data", PackedByteArray())
			download_error = ""
			break
		download_error = str(result.get("error", ""))
		if not bool(result.get("retry", false)):
			break

	if _consume_cancel(track_id):
		return
	if body.is_empty():
		_fail(track, _pick_error(download_error, "下载内容为空。"))
		return
	if not _is_valid_audio(body, extension):
		_fail(track, "下载内容不是有效的音频文件。")
		return

	var parent_dir := target_path.get_base_dir()
	var make_dir_result = DX.files.make_dir_recursive(parent_dir)
	if not bool(make_dir_result.get("ok", false)):
		_fail(track, _pick_error(str(make_dir_result.get("error", "")), "无法创建下载目录。"))
		return

	var write_result = DX.files.write_bytes(part_path, body)
	if not bool(write_result.get("ok", false)):
		DX.files.delete_file(part_path)
		_fail(track, _pick_error(str(write_result.get("error", "")), "无法写入下载文件。"))
		return

	if DX.files.exists(target_path):
		DX.files.delete_file(target_path)
	var move_result = DX.files.move(part_path, target_path, true)
	if not bool(move_result.get("ok", false)):
		DX.files.delete_file(part_path)
		_fail(track, _pick_error(str(move_result.get("error", "")), "无法保存下载文件。"))
		return

	var record := _build_record(track, target_path, extension, body.size())
	get_app_state().set_download_record(record)
	_save_state()

	_progress[track_id] = {"received": body.size(), "total": body.size()}
	_set_status(track_id, Status.DONE)
	download_finished.emit(track_id, record)
	if get_selected_track_id() == track_id:
		request_audio_sync()

## 通过 HTTPRequest 下载完整字节；返回 `{ok, error, retry, data}`。
func _download_bytes(url: String, headers: Dictionary, track_id: String) -> Dictionary:
	var host = get_showcase()
	if host == null or not is_instance_valid(host):
		return {"ok": false, "error": "下载控制器未绑定界面。", "retry": false}

	var request := HTTPRequest.new()
	request.timeout = REMOTE_TIMEOUT_SECONDS
	request.body_size_limit = REMOTE_BODY_SIZE_LIMIT
	host.add_child(request)
	_active_request = request
	_set_status(track_id, Status.DOWNLOADING)
	_progress[track_id] = {"received": 0, "total": 0}

	var err := request.request(url, _build_http_headers(headers), HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		_active_request = null
		return {"ok": false, "error": "无法发起音频下载请求。", "retry": true}

	_poll_download_progress(request, track_id)
	var response: Array = await request.request_completed
	var result_code := int(response[0]) if response.size() > 0 else HTTPRequest.RESULT_CANT_CONNECT
	var response_code := int(response[1]) if response.size() > 1 else 0
	var response_body: PackedByteArray = response[3] if response.size() > 3 else PackedByteArray()
	if not is_instance_valid(request):
		return {"ok": false, "error": "下载请求已中断。", "retry": true}
	request.queue_free()
	_active_request = null

	if _consume_cancel(track_id):
		return {"ok": false, "error": "下载已取消。", "retry": false}
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "音频下载失败，请检查网络或尝试较短的视频。", "retry": true}
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": "音频下载失败 (HTTP %d)，请重试。" % response_code,
			"retry": response_code >= 500,
		}
	if response_body.is_empty():
		return {"ok": false, "error": "音频响应为空。", "retry": true}
	return {"ok": true, "error": "", "retry": false, "data": response_body}

func _poll_download_progress(request: HTTPRequest, track_id: String) -> void:
	var tree := _get_scene_tree()
	if tree == null:
		return
	while is_instance_valid(request) and not request.is_queued_for_deletion():
		var received := request.get_downloaded_bytes()
		var total := request.get_body_size()
		_progress[track_id] = {"received": received, "total": total}
		download_progress_changed.emit(track_id, received, total)
		download_state_changed.emit(track_id)
		await tree.create_timer(PROGRESS_INTERVAL_SECONDS).timeout

func _build_record(track: TrackData, path: String, extension: String, byte_count: int) -> MusicDownloadRecordData:
	var record := MusicDownloadRecordData.new()
	record.track_id = track.id
	record.plugin_id = track.plugin_id
	record.media_id = str(track.plugin_data.get("cid", "")) if track.plugin_data != null else ""
	if record.media_id.is_empty():
		record.media_id = str(track.plugin_data.get("id", "")) if track.plugin_data != null else ""
	record.title = track.title
	record.artist = track.artist
	record.path = path
	record.format = extension
	record.bytes = byte_count
	record.duration = track.duration
	record.source_url = build_source_url(track)
	record.created_at = Time.get_datetime_string_from_system()
	record.normalize()
	return record

func _build_target_path(track: TrackData, extension: String) -> String:
	var root := get_download_root_virtual()
	var plugin_dir := _sanitize_path_segment(track.plugin_id)
	if plugin_dir.is_empty():
		plugin_dir = "plugin"
	var file_stem := track.id.sha256_text().substr(0, 16)
	if file_stem.is_empty():
		file_stem = str(abs(track.id.hash()))
	return "%s/%s/%s.%s" % [root, plugin_dir, file_stem, extension]

func _normalize_extension(format_hint: String, url: String) -> String:
	var normalized_format := format_hint.strip_edges().to_lower().trim_prefix(".")
	if not normalized_format.is_empty():
		match normalized_format:
			"mp4", "aac":
				return "m4a"
			"m4a", "mp3", "ogg", "wav":
				return normalized_format
	var from_url := _extension_from_url(url)
	if not from_url.is_empty():
		return from_url
	return "m4a"

func _extension_from_url(url: String) -> String:
	var cleaned := url.strip_edges()
	var query_index := cleaned.find("?")
	if query_index >= 0:
		cleaned = cleaned.substr(0, query_index)
	cleaned = cleaned.get_file()
	var dot_index := cleaned.rfind(".")
	if dot_index < 0 or dot_index >= cleaned.length() - 1:
		return ""
	var extension := cleaned.substr(dot_index + 1).to_lower()
	if WEB_FORMAT_EXTENSIONS.has(extension):
		return "m4a"
	if extension in ["m4a", "mp3", "ogg", "wav"]:
		return extension
	return ""

func _is_valid_audio(data: PackedByteArray, extension: String) -> bool:
	if data.is_empty():
		return false
	if extension == "m4a":
		return data.size() > 12 and data.slice(4, 8).get_string_from_ascii() == "ftyp"
	if extension == "mp3":
		return data.size() > 3 and (data.slice(0, 3).get_string_from_ascii().begins_with("ID3")
			or (data[0] == 0xFF and (data[1] & 0xE0) == 0xE0))
	if extension == "ogg":
		return data.size() > 4 and data.slice(0, 4).get_string_from_ascii() == "OggS"
	return true

func _build_http_headers(headers: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for key in headers.keys():
		result.append("%s: %s" % [str(key), str(headers[key])])
	return result

func _sanitize_path_segment(value: String) -> String:
	var result := value.strip_edges().replace("\\", "_").replace("/", "_").replace(":", "_")
	result = result.replace("*", "_").replace("?", "_").replace("\"", "_").replace("<", "_")
	result = result.replace(">", "_").replace("|", "_")
	return result.strip_edges()

func _verify_records() -> void:
	var app_state := get_app_state()
	var missing: Array[String] = []
	for record in app_state.get_download_records():
		if record == null or record.path.is_empty() or not DX.files.is_file(record.path):
			if record != null:
				missing.append(record.track_id)
	for track_id in missing:
		app_state.remove_download_record(track_id)
	if not missing.is_empty():
		_save_state()

func _cleanup_part_files(root: String) -> void:
	var listed = DX.files.list_dir(root)
	if not bool(listed.get("ok", false)):
		return
	var entries: Array = listed.get("entries", [])
	for entry in entries:
		var entry_name := str(entry) if entry is String else str(entry.get("name", ""))
		if entry_name.is_empty() or entry_name.begins_with("."):
			continue
		var entry_path := "%s/%s" % [root, entry_name]
		if DX.files.is_dir(entry_path):
			_delete_part_files_in_dir(entry_path)
		elif entry_name.ends_with(PART_SUFFIX):
			DX.files.delete_file(entry_path)

func _delete_part_files_in_dir(dir_path: String) -> void:
	var listed = DX.files.list_dir(dir_path)
	if not bool(listed.get("ok", false)):
		return
	for entry in listed.get("entries", []):
		var entry_name := str(entry) if entry is String else str(entry.get("name", ""))
		if entry_name.ends_with(PART_SUFFIX):
			DX.files.delete_file("%s/%s" % [dir_path, entry_name])

func _set_status(track_id: String, status: int) -> void:
	_status[track_id] = status
	download_state_changed.emit(track_id)

func _consume_cancel(track_id: String) -> bool:
	if not _cancelled.has(track_id):
		return false
	_cancelled.erase(track_id)
	_set_status(track_id, Status.CANCELLED)
	return true

func _fail(track: TrackData, message: String) -> void:
	var track_id := track.id if track != null else _active_track_id
	last_error = message
	_set_status(track_id, Status.FAILED)
	download_failed.emit(track_id, message)

func _pick_error(candidate: String, fallback: String) -> String:
	var text := candidate.strip_edges()
	return text if not text.is_empty() else fallback

func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message, "cached": false, "record": null}

func _get_scene_tree() -> SceneTree:
	var host = get_showcase()
	if host == null or not is_instance_valid(host):
		return null
	return host.get_tree()

func _save_state() -> void:
	var save_manager := get_save_manager()
	if save_manager != null:
		save_manager.save(false)
