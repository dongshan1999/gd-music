extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicHashUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_hash_utils.gd")

const PLATFORM := "Airsonic Advanced"
const AUTHOR := "JumuFeng"
const DESCRIPTION := "支持 Airsonic Advanced 服务器，自动检测服务器版本和兼容性"
const VERSION := "0.1.0"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/airsonic/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music", "album", "artist"]
const SUPPORTED_METHODS := [
	"search",
	"getMediaSource",
	"getLyric",
	"getAlbumInfo",
	"getArtistWorks",
	"getTopLists",
	"getTopListDetail",
]
const USER_VARIABLES := [
	{"key": "url", "name": "服务器地址", "type": ""},
	{"key": "username", "name": "用户名", "type": ""},
	{"key": "password", "name": "密码", "type": ""},
]
const PAGE_SIZE := 25
const CLIENT_NAME := "GDMusic"
const DEFAULT_API_VERSION := "1.16.1"

var _http := GDMusicHttpJsonClient.new()
var _cached_server_info: Dictionary = {}
var _last_config_hash := ""

func get_platform() -> String:
	return PLATFORM

func get_author() -> String:
	return AUTHOR

func get_description() -> String:
	return DESCRIPTION

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

func get_user_variables() -> Array[Dictionary]:
	return USER_VARIABLES

func get_migration_difficulty() -> String:
	return "high"

func search(query: String, page: int, media_type: String) -> Dictionary:
	if media_type == "music":
		return await _search_music(query, page)
	if media_type == "album":
		return await _search_album(query, page)
	if media_type == "artist":
		return await _search_artist(query, page)
	return {"isEnd": true, "data": []}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	var data = await _http_get("getAlbum", {"id": album_item.get("id", "")})
	var response := _get_subsonic_response(data)
	var album: Dictionary = response.get("album", {})
	var songs := _ensure_array(album.get("song", []))
	var mapped: Array = []
	for song in songs:
		mapped.append(_format_music_item(song))
	return {
		"isEnd": true,
		"data": mapped,
	}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	if media_type == "album":
		var data = await _http_get("getArtist", {"id": artist_item.get("id", "")})
		var response := _get_subsonic_response(data)
		var artist: Dictionary = response.get("artist", {})
		var albums := _ensure_array(artist.get("album", []))
		var mapped: Array = []
		for album in albums:
			mapped.append(_format_album_item(album))
		return {
			"isEnd": true,
			"data": mapped,
		}

	if media_type == "music":
		var artist_data = await _http_get("getArtist", {"id": artist_item.get("id", "")})
		var artist_response := _get_subsonic_response(artist_data)
		var artist: Dictionary = artist_response.get("artist", {})
		var albums := _ensure_array(artist.get("album", []))
		var all_songs: Array = []
		for album in albums:
			var album_data = await _http_get("getAlbum", {"id": (album as Dictionary).get("id", "")})
			var album_response := _get_subsonic_response(album_data)
			var full_album: Dictionary = album_response.get("album", {})
			var songs := _ensure_array(full_album.get("song", []))
			for song in songs:
				all_songs.append(_format_music_item(song))
		return {
			"isEnd": true,
			"data": all_songs,
		}

	return {"isEnd": true, "data": []}

func get_toplists() -> Array:
	var groups: Array = []
	groups.append(await _build_toplist_group("最新专辑", "newest"))
	groups.append(await _build_toplist_group("最近播放", "recent"))
	groups.append(await _build_toplist_group("随机专辑", "random"))
	return groups

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	var album_info = await get_album_info({"id": toplist_item.get("id", "")}, 1)
	var result := toplist_item.duplicate(true)
	result["musicList"] = album_info.get("data", [])
	return result

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	var config := _get_config()
	if config.is_empty():
		return {}

	var server_info = await _ensure_server_info()
	if server_info.is_empty():
		return {}

	var query := _build_auth_params(config, str(server_info.get("authMethod", "password")), str(server_info.get("version", DEFAULT_API_VERSION)))
	query["id"] = str(music_item.get("id", ""))
	query["c"] = CLIENT_NAME
	query["f"] = "json"

	return {"url": _http.build_url("%s/rest/stream" % config["url"], query)}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var data = await _http_get("getLyrics", {
		"artist": str(music_item.get("artist", "")),
		"title": str(music_item.get("title", "")),
	})
	var response := _get_subsonic_response(data)
	var lyrics = response.get("lyrics", null)
	if lyrics is Dictionary:
		return {"rawLrc": str((lyrics as Dictionary).get("value", ""))}
	if lyrics is Array and not lyrics.is_empty():
		var first_lyric = lyrics[0]
		if first_lyric is Dictionary:
			return {"rawLrc": str((first_lyric as Dictionary).get("value", ""))}
	return {}

