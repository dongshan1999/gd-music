class_name GDMusicBilibiliPlugin
extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicHashUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_hash_utils.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "bilibili"
const AUTHOR := "猫头猫"
const VERSION := "0.2.3"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/bilibili/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"getMediaSource",
	"getAlbumInfo",
	"getArtistWorks",
	"importMusicSheet",
	"getTopLists",
	"getTopListDetail",
]
const DEFAULT_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36 Edg/89.0.774.63",
	"accept": "*/*",
	"accept-encoding": "gzip, deflate, br",
	"accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
}
const SEARCH_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36 Edg/89.0.774.63",
	"accept": "application/json, text/plain, */*",
	"accept-encoding": "gzip, deflate, br",
	"origin": "https://search.bilibili.com",
	"sec-fetch-site": "same-site",
	"sec-fetch-mode": "cors",
	"sec-fetch-dest": "empty",
	"referer": "https://search.bilibili.com/",
	"accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
}
const MOBILE_SAFARI_USER_AGENT := "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/114.0.0.0"
const PAGE_SIZE := 20
const WBI_HEX_KEY := "XgwSnGZ1p"
const MIXIN_KEY_TABLE := [
	46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
	27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
	37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
	22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
]

var _http = GDMusicHttpJsonClient.new()
var _cookie: Dictionary = {}
var _wbi_img: String = ""
var _wbi_sub: String = ""
var _wbi_sync_date: String = ""
var _w_webid: String = ""
var _w_webid_time_msec: int = 0

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
	return "high"

func search(query: String, page: int, media_type: String) -> Dictionary:
	if media_type == "album" or media_type == "music":
		return await _search_album(query, page)
	if media_type == "artist":
		return await _search_artist(query, page)
	return {"isEnd": true, "data": []}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
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
	query_headers["accept-encoding"] = "gzip, deflate, br, zstd"
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
	params["w_rid"] = w_rid

	var data = await _http.get_json(
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
	var cid = music_item.get("cid", null)
	if cid == null:
		var cid_data = await _get_cid(str(music_item.get("bvid", "")), music_item.get("aid", null))
		cid = (cid_data as Dictionary).get("data", {}).get("cid", null)
	if cid == null:
		return {}

	var params = {"cid": cid, "fnval": 16}
	if not str(music_item.get("bvid", "")).is_empty():
		params["bvid"] = str(music_item.get("bvid", ""))
	else:
		params["aid"] = music_item.get("aid", null)

	var data = await _http.get_json(
		"https://api.bilibili.com/x/player/playurl",
		params,
		DEFAULT_HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {})
	var url = ""
	if payload.has("dash"):
		var dash: Dictionary = payload.get("dash", {})
		var audios = _ensure_array(dash.get("audio", []))
		audios.sort_custom(func(a, b): return int((a as Dictionary).get("bandwidth", 0)) < int((b as Dictionary).get("bandwidth", 0)))
		if not audios.is_empty():
			var quality_index = _quality_to_index(quality)
			quality_index = clampi(quality_index, 0, audios.size() - 1)
			url = str((audios[quality_index] as Dictionary).get("baseUrl", ""))
	else:
		var durl = _ensure_array(payload.get("durl", []))
		if not durl.is_empty():
			url = str((durl[0] as Dictionary).get("url", ""))
	if url.is_empty():
		return {}

	var host = ""
	var url_parts = url.split("/", false, 3)
	if url_parts.size() >= 3:
		host = url_parts[2]

	var refer_id = str(music_item.get("bvid", music_item.get("aid", "")))
	return {
		"url": url,
		"headers": {
			"user-agent": DEFAULT_HEADERS["user-agent"],
			"accept": "*/*",
			"host": host,
			"accept-encoding": "gzip, deflate, br",
			"connection": "keep-alive",
			"referer": "https://www.bilibili.com/video/%s" % refer_id,
		},
	}

func get_toplists() -> Array:
	var weekly_data = await _http.get_json(
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
	var data = await _http.get_json(
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
		mapped.append(_format_media(item))
	return {
		"isEnd": int((result_data as Dictionary).get("numResults", 0)) <= page * PAGE_SIZE,
		"data": mapped,
	}

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
	var data = await _http.get_json(
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
		var data = await _http.get_json(
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
		params["aid"] = aid
	return await _http.get_json(
		"https://api.bilibili.com/x/web-interface/view",
		params,
		DEFAULT_HEADERS
	)

func _ensure_cookie() -> void:
	if not _cookie.is_empty():
		return
	var data = await _http.get_json(
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
	raw_title = GDMusicTextUtils.strip_html_emphasis(raw_title)
	raw_title = GDMusicTextUtils.decode_basic_html_entities(raw_title)

	var artwork = str(source.get("pic", ""))
	if artwork.begins_with("//"):
		artwork = "http:%s" % artwork

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
		"aid": source.get("aid", null),
		"bvid": str(source.get("bvid", "")),
		"artist": str(source.get("author", source.get("owner", {}).get("name", ""))),
		"title": raw_title,
		"alias": alias,
		"album": str(source.get("bvid", source.get("aid", ""))),
		"artwork": artwork,
		"duration": _duration_to_sec(source.get("duration", 0)),
		"tags": tags,
		"date": GDMusicTextUtils.unix_to_date_string(timestamp),
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

func _get_bili_ticket(csrf: String = "") -> Variant:
	var ts = int(Time.get_unix_time_from_system())
	var hex_sign = GDMusicHashUtils.hmac_sha256_hex(WBI_HEX_KEY, "ts%d" % ts)
	return await _http.request_json(
		"https://api.bilibili.com/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket",
		{
			"key_id": "ec02",
			"hexsign": hex_sign,
			"context[ts]": ts,
			"csrf": csrf,
		},
		{"User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"},
		HTTPClient.METHOD_POST
	)

func _get_wbi_keys() -> Dictionary:
	var today = Time.get_date_string_from_system()
	if not _wbi_img.is_empty() and not _wbi_sub.is_empty() and _wbi_sync_date == today:
		return {"img": _wbi_img, "sub": _wbi_sub}

	var data = await _get_bili_ticket("")
	var nav: Dictionary = (data as Dictionary).get("data", {}).get("nav", {})
	var img_url = str(nav.get("img", ""))
	var sub_url = str(nav.get("sub", ""))
	_wbi_img = _basename_without_ext(img_url)
	_wbi_sub = _basename_without_ext(sub_url)
	_wbi_sync_date = today
	return {"img": _wbi_img, "sub": _wbi_sub}

func _get_rid(params: Dictionary) -> String:
	var keys = await _get_wbi_keys()
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
		var value_text = str(value)
		if value is String:
			value_text = invalid_chars.sub(value_text, "", true)
		pairs.append("%s=%s" % [str(key).uri_encode(), value_text.uri_encode()])
	var query = "&".join(pairs)
	return GDMusicHashUtils.md5_hex(query + mixin_key)

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
