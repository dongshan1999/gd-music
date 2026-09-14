extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const HttpJsonClientScript = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const TextUtilsScript = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "bilibili"
const AUTHOR := "猫头猫"
const VERSION := "0.2.4"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/bilibili/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"get_media_source",
	"getMediaSource",
	"get_album_info",
	"getAlbumInfo",
	"get_artist_works",
	"getArtistWorks",
	"import_music_sheet",
	"importMusicSheet",
	"get_toplists",
	"getTopLists",
	"get_toplist_detail",
	"getTopListDetail",
]
const DEFAULT_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36 Edg/89.0.774.63",
	"accept": "*/*",
	"accept-encoding": "gzip",
	"accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
}
const SEARCH_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36 Edg/89.0.774.63",
	"accept": "application/json, text/plain, */*",
	"accept-encoding": "gzip",
	"origin": "https://search.bilibili.com",
	"sec-fetch-site": "same-site",
	"sec-fetch-mode": "cors",
	"sec-fetch-dest": "empty",
	"referer": "https://search.bilibili.com/",
	"accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
}
const MOBILE_SAFARI_USER_AGENT := "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/114.0.0.0"
const PAGE_SIZE := 20
const MIXIN_KEY_TABLE := [
	46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
	27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
	37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
	22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
]

var last_error := ""

var _http = HttpJsonClientScript.new()
var _cookie: Dictionary = {}
var _wbi_img: String = ""
var _wbi_sub: String = ""
var _wbi_sync_date: String = ""

func get_platform() -> String:
	return PLATFORM

func get_name() -> String:
	return "Bilibili"

func get_description() -> String:
	return "搜索 Bilibili 视频并播放音频。"

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
	return "high"

func search(query: String, page: int, media_type: String) -> Dictionary:
	last_error = ""
	print("[Bilibili] search request: ", {"query": query, "page": page, "media_type": media_type})
	if media_type == "music":
		var music_result := await _search_music(query, page)
		_log_search_result("music", music_result)
		return music_result
	if media_type == "album":
		var album_result := await _search_album(query, page)
		_log_search_result("album", album_result)
		return album_result
	if media_type == "artist":
		var artist_result := await _search_artist(query, page)
		_log_search_result("artist", artist_result)
		return artist_result
	return {"isEnd": true, "data": []}

