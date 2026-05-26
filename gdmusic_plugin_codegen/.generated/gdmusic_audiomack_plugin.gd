extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicHashUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_hash_utils.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "Audiomack"
const AUTHOR := "猫头猫"
const VERSION := "0.0.2"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/audiomack/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "sheet", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"get_media_source",
	"getMediaSource",
	"get_album_info",
	"getAlbumInfo",
	"get_artist_works",
	"getArtistWorks",
	"get_toplists",
	"getTopLists",
	"get_toplist_detail",
	"getTopListDetail",
]
const API_BASE := "https://api.audiomack.com/v1"
const PAGE_SIZE := 20
const OAUTH_CONSUMER_KEY := "audiomack-js"
const OAUTH_SIGNATURE_METHOD := "HMAC-SHA1"
const OAUTH_VERSION := "1.0"
const OAUTH_SECRET := "f3ac5b086f3eab260520d8e3049561e6"
const HEADERS := {
	"user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
}

var _http := GDMusicHttpJsonClient.new()
var _data_url_base := ""

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
		"sheet":
			return await _search_music_sheet(query, page)
		"artist":
			return await _search_artist(query, page)
		_:
			return {"isEnd": true, "data": []}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	if quality != "standard":
		return {}

	var params = _build_oauth_params()
	params["environment"] = "desktop-web"
	params["hq"] = true
	params["section"] = "/search"
	var partial_path = "/music/play/%s" % str(music_item.get("id", ""))
	params["oauth_signature"] = _get_signature("GET", partial_path, params)

	var data = await _http.get_json(
		"%s%s" % [API_BASE, partial_path],
		params,
		{
			"user-agent": HEADERS["user-agent"],
			"origin": "https://audiomack.com",
		}
	)
	if not (data is Dictionary):
		return {}
	var url = str((data as Dictionary).get("signedUrl", ""))
	if url.is_empty():
		return {}
	return {"url": url}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var music_list = _ensure_array(album_item.get("_musicList", []))
	var cloned: Array = []
	for item in music_list:
		if item is Dictionary:
			cloned.append((item as Dictionary).duplicate(true))
	return {"musicList": cloned}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type != "music" and media_type != "album":
		return {"isEnd": true, "data": []}

	var params = _build_oauth_params()
	params["artist_id"] = artist_item.get("id", "")
	params["limit"] = PAGE_SIZE
	params["page"] = page
	params["sort"] = "rank"
	params["type"] = "songs" if media_type == "music" else "albums"
	params["oauth_signature"] = _get_signature("GET", "/search_artist_content", params)

	var data = await _http.get_json(
		"%s/search_artist_content" % API_BASE,
		params,
		HEADERS
	)
	var results = _ensure_array((data as Dictionary).get("results", []))
	var mapped: Array = []
	for item in results:
		mapped.append(_format_music_item(item) if media_type == "music" else _format_album_item(item))
	return {
		"isEnd": results.size() < PAGE_SIZE,
		"data": mapped,
	}

func get_toplists() -> Array:
	var genres = [
		{"title": "All Genres", "url_slug": null},
		{"title": "Afrosounds", "url_slug": "afrobeats"},
		{"title": "Hip-Hop/Rap", "url_slug": "rap"},
		{"title": "Latin", "url_slug": "latin"},
		{"title": "Caribbean", "url_slug": "caribbean"},
		{"title": "Pop", "url_slug": "pop"},
		{"title": "R&B", "url_slug": "rb"},
		{"title": "Gospel", "url_slug": "gospel"},
		{"title": "Electronic", "url_slug": "electronic"},
		{"title": "Rock", "url_slug": "rock"},
		{"title": "Punjabi", "url_slug": "punjabi"},
		{"title": "Country", "url_slug": "country"},
		{"title": "Instrumental", "url_slug": "instrumental"},
		{"title": "Podcast", "url_slug": "podcast"},
	]
	return [
		{
			"title": "Trending Songs",
			"data": _build_toplist_items(genres, "trending"),
		},
		{
			"title": "Recently Added Music",
			"data": _build_toplist_items(genres, "recent"),
		},
	]

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var page = int(toplist_item.get("page", 1))
	var list_type = str(toplist_item.get("type", "trending"))
	var url_slug = str(toplist_item.get("url_slug", ""))
	var partial_path = "/music/%s%s/page/%d" % [
		("%s/" % url_slug) if not url_slug.is_empty() else "",
		list_type,
		page,
	]

	var params = _build_oauth_params()
	params["type"] = "song"
	params["oauth_signature"] = _get_signature("GET", partial_path, params)

	var data = await _http.get_json(
		"%s%s" % [API_BASE, partial_path],
		params,
		HEADERS
	)
	var results = _ensure_array((data as Dictionary).get("results", []))
	var music_list: Array = []
	for item in results:
		music_list.append(_format_music_item(item))

	var result = toplist_item.duplicate(true)
	result["musicList"] = music_list
	return result

