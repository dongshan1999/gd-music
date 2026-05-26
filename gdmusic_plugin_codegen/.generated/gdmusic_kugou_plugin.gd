extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "酷狗"
const AUTHOR := "猫头猫"
const VERSION := "0.1.5"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/kugou/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "sheet"]
const SUPPORTED_METHODS := [
	"search",
	"get_media_source",
	"getMediaSource",
	"get_lyric",
	"getLyric",
	"get_album_info",
	"getAlbumInfo",
	"import_music_sheet",
	"importMusicSheet",
	"get_toplists",
	"getTopLists",
	"get_toplist_detail",
	"getTopListDetail",
]
const PAGE_SIZE := 20
const HEADERS := {
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36",
	"Accept": "*/*",
	"Accept-Encoding": "gzip, deflate",
	"Accept-Language": "zh-CN,zh;q=0.9",
}

var _http := GDMusicHttpJsonClient.new()

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
			return await _search_music(query, page)
		"album":
			return await _search_album(query, page)
		"sheet":
			return await _search_music_sheet(query, page)
		_:
			return {"isEnd": true, "data": []}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	var hash = _hash_for_quality(music_item, quality)
	if hash.is_empty():
		return {}
	var data = await _http.get_json(
		"https://wwwapi.kugou.com/yy/index.php",
		{
			"r": "play/getdata",
			"hash": hash,
			"appid": "1014",
			"mid": "56bbbd2918b95d6975f420f96c5c29bb",
			"album_id": music_item.get("album_id", ""),
			"album_audio_id": music_item.get("album_audio_id", ""),
			"_": Time.get_ticks_msec(),
		},
		HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var url = str(payload.get("play_url", payload.get("play_backup_url", "")))
	if url.is_empty():
		return {}
	return {
		"url": url,
		"rawLrc": str(payload.get("lyrics", "")),
		"artwork": str(payload.get("img", "")),
	}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var source = await get_media_source(music_item, "low")
	var raw_lrc = str(source.get("rawLrc", ""))
	return {"rawLrc": raw_lrc} if not raw_lrc.is_empty() else {}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://mobilecdn.kugou.com/api/v3/album/song",
		{
			"version": 9108,
			"albumid": album_item.get("id", ""),
			"plat": 0,
			"pagesize": 100,
			"area_code": 1,
			"page": page,
			"with_res_tag": 0,
		},
		HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("info", [])):
		if not _valid_music_filter(item):
			continue
		var source: Dictionary = item
		var filename = str(source.get("filename", ""))
		var artist = ""
		var title = filename
		var parts = filename.split("-", false, 1)
		if parts.size() >= 2:
			artist = parts[0].strip_edges()
			title = parts[1].strip_edges()
		mapped.append({
			"id": source.get("hash", ""),
			"title": title,
			"artist": artist,
			"album": str(source.get("album_name", source.get("remark", ""))),
			"album_id": source.get("album_id", ""),
			"album_audio_id": source.get("album_audio_id", ""),
			"artwork": str(album_item.get("artwork", "")),
			"320hash": source.get("320hash", ""),
			"sqhash": source.get("sqhash", ""),
			"origin_hash": source.get("origin_hash", ""),
			"platform": PLATFORM,
		})
	return {
		"isEnd": page * 100 >= int(payload.get("total", mapped.size())),
		"albumItem": {"worksNum": payload.get("total", mapped.size())},
		"musicList": mapped,
	}

func get_toplists() -> Array:
	var data = await _http.get_json(
		"http://mobilecdnbj.kugou.com/api/v3/rank/list",
		{
			"version": 9108,
			"plat": 0,
			"showtype": 2,
			"parentid": 0,
			"apiver": 6,
			"area_code": 1,
			"withsong": 0,
			"with_res_tag": 0,
		},
		HEADERS
	)
	var lists = _ensure_array((data as Dictionary).get("data", {}).get("info", [])) if data is Dictionary else []
	var result := [
		{"title": "热门榜单", "data": []},
		{"title": "特色音乐榜", "data": []},
		{"title": "全球榜", "data": []},
	]
	var extra := {"title": "其他", "data": []}
	for item in lists:
		var source: Dictionary = item
		var mapped = {
			"id": source.get("rankid", ""),
			"description": str(source.get("intro", "")),
			"coverImg": str(source.get("imgurl", "")).replace("{size}", "400"),
			"title": str(source.get("rankname", "")),
		}
		var classify = int(source.get("classify", 0))
		if classify == 1 or classify == 2:
			result[0]["data"].append(mapped)
		elif classify == 3 or classify == 5:
			result[1]["data"].append(mapped)
		elif classify == 4:
			result[2]["data"].append(mapped)
		else:
			extra["data"].append(mapped)
	if not (extra["data"] as Array).is_empty():
		result.append(extra)
	return result

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var data = await _http.get_json(
		"http://mobilecdnbj.kugou.com/api/v3/rank/song",
		{
			"version": 9108,
			"ranktype": 0,
			"plat": 0,
			"pagesize": 100,
			"area_code": 1,
			"page": 1,
			"volid": 35050,
			"rankid": toplist_item.get("id", ""),
			"with_res_tag": 0,
		},
		HEADERS
	)
	var items = _ensure_array((data as Dictionary).get("data", {}).get("info", [])) if data is Dictionary else []
	var music_list: Array = []
	for item in items:
		music_list.append(_format_music_item(item))
	var result = toplist_item.duplicate(true)
	result["musicList"] = music_list
	return result

