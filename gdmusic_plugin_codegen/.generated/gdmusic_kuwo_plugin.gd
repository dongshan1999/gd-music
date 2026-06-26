extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "酷我"
const AUTHOR := "猫头猫"
const VERSION := "0.1.7"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/kuwo/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "sheet", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"get_media_source",
	"getMediaSource",
	"get_lyric",
	"getLyric",
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
	"get_recommend_sheet_tags",
	"getRecommendSheetTags",
	"get_recommend_sheets_by_tag",
	"getRecommendSheetsByTag",
	"get_music_sheet_info",
	"getMusicSheetInfo",
]
const PAGE_SIZE := 30
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
		"artist":
			return await _search_artist(query, page)
		"sheet":
			return await _search_music_sheet(query, page)
		_:
			return {"isEnd": true, "data": []}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type == "music":
		return await _get_artist_music_works(artist_item, page)
	if media_type == "album":
		return await _get_artist_album_works(artist_item, page)
	return {"isEnd": true, "data": []}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var data = await _http.get_json(
		"http://m.kuwo.cn/newh5/singles/songinfoandlrc",
		{
			"musicId": music_item.get("id", ""),
			"httpStatus": 1,
		},
		HEADERS
	)
	var list = _ensure_array((data as Dictionary).get("data", {}).get("lrclist", [])) if data is Dictionary else []
	var lines: Array[String] = []
	for item in list:
		var source: Dictionary = item
		lines.append("[%s]%s" % [str(source.get("time", "")), str(source.get("lineLyric", ""))])
	return {"rawLrc": "\n".join(lines)}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json(
		"http://search.kuwo.cn/r.s",
		_album_params(album_item.get("id", "")),
		HEADERS
	)
	var list = _ensure_array((data as Dictionary).get("musiclist", [])) if data is Dictionary else []
	var mapped: Array = []
	for item in list:
		if _music_list_filter(item):
			var music = _format_music_item(item)
			music["artwork"] = str(album_item.get("artwork", (data as Dictionary).get("img", ""))) if data is Dictionary else str(album_item.get("artwork", ""))
			music["albumId"] = album_item.get("id", music.get("albumId", ""))
			mapped.append(music)
	return {"musicList": mapped}

func get_toplists() -> Array:
	var data = await _http.get_json("http://wapi.kuwo.cn/api/pc/bang/list", {}, HEADERS)
	var groups = _ensure_array((data as Dictionary).get("child", [])) if data is Dictionary else []
	var result: Array = []
	for group in groups:
		var source: Dictionary = group
		var items: Array = []
		for item in _ensure_array(source.get("child", [])):
			var raw: Dictionary = item
			items.append({
				"id": raw.get("sourceid", ""),
				"coverImg": str(raw.get("pic5", raw.get("pic2", raw.get("pic", "")))),
				"title": str(raw.get("name", "")),
				"description": str(raw.get("intro", "")),
			})
		result.append({"title": str(source.get("disname", "")), "data": items})
	return result

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var data = await _http.get_json(
		"http://kbangserver.kuwo.cn/ksong.s",
		{
			"from": "pc",
			"fmt": "json",
			"pn": 0,
			"rn": 80,
			"type": "bang",
			"data": "content",
			"id": toplist_item.get("id", ""),
			"show_copyright_off": 0,
			"pcmp4": 1,
			"isbang": 1,
			"userid": 0,
			"httpStatus": 1,
		},
		HEADERS
	)
	var music_list: Array = []
	for item in _ensure_array((data as Dictionary).get("musiclist", [])) if data is Dictionary else []:
		music_list.append(_format_music_item(item))
	var result = toplist_item.duplicate(true)
	result["musicList"] = music_list
	return result