func get_music_sheet_info(sheet: Dictionary, page: int = 1) -> Dictionary:
	var data_url_base = await _get_data_url_base()
	if data_url_base.is_empty():
		return {"isEnd": true, "musicList": []}

	var artist_item: Dictionary = sheet.get("artistItem", {})
	var page_slug = str(artist_item.get("url_slug", ""))
	var playlist_slug = str(sheet.get("url_slug", ""))
	var data = await _http.get_json(
		"%s/%s/playlist/%s.json" % [data_url_base, page_slug, playlist_slug],
		{
			"page_slug": page_slug,
			"playlist_slug": playlist_slug,
			"page": page,
		},
		HEADERS
	)
	var page_props: Dictionary = (data as Dictionary).get("pageProps", {})
	var initial_state: Dictionary = page_props.get("initialState", {})
	var music_page: Dictionary = initial_state.get("musicPage", {})
	var target_key := ""
	for key in music_page.keys():
		if str(key).begins_with("musicMusicPage"):
			target_key = str(key)
			break
	if target_key.is_empty():
		return {"isEnd": true, "musicList": []}
	var tracks = _ensure_array(music_page.get(target_key, {}).get("results", {}).get("tracks", []))
	var music_list: Array = []
	for item in tracks:
		music_list.append(_format_music_item(item))
	return {
		"isEnd": true,
		"musicList": music_list,
	}

func get_recommend_sheet_tags() -> Dictionary:
	var html = await _http.get_text("https://audiomack.com/playlists")
	if html.is_empty():
		return {"data": []}
	var next_data_text = GDMusicTextUtils.extract_next_data_json(html)
	if next_data_text.is_empty():
		return {"data": []}
	var next_data = JSON.parse_string(next_data_text)
	if not (next_data is Dictionary):
		return {"data": []}
	var categories = _ensure_array((next_data as Dictionary).get("props", {}).get("pageProps", {}).get("categories", []))
	return {"data": [{"data": categories}]}

func get_recommend_sheets_by_tag(tag: Dictionary, page: int) -> Dictionary:
	var normalized_tag = tag
	if normalized_tag.get("id", null) == null:
		normalized_tag = {"id": "34", "title": "What's New", "url_slug": "whats-new"}

	var params = _build_oauth_params()
	params["featured"] = "yes"
	params["limit"] = PAGE_SIZE
	params["page"] = page
	params["slug"] = str(normalized_tag.get("url_slug", ""))
	params["oauth_signature"] = _get_signature("GET", "/playlist/categories", params)

	var data = await _http.get_json(
		"%s/playlist/categories" % API_BASE,
		params,
		HEADERS
	)
	var results = _ensure_array((data as Dictionary).get("results", {}).get("playlists", []))
	var mapped: Array = []
	for item in results:
		mapped.append(_format_music_sheet_item(item))
	return {
		"isEnd": results.size() < PAGE_SIZE,
		"data": mapped,
	}

func _search_music(query: String, page: int) -> Dictionary:
	return await _search_base(query, page, "songs", Callable(self, "_format_music_item"))

func _search_album(query: String, page: int) -> Dictionary:
	return await _search_base(query, page, "albums", Callable(self, "_format_album_item"))

func _search_music_sheet(query: String, page: int) -> Dictionary:
	return await _search_base(query, page, "playlists", Callable(self, "_format_music_sheet_item"))

func _search_artist(query: String, page: int) -> Dictionary:
	return await _search_base(query, page, "artists", Callable(self, "_format_artist_item"))

func _search_base(query: String, page: int, show: String, formatter: Callable) -> Dictionary:
	var params = _build_oauth_params()
	params["limit"] = PAGE_SIZE
	params["page"] = page
	params["q"] = query
	params["show"] = show
	params["sort"] = "popular"
	params["oauth_signature"] = _get_signature("GET", "/search", params)

	var data = await _http.get_json(
		"%s/search" % API_BASE,
		params,
		HEADERS
	)
	var results = _ensure_array((data as Dictionary).get("results", []))
	var mapped: Array = []
	for item in results:
		mapped.append(formatter.call(item))
	return {
		"isEnd": results.size() < PAGE_SIZE,
		"data": mapped,
	}

func _build_oauth_params() -> Dictionary:
	return {
		"oauth_consumer_key": OAUTH_CONSUMER_KEY,
		"oauth_nonce": _nonce(32),
		"oauth_signature_method": OAUTH_SIGNATURE_METHOD,
		"oauth_timestamp": int(Time.get_unix_time_from_system()),
		"oauth_version": OAUTH_VERSION,
	}