func get_server_status() -> Dictionary:
	var server_info = await _ensure_server_info()
	if server_info.is_empty():
		return {
			"connected": false,
			"error": "无法连接到服务器",
		}
	return server_info.duplicate(true)

func _search_music(query: String, page: int) -> Dictionary:
	return await _search_with_type(query, page, "song", "songCount", "songOffset", Callable(self, "_format_music_item"))

func _search_album(query: String, page: int) -> Dictionary:
	return await _search_with_type(query, page, "album", "albumCount", "albumOffset", Callable(self, "_format_album_item"))

func _search_artist(query: String, page: int) -> Dictionary:
	return await _search_with_type(query, page, "artist", "artistCount", "artistOffset", Callable(self, "_format_artist_item"))

func _search_with_type(
	query: String,
	page: int,
	result_key: String,
	count_key: String,
	offset_key: String,
	formatter: Callable
) -> Dictionary:
	var server_info = await _ensure_server_info()
	if server_info.is_empty():
		return {"isEnd": true, "data": []}

	var use_search3 := _is_version_at_least(str(server_info.get("version", DEFAULT_API_VERSION)), "1.4.0")
	var endpoint := "search3" if use_search3 else "search2"
	var data = await _http_get(endpoint, {
		"query": query,
		count_key: PAGE_SIZE,
		offset_key: (max(page, 1) - 1) * PAGE_SIZE,
	})
	var response := _get_subsonic_response(data)
	var result_field := "searchResult3" if use_search3 else "searchResult2"
	var search_result: Dictionary = response.get(result_field, {})
	var entries := _ensure_array((search_result as Dictionary).get(result_key, []))
	var mapped: Array = []
	for entry in entries:
		mapped.append(formatter.call(entry))
	return {
		"isEnd": entries.size() < PAGE_SIZE,
		"data": mapped,
	}

func _build_toplist_group(title: String, list_type: String) -> Dictionary:
	var data = await _http_get("getAlbumList2", {"type": list_type, "size": 20})
	var response := _get_subsonic_response(data)
	var album_list: Dictionary = response.get("albumList2", {})
	var albums := _ensure_array(album_list.get("album", []))
	var items: Array = []
	for album in albums:
		var item: Dictionary = album
		items.append({
			"id": str(item.get("id", "")),
			"title": str(item.get("name", "")),
			"coverImg": str(item.get("coverArt", "")),
			"description": "%s - %s 首歌曲" % [
				str(item.get("artist", "")),
				str(item.get("songCount", 0)),
			],
		})
	return {
		"title": title,
		"data": items,
	}

func _ensure_server_info() -> Dictionary:
	var config := _get_config()
	if config.is_empty():
		_cached_server_info = {}
		_last_config_hash = ""
		return {}

	var config_hash := GDMusicHashUtils.md5_hex("%s:%s:%s" % [config["url"], config["username"], config["password"]])
	if config_hash == _last_config_hash and not _cached_server_info.is_empty():
		return _cached_server_info

	var token_result = await _ping_server(config, "token")
	if bool(token_result.get("connected", false)):
		_cached_server_info = token_result
		_last_config_hash = config_hash
		return _cached_server_info

	var password_result = await _ping_server(config, "password")
	if bool(password_result.get("connected", false)):
		_cached_server_info = password_result
		_last_config_hash = config_hash
		return _cached_server_info

	_cached_server_info = {}
	_last_config_hash = config_hash
	return {}

func _ping_server(config: Dictionary, auth_method: String) -> Dictionary:
	var params := _build_auth_params(config, auth_method, DEFAULT_API_VERSION)
	params["c"] = CLIENT_NAME
	params["f"] = "json"
	var data = await _http.get_json("%s/rest/ping" % config["url"], params, {}, 10.0)
	var response := _get_subsonic_response(data)
	if str(response.get("status", "")) != "ok":
		return {}

	return {
		"connected": true,
		"version": str(response.get("version", DEFAULT_API_VERSION)),
		"type": str(response.get("type", "airsonic")),
		"serverVersion": str(response.get("version", DEFAULT_API_VERSION)),
		"openSubsonic": bool(response.get("openSubsonic", false)),
		"authMethod": auth_method,
	}

