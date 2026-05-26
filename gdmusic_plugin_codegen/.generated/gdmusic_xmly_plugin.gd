extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicHashUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_hash_utils.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "喜马拉雅"
const AUTHOR := "猫头猫"
const VERSION := "0.1.6"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/xmly/index.js"
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
]
const PAGE_SIZE := 20
const ALBUM_PAGE_SIZE := 50
const ARTIST_PAGE_SIZE := 30
const PLAY_URL_KEY_HEX := "aaad3e4fd540b0f79dca95606e72bf93"

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
	return "high"

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

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var data = await _http.get_json(
		"https://www.ximalaya.com/revision/album/v1/getTracksList",
		{
			"albumId": album_item.get("id", ""),
			"pageNum": page,
			"pageSize": ALBUM_PAGE_SIZE,
		}
	)
	if not (data is Dictionary):
		return {"isEnd": true, "musicList": []}
	var payload: Dictionary = (data as Dictionary).get("data", {})
	var tracks = _ensure_array(payload.get("tracks", []))
	var mapped: Array = []
	for item in tracks:
		if not _paid_music_filter(item):
			continue
		var music = _format_music_item(item)
		music["artwork"] = str(album_item.get("artwork", music.get("artwork", "")))
		music["artist"] = str(album_item.get("artist", music.get("artist", "")))
		mapped.append(music)
	var total = int(payload.get("trackTotalCount", mapped.size()))
	return {
		"isEnd": page * ALBUM_PAGE_SIZE >= total,
		"albumItem": {"worksNum": total},
		"musicList": mapped,
	}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if quality != "standard":
		return {}
	var data = await _http.get_json(
		"https://www.ximalaya.com/mobile-playpage/track/v3/baseInfo/%d" % int(Time.get_ticks_msec()),
		{
			"device": "www",
			"trackId": music_item.get("id", ""),
			"trackQualityLevel": 1,
		}
	)
	if not (data is Dictionary):
		return {}
	var track_info: Dictionary = (data as Dictionary).get("trackInfo", {})
	var urls = _ensure_array(track_info.get("playUrlList", []))
	if urls.is_empty():
		return {}
	var encode_text = str((urls[0] as Dictionary).get("url", ""))
	var url = GDMusicHashUtils.aes_ecb_pkcs7_decrypt_base64url_to_utf8(encode_text, PLAY_URL_KEY_HEX)
	return {"url": url} if not url.is_empty() else {}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type == "music":
		var data = await _http.get_json(
			"https://www.ximalaya.com/revision/user/track",
			{
				"page": page,
				"pageSize": ARTIST_PAGE_SIZE,
				"uid": artist_item.get("id", ""),
			}
		)
		var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
		var tracks = _ensure_array(payload.get("trackList", []))
		var mapped: Array = []
		for item in tracks:
			if _paid_music_filter(item):
				var music = _format_music_item(item)
				music["artist"] = str(artist_item.get("name", music.get("artist", "")))
				mapped.append(music)
		return {
			"isEnd": int(payload.get("page", page)) * int(payload.get("pageSize", ARTIST_PAGE_SIZE)) >= int(payload.get("totalCount", mapped.size())),
			"data": mapped,
		}

	var data = await _http.get_json(
		"https://www.ximalaya.com/revision/user/pub",
		{
			"page": page,
			"pageSize": ARTIST_PAGE_SIZE,
			"uid": artist_item.get("id", ""),
		}
	)
	var payload: Dictionary = (data as Dictionary).get("data", {}) if data is Dictionary else {}
	var albums = _ensure_array(payload.get("albumList", []))
	var mapped: Array = []
	for item in albums:
		if _paid_album_filter(item):
			var album = _format_album_item(item)
			album["artist"] = str(artist_item.get("name", album.get("artist", "")))
			mapped.append(album)
	return {
		"isEnd": int(payload.get("page", page)) * int(payload.get("pageSize", ARTIST_PAGE_SIZE)) >= int(payload.get("totalCount", mapped.size())),
		"data": mapped,
	}

func _search_music(query: String, page: int) -> Dictionary:
	var result = await _search_base(query, page, "track")
	var payload: Dictionary = result.get("data", {}).get("track", {})
	var docs = _ensure_array(payload.get("docs", []))
	var mapped: Array = []
	for item in docs:
		if _paid_music_filter(item):
			mapped.append(_format_music_item(item))
	return {"isEnd": page >= int(payload.get("totalPage", page)), "data": mapped}

func _search_album(query: String, page: int) -> Dictionary:
	var result = await _search_base(query, page, "album")
	var payload: Dictionary = result.get("data", {}).get("album", {})
	var docs = _ensure_array(payload.get("docs", []))
	var mapped: Array = []
	for item in docs:
		if _paid_album_filter(item):
			mapped.append(_format_album_item(item))
	return {"isEnd": page >= int(payload.get("totalPage", page)), "data": mapped}

func _search_artist(query: String, page: int) -> Dictionary:
	var result = await _search_base(query, page, "user")
	var payload: Dictionary = result.get("data", {}).get("user", {})
	var docs = _ensure_array(payload.get("docs", []))
	var mapped: Array = []
	for item in docs:
		mapped.append(_format_artist_item(item))
	return {"isEnd": page >= int(payload.get("totalPage", page)), "data": mapped}

func _search_base(query: String, page: int, core: String) -> Dictionary:
	var data = await _http.get_json(
		"https://www.ximalaya.com/revision/search/main",
		{
			"kw": query,
			"page": page,
			"spellchecker": true,
			"condition": "relation",
			"rows": PAGE_SIZE,
			"device": "iPhone",
			"core": core,
			"paidFilter": true,
		}
	)
	return data if data is Dictionary else {}

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("id", source.get("trackId", "")),
		"artist": str(source.get("nickname", "")),
		"title": str(source.get("title", "")),
		"album": str(source.get("albumTitle", "")),
		"duration": int(source.get("duration", 0)),
		"artwork": GDMusicTextUtils.normalize_protocol_url(source.get("coverPath", "")),
		"platform": PLATFORM,
	}

func _format_album_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("albumId", source.get("id", "")),
		"artist": str(source.get("nickname", "")),
		"title": str(source.get("title", "")),
		"artwork": GDMusicTextUtils.normalize_protocol_url(source.get("coverPath", "")),
		"description": str(source.get("intro", source.get("description", ""))),
		"date": _date_from_msec(source.get("updatedAt", null)),
		"platform": PLATFORM,
	}

func _format_artist_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"name": str(source.get("nickname", "")),
		"id": source.get("uid", ""),
		"fans": source.get("followersCount", 0),
		"description": str(source.get("description", "")),
		"avatar": str(source.get("logoPic", "")),
		"worksNum": source.get("tracksCount", 0),
		"platform": PLATFORM,
	}

func _paid_album_filter(raw: Variant) -> bool:
	var source: Dictionary = raw if raw is Dictionary else {}
	return _ensure_array(source.get("priceTypes", [])).is_empty()

func _paid_music_filter(raw: Variant) -> bool:
	var source: Dictionary = raw if raw is Dictionary else {}
	return int(source.get("tag", 0)) == 0 or bool(source.get("isPaid", false)) == false or float(source.get("price", 0.0)) == 0.0

func _date_from_msec(value: Variant) -> String:
	if value == null:
		return ""
	var timestamp = int(value)
	if timestamp > 100000000000:
		timestamp = int(timestamp / 1000)
	return GDMusicTextUtils.unix_to_date_string(timestamp)

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