func get_album_info(album_item: Dictionary, _page: int) -> Dictionary:
	var cid_data = await _get_cid(str(album_item.get("bvid", "")), album_item.get("aid", null))
	var cid_response: Dictionary = (cid_data as Dictionary).get("data", {})
	var cid = cid_response.get("cid", null)
	var pages = _ensure_array(cid_response.get("pages", []))
	var music_list: Array = []

	if pages.size() <= 1:
		var single_item = album_item.duplicate(true)
		single_item["cid"] = cid
		music_list.append(single_item)
	else:
		for page_item in pages:
			var part: Dictionary = page_item
			var mapped = album_item.duplicate(true)
			mapped["cid"] = part.get("cid", null)
			mapped["title"] = str(part.get("part", mapped.get("title", "")))
			mapped["duration"] = _duration_to_sec(part.get("duration", 0))
			mapped["id"] = part.get("cid", mapped.get("id", ""))
			music_list.append(mapped)

	return {"musicList": music_list}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type != "music" and media_type != "album":
		return {"isEnd": true, "data": []}

	await _ensure_cookie()
	var query_headers = DEFAULT_HEADERS.duplicate(true)
	query_headers["accept"] = "*/*"
	query_headers["accept-encoding"] = "gzip"
	query_headers["origin"] = "https://space.bilibili.com"
	query_headers["sec-fetch-site"] = "same-site"
	query_headers["sec-fetch-mode"] = "cors"
	query_headers["sec-fetch-dest"] = "empty"
	query_headers["referer"] = "https://space.bilibili.com/%s/video" % str(artist_item.get("id", ""))
	query_headers["cookie"] = _build_cookie_header()

	var now = int(Time.get_unix_time_from_system())
	var params = {
		"mid": str(artist_item.get("id", "")),
		"ps": 30,
		"tid": 0,
		"pn": page,
		"web_location": 1550101,
		"order_avoided": true,
		"order": "pubdate",
		"keyword": "",
		"platform": "web",
		"dm_img_list": "[]",
		"dm_img_str": "V2ViR0wgMS4wIChPcGVuR0wgRVMgMi4wIENocm9taXVtKQ",
		"dm_cover_img_str": "QU5HTEUgKE5WSURJQSwgTlZJRElBIEdlRm9yY2UgR1RYIDE2NTAgKDB4MDAwMDFGOTEpIERpcmVjdDNEMTEgdnNfNV8wIHBzXzVfMCwgRDNEMTEpR29vZ2xlIEluYy4gKE5WSURJQS",
		"dm_img_inter": "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}",
		"wts": str(now),
	}
	var w_rid = await _get_rid(params)
	if w_rid.is_empty():
		return {"isEnd": true, "data": []}
	params["w_rid"] = w_rid

	var data = await _request_api(
		"https://api.bilibili.com/x/space/wbi/arc/search",
		params,
		query_headers
	)
	var result_data: Dictionary = (data as Dictionary).get("data", {})
	var list_info: Dictionary = result_data.get("list", {})
	var videos = _ensure_array(list_info.get("vlist", []))
	var mapped: Array = []
	for video in videos:
		mapped.append(_format_media(video))

	var page_info: Dictionary = result_data.get("page", {})
	var pn = int(page_info.get("pn", page))
	var ps = int(page_info.get("ps", 30))
	var count = int(page_info.get("count", mapped.size()))
	return {
		"isEnd": pn * ps >= count,
		"data": mapped,
	}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	last_error = ""
	var cid = music_item.get("cid", null)
	if cid == null:
		var cid_data = await _get_cid(str(music_item.get("bvid", "")), music_item.get("aid", null))
		cid = (cid_data as Dictionary).get("data", {}).get("cid", null)
	if cid == null:
		if last_error.is_empty():
			last_error = "无法获取视频分 P 信息。"
		return {}

	# JSON numbers are floats in Godot; Bilibili rejects decimal/scientific IDs.
	var params = {"cid": int(cid), "fnval": 16, "fourk": 0}
	if not str(music_item.get("bvid", "")).is_empty():
		params["bvid"] = str(music_item.get("bvid", ""))
	else:
		params["aid"] = int(music_item.get("aid", 0))

	var data = await _request_api(
		"https://api.bilibili.com/x/player/playurl",
		params,
		DEFAULT_HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {})
	var url = ""
	if payload.get("dash") is Dictionary:
		var dash: Dictionary = payload.get("dash", {})
		var audios = _ensure_array(dash.get("audio", []))
		audios.sort_custom(func(a, b): return int((a as Dictionary).get("bandwidth", 0)) < int((b as Dictionary).get("bandwidth", 0)))
		if not audios.is_empty():
			var quality_index = _quality_to_index(quality)
			quality_index = clampi(quality_index, 0, audios.size() - 1)
			url = str((audios[quality_index] as Dictionary).get("baseUrl", (audios[quality_index] as Dictionary).get("base_url", "")))
	if url.is_empty():
		if last_error.is_empty():
			last_error = "该视频没有可用的音频流，可能需要登录或暂不可播放。"
		return {}
	if url.begins_with("http://"):
		url = "https://" + url.trim_prefix("http://")

	var refer_id = str(music_item.get("bvid", ""))
	if refer_id.is_empty():
		refer_id = "av%d" % int(music_item.get("aid", 0))
	return {
		"url": url,
		"format": "m4a",
		"headers": {
			"user-agent": DEFAULT_HEADERS["user-agent"],
			"accept": "*/*",
			"accept-encoding": "gzip",
			"referer": "https://www.bilibili.com/video/%s" % refer_id,
		},
	}

