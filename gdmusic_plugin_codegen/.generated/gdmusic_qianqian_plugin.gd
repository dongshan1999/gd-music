extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicHashUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_hash_utils.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "千千音乐"
const AUTHOR := "猫头猫"
const VERSION := "0.1.3"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/qianqian/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "artist"]
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
	"get_toplists",
	"getTopLists",
	"get_toplist_detail",
	"getTopListDetail",
]
const PAGE_SIZE := 20
const SECRET := "0b50b02fd0d73a9c4c8c3a781c30845f"
const APP_ID := "16073360"
const SEARCH_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36",
	"referer": "https://music.91q.com/",
	"from": "web",
	"accept": "application/json, text/plain, */*",
	"accept-encoding": "gzip, deflate, br",
	"accept-language": "zh-CN,zh;q=0.9",
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
		_:
			return {"isEnd": true, "data": []}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type == "music":
		return await _get_artist_music_works(artist_item, page)
	if media_type == "album":
		return await _get_artist_album_works(artist_item, page)
	return {"isEnd": true, "data": []}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var lrc = str(music_item.get("lrc", ""))
	return {"lrc": lrc, "rawLrc": lrc}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	if album_item.has("musicList"):
		return album_item
	var headers = SEARCH_HEADERS.duplicate(true)
	headers["referer"] = "https://music.91q.com/search?word=%s" % str(album_item.get("name", album_item.get("title", ""))).uri_encode()
	var data = await _http.get_json(
		"https://music.91q.com/v1/album/info",
		_get_signed_params({
			"appid": APP_ID,
			"albumAssetCode": album_item.get("id", ""),
		}),
		headers
	)
	var tracks = _ensure_array((data as Dictionary).get("data", {}).get("trackList", [])) if data is Dictionary else []
	var mapped: Array = []
	for item in tracks:
		if _music_can_play_filter(item):
			var music = _format_music_item(item)
			music["artwork"] = str(album_item.get("artwork", music.get("artwork", "")))
			music["album"] = str(album_item.get("name", album_item.get("title", music.get("album", ""))))
			mapped.append(music)
	return {"musicList": mapped}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if quality != "standard":
		return {}
	var artist_items = _ensure_array(music_item.get("artistItems", []))
	var artist_id = ""
	if not artist_items.is_empty() and artist_items[0] is Dictionary:
		artist_id = str((artist_items[0] as Dictionary).get("id", ""))
	var headers = {
		"user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
		"referer": "https://music.91q.com/artist/%s" % artist_id,
		"from": "webapp_music",
		"accept": "application/json, text/plain, */*",
		"accept-encoding": "gzip, deflate, br",
		"accept-language": "zh-CN,zh;q=0.9",
	}
	var data = await _http.get_json(
		"https://music.91q.com/v1/song/tracklink",
		_get_signed_params({
			"appid": APP_ID,
			"TSID": music_item.get("id", ""),
		}),
		headers
	)
	var url = str((data as Dictionary).get("data", {}).get("path", "")) if data is Dictionary else ""
	return {"url": url} if not url.is_empty() else {}

func get_toplists() -> Array:
	var html = await _http.get_text(
		"https://music.91q.com/toplist",
		{},
		{
			"referer": "https://m.baidu.com/",
			"user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
		}
	)
	var page_data = GDMusicTextUtils.extract_first_match(html, "pageData\\s*:\\s*(\\[[\\s\\S]*?\\])\\s*[,}]")
	var items: Array = []
	var item_regex = RegEx.new()
	if item_regex.compile("\\{[\\s\\S]*?bdid\\s*:\\s*[\"']?([^,\"'}]+)[\"']?[\\s\\S]*?title\\s*:\\s*[\"']([^\"']+)[\"'][\\s\\S]*?pic\\s*:\\s*[\"']([^\"']*)[\"'][\\s\\S]*?\\}") == OK:
		for match in item_regex.search_all(page_data):
			items.append({
				"title": GDMusicTextUtils.decode_basic_html_entities(match.get_string(2)),
				"id": match.get_string(1),
				"coverImg": match.get_string(3),
			})
	if items.is_empty():
		var json = JSON.parse_string(page_data)
		if json is Array:
			for item in json:
				if item is Dictionary:
					items.append({
						"title": str((item as Dictionary).get("title", "")),
						"id": (item as Dictionary).get("bdid", ""),
						"coverImg": str((item as Dictionary).get("pic", "")),
					})
	return [{"title": "排行榜", "data": items}]

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var headers = SEARCH_HEADERS.duplicate(true)
	headers["referer"] = "https://music.91q.com/toplist"
	var data = await _http.get_json(
		"https://music.91q.com/v1/bd/list",
		_get_signed_params({
			"bdid": toplist_item.get("id", ""),
			"appid": APP_ID,
		}),
		headers
	)
	var mapped: Array = []
	for item in _ensure_array((data as Dictionary).get("data", {}).get("result", [])) if data is Dictionary else []:
		if _music_can_play_filter(item):
			mapped.append(_format_music_item(item))
	var result = toplist_item.duplicate(true)
	result["musicList"] = mapped
	return result

func _search_music(query: String, page: int) -> Dictionary:
	var res = await _search_base(query, page, 1)
	var payload: Dictionary = res.get("data", {})
	var mapped: Array = []
	for item in _ensure_array(payload.get("typeTrack", [])):
		if _music_can_play_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": int(payload.get("total", mapped.size())) <= page * PAGE_SIZE, "data": mapped}