func import_music_sheet(url_like: String) -> Array:
	var id = GDMusicTextUtils.extract_first_match(url_like, "^(?:.*?)(\\d+)(?:.*?)$")
	if id.is_empty():
		return []
	var command_data = await _http.request_json(
		"http://t.kugou.com/command/",
		{},
		{"Content-Type": "application/json"},
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"appid": 1001,
			"clientver": 9020,
			"mid": "21511157a05844bd085308bc76ef3343",
			"clienttime": 640612895,
			"key": "36164c4015e704673c588ee202b9ecb8",
			"data": id,
		})
	)
	if not (command_data is Dictionary) or int((command_data as Dictionary).get("status", 0)) != 1:
		return []
	var info: Dictionary = (command_data as Dictionary).get("data", {}).get("info", {})
	var response = await _http.request_json(
		"http://www2.kugou.kugou.com/apps/kucodeAndShare/app/",
		{},
		{"Content-Type": "application/json"},
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"appid": 1001,
			"clientver": 10112,
			"mid": "70a02aad1ce4648e7dca77f2afa7b182",
			"clienttime": 722219501,
			"key": "381d7062030e8a5a94cfbe50bfe65433",
			"data": {
				"id": info.get("id", ""),
				"type": 3,
				"userid": info.get("userid", ""),
				"collect_type": info.get("collect_type", ""),
				"page": 1,
				"pagesize": info.get("count", 0),
			},
		})
	)
	if not (response is Dictionary) or int((response as Dictionary).get("status", 0)) != 1:
		return []
	var resource: Array = []
	for song in _ensure_array((response as Dictionary).get("data", [])):
		var source: Dictionary = song
		resource.append({
			"album_audio_id": 0,
			"album_id": "0",
			"hash": source.get("hash", ""),
			"id": 0,
			"name": str(source.get("filename", "")).replace(".mp3", ""),
			"page_id": 0,
			"type": "audio",
		})
	var result = await _http.request_json(
		"https://gateway.kugou.com/v2/get_res_privilege/lite?appid=1001&clienttime=1668883879&clientver=10112&dfid=2O3jKa20Gdks0LWojP3ly7ck&mid=70a02aad1ce4648e7dca77f2afa7b182&userid=390523108&uuid=92691C6246F86F28B149BAA1FD370DF1",
		{},
		{
			"Content-Type": "application/json",
			"x-router": "media.store.kugou.com",
		},
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"appid": 1001,
			"area_code": "1",
			"behavior": "play",
			"clientver": "10112",
			"dfid": "2O3jKa20Gdks0LWojP3ly7ck",
			"mid": "70a02aad1ce4648e7dca77f2afa7b182",
			"need_hash_offset": 1,
			"relate": 1,
			"resource": resource,
			"token": "",
			"userid": "0",
			"vip": 0,
		})
	)
	var mapped: Array = []
	for item in _ensure_array((result as Dictionary).get("data", [])) if result is Dictionary else []:
		if _valid_music_filter(item):
			mapped.append(_format_import_music_item(item))
	return mapped

func _search_music(query: String, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://mobilecdn.kugou.com/api/v3/search/song",
		{
			"format": "json",
			"keyword": query,
			"page": page,
			"pagesize": PAGE_SIZE,
			"showtype": 1,
		},
		HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("info", [])):
		if _valid_music_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": page * PAGE_SIZE >= int(payload.get("total", mapped.size())), "data": mapped}