func get_toplists() -> Array:
	var weekly_data = await _request_api(
		"https://api.bilibili.com/x/web-interface/popular/series/list",
		{},
		{"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"}
	)
	var weekly_items = _ensure_array((weekly_data as Dictionary).get("data", {}).get("list", []))
	var weekly: Array = []
	for item in weekly_items.slice(0, 8):
		var source: Dictionary = item
		weekly.append({
			"id": "popular/series/one?number=%s" % str(source.get("number", "")),
			"title": str(source.get("subject", "")),
			"description": str(source.get("name", "")),
			"coverImg": "https://s1.hdslb.com/bfs/static/jinkela/popular/assets/icon_weekly.png",
		})

	var board_keys = [
		{"id": "ranking/v2?rid=0&type=all", "title": "全站"},
		{"id": "ranking/v2?rid=3&type=all", "title": "音乐"},
		{"id": "ranking/v2?rid=1&type=all", "title": "动画"},
		{"id": "ranking/v2?rid=119&type=all", "title": "鬼畜"},
		{"id": "ranking/v2?rid=168&type=all", "title": "国创相关"},
		{"id": "ranking/v2?rid=129&type=all", "title": "舞蹈"},
		{"id": "ranking/v2?rid=4&type=all", "title": "游戏"},
		{"id": "ranking/v2?rid=36&type=all", "title": "知识"},
		{"id": "ranking/v2?rid=188&type=all", "title": "科技"},
		{"id": "ranking/v2?rid=234&type=all", "title": "运动"},
		{"id": "ranking/v2?rid=223&type=all", "title": "汽车"},
		{"id": "ranking/v2?rid=160&type=all", "title": "生活"},
		{"id": "ranking/v2?rid=211&type=all", "title": "美食"},
		{"id": "ranking/v2?rid=217&type=all", "title": "动物圈"},
		{"id": "ranking/v2?rid=155&type=all", "title": "时尚"},
		{"id": "ranking/v2?rid=5&type=all", "title": "娱乐"},
		{"id": "ranking/v2?rid=181&type=all", "title": "影视"},
		{"id": "ranking/v2?rid=0&type=origin", "title": "原创"},
		{"id": "ranking/v2?rid=0&type=rookie", "title": "新人"},
	]
	var board: Array = []
	for item in board_keys:
		var source: Dictionary = item
		var mapped = source.duplicate(true)
		mapped["coverImg"] = "https://s1.hdslb.com/bfs/static/jinkela/popular/assets/icon_rank.png"
		board.append(mapped)

	return [
		{
			"title": "每周必看",
			"data": weekly,
		},
		{
			"title": "入站必刷",
			"data": [{
				"id": "popular/precious?page_size=100&page=1",
				"title": "入站必刷",
				"coverImg": "https://s1.hdslb.com/bfs/static/jinkela/popular/assets/icon_history.png",
			}],
		},
		{
			"title": "排行榜",
			"data": board,
		},
	]

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var data = await _request_api(
		"https://api.bilibili.com/x/web-interface/%s" % str(toplist_item.get("id", "")),
		{},
		{
			"user-agent": DEFAULT_HEADERS["user-agent"],
			"accept": DEFAULT_HEADERS["accept"],
			"accept-encoding": DEFAULT_HEADERS["accept-encoding"],
			"accept-language": DEFAULT_HEADERS["accept-language"],
			"referer": "https://www.bilibili.com/",
		}
	)
	var items = _ensure_array((data as Dictionary).get("data", {}).get("list", []))
	var music_list: Array = []
	for item in items:
		music_list.append(_format_media(item))
	var result = toplist_item.duplicate(true)
	result["musicList"] = music_list
	return result

func import_music_sheet(url_like: String) -> Array:
	var media_id = _extract_favorite_id(url_like)
	if media_id.is_empty():
		return []

	var music_sheet = await _get_favorite_list(media_id)
	var mapped: Array = []
	for item in music_sheet:
		var source: Dictionary = item
		mapped.append({
			"id": source.get("id", ""),
			"aid": source.get("aid", null),
			"bvid": str(source.get("bvid", "")),
			"artwork": str(source.get("cover", "")),
			"title": str(source.get("title", "")),
			"artist": str(source.get("upper", {}).get("name", "")),
			"album": str(source.get("bvid", source.get("aid", ""))),
			"duration": _duration_to_sec(source.get("duration", 0)),
			"platform": PLATFORM,
		})
	return mapped

func _search_album(query: String, page: int) -> Dictionary:
	var result_data = await _search_base(query, page, "video")
	var result_items = _ensure_array((result_data as Dictionary).get("result", []))
	var mapped: Array = []
	for item in result_items:
		var collection := _format_media(item)
		collection["id"] = str(item.get("bvid", item.get("aid", "")))
		collection["mediaType"] = "album"
		collection["collectionType"] = "album"
		collection["album"] = "视频合集"
		collection["duration"] = 0
		mapped.append(collection)
	return {
		"isEnd": int((result_data as Dictionary).get("numResults", 0)) <= page * PAGE_SIZE,
		"data": mapped,
	}