func _search_album(query: String, page: int) -> Dictionary:
	var res = await _search_base(query, page, 3)
	var payload: Dictionary = res.get("data", {})
	var mapped: Array = []
	for item in _ensure_array(payload.get("typeAlbum", [])):
		mapped.append(_format_album_item(item))
	return {"isEnd": int(payload.get("total", mapped.size())) <= page * PAGE_SIZE, "data": mapped}

func _search_artist(query: String, page: int) -> Dictionary:
	var res = await _search_base(query, page, 2)
	var payload: Dictionary = res.get("data", {})
	var mapped: Array = []
	for item in _ensure_array(payload.get("typeArtist", [])):
		mapped.append(_format_artist_item(item))
	return {"isEnd": int(payload.get("total", mapped.size())) <= page * PAGE_SIZE, "data": mapped}

func _search_base(query: String, page: int, type: int) -> Dictionary:
	var data = await _http.get_json(
		"https://music.91q.com/v1/search",
		_get_signed_params({
			"appid": APP_ID,
			"type": type,
			"word": query,
			"pageNo": page,
			"pageSize": PAGE_SIZE,
		}),
		SEARCH_HEADERS
	)
	return data if data is Dictionary else {}

func _get_artist_music_works(artist_item: Dictionary, page: int) -> Dictionary:
	var headers = SEARCH_HEADERS.duplicate(true)
	headers["referer"] = "https://music.91q.com/search?word=%s" % str(artist_item.get("name", "")).uri_encode()
	var data = await _http.get_json(
		"https://music.91q.com/v1/artist/song",
		_get_signed_params({
			"appid": APP_ID,
			"artistCode": artist_item.get("id", ""),
			"pageNo": page,
			"pageSize": PAGE_SIZE,
		}),
		headers
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("result", [])):
		if _music_can_play_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": int(payload.get("total", mapped.size())) <= page * PAGE_SIZE, "data": mapped}

func _get_artist_album_works(artist_item: Dictionary, page: int) -> Dictionary:
	var headers = SEARCH_HEADERS.duplicate(true)
	headers["referer"] = "https://music.91q.com/search?word=%s" % str(artist_item.get("name", "")).uri_encode()
	var data = await _http.get_json(
		"https://music.91q.com/v1/artist/album",
		_get_signed_params({
			"appid": APP_ID,
			"artistCode": artist_item.get("id", ""),
			"pageNo": page,
			"pageSize": PAGE_SIZE,
		}),
		headers
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var mapped: Array = []
	for item in _ensure_array(payload.get("result", [])):
		mapped.append(_format_album_item(item))
	return {"isEnd": int(payload.get("total", mapped.size())) <= page * PAGE_SIZE, "data": mapped}

func _get_signed_params(params: Dictionary) -> Dictionary:
	var result = params.duplicate(true)
	var timestamp = int(Time.get_unix_time_from_system())
	result["timestamp"] = timestamp
	var keys = result.keys()
	keys.sort()
	var pairs: Array[String] = []
	for key in keys:
		pairs.append("%s=%s" % [str(key), str(result[key])])
	var sign_text = "%s%s" % ["&".join(pairs), SECRET]
	result["sign"] = GDMusicHashUtils.md5_hex(sign_text)
	result["timestamp"] = timestamp
	return result

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var artist_items: Array = []
	var artist_names: Array[String] = []
	for artist in _ensure_array(source.get("artist", [])):
		if artist is Dictionary:
			var mapped = _format_artist_item(artist)
			artist_items.append(mapped)
			artist_names.append(str(mapped.get("name", "")))
	return {
		"id": source.get("id", source.get("assetId", "")),
		"artwork": str(source.get("pic", "")),
		"title": str(source.get("title", "")),
		"artist": "、".join(artist_names),
		"artistItems": artist_items,
		"album": str(source.get("albumTitle", "")),
		"lrc": str(source.get("lyric", "")),
		"platform": PLATFORM,
	}

func _format_album_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var names: Array[String] = []
	for artist in _ensure_array(source.get("artist", [])):
		if artist is Dictionary:
			names.append(str((artist as Dictionary).get("name", "")))
	return {
		"id": source.get("albumAssetCode", ""),
		"artist": "、".join(names),
		"title": str(source.get("title", "")),
		"artwork": str(source.get("pic", "")),
		"description": "",
		"date": _date_string(source.get("releaseDate", null)),
		"platform": PLATFORM,
	}

func _format_artist_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"name": str(source.get("name", "")),
		"id": source.get("artistCode", ""),
		"avatar": str(source.get("pic", "")),
		"worksNum": source.get("trackTotal", 0),
		"description": str(source.get("introduce", "")),
		"platform": PLATFORM,
	}

func _music_can_play_filter(raw: Variant) -> bool:
	var source: Dictionary = raw if raw is Dictionary else {}
	return not bool(source.get("isVip", false))

func _date_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is int or value is float:
		var timestamp = int(value)
		if timestamp > 100000000000:
			timestamp = int(timestamp / 1000)
		return GDMusicTextUtils.unix_to_date_string(timestamp)
	return str(value).substr(0, 10)

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
