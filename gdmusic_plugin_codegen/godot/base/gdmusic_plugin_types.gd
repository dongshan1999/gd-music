class_name GDMusicPluginTypes
extends RefCounted

const SEARCH_TYPE_MUSIC := "music"
const SEARCH_TYPE_ALBUM := "album"
const SEARCH_TYPE_ARTIST := "artist"
const SEARCH_TYPE_SHEET := "sheet"
const SEARCH_TYPE_LYRIC := "lyric"

static func build_media_source_result(
	url: String = "",
	headers: Dictionary = {},
	user_agent: String = "",
	quality: String = ""
) -> Dictionary:
	return {
		"url": url,
		"headers": headers,
		"userAgent": user_agent,
		"quality": quality,
	}

static func build_search_result(data: Array = [], is_end: bool = true) -> Dictionary:
	return {
		"isEnd": is_end,
		"data": data,
	}