func import_music_sheet(url_like: String) -> Array:
	var id = _extract_sheet_id(url_like)
	if id.is_empty():
		return []
	var page = 1
	var total_page = 30
	var music_list: Array = []
	while page <= total_page:
		var data = await _get_music_sheet_response_by_id(id, page, 80)
		var total = int(data.get("total", 0))
		total_page = int(ceil(float(total) / 80.0))
		if total_page <= 0:
			total_page = 1
		for item in _ensure_array(data.get("musicList", data.get("musiclist", []))):
			if _music_list_filter(item):
				music_list.append(_format_music_item(item))
		page += 1
	return music_list

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if quality != "standard":
		return {}
	var data = await _http.get_json(
		"https://antiserver.kuwo.cn/anti.s",
		{
			"type": "convert_url3",
			"rid": music_item.get("id", ""),
			"format": "mp3",
		},
		HEADERS
	)
	var url = str((data as Dictionary).get("url", "")) if data is Dictionary else ""
	return {"url": url} if not url.is_empty() else {}

func get_recommend_sheet_tags() -> Dictionary:
	var data = await _http.get_json(
		"http://wapi.kuwo.cn/api/pc/classify/playlist/getTagList",
		{
			"cmd": "rcm_keyword_playlist",
			"user": 0,
			"prod": "kwplayer_pc_9.0.5.0",
			"vipver": "9.0.5.0",
			"source": "kwplayer_pc_9.0.5.0",
			"loginUid": 0,
			"loginSid": 0,
			"appUid": 76039576,
		},
		HEADERS
	)
	var groups = _ensure_array((data as Dictionary).get("data", [])) if data is Dictionary else []
	var mapped: Array = []
	for group in groups:
		var source: Dictionary = group
		var items: Array = []
		for item in _ensure_array(source.get("data", [])):
			var raw: Dictionary = item
			items.append({
				"id": raw.get("id", ""),
				"digest": raw.get("digest", ""),
				"title": str(raw.get("name", "")),
			})
		if not items.is_empty():
			mapped.append({"title": str(source.get("name", "")), "data": items})
	return {
		"data": mapped,
		"pinned": [
			{"id": "1848", "title": "翻唱", "digest": "10000"},
			{"id": "621", "title": "网络", "digest": "10000"},
			{"id": "146", "title": "伤感", "digest": "10000"},
			{"id": "35", "title": "欧美", "digest": "10000"},
		],
	}

func get_recommend_sheets_by_tag(tag: Dictionary, page: int) -> Dictionary:
	var page_size = 20
	var res: Dictionary = {}
	if tag.has("id") and not str(tag.get("id", "")).is_empty():
		if str(tag.get("digest", "")) == "10000":
			var data = await _http.get_json(
				"http://wapi.kuwo.cn/api/pc/classify/playlist/getTagPlayList",
				{
					"loginUid": 0,
					"loginSid": 0,
					"appUid": 76039576,
					"pn": page - 1,
					"id": tag.get("id", ""),
					"rn": page_size,
				},
				HEADERS
			)
			res = (data as Dictionary).get("data", {}) if data is Dictionary else {}
		else:
			var digest_data = await _http.get_json(
				"http://mobileinterfaces.kuwo.cn/er.s",
				{
					"type": "get_pc_qz_data",
					"f": "web",
					"id": tag.get("id", ""),
					"prod": "pc",
				},
				HEADERS
			)
			var flattened: Array = []
			for group in _ensure_array(digest_data):
				if group is Dictionary:
					flattened.append_array(_ensure_array((group as Dictionary).get("list", [])))
			res = {"total": 0, "data": flattened}
	else:
		var data = await _http.get_json(
			"https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList",
			{
				"loginUid": 0,
				"loginSid": 0,
				"appUid": 76039576,
				"pn": page - 1,
				"rn": page_size,
				"order": "hot",
			},
			HEADERS
		)
		res = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var items = _ensure_array(res.get("data", []))
	var mapped: Array = []
	for item in items:
		var source: Dictionary = item
		mapped.append({
			"title": str(source.get("name", "")),
			"artist": str(source.get("uname", "")),
			"id": source.get("id", ""),
			"artwork": str(source.get("img", "")),
			"playCount": source.get("listencnt", 0),
			"createUserId": source.get("uid", ""),
			"platform": PLATFORM,
		})
	return {
		"isEnd": page * page_size >= int(res.get("total", items.size())),
		"data": mapped,
	}

