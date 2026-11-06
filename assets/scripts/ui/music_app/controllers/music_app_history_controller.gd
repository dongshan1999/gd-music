class_name MusicAppHistoryController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 播放历史页控制器：把全局播放统计整理成「最近播放 / 播放最多」两种排序视图，
## 并负责页面上的格式化文案（相对时间、次数）与点歌、清空动作。
## 弹窗打开时加载，关闭后随弹窗释放，不缓存列表。

enum Tab {
	RECENT,
	MOST_PLAYED,
}

const TAB_COUNT := 2
## 「N 天前」最多显示到这个天数，再久就直接用日期，避免出现「137 天前」。
const RELATIVE_DAYS_LIMIT := 7

const HistoryStateControllerScript := preload("res://assets/scripts/ui/music_app/controllers/global/music_app_history_state_controller.gd")

var _tab: int = Tab.RECENT
## 清空确认后的回调，页面用它触发列表刷新；弹窗是异步的，所以只能暂存。
var _clear_done_callback := Callable()
## showcase 还没装配好时的兜底实例，保证页面不会因为拿不到全局控制器而空白。
var _fallback_history_state_controller

## 取全局播放历史控制器；宿主未就绪时退回本地实例（读取的是同一份存档状态）。
func _resolve_history_state_controller() -> MusicAppHistoryStateController:
	var history_state_controller = get_history_state_controller()
	if history_state_controller != null:
		return history_state_controller
	if _fallback_history_state_controller == null:
		_fallback_history_state_controller = HistoryStateControllerScript.new(controller)
	return _fallback_history_state_controller

## 当前排序标签页。
func get_tab() -> int:
	return _tab

## 切换排序标签页，返回是否真的发生了变化。
func set_tab(tab: int) -> bool:
	var next_tab := clampi(tab, 0, TAB_COUNT - 1)
	if next_tab == _tab:
		return false
	_tab = next_tab
	return true

## 循环切换排序标签页，返回切换后的标签页。
func cycle_tab() -> int:
	_tab = (_tab + 1) % TAB_COUNT
	return _tab

## 标签页文案（传入 -1 取当前标签页）。
func get_tab_title(tab: int = -1) -> String:
	var resolved_tab := _tab if tab < 0 else clampi(tab, 0, TAB_COUNT - 1)
	if resolved_tab == Tab.MOST_PLAYED:
		return tr("music_app.history.tab.most_played")
	return tr("music_app.history.tab.recent")

## 当前标签页要展示的曲目 ID 顺序。
func get_track_ids() -> Array[String]:
	return get_track_ids_for_tab(_tab)

## 指定标签页的曲目 ID 顺序。
func get_track_ids_for_tab(tab: int) -> Array[String]:
	var history_state_controller = _resolve_history_state_controller()
	if history_state_controller == null:
		var empty: Array[String] = []
		return empty
	if tab == Tab.MOST_PLAYED:
		return history_state_controller.get_most_played_track_ids()
	return history_state_controller.get_recent_track_ids()

func get_track(track_id: String) -> TrackData:
	return get_track_by_id(track_id)

## 页头统计：共 N 首 · 累计 M 次播放。
func get_summary_text() -> String:
	var history_state_controller = _resolve_history_state_controller()
	if history_state_controller == null:
		return ""
	return tr("music_app.history.summary").format({
		"tracks": str(history_state_controller.get_history_track_count()),
		"plays": str(history_state_controller.get_total_play_count()),
	})

## 空态主标题（区分两个标签页）。
func get_empty_title() -> String:
	if _tab == Tab.MOST_PLAYED:
		return tr("music_app.history.empty.most.title")
	return tr("music_app.history.empty.recent.title")

## 空态副标题。
func get_empty_hint() -> String:
	if _tab == Tab.MOST_PLAYED:
		return tr("music_app.history.empty.most.hint")
	return tr("music_app.history.empty.recent.hint")

## 行主标题：曲名。
func get_row_title(track_id: String) -> String:
	var track := get_track(track_id)
	if track == null:
		return tr("music_app.history.unknown_track")
	return track.title if not track.title.is_empty() else tr("music_app.history.unknown_track")