func _search_music(query: String, page: int) -> Dictionary:
	var result_data = await _search_base(query, page, "video")
	var result_items = _ensure_array((result_data as Dictionary).get("result", []))
	var mapped: Array = []
	for item in result_items:
		var music := _format_media(item)
		# Search API returns videos for both tabs. Keep the raw API evidence so
		# the click handler can resolve the actual page count before classifying.
		music["mediaType"] = "music"
		music["collectionType"] = ""
		if _is_collection_result(item, music):
			music["mediaType"] = "album"
			music["collectionType"] = "album"
			music["album"] = "视频合集"
			music["duration"] = 0
		mapped.append(music)
	return {
		"isEnd": int((result_data as Dictionary).get("numResults", 0)) <= page * PAGE_SIZE,
		"data": mapped,
	}

func _log_search_result(result_type: String, result: Dictionary) -> void:
	var items: Array = result.get("data", []) if result is Dictionary else []
	var first: Dictionary = items[0] if not items.is_empty() and items[0] is Dictionary else {}
	print("[Bilibili] search result: ", {
		"result_type": result_type,
		"count": items.size(),
		"is_end": result.get("isEnd", true),
		"first_id": first.get("id", ""),
		"first_bvid": first.get("bvid", ""),
		"first_title": first.get("title", first.get("name", "")),
		"first_media_type": first.get("mediaType", ""),
		"first_collection_type": first.get("collectionType", ""),
		"first_keys": first.keys(),
	})
	if not items.is_empty():
		for index in mini(items.size(), 3):
			print("[Bilibili] raw result[%d]: %s" % [index, JSON.stringify(items[index])])

func _looks_like_collection_title(title: String) -> bool:
	var normalized := title.strip_edges()
	if normalized.is_empty():
		return false
	var count_pattern := RegEx.new()
	if count_pattern.compile("(?:[0-9０-９一二三四五六七八九十百千]+)\\s*首") == OK and count_pattern.search(normalized) != null:
		return true
	for keyword in ["合集", "歌单", "精选集", "串烧", "全辑", "全集", "多首"]:
		if normalized.contains(keyword):
			return true
	return false

func _is_collection_result(raw_item: Dictionary, mapped_item: Dictionary) -> bool:
	var title: String = str(mapped_item.get("title", ""))
	var description: String = str(raw_item.get("description", ""))
	var tags: Variant = raw_item.get("tag", "")
	var tag_text: String = ""
	if tags is Array:
		for tag in tags:
			tag_text += "|" + str(tag)
	else:
		tag_text = str(tags)
	var evidence: int = 0
	var reason: String = ""
	var count_pattern := RegEx.new()
	if count_pattern.compile("(?:[0-9０-９一二三四五六七八九十百千]+)\\s*首") == OK and count_pattern.search(title) != null:
		evidence += 4
		reason = "title-count"
	for marker in ["合集", "选集", "歌单", "串烧", "全辑", "多首"]:
		if tag_text.contains(marker):
			evidence += 4
			reason = "tag:%s" % marker
			break
	for marker in ["合集", "选集", "歌单", "串烧", "曲目列表", "共"]:
		if description.contains(marker):
			evidence += 2
			break
	var music_context := tag_text.contains("音乐") or tag_text.contains("歌曲") or tag_text.contains("钢琴")
	if music_context and int(mapped_item.get("duration", 0)) >= 3600:
		evidence += 2
	var exclusion := title.contains("教程") or title.contains("教学") or title.contains("直播") or title.contains("演奏")
	if exclusion and evidence < 8:
		evidence -= 4
	print("[Bilibili] collection evidence: ", {"score": evidence, "reason": reason, "title": title, "tags": tag_text, "duration": mapped_item.get("duration", 0)})
	return evidence >= 4

func _search_artist(query: String, page: int) -> Dictionary:
	var result_data = await _search_base(query, page, "bili_user")
	var result_items = _ensure_array((result_data as Dictionary).get("result", []))
	var mapped: Array = []
	for item in result_items:
		var source: Dictionary = item
		var avatar = str(source.get("upic", ""))
		if avatar.begins_with("//"):
			avatar = "https:%s" % avatar
		mapped.append({
			"name": str(source.get("uname", "")),
			"id": source.get("mid", ""),
			"fans": source.get("fans", 0),
			"description": str(source.get("usign", "")),
			"avatar": avatar,
			"worksNum": source.get("videos", 0),
			"platform": PLATFORM,
		})
	return {
		"isEnd": int((result_data as Dictionary).get("numResults", 0)) <= page * PAGE_SIZE,
		"data": mapped,
	}

