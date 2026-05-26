extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "5sing"
const AUTHOR := "猫头猫"
const VERSION := "0.1.2"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/5sing/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"get_media_source",
	"getMediaSource",
	"get_album_info",
	"getAlbumInfo",
	"get_lyric",
	"getLyric",
	"get_artist_works",
	"getArtistWorks",
	"get_toplists",
	"getTopLists",
	"get_toplist_detail",
	"getTopListDetail",
]
const PAGE_SIZE := 10
const SEARCH_HEADERS := {
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36",
	"Host": "search.5sing.kugou.com",
	"Accept": "application/json, text/javascript, */*; q=0.01",
	"Accept-Encoding": "gzip, deflate",
	"Accept-Language": "zh-CN,zh;q=0.9",
	"Referer": "http://search.5sing.kugou.com/home/index",
}
const SERVICE_HEADERS := {
	"Accept": "*/*",
	"Accept-Encoding": "gzip, deflate",
	"Accept-Language": "zh-CN,zh;q=0.9",
	"Host": "service.5sing.kugou.com",
	"Referer": "http://5sing.kugou.com/",
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36",
}
const MOBILE_SERVICE_HEADERS := {
	"Accept": "application/json, text/plain, */*",
	"Accept-Encoding": "gzip, deflate",
	"Accept-Language": "zh-CN,zh;q=0.9",
	"Cache-Control": "no-cache",
	"Connection": "keep-alive",
	"Host": "service.5sing.kugou.com",
	"Origin": "http://5sing.kugou.com",
	"Pragma": "no-cache",
	"Referer": "http://5sing.kugou.com/",
	"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
}

var _http := GDMusicHttpJsonClient.new()
var _artist_end_state := {"fc": false, "yc": false, "bz": false}

func get_platform() -> String:
	return PLATFORM

func get_author() -> String:
	return AUTHOR

func get_version() -> String:
	return VERSION

func get_src_url() -> String:
	return SRC_URL

func get_default_search_type() -> String:
	return DEFAULT_SEARCH_TYPE

func get_supported_search_types() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_SEARCH_TYPES)

func get_supported_methods() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_METHODS)

func get_migration_difficulty() -> String:
	return "medium"

func search(query: String, page: int, media_type: String) -> Dictionary:
	match media_type:
		"music":
			return await _search_base(query, page, 0, 0, Callable(self, "_format_music_item"))
		"album":
			return await _search_base(query, page, 0, 1, Callable(self, "_format_album_item"))
		"artist":
			return await _search_base(query, page, 1, 2, Callable(self, "_format_artist_item"))
		_:
			return {"isEnd": true, "data": []}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type != "music":
		return {"isEnd": true, "data": []}
	if page <= 1:
		_artist_end_state = {"fc": false, "yc": false, "bz": false}

	var result: Array = []
	for type_ename in ["fc", "yc", "bz"]:
		if bool(_artist_end_state.get(type_ename, false)):
			continue
		var response = await _http.get_json(
			"http://service.5sing.kugou.com/user/songlist",
			{
				"userId": artist_item.get("id", ""),
				"type": type_ename,
				"pageSize": PAGE_SIZE,
				"page": page,
			},
			MOBILE_SERVICE_HEADERS
		)
		var payload: Dictionary = response if response is Dictionary else {}
		if int(payload.get("count", 0)) <= page * PAGE_SIZE:
			_artist_end_state[type_ename] = true
		for item in _ensure_array(payload.get("data", [])):
			var source: Dictionary = item
			var type_name = _type_name(type_ename)
			result.append({
				"id": source.get("songId", ""),
				"artist": str(artist_item.get("name", "")),
				"title": str(source.get("songName", "")),
				"typeEname": type_ename,
				"typeName": type_name,
				"type": source.get("songType", type_ename),
				"album": type_name,
				"platform": PLATFORM,
			})
	return {
		"isEnd": bool(_artist_end_state.get("fc", false)) and bool(_artist_end_state.get("yc", false)) and bool(_artist_end_state.get("bz", false)),
		"data": result,
	}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var data = await _http.get_json(
		"http://5sing.kugou.com/fm/m/json/lrc",
		{
			"songId": music_item.get("id", ""),
			"songType": music_item.get("typeEname", music_item.get("type", "")),
		},
		SERVICE_HEADERS
	)
	if data is Dictionary:
		return {"rawLrc": str((data as Dictionary).get("txt", ""))}
	return {}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://service.5sing.kugou.com/song/getPlayListSong",
		{"id": album_item.get("id", "")},
		MOBILE_SERVICE_HEADERS
	)
	var payload: Dictionary = data if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("data", [])):
		var source: Dictionary = item
		var user: Dictionary = source.get("user", {})
		mapped.append({
			"id": source.get("ID", ""),
			"typeEname": source.get("SK", ""),
			"title": str(source.get("SN", "")),
			"artist": str(user.get("NN", "")),
			"singerId": user.get("ID", ""),
			"album": str(album_item.get("title", "")),
			"artwork": str(album_item.get("artwork", "")),
			"platform": PLATFORM,
		})
	return {"musicList": mapped}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if quality == "super":
		return {}
	var text = await _http.get_text(
		"http://service.5sing.kugou.com/song/getsongurl",
		{
			"songid": music_item.get("id", ""),
			"songtype": music_item.get("typeEname", music_item.get("type", "")),
			"from": "web",
			"version": "6.6.72",
			"_": Time.get_ticks_msec(),
		},
		SERVICE_HEADERS
	)
	var json_text = text.strip_edges()
	if json_text.begins_with("(") and json_text.ends_with(")"):
		json_text = json_text.substr(1, json_text.length() - 2)
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {}
	var payload: Dictionary = (parsed as Dictionary).get("data", {})
	var url := ""
	match quality:
		"standard":
			url = str(payload.get("squrl", payload.get("squrl_backup", "")))
		"high":
			url = str(payload.get("hqurl", payload.get("hqurl_backup", "")))
		_:
			url = str(payload.get("lqurl", payload.get("lqurl_backup", "")))
	return {"url": url} if not url.is_empty() else {}