func get_music_sheet_info(sheet: Dictionary, page: int = 1) -> Dictionary:
	var data = await _get_music_sheet_response_by_id(str(sheet.get("id", "")), page, PAGE_SIZE)
	var total = int(data.get("total", 0))
	var mapped: Array = []
	for item in _ensure_array(data.get("musiclist", data.get("musicList", []))):
		if _music_list_filter(item):
			mapped.append(_format_music_item(item))
	return {
		"isEnd": page * PAGE_SIZE >= total,
		"musicList": mapped,
	}

func _search_music(query: String, page: int) -> Dictionary:
	var data = await _search_base(query, page, "music")
	var items = _ensure_array(data.get("abslist", []))
	var mapped: Array = []
	for item in items:
		if _music_list_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": (int(data.get("PN", page - 1)) + 1) * int(data.get("RN", PAGE_SIZE)) >= int(data.get("TOTAL", mapped.size())), "data": mapped}

func _search_album(query: String, page: int) -> Dictionary:
	var data = await _search_base(query, page, "album")
	var items = _ensure_array(data.get("albumlist", []))
	var mapped: Array = []
	for item in items:
		mapped.append(_format_album_item(item))
	return {"isEnd": (int(data.get("PN", page - 1)) + 1) * int(data.get("RN", PAGE_SIZE)) >= int(data.get("TOTAL", mapped.size())), "data": mapped}

func _search_artist(query: String, page: int) -> Dictionary:
	var data = await _search_base(query, page, "artist")
	var mapped: Array = []
	for item in _ensure_array(data.get("abslist", [])):
		mapped.append(_format_artist_item(item))
	return {"isEnd": (int(data.get("PN", page - 1)) + 1) * int(data.get("RN", PAGE_SIZE)) >= int(data.get("TOTAL", mapped.size())), "data": mapped}

func _search_music_sheet(query: String, page: int) -> Dictionary:
	var data = await _search_base(query, page, "playlist")
	var mapped: Array = []
	for item in _ensure_array(data.get("abslist", [])):
		mapped.append(_format_music_sheet(item))
	return {"isEnd": (int(data.get("PN", page - 1)) + 1) * int(data.get("RN", PAGE_SIZE)) >= int(data.get("TOTAL", mapped.size())), "data": mapped}

func _search_base(query: String, page: int, ft: String) -> Dictionary:
	var data = await _http.get_json(
		"http://search.kuwo.cn/r.s",
		{
			"all": query,
			"ft": ft,
			"itemset": "web_2013",
			"client": "kt",
			"pn": page - 1,
			"rn": PAGE_SIZE,
			"rformat": "json",
			"encoding": "utf8",
			"pcjson": 1,
		},
		HEADERS
	)
	return data if data is Dictionary else {}