## 行副标题：
## - 最近播放：歌手，播放超过一次时补「共 N 次」
## - 播放最多：歌手，补最近一次播放时间
func get_row_subtitle(track_id: String) -> String:
	var track := get_track(track_id)
	if track == null:
		return ""
	var parts: Array[String] = []
	var artist_text := track.artist.strip_edges()
	if artist_text.is_empty():
		artist_text = track.subtitle.strip_edges()
	if not artist_text.is_empty():
		parts.append(artist_text)
	var history_state_controller = _resolve_history_state_controller()
	if history_state_controller == null:
		return " · ".join(parts)
	var play_count := history_state_controller.get_play_count(track_id)
	if _tab == Tab.MOST_PLAYED:
		var last_played_at := history_state_controller.get_last_played_at(track_id)
		if last_played_at > 0:
			parts.append(tr("music_app.history.last_played_hint").format({
				"time": format_relative_time(last_played_at),
			}))
	elif play_count > 1:
		parts.append(tr("music_app.history.total_plays_hint").format({"count": str(play_count)}))
	return " · ".join(parts)

## 行右侧主信息：最近播放显示时间，播放最多显示次数。
func get_row_side_text(track_id: String) -> String:
	var history_state_controller = _resolve_history_state_controller()
	if history_state_controller == null:
		return ""
	if _tab == Tab.MOST_PLAYED:
		return format_play_count(history_state_controller.get_play_count(track_id))
	return format_relative_time(history_state_controller.get_last_played_at(track_id))

## 播放次数文案（单复数走两条 key，避免英文出现 "1 plays"）。
func format_play_count(count: int) -> String:
	if count <= 1:
		return tr("music_app.history.play_count_one")
	return tr("music_app.history.play_count").format({"count": str(count)})

## 把 Unix 秒格式化成「刚刚 / N 分钟前 / N 小时前 / N 天前 / YYYY-MM-DD」。
func format_relative_time(timestamp: int, now: int = -1) -> String:
	if timestamp <= 0:
		return ""
	var current := now if now > 0 else int(Time.get_unix_time_from_system())
	var delta := current - timestamp
	if delta < 0:
		delta = 0
	if delta < 60:
		return tr("music_app.history.just_now")
	if delta < 3600:
		return tr("music_app.history.minutes_ago").format({"count": str(delta / 60)})
	if delta < 86400:
		return tr("music_app.history.hours_ago").format({"count": str(delta / 3600)})
	var days := delta / 86400
	if days < RELATIVE_DAYS_LIMIT:
		return tr("music_app.history.days_ago").format({"count": str(days)})
	return Time.get_date_string_from_unix_time(timestamp)

## 用历史页当前顺序作为播放队列，从指定槽位开始播放，并打开播放器页。
func play_track_list(track_ids: Array[String], slot_index: int) -> bool:
	if track_ids.is_empty() or slot_index < 0 or slot_index >= track_ids.size():
		return false
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return false
	if not playback_controller.set_playback_queue(track_ids, slot_index):
		return false
	if not playback_controller.play_queue_index(playback_controller.get_playback_queue_index(), true):
		return false
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	return true

## 弹出二次确认后清空播放历史。on_done 在真正清空后回调，用于页面刷新。
func request_clear_history(on_done: Callable = Callable()) -> void:
	if not has_history():
		show_toast(tr("music_app.history.empty_toast"))
		return
	_clear_done_callback = on_done
	var popup = show_popup(DX_PopupRegistry.PopupId.COMMON_DIALOG)
	if popup is CommonDialogPopup:
		var dialog := popup as CommonDialogPopup
		dialog.show_confirm(
			tr("music_app.history.clear_title"),
			tr("music_app.history.clear_message"),
			Callable(self, "clear_history"),
			Callable(),
			tr("music_app.history.clear_confirm"),
			tr("music_app.history.clear_cancel")
		)

## 真正执行清空，返回被清掉的条数。
func clear_history() -> int:
	var history_state_controller = _resolve_history_state_controller()
	if history_state_controller == null:
		return 0
	var removed := history_state_controller.clear_history()
	show_toast(tr("music_app.history.cleared"))
	if _clear_done_callback.is_valid():
		_clear_done_callback.call()
	_clear_done_callback = Callable()
	return removed

## 历史里是否有可展示内容。
func has_history() -> bool:
	var history_state_controller = _resolve_history_state_controller()
	return history_state_controller != null and history_state_controller.has_history()
