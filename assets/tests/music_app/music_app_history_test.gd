extends Node
## 播放历史功能回归测试：数据层计数/排序、全局记录控制器、页面控制器格式化与行渲染。
## 不加载 showcase，直接走 MusicAppControllerBase 的内存兜底状态，保证 headless 可跑。

const StateDataType := preload("res://assets/scripts/save/music/music_app_state_data.gd")
const TrackDataType := preload("res://assets/scripts/save/music/track_data.gd")
const ControllerBaseScript := preload("res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd")
const HistoryStateControllerScript := preload("res://assets/scripts/ui/music_app/controllers/global/music_app_history_state_controller.gd")
const HistoryControllerScript := preload("res://assets/scripts/ui/music_app/controllers/music_app_history_controller.gd")
const HistoryRowScene := preload("res://assets/scenes/ui/music_app/history/history_row.tscn")
const HistoryPageScene := preload("res://assets/scenes/ui/music_app/history/music_app_history_page.tscn")

const NOW := 1_700_000_000

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	TranslationServer.set_locale("zh_CN")
	_test_state_data()
	_test_history_state_controller()
	_test_page_controller()
	await _test_row_scene()
	await _test_page_scene()
	print("Music app history tests: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _reset_state() -> MusicAppStateData:
	var state := ControllerBaseScript.new().get_app_state()
	state.tracks.clear()
	state.play_history.clear()
	for index in 3:
		state.tracks.append(_make_track("t%d" % index, "曲目 %d" % index, "歌手 %d" % index))
	state.normalize()
	return state

func _make_track(id: String, title: String, artist: String) -> TrackData:
	var track := TrackDataType.new()
	track.id = id
	track.title = title
	track.artist = artist
	return track

func _test_state_data() -> void:
	var state := _reset_state()

	_check(state.get_play_history_entries().is_empty(), "初始历史应为空")

	state.record_play("t0", NOW - 300)
	state.record_play("t1", NOW - 100)
	state.record_play("t0", NOW - 50)

	_check(state.get_play_history_entries().size() == 2, "同一首歌不应产生重复历史条目")
	var entry = state.get_play_history_entry("t0")
	_check(entry != null and entry.play_count == 2, "重复播放应累加次数")
	_check(entry != null and entry.last_played_at == NOW - 50, "最近播放时间应取较新的那次")
	_check(state.get_play_history_entries()[0].track_id == "t0", "历史应按最近播放时间降序排在最前")
	_check(state.get_total_play_count() == 3, "累计次数应为 3")

	# 超过上限时截断，只保留最近的若干条（用不同曲目 ID 撑爆上限）。
	for index in StateDataType.PLAY_HISTORY_LIMIT + 20:
		state.record_play("bulk%d" % index, NOW + index)
	_check(
		state.get_play_history_entries().size() == StateDataType.PLAY_HISTORY_LIMIT,
		"历史条数应被截断到 PLAY_HISTORY_LIMIT"
	)

	# 空 ID 不应写进历史。
	state.record_play("")
	_check(state.get_play_history_entry("") == null, "空曲目 ID 不应被记录")

	var removed := state.clear_play_history()
	_check(removed == StateDataType.PLAY_HISTORY_LIMIT, "清空应返回被清掉的条数")
	_check(state.get_play_history_entries().is_empty(), "清空后历史应为空")

func _test_history_state_controller() -> void:
	var state := _reset_state()
	var history_state := HistoryStateControllerScript.new(ControllerBaseScript.new())

	state.record_play("t0", NOW - 300)
	state.record_play("t0", NOW - 290)
	state.record_play("t0", NOW - 280)
	state.record_play("t1", NOW - 100)
	state.record_play("t2", NOW - 200)

	var recent := history_state.get_recent_track_ids()
	_check(recent.size() == 3, "最近播放应返回全部有记录的曲目")
	_check(recent[0] == "t1" and recent[1] == "t2" and recent[2] == "t0", "最近播放应按时间从新到旧")

	var most := history_state.get_most_played_track_ids()
	_check(most.size() == 3, "播放最多应返回全部有记录的曲目")
	_check(most[0] == "t0", "播放最多应按次数降序")

	_check(history_state.get_play_count("t0") == 3, "播放次数应可查询")
	_check(history_state.get_history_track_count() == 3, "历史曲目数应为 3")
	_check(history_state.get_total_play_count() == 5, "累计播放次数应为 5")

	# 曲目从资料库移除后，历史不应再展示它。
	state.tracks.erase(state.get_track_by_id("t1"))
	state.normalize()
	var filtered := history_state.get_recent_track_ids()
	_check(not filtered.has("t1"), "已删除的曲目应被过滤掉")
	_check(history_state.get_history_track_count() == 2, "过滤后历史曲目数应为 2")

	# 同一首曲目的续播事件应被折叠，只有播完后的下一轮才重新计数。
	state.clear_play_history()
	_check(history_state.record_playback("t0", NOW) == true, "首次起播应记录")
	_check(history_state.record_playback("t0", NOW + 1) == false, "同一首歌的续播不应重复计数")
	_check(history_state.get_play_count("t0") == 1, "续播后次数应仍为 1")
	history_state._on_playback_finished(null)
	_check(history_state.record_playback("t0", NOW + 2) == true, "播完后的下一轮应重新计数")
	_check(history_state.get_play_count("t0") == 2, "重新计数后次数应为 2")

func _test_page_controller() -> void:
	var state := _reset_state()
	state.record_play("t0", NOW - 30)
	state.record_play("t0", NOW - 20)
	state.record_play("t1", NOW - 4000)

	var controller := HistoryControllerScript.new()

	_check(controller.get_tab() == HistoryControllerScript.Tab.RECENT, "默认标签页应为最近播放")
	_check(controller.set_tab(HistoryControllerScript.Tab.MOST_PLAYED), "切换标签页应返回 true")
	_check(not controller.set_tab(HistoryControllerScript.Tab.MOST_PLAYED), "切到相同标签页应返回 false")
	_check(controller.cycle_tab() == HistoryControllerScript.Tab.RECENT, "循环切换应回到最近播放")
	_check(controller.set_tab(99) == true and controller.get_tab() == 1, "越界标签页应被夹到有效范围")

	var recent_ids := controller.get_track_ids()
	_check(recent_ids.size() == 2 and recent_ids[0] == "t0", "最近播放应以新到旧排列")

	controller.set_tab(HistoryControllerScript.Tab.MOST_PLAYED)
	var most_ids := controller.get_track_ids()
	_check(most_ids.size() == 2 and most_ids[0] == "t0", "播放最多应以次数降序排列")

	_check(controller.get_row_title("t0") == "曲目 0", "行标题应取曲名")
	_check(controller.get_row_title("missing") == tr("music_app.history.unknown_track"), "未知曲目应回退到占位文案")
	_check(not controller.get_row_side_text("t0").is_empty(), "播放最多右列应显示次数")
	_check(not controller.get_row_subtitle("t0").is_empty(), "行副标题不应为空")

	controller.set_tab(HistoryControllerScript.Tab.RECENT)
	_check(controller.get_row_side_text("t0") != "", "最近播放右列应显示相对时间")

	_check(controller.format_relative_time(0) == "", "时间戳 0 应返回空串")
	_check(
		controller.format_relative_time(NOW - 10, NOW) != controller.format_relative_time(NOW - 3700, NOW),
		"不同时间跨度应产生不同文案"
	)
	var long_ago := controller.format_relative_time(NOW - 86400 * 30, NOW)
	_check(long_ago.length() == 10 and long_ago[4] == "-", "超过 7 天应回退到日期格式")

	_check(controller.format_play_count(1) != controller.format_play_count(5), "1 次与多次应使用不同文案")

	var summary := controller.get_summary_text()
	_check(summary.contains("2"), "统计文案应包含曲目数量")
	var recent_empty_title := controller.get_empty_title()
	var recent_empty_hint := controller.get_empty_hint()
	_check(not recent_empty_title.is_empty(), "空态标题不应为空")
	controller.set_tab(HistoryControllerScript.Tab.MOST_PLAYED)
	_check(controller.get_empty_title() != recent_empty_title, "两个标签页的空态标题应有区分")
	_check(controller.get_empty_hint() != recent_empty_hint, "两个标签页的空态提示应有区分")
	controller.set_tab(HistoryControllerScript.Tab.RECENT)

	_check(controller.has_history(), "有记录时应返回 true")
	state.clear_play_history()
	_check(not controller.has_history(), "清空后 has_history 应为 false")

func _test_row_scene() -> void:
	var row := HistoryRowScene.instantiate() as MusicAppHistoryRow
	add_child(row)
	await get_tree().process_frame
	row.configure(2, "副标题曲目", "歌手 - 备注", "播放 12 次")
	_check(row.get_node("Margin/Row/IndexLabel").text == "3", "行序号应从 1 开始")
	_check(row.get_node("Margin/Row/Info/TitleLabel").text == "副标题曲目", "行标题应写入曲名")
	_check(row.get_node("Margin/Row/Info/SubtitleLabel").text == "歌手 - 备注", "行副标题应写入传入文本")
	_check(row.get_node("Margin/Row/SideChip/Margin/SideLabel").text == "播放 12 次", "右侧信息应写入传入文本")

	var emitted: Array[int] = []
	row.play_requested.connect(func(index: int) -> void: emitted.append(index))
	row.get_node("OpenButton").pressed.emit()
	_check(emitted == [2], "点击整行应发出对应槽位")
	row.queue_free()
	await get_tree().process_frame

func _test_page_scene() -> void:
	var page := HistoryPageScene.instantiate() as MusicAppHistoryView
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	_check(page.get_node_or_null("%HistoryBackButton") != null, "页面应包含返回按钮")
	_check(page.get_node_or_null("%HistoryRecentTabButton") != null, "页面应包含最近播放标签")
	_check(page.get_node_or_null("%HistoryMostPlayedTabButton") != null, "页面应包含播放最多标签")
	_check(page.get_node_or_null("%HistoryList") != null, "页面应包含列表容器")
	page.queue_free()
	await get_tree().process_frame