func _http_get(url_path: String, params: Dictionary = {}) -> Variant:
	var config := _get_config()
	if config.is_empty():
		return null

	var server_info = await _ensure_server_info()
	if server_info.is_empty():
		return null

	var query := _build_auth_params(config, str(server_info.get("authMethod", "password")), str(server_info.get("version", DEFAULT_API_VERSION)))
	query["c"] = CLIENT_NAME
	query["f"] = "json"
	for key in params.keys():
		query[key] = params[key]

	return await _http.get_json("%s/rest/%s" % [config["url"], url_path], query)

func _build_auth_params(config: Dictionary, auth_method: String, version: String) -> Dictionary:
	var params := {
		"u": str(config.get("username", "")),
		"v": version,
	}
	if auth_method == "token":
		var salt := GDMusicHashUtils.random_hex(12)
		params["s"] = salt
		params["t"] = GDMusicHashUtils.md5_hex("%s%s" % [str(config.get("password", "")), salt])
	else:
		params["p"] = str(config.get("password", ""))
	return params

func _get_config() -> Dictionary:
	var raw_url := str(get_runtime_user_variable("url", "")).strip_edges()
	var username := str(get_runtime_user_variable("username", "")).strip_edges()
	var password := str(get_runtime_user_variable("password", "")).strip_edges()
	if raw_url.is_empty() or username.is_empty() or password.is_empty():
		return {}

	var normalized_url := raw_url
	if not normalized_url.begins_with("http://") and not normalized_url.begins_with("https://"):
		normalized_url = "http://%s" % normalized_url
	normalized_url = normalized_url.trim_suffix("/")

	return {
		"url": normalized_url,
		"username": username,
		"password": password,
	}

func _get_subsonic_response(data: Variant) -> Dictionary:
	if data is Dictionary:
		return (data as Dictionary).get("subsonic-response", {})
	return {}

func _ensure_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary:
		return [value]
	return []

func _format_music_item(item: Variant) -> Dictionary:
	var source: Dictionary = item if item is Dictionary else {}
	return {
		"id": str(source.get("id", "")),
		"title": str(source.get("title", "")),
		"artist": str(source.get("artist", "")),
		"album": str(source.get("album", "")),
		"duration": source.get("duration", 0),
		"artwork": str(source.get("coverArt", "")),
		"albumId": str(source.get("albumId", "")),
		"artistId": str(source.get("artistId", "")),
		"track": source.get("track", 0),
		"year": source.get("year", 0),
		"genre": str(source.get("genre", "")),
		"bitRate": source.get("bitRate", 0),
		"size": source.get("size", 0),
		"suffix": str(source.get("suffix", "")),
		"contentType": str(source.get("contentType", "")),
		"path": str(source.get("path", "")),
		"platform": PLATFORM,
	}

func _format_album_item(item: Variant) -> Dictionary:
	var source: Dictionary = item if item is Dictionary else {}
	return {
		"id": str(source.get("id", "")),
		"title": str(source.get("name", source.get("title", ""))),
		"artist": str(source.get("artist", "")),
		"artwork": str(source.get("coverArt", "")),
		"artistId": str(source.get("artistId", "")),
		"songCount": source.get("songCount", 0),
		"duration": source.get("duration", 0),
		"created": str(source.get("created", "")),
		"year": source.get("year", 0),
		"genre": str(source.get("genre", "")),
		"platform": PLATFORM,
	}

func _format_artist_item(item: Variant) -> Dictionary:
	var source: Dictionary = item if item is Dictionary else {}
	return {
		"id": str(source.get("id", "")),
		"name": str(source.get("name", "")),
		"avatar": str(source.get("artistImageUrl", "")),
		"albumCount": source.get("albumCount", 0),
		"starred": source.get("starred", null),
		"platform": PLATFORM,
	}

func _is_version_at_least(version: String, minimum: String) -> bool:
	return _compare_versions(version, minimum) >= 0

func _compare_versions(left: String, right: String) -> int:
	var left_parts := left.split(".")
	var right_parts := right.split(".")
	var max_size := maxi(left_parts.size(), right_parts.size())
	for index in max_size:
		var left_part := left_parts[index] if index < left_parts.size() else "0"
		var right_part := right_parts[index] if index < right_parts.size() else "0"
		var left_value := int(left_part) if left_part.is_valid_int() else 0
		var right_value := int(right_part) if right_part.is_valid_int() else 0
		if left_value > right_value:
			return 1
		if left_value < right_value:
			return -1
	return 0