func _get_artist_music_works(artist_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json("http://search.kuwo.cn/r.s", _artist_params(artist_item.get("id", ""), page, "artist2music", 0), HEADERS)
	var mapped: Array = []
	for item in _ensure_array((data as Dictionary).get("musiclist", [])) if data is Dictionary else []:
		if _music_list_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": (int((data as Dictionary).get("pn", page - 1)) + 1) * PAGE_SIZE >= int((data as Dictionary).get("total", mapped.size())) if data is Dictionary else true, "data": mapped}

func _get_artist_album_works(artist_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json("http://search.kuwo.cn/r.s", _artist_params(artist_item.get("id", ""), page, "albumlist", 1), HEADERS)
	var mapped: Array = []
	for item in _ensure_array((data as Dictionary).get("albumlist", [])) if data is Dictionary else []:
		mapped.append(_format_album_item(item))
	return {"isEnd": (int((data as Dictionary).get("pn", page - 1)) + 1) * PAGE_SIZE >= int((data as Dictionary).get("total", mapped.size())) if data is Dictionary else true, "data": mapped}

func _get_music_sheet_response_by_id(id: String, page: int, pagesize: int = 50) -> Dictionary:
	var data = await _http.get_json(
		"http://nplserver.kuwo.cn/pl.svc",
		{
			"op": "getlistinfo",
			"pid": id,
			"pn": page - 1,
			"rn": pagesize,
			"encode": "utf8",
			"keyset": "pl2012",
			"vipver": "MUSIC_9.1.1.2_BCS2",
			"newver": 1,
		},
		HEADERS
	)
	return data if data is Dictionary else {}

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var id = str(source.get("MUSICRID", source.get("musicrid", source.get("id", "")))).replace("MUSIC_", "")
	return {
		"id": id,
		"artwork": _artwork_short_to_long(source.get("web_albumpic_short", "")),
		"title": GDMusicTextUtils.decode_basic_html_entities(str(source.get("NAME", source.get("name", "")))),
		"artist": GDMusicTextUtils.decode_basic_html_entities(str(source.get("ARTIST", source.get("artist", "")))),
		"album": GDMusicTextUtils.decode_basic_html_entities(str(source.get("ALBUM", source.get("album", "")))),
		"albumId": source.get("ALBUMID", source.get("albumid", "")),
		"artistId": source.get("ARTISTID", source.get("artistid", "")),
		"formats": source.get("FORMATS", source.get("formats", "")),
		"platform": PLATFORM,
	}

func _format_album_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("albumid", ""),
		"artist": GDMusicTextUtils.decode_basic_html_entities(str(source.get("artist", ""))),
		"title": GDMusicTextUtils.decode_basic_html_entities(str(source.get("name", ""))),
		"artwork": str(source.get("img", _artwork_short_to_long(source.get("pic", "")))),
		"description": GDMusicTextUtils.decode_basic_html_entities(str(source.get("info", ""))),
		"date": source.get("pub", ""),
		"artistId": source.get("artistid", ""),
		"platform": PLATFORM,
	}

func _format_artist_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("ARTISTID", ""),
		"avatar": str(source.get("hts_PICPATH", "")),
		"name": GDMusicTextUtils.decode_basic_html_entities(str(source.get("ARTIST", ""))),
		"artistId": source.get("ARTISTID", ""),
		"description": GDMusicTextUtils.decode_basic_html_entities(str(source.get("desc", ""))),
		"worksNum": source.get("SONGNUM", 0),
		"platform": PLATFORM,
	}

func _format_music_sheet(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("playlistid", ""),
		"title": GDMusicTextUtils.decode_basic_html_entities(str(source.get("name", ""))),
		"artist": GDMusicTextUtils.decode_basic_html_entities(str(source.get("nickname", ""))),
		"artwork": str(source.get("pic", "")),
		"playCount": source.get("playcnt", 0),
		"description": GDMusicTextUtils.decode_basic_html_entities(str(source.get("intro", ""))),
		"worksNum": source.get("songnum", 0),
		"platform": PLATFORM,
	}

func _artwork_short_to_long(albumpic_short: Variant) -> String:
	var text = str(albumpic_short)
	var slash = text.find("/")
	if slash == -1:
		return ""
	return "https://img4.kuwo.cn/star/albumcover/256%s" % text.substr(slash)

func _music_list_filter(raw: Variant) -> bool:
	var source: Dictionary = raw if raw is Dictionary else {}
	var pay_info: Dictionary = source.get("payInfo", {})
	return str(pay_info.get("listen_fragment", "")) != "1"

func _artist_params(artist_id: Variant, page: int, stype: String, sortby: int) -> Dictionary:
	return {
		"pn": page - 1,
		"rn": PAGE_SIZE,
		"artistid": artist_id,
		"stype": stype,
		"sortby": sortby,
		"alflac": 1,
		"show_copyright_off": 1,
		"pcmp4": 1,
		"encoding": "utf8",
		"plat": "pc",
		"thost": "search.kuwo.cn",
		"vipver": "MUSIC_9.1.1.2_BCS2",
		"devid": "38668888",
		"newver": 1,
		"pcjson": 1,
	}

func _album_params(album_id: Variant) -> Dictionary:
	var params = _artist_params("", 1, "albuminfo", 0)
	params.erase("artistid")
	params["albumid"] = album_id
	params["pn"] = 0
	params["rn"] = 100
	return params

func _extract_sheet_id(url_like: String) -> String:
	var patterns = [
		"https?://www\\.kuwo\\.cn/playlist_detail/(\\d+)",
		"https?://m\\.kuwo\\.cn/h5app/playlist/(\\d+)",
		"^\\s*(\\d+)\\s*$",
	]
	for pattern in patterns:
		var id = GDMusicTextUtils.extract_first_match(url_like, pattern)
		if not id.is_empty():
			return id
	return ""

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