func _search_base(query: String, page: int, search_type: String) -> Variant:
	await _ensure_cookie()
	var headers = SEARCH_HEADERS.duplicate(true)
	headers["cookie"] = _build_cookie_header()
	var data = await _request_api(
		"https://api.bilibili.com/x/web-interface/search/type",
		{
			"context": "",
			"page": page,
			"order": "",
			"page_size": PAGE_SIZE,
			"keyword": query,
			"duration": "",
			"tids_1": "",
			"tids_2": "",
			"__refresh__": true,
			"_extra": "",
			"highlight": 1,
			"single_column": 0,
			"platform": "pc",
			"from_source": "",
			"search_type": search_type,
			"dynamic_offset": 0,
		},
		headers
	)
	if data is Dictionary:
		return (data as Dictionary).get("data", {})
	return {}

func _get_favorite_list(media_id: String) -> Array:
	var result: Array = []
	var page = 1
	while true:
		var data = await _request_api(
			"https://api.bilibili.com/x/v3/fav/resource/list",
			{
				"media_id": media_id,
				"platform": "web",
				"ps": PAGE_SIZE,
				"pn": page,
			},
			DEFAULT_HEADERS
		)
		var payload: Dictionary = (data as Dictionary).get("data", {})
		var medias = _ensure_array(payload.get("medias", []))
		for media in medias:
			result.append(media)
		if not bool(payload.get("has_more", false)):
			break
		page += 1
	return result

func _get_cid(bvid: String, aid: Variant) -> Variant:
	var params = {}
	if not bvid.is_empty():
		params["bvid"] = bvid
	elif aid != null:
		params["aid"] = int(aid)
	return await _request_api(
		"https://api.bilibili.com/x/web-interface/view",
		params,
		DEFAULT_HEADERS
	)

func _ensure_cookie() -> void:
	if not _cookie.is_empty():
		return
	var data = await _request_api(
		"https://api.bilibili.com/x/frontend/finger/spi",
		{},
		{"User-Agent": MOBILE_SAFARI_USER_AGENT}
	)
	if data is Dictionary:
		var data_dict: Dictionary = data
		var cookie_data = data_dict.get("data", {})
		_cookie = cookie_data if cookie_data is Dictionary else {}
	else:
		_cookie = {}

func _build_cookie_header() -> String:
	if _cookie.is_empty():
		return ""
	return "buvid3=%s;buvid4=%s" % [
		str(_cookie.get("b_3", "")),
		str(_cookie.get("b_4", "")),
	]

func _format_media(result: Variant) -> Dictionary:
	var source: Dictionary = result if result is Dictionary else {}
	var raw_title = str(source.get("title", ""))
	raw_title = TextUtilsScript.strip_html_emphasis(raw_title)
	raw_title = TextUtilsScript.decode_basic_html_entities(raw_title)

	var artwork = str(source.get("pic", ""))
	if artwork.begins_with("//"):
		artwork = "https:%s" % artwork

	var title_match = RegEx.new()
	var alias = ""
	if title_match.compile("《(.+?)》") == OK:
		var match = title_match.search(raw_title)
		if match != null and match.get_group_count() >= 1:
			alias = match.get_string(1)

	var tags_value = source.get("tag", "")
	var tags: Array = []
	if tags_value is String and not str(tags_value).is_empty():
		tags.assign(str(tags_value).split(","))

	var timestamp = int(source.get("pubdate", source.get("created", 0)))
	return {
		"id": source.get("cid", source.get("bvid", source.get("aid", ""))),
		"cid": source.get("cid", null),
		"aid": source.get("aid", null),
		"bvid": str(source.get("bvid", "")),
		"artist": str(source.get("author", source.get("owner", {}).get("name", ""))),
		"title": raw_title,
		"alias": alias,
		"album": str(source.get("bvid", source.get("aid", ""))),
		"artwork": artwork,
		"duration": _duration_to_sec(source.get("duration", 0)),
		"tags": tags,
		"date": TextUtilsScript.unix_to_date_string(timestamp),
		"platform": PLATFORM,
	}

