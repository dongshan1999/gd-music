extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")
const GDMusicTextUtils = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_text_utils.gd")

const PLATFORM := "歌词网"
const VERSION := "0.0.0"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/geciwang/index.js"
const DEFAULT_SEARCH_TYPE := "lyric"
const SUPPORTED_SEARCH_TYPES := ["lyric"]
const SUPPORTED_METHODS := ["search", "get_lyric", "getLyric"]

var _http := GDMusicHttpJsonClient.new()

func get_platform() -> String:
	return PLATFORM

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
	if media_type != "lyric":
		return {"isEnd": true, "data": []}

	var html := await _http.get_text(
		"https://zh.followlyrics.com/search",
		{
			"name": query,
			"type": "song",
		}
	)
	if html.is_empty():
		return {"isEnd": true, "data": []}

	var tbody_block := _extract_first_match(
		html,
		"<tbody[^>]*>([\\s\\S]*?)</tbody>"
	)
	if tbody_block.is_empty():
		return {"isEnd": true, "data": []}

	var row_regex := RegEx.new()
	if row_regex.compile("<tr[^>]*>([\\s\\S]*?)</tr>") != OK:
		return {"isEnd": true, "data": []}

	var rows = row_regex.search_all(tbody_block)
	var results: Array = []
	for row_match in rows:
		var row_html = row_match.get_string(1)
		var cell_regex := RegEx.new()
		if cell_regex.compile("<td[^>]*>([\\s\\S]*?)</td>") != OK:
			continue
		var cells = cell_regex.search_all(row_html)
		if cells.size() < 4:
			continue

		var title = _clean_html_text(cells[0].get_string(1))
		var artist = _clean_html_text(cells[1].get_string(1))
		var album = _clean_html_text(cells[2].get_string(1))
		var link_html = cells[3].get_string(1)
		var id = _extract_first_match(link_html, "href=[\"']([^\"']+)[\"']")
		if id.is_empty():
			continue
		if id.begins_with("/"):
			id = "https://zh.followlyrics.com%s" % id

		results.append({
			"title": title,
			"artist": artist,
			"album": album,
			"id": id,
			"platform": PLATFORM,
		})

	return {
		"isEnd": true,
		"data": results,
	}

func get_lyric(music_item: Dictionary) -> Dictionary:
	var url = str(music_item.get("id", ""))
	if url.is_empty():
		return {}

	var html = await _http.get_text(url)
	if html.is_empty():
		return {}

	var raw_lrc = _extract_first_match(html, "<div[^>]+id=[\"']lyrics[\"'][^>]*>([\\s\\S]*?)</div>")
	raw_lrc = _clean_html_text(raw_lrc).replace("\n", "")
	if raw_lrc.is_empty():
		return {}
	return {"rawLrc": raw_lrc}

func _clean_html_text(text: String) -> String:
	return GDMusicTextUtils.decode_basic_html_entities(
		GDMusicTextUtils.strip_tags(text)
	).strip_edges()

func _extract_first_match(text: String, pattern: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return ""
	var match = regex.search(text)
	if match == null or match.get_group_count() < 1:
		return ""
	return match.get_string(1)