func get_toplists() -> Array:
	return [{
		"title": "排行榜",
		"data": [
			{
				"id": "/",
				"title": "原创音乐榜",
				"description": "最热门的原创音乐歌曲榜",
				"typeEname": "yc",
				"typeName": "原创",
			},
			{
				"id": "/fc",
				"title": "翻唱音乐榜",
				"description": "最热门的流行歌曲翻唱排行",
				"typeEname": "fc",
				"typeName": "翻唱",
			},
			{
				"id": "/bz",
				"title": "伴奏音乐榜",
				"description": "搜索最多的伴奏排行",
				"typeEname": "bz",
				"typeName": "伴奏",
			},
		],
	}]

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var html = await _http.get_text("http://5sing.kugou.com/top%s" % str(toplist_item.get("id", "")))
	var tbody = GDMusicTextUtils.extract_first_match(html, "<div[^>]*class=[\"'][^\"']*rank_view[^\"']*[\"'][^>]*>[\\s\\S]*?<tbody[^>]*>([\\s\\S]*?)</tbody>")
	var row_regex = RegEx.new()
	if row_regex.compile("<tr[^>]*>([\\s\\S]*?)</tr>") != OK:
		var empty_result = toplist_item.duplicate(true)
		empty_result["musicList"] = []
		return empty_result
	var rows = row_regex.search_all(tbody)
	var music_list: Array = []
	for row_index in range(1, rows.size()):
		var row_html = rows[row_index].get_string(1)
		var title = GDMusicTextUtils.clean_html_text(GDMusicTextUtils.extract_first_match(row_html, "<td[^>]*class=[\"'][^\"']*r_td_3[^\"']*[\"'][^>]*>([\\s\\S]*?)</td>"))
		var artist_html = GDMusicTextUtils.extract_first_match(row_html, "<td[^>]*class=[\"'][^\"']*r_td_4[^\"']*[\"'][^>]*>([\\s\\S]*?)</td>")
		var artist = GDMusicTextUtils.clean_html_text(artist_html)
		var singer_id = GDMusicTextUtils.extract_first_match(artist_html, "http://5sing\\.kugou\\.com/(\\d+)")
		var link_html = GDMusicTextUtils.extract_first_match(row_html, "<td[^>]*class=[\"'][^\"']*r_td_6[^\"']*[\"'][^>]*>([\\s\\S]*?)</td>")
		var id = GDMusicTextUtils.extract_first_match(link_html, "http://5sing\\.kugou\\.com/.+?(\\d+)\\.html")
		if id.is_empty():
			continue
		music_list.append({
			"title": title,
			"artist": artist,
			"singerId": singer_id,
			"id": id,
			"typeEname": toplist_item.get("typeEname", ""),
			"typeName": toplist_item.get("typeName", ""),
			"type": toplist_item.get("typeEname", ""),
			"album": toplist_item.get("typeName", ""),
			"platform": PLATFORM,
		})
	var result = toplist_item.duplicate(true)
	result["musicList"] = music_list
	return result

func _search_base(query: String, page: int, filter: int, type: int, formatter: Callable) -> Dictionary:
	var data = await _http.get_json(
		"http://search.5sing.kugou.com/home/json",
		{
			"keyword": query,
			"sort": 1,
			"page": page,
			"filter": filter,
			"type": type,
		},
		SEARCH_HEADERS
	)
	var payload: Dictionary = data if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("list", [])):
		mapped.append(formatter.call(item))
	var page_info: Dictionary = payload.get("pageInfo", {})
	return {
		"isEnd": int(page_info.get("cur", page)) >= int(page_info.get("totalPages", page)),
		"data": mapped,
	}

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("songId", ""),
		"title": GDMusicTextUtils.clean_html_text(str(source.get("songName", ""))),
		"artist": str(source.get("singer", "")),
		"singerId": source.get("singerId", ""),
		"album": str(source.get("typeName", "")),
		"type": source.get("type", ""),
		"typeName": str(source.get("typeName", "")),
		"typeEname": str(source.get("typeEname", "")),
		"platform": PLATFORM,
	}

func _format_album_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("songListId", ""),
		"artist": str(source.get("userName", "")),
		"title": GDMusicTextUtils.clean_html_text(str(source.get("title", ""))),
		"artwork": str(source.get("pictureUrl", "")),
		"description": str(source.get("content", "")),
		"date": source.get("createTime", ""),
		"platform": PLATFORM,
	}

func _format_artist_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("id", ""),
		"name": GDMusicTextUtils.clean_html_text(str(source.get("nickName", ""))),
		"fans": source.get("fans", 0),
		"avatar": str(source.get("pictureUrl", "")),
		"description": str(source.get("description", "")),
		"worksNum": source.get("totalSong", 0),
		"platform": PLATFORM,
	}

func _type_name(type_ename: String) -> String:
	match type_ename:
		"fc":
			return "翻唱"
		"yc":
			return "原创"
		"bz":
			return "伴奏"
		_:
			return type_ename

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