func _duration_to_sec(duration: Variant) -> int:
	if duration is int:
		return int(duration)
	if duration is float:
		return int(duration)
	if duration is String:
		var parts = str(duration).split(":")
		var total = 0
		for part in parts:
			total = total * 60 + int(part) if part.is_valid_int() else total * 60
		return total
	return 0

func _get_wbi_keys() -> Dictionary:
	var today = Time.get_date_string_from_system()
	if not _wbi_img.is_empty() and not _wbi_sub.is_empty() and _wbi_sync_date == today:
		return {"img": _wbi_img, "sub": _wbi_sub}

	# The anonymous nav response may use code -101 but still contains WBI keys.
	var data = await _http.get_json("https://api.bilibili.com/x/web-interface/nav", {}, DEFAULT_HEADERS)
	if not (data is Dictionary) or not (data.get("data") is Dictionary):
		last_error = "无法获取 Bilibili 请求签名。"
		return {}
	var nav: Dictionary = data.data.get("wbi_img", {})
	var img_url = str(nav.get("img_url", ""))
	var sub_url = str(nav.get("sub_url", ""))
	_wbi_img = _basename_without_ext(img_url)
	_wbi_sub = _basename_without_ext(sub_url)
	_wbi_sync_date = today
	return {"img": _wbi_img, "sub": _wbi_sub}

func _get_rid(params: Dictionary) -> String:
	var keys = await _get_wbi_keys()
	if str(keys.get("img", "")).is_empty() or str(keys.get("sub", "")).is_empty():
		last_error = "Bilibili 请求签名为空，请稍后重试。"
		return ""
	var mixin_key = _get_mixin_key("%s%s" % [str(keys.get("img", "")), str(keys.get("sub", ""))])
	var ordered_keys = params.keys()
	ordered_keys.sort()
	var pairs: Array[String] = []
	var invalid_chars = RegEx.new()
	invalid_chars.compile("[!'()*]")
	for key in ordered_keys:
		var value = params[key]
		if value == null:
			continue
		var value_text = ("true" if value else "false") if value is bool else str(value)
		if value is String:
			value_text = invalid_chars.sub(value_text, "", true)
		pairs.append("%s=%s" % [str(key).uri_encode(), value_text.uri_encode()])
	var query = "&".join(pairs)
	return (query + mixin_key).md5_text()

func _get_mixin_key(source: String) -> String:
	var chars: Array[String] = []
	for index in MIXIN_KEY_TABLE.size():
		var char_index = int(MIXIN_KEY_TABLE[index])
		if char_index < source.length():
			chars.append(source.substr(char_index, 1))
	return "".join(chars).substr(0, 32)

func _extract_favorite_id(url_like: String) -> String:
	var patterns = [
		"^\\s*(\\d+)\\s*$",
		"^(?:.*)fid=(\\d+).*$",
		"/playlist/pl(\\d+)",
		"/list/ml(\\d+)",
	]
	for pattern in patterns:
		var regex = RegEx.new()
		if regex.compile(pattern) != OK:
			continue
		var match = regex.search(url_like)
		if match != null and match.get_group_count() >= 1:
			return match.get_string(1)
	return ""

func _quality_to_index(quality: String) -> int:
	match quality:
		"low":
			return 0
		"standard":
			return 1
		"high":
			return 2
		"super":
			return 3
		_:
			return 1

func _basename_without_ext(url: String) -> String:
	if url.is_empty():
		return ""
	var last_slash = url.rfind("/")
	var file_name = url.substr(last_slash + 1) if last_slash >= 0 else url
	var last_dot = file_name.rfind(".")
	return file_name.substr(0, last_dot) if last_dot >= 0 else file_name

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []

func _request_api(url: String, query: Dictionary = {}, headers: Dictionary = {}) -> Dictionary:
	var response = await _http.get_json(url, query, headers)
	if not (response is Dictionary):
		last_error = _http.last_error if not _http.last_error.is_empty() else "Bilibili 返回了无效响应。"
		return {}
	var code := int(response.get("code", 0))
	if code != 0:
		last_error = "Bilibili (%d): %s" % [code, str(response.get("message", "请求失败"))]
		return {}
	if response.has("data") and not (response.get("data") is Dictionary):
		last_error = "Bilibili 返回的数据不完整。"
		return {}
	return response