func _get_signature(method: String, url_path: String, params: Dictionary, secret: String = OAUTH_SECRET) -> String:
	var normalized_url_path = url_path.split("?")[0]
	var full_url = normalized_url_path if normalized_url_path.begins_with("http") else "%s%s" % [API_BASE, normalized_url_path]
	var normalized_params = _get_normalized_params(params)
	var message = "%s&%s&%s" % [
		method.to_upper().uri_encode(),
		full_url.uri_encode(),
		normalized_params.uri_encode(),
	]
	return GDMusicHashUtils.hmac_sha1_base64("%s&" % secret, message)

func _get_normalized_params(parameters: Dictionary) -> String:
	var encoded_keys: Array[String] = []
	for key in parameters.keys():
		encoded_keys.append(str(key).uri_encode())
	encoded_keys.sort()

	var normalized: Array[String] = []
	for encoded_key in encoded_keys:
		var decoded_key = encoded_key.uri_decode()
		var value = parameters.get(decoded_key, "")
		var values: Array = []
		if value is Array:
			values.assign(value)
		else:
			values.append(value)

		var string_values: Array[String] = []
		for item in values:
			string_values.append(str(item))
		string_values.sort()
		for item in string_values:
			normalized.append("%s=%s" % [encoded_key, item.uri_encode()])
	return "&".join(normalized)

func _nonce(length: int = 10) -> String:
	var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var result = ""
	for _index in range(length):
		result += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return result

func _format_music_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"id": source.get("id", ""),
		"artwork": str(source.get("image", source.get("image_base", ""))),
		"duration": int(source.get("duration", 0)),
		"title": str(source.get("title", "")),
		"artist": str(source.get("artist", "")),
		"album": str(source.get("album", "")),
		"url_slug": str(source.get("url_slug", "")),
		"platform": PLATFORM,
	}

func _format_album_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var tracks = _ensure_array(source.get("tracks", []))
	var music_list: Array = []
	for track in tracks:
		var track_item: Dictionary = track
		music_list.append({
			"id": track_item.get("song_id", track_item.get("id", "")),
			"artwork": str(source.get("image", source.get("image_base", ""))),
			"duration": int(track_item.get("duration", 0)),
			"title": str(track_item.get("title", "")),
			"artist": str(track_item.get("artist", "")),
			"album": str(source.get("title", "")),
			"platform": PLATFORM,
		})

	return {
		"artist": str(source.get("artist", "")),
		"artwork": str(source.get("image", source.get("image_base", ""))),
		"id": source.get("id", ""),
		"date": GDMusicTextUtils.unix_to_date_string(int(source.get("released", 0))),
		"title": str(source.get("title", "")),
		"_musicList": music_list,
		"platform": PLATFORM,
	}

func _format_music_sheet_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var artist_item: Dictionary = source.get("artist", {})
	return {
		"worksNum": source.get("track_count", 0),
		"id": source.get("id", ""),
		"title": str(source.get("title", "")),
		"artist": str(artist_item.get("name", "")),
		"artwork": str(source.get("image", source.get("image_base", ""))),
		"artistItem": {
			"id": artist_item.get("id", ""),
			"avatar": str(artist_item.get("image", artist_item.get("image_base", ""))),
			"name": str(artist_item.get("name", "")),
			"url_slug": str(artist_item.get("url_slug", "")),
		},
		"createAt": GDMusicTextUtils.unix_to_date_string(int(source.get("created", 0))),
		"url_slug": str(source.get("url_slug", "")),
		"platform": PLATFORM,
	}

func _format_artist_item(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	return {
		"name": str(source.get("name", "")),
		"id": source.get("id", ""),
		"avatar": str(source.get("image", source.get("image_base", ""))),
		"url_slug": str(source.get("url_slug", "")),
		"platform": PLATFORM,
	}

func _get_data_url_base() -> String:
	if not _data_url_base.is_empty():
		return _data_url_base
	var html = await _http.get_text("https://audiomack.com/")
	if html.is_empty():
		return ""
	var next_data_text = GDMusicTextUtils.extract_next_data_json(html)
	if next_data_text.is_empty():
		return ""
	var next_data = JSON.parse_string(next_data_text)
	if not (next_data is Dictionary):
		return ""
	var build_id = str((next_data as Dictionary).get("buildId", ""))
	if build_id.is_empty():
		return ""
	_data_url_base = "https://audiomack.com/_next/data/%s" % build_id
	return _data_url_base

func _build_toplist_items(genres: Array, list_type: String) -> Array:
	var items: Array = []
	for item in genres:
		var source: Dictionary = item
		items.append({
			"title": str(source.get("title", "")),
			"url_slug": source.get("url_slug", null),
			"type": list_type,
			"id": source.get("url_slug", source.get("title", "")),
			"page": 1,
		})
	return items

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []
