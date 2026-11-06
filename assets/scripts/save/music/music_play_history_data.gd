class_name MusicPlayHistoryData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

## 一条播放历史统计。
##
## 刻意不把这些字段塞进 TrackData：TrackData 是插件/本地扫描写入的曲目元数据，
## 播放次数与播放时间属于用户行为，两者混在一起会让插件刷新曲目时丢掉统计。
## 以 track_id 为键单独聚合，曲目被移出资料库后统计仍保留，重新加回即可续上。
var track_id: String = ""
## 累计播放次数（一次「起播」记一次，暂停恢复不重复记）。
var play_count: int = 0
## 最近一次播放的时间戳（Unix 秒，0 表示从未播放）。
var last_played_at: int = 0

func normalize() -> void:
	track_id = track_id.strip_edges()
	play_count = maxi(0, play_count)
	last_played_at = maxi(0, last_played_at)

## 是否是一条有效统计（有播放次数或播放时间）。
func has_playback() -> bool:
	return play_count > 0 or last_played_at > 0
