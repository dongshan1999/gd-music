class_name MusicAppHistoryStateController
extends RefCounted

## 全局播放历史控制器：负责「记录播放」这一侧。
## 记录时机挂在全局播放事件上，不侵入音频链路，四条起播链路（native / ffmpeg / mpv）统一生效。
## 排序与展示口径在页面控制器 MusicAppHistoryController 里，这里只提供干净的数据视图。

const MusicAppShowcaseControllerScript := preload("res://assets/scripts/ui/music_app/music_app_showcase.gd")
const MusicAppControllerBaseScript := preload("res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd")
const PlaybackStartedEventScript := preload("res://assets/scripts/ui/music_app/events/music_app_playback_started_event.gd")
const PlaybackFinishedEventScript := preload("res://assets/scripts/ui/music_app/events/music_app_playback_finished_event.gd")

var controller
## 当前这一轮播放的曲目 ID。
## 音频同步在「同一首歌暂停→恢复」时会再发一次 playback_started，这是同一次播放的续播，
## 不该再记一次；播完（finished）后清空，于是单曲循环的下一轮又能正常计数。
var _active_track_id: String = ""

func _init(owner = null) -> void:
	controller = owner

func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

func _get_base_controller() -> MusicAppControllerBase:
	return MusicAppControllerBaseScript.new(controller)

func get_app_state() -> MusicAppStateData:
	return _get_base_controller().get_app_state()

## 订阅全局播放事件，重复调用安全。
func bind_playback_events() -> void:
	if DX == null or DX.signals == null:
		return
	DX.signals.subscribe(PlaybackStartedEventScript, _on_playback_started)
	DX.signals.subscribe(PlaybackFinishedEventScript, _on_playback_finished)

## 解除订阅，避免退出场景后回调打到已释放的控制器。
func unbind_playback_events() -> void:
	if DX == null or DX.signals == null:
		return
	DX.signals.unsubscribe(PlaybackStartedEventScript, _on_playback_started)
	DX.signals.unsubscribe(PlaybackFinishedEventScript, _on_playback_finished)

func _on_playback_started(event) -> void:
	var track = event.track if event != null else null
	if track == null:
		return
	record_playback(track.id)

func _on_playback_finished(event) -> void:
	var track = event.track if event != null else null
	if track != null and not _active_track_id.is_empty() and track.id != _active_track_id:
		return
	_active_track_id = ""

## 记录一次起播。同一首曲目的「续播」重复事件会被折叠，返回是否真正记了一笔。
func record_playback(track_id: String, played_at: int = -1) -> bool:
	var normalized_id := track_id.strip_edges()
	if normalized_id.is_empty():
		return false
	if normalized_id == _active_track_id:
		return false
	var state := get_app_state()
	if state == null:
		return false
	_active_track_id = normalized_id
	state.record_play(normalized_id, played_at)
	# 播放次数是低频写入，标脏交自动存档即可；同步落盘会序列化整个资料库，卡住主线程。
	var save_manager := _get_base_controller().get_save_manager()
	if save_manager != null:
		save_manager.save(false)
	return true

## 清空历史并立即落盘（用户显式操作，直接 flush 更符合预期）。
func clear_history() -> int:
	var state := get_app_state()
	if state == null:
		return 0
	var removed := state.clear_play_history()
	_active_track_id = ""
	var save_manager := _get_base_controller().get_save_manager()
	if save_manager != null:
		save_manager.save(true)
	return removed

## 播放次数最多的曲目 ID 列表：次数降序，同次数时最近播放的靠前。
## 只返回仍在资料库里的曲目，避免点到已删除的条目。
func get_most_played_track_ids(limit: int = 0) -> Array[String]:
	var result: Array[String] = []
	var state := get_app_state()
	if state == null:
		return result
	var entries := _collect_valid_entries(state)
	entries.sort_custom(func(left: MusicPlayHistoryData, right: MusicPlayHistoryData) -> bool:
		if left.play_count != right.play_count:
			return left.play_count > right.play_count
		return left.last_played_at > right.last_played_at
	)
	for entry in entries:
		if entry.play_count <= 0:
			continue
		result.append(entry.track_id)
		if limit > 0 and result.size() >= limit:
			break
	return result

## 最近播放的曲目 ID 列表：按最近播放时间降序（同一首歌只出现一次）。
func get_recent_track_ids(limit: int = 0) -> Array[String]:
	var result: Array[String] = []
	var state := get_app_state()
	if state == null:
		return result
	var entries := _collect_valid_entries(state)
	entries.sort_custom(func(left: MusicPlayHistoryData, right: MusicPlayHistoryData) -> bool:
		if left.last_played_at != right.last_played_at:
			return left.last_played_at > right.last_played_at
		return left.play_count > right.play_count
	)
	for entry in entries:
		if entry.last_played_at <= 0:
			continue
		result.append(entry.track_id)
		if limit > 0 and result.size() >= limit:
			break
	return result

## 某首曲目的累计播放次数。
func get_play_count(track_id: String) -> int:
	var state := get_app_state()
	if state == null:
		return 0
	var entry := state.get_play_history_entry(track_id)
	return entry.play_count if entry != null else 0

## 某首曲目最近一次播放的时间戳（Unix 秒），从未播放返回 0。
func get_last_played_at(track_id: String) -> int:
	var state := get_app_state()
	if state == null:
		return 0
	var entry := state.get_play_history_entry(track_id)
	return entry.last_played_at if entry != null else 0

## 历史里仍在资料库中的曲目数量。
func get_history_track_count() -> int:
	var state := get_app_state()
	if state == null:
		return 0
	return _collect_valid_entries(state).size()

## 历史里仍在资料库中的曲目累计播放次数。
func get_total_play_count() -> int:
	var state := get_app_state()
	if state == null:
		return 0
	var total := 0
	for entry in _collect_valid_entries(state):
		total += maxi(0, entry.play_count)
	return total

## 历史是否有可展示内容。
func has_history() -> bool:
	return get_history_track_count() > 0

## 过滤出仍然存在的曲目对应的历史条目。
func _collect_valid_entries(state: MusicAppStateData) -> Array[MusicPlayHistoryData]:
	var result: Array[MusicPlayHistoryData] = []
	for entry in state.get_play_history_entries():
		if entry == null or entry.track_id.is_empty():
			continue
		if state.get_track_by_id(entry.track_id) == null:
			continue
		result.append(entry)
	return result