func _search_album(query: String, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://msearch.kugou.com/api/v3/search/album",
		{
			"version": 9108,
			"iscorrection": 1,
			"highlight": "em",
			"plat": 0,
			"keyword": query,
			"pagesize": 20,
			"page": page,
			"sver": 2,
			"with_res_tag": 0,
		},
		HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("info", [])):
		var source: Dictionary = item
		mapped.append({
			"id": source.get("albumid", ""),
			"artwork": str(source.get("imgurl", "")).replace("{size}", "400"),
			"artist": str(source.get("singername", "")),
			"title": GDMusicTextUtils.clean_html_text(str(source.get("albumname", ""))),
			"description": str(source.get("intro", "")),
			"date": str(source.get("publishtime", "")).substr(0, 10),
			"platform": PLATFORM,
		})
	return {"isEnd": page * 20 >= int(payload.get("total", mapped.size())), "data": mapped}

func _search_music_sheet(query: String, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://mobilecdn.kugou.com/api/v3/search/special",
		{
			"format": "json",
			"keyword": query,
			"page": page,
			"pagesize": PAGE_SIZE,
			"showtype": 1,
		},
		HEADERS
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("info", [])):
		var source: Dictionary = item
		mapped.append({
			"title": str(source.get("specialname", "")),
			"createAt": source.get("publishtime", ""),
			"description": str(source.get("intro", "")),
			"artist": str(source.get("nickname", "")),
			"coverImg": str(source.get("imgurl", "")),
			"gid": source.get("gid", ""),
			"playCount": source.get("playcount", 0),
			"id": source.get("specialid", ""),
			"worksNum": source.get("songcount", 0),
			"platform": PLATFORM,
		})
	return {"isEnd": page * PAGE_SIZE >= int(payload.get("total", mapped.size())), "data": mapped}

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var artist = source.get("singername", null)
	if artist == null:
		var authors = _ensure_array(source.get("authors", []))
		var names: Array[String] = []
		for author in authors:
			if author is Dictionary:
				names.append(str((author as Dictionary).get("author_name", "")))
		artist = ", ".join(names)
	if str(artist).is_empty():
		artist = str(source.get("filename", "")).split("-")[0].strip_edges()
	return {
		"id": source.get("hash", ""),
		"title": str(source.get("songname", "")),
		"artist": str(artist),
		"album": str(source.get("album_name", source.get("remark", ""))),
		"album_id": source.get("album_id", ""),
		"album_audio_id": source.get("album_audio_id", ""),
		"artwork": str(source.get("album_sizable_cover", "")).replace("{size}", "400"),
		"320hash": source.get("320hash", ""),
		"sqhash": source.get("sqhash", ""),
		"origin_hash": source.get("origin_hash", ""),
		"platform": PLATFORM,
	}

func _format_import_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var title = str(source.get("name", ""))
	var singer_name = str(source.get("singername", ""))
	if not singer_name.is_empty() and not title.is_empty():
		var index = title.find(singer_name)
		if index != -1:
			title = title.substr(index + singer_name.length() + 2).strip_edges()
		if title.is_empty():
			title = singer_name
	var qualities = _ensure_array(source.get("relate_goods", []))
	var info: Dictionary = source.get("info", {})
	var image: Dictionary = info.get("image", {})
	return {
		"id": source.get("hash", ""),
		"title": title,
		"artist": singer_name,
		"album": str(source.get("albumname", "")),
		"album_id": source.get("album_id", ""),
		"album_audio_id": source.get("album_audio_id", ""),
		"artwork": str(image).replace("{size}", "400"),
		"320hash": (qualities[1] as Dictionary).get("hash", "") if qualities.size() > 1 and qualities[1] is Dictionary else "",
		"sqhash": (qualities[2] as Dictionary).get("hash", "") if qualities.size() > 2 and qualities[2] is Dictionary else "",
		"origin_hash": (qualities[3] as Dictionary).get("hash", "") if qualities.size() > 3 and qualities[3] is Dictionary else "",
		"platform": PLATFORM,
	}

func _hash_for_quality(music_item: Dictionary, quality: String) -> String:
	match quality:
		"low":
			return str(music_item.get("id", ""))
		"standard":
			return str(music_item.get("320hash", ""))
		"high":
			return str(music_item.get("sqhash", ""))
		_:
			return str(music_item.get("origin_hash", ""))

func _valid_music_filter(raw: Variant) -> bool:
	var source: Dictionary = raw if raw is Dictionary else {}
	var privilege = int(source.get("privilege", 0))
	return privilege == 0 or privilege == 8

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
