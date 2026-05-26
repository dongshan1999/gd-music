extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"

const GDMusicHttpJsonClient = preload("res://gdmusic_plugin_codegen/godot/runtime/gdmusic_http_json_client.gd")

const PLATFORM := "快手"
const AUTHOR := "猫头猫"
const VERSION := "0.0.2"
const SRC_URL := "https://gitee.com/maotoumao/MusicFreePlugins/raw/v0.1/dist/kuaishou/index.js"
const DEFAULT_SEARCH_TYPE := "music"
const SUPPORTED_SEARCH_TYPES := ["music"]
const SUPPORTED_METHODS := ["search", "getMediaSource"]
const PAGE_SIZE := 20
const SEARCH_QUERY := """fragment photoContent on PhotoEntity {
  __typename
  id
  duration
  caption
  originCaption
  likeCount
  viewCount
  commentCount
  realLikeCount
  coverUrl
  photoUrl
  photoH265Url
  manifest
  manifestH265
  videoResource
  coverUrls {
    url
    __typename
  }
  timestamp
  expTag
  animatedCoverUrl
  distance
  videoRatio
  liked
  stereoType
  profileUserTopPhoto
  musicBlocked
  riskTagContent
  riskTagUrl
}

fragment recoPhotoFragment on recoPhotoEntity {
  __typename
  id
  duration
  caption
  originCaption
  likeCount
  viewCount
  commentCount
  realLikeCount
  coverUrl
  photoUrl
  photoH265Url
  manifest
  manifestH265
  videoResource
  coverUrls {
    url
    __typename
  }
  timestamp
  expTag
  animatedCoverUrl
  distance
  videoRatio
  liked
  stereoType
  profileUserTopPhoto
  musicBlocked
  riskTagContent
  riskTagUrl
}

fragment feedContent on Feed {
  type
  author {
    id
    name
    headerUrl
    following
    headerUrls {
      url
      __typename
    }
    __typename
  }
  photo {
    ...photoContent
    ...recoPhotoFragment
    __typename
  }
  canAddComment
  llsid
  status
  currentPcursor
  tags {
    type
    name
    __typename
  }
  __typename
}

query visionSearchPhoto($keyword: String, $pcursor: String, $searchSessionId: String, $page: String, $webPageArea: String) {
  visionSearchPhoto(keyword: $keyword, pcursor: $pcursor, searchSessionId: $searchSessionId, page: $page, webPageArea: $webPageArea) {
    result
    llsid
    webPageArea
    feeds {
      ...feedContent
      __typename
    }
    searchSessionId
    pcursor
    aladdinBanner {
      imgUrl
      link
      __typename
    }
    __typename
  }
}"""
const SEARCH_HEADERS := {
	"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
	"host": "www.kuaishou.com",
	"origin": "https://www.kuaishou.com",
	"content-type": "application/json",
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
	return "low"

func search(query: String, page: int, media_type: String) -> Dictionary:
	if media_type != "music":
		return {"isEnd": true, "data": []}

	var request_body := {
		"query": SEARCH_QUERY,
		"variables": {
			"keyword": query,
			"page": "search",
			"pcursor": str(maxi(0, page - 1)),
		},
	}
	var headers := SEARCH_HEADERS.duplicate(true)
	headers["referer"] = "https://www.kuaishou.com/search/video?searchKey=%s" % query.uri_encode()

	var response = await _http.request_json(
		"https://www.kuaishou.com/graphql",
		{},
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(request_body)
	)
	var payload: Dictionary = (response as Dictionary).get("data", {}).get("visionSearchPhoto", {})
	var feeds := _ensure_array(payload.get("feeds", []))
	var items: Array = []
	for feed in feeds:
		items.append(_format_music_item(feed))

	var next_pcursor := str(payload.get("pcursor", ""))
	return {
		"isEnd": next_pcursor.is_empty() or next_pcursor == "no_more" or items.size() < PAGE_SIZE,
		"data": items,
	}

func get_media_source(music_item: Dictionary, _quality: String) -> Dictionary:
	var manifest = music_item.get("manifest", {})
	if not (manifest is Dictionary):
		return {}

	var adaptation_set := _ensure_array((manifest as Dictionary).get("adaptationSet", []))
	if adaptation_set.is_empty():
		return {}

	var first_set: Dictionary = adaptation_set[0] if adaptation_set[0] is Dictionary else {}
	var representations := _ensure_array(first_set.get("representation", []))
	if representations.is_empty():
		return {}

	var first_representation: Dictionary = representations[0] if representations[0] is Dictionary else {}
	var url := str(first_representation.get("url", ""))
	if url.is_empty():
		return {}
	return {"url": url}

func _format_music_item(feed_value: Variant) -> Dictionary:
	var feed: Dictionary = feed_value if feed_value is Dictionary else {}
	var photo: Dictionary = feed.get("photo", {}) if feed.get("photo", {}) is Dictionary else {}
	var author: Dictionary = feed.get("author", {}) if feed.get("author", {}) is Dictionary else {}

	var artwork := str(photo.get("coverUrl", ""))
	if artwork.is_empty():
		artwork = str(photo.get("photoUrl", ""))
	if artwork.is_empty():
		var cover_urls := _ensure_array(photo.get("coverUrls", []))
		if not cover_urls.is_empty() and cover_urls[0] is Dictionary:
			artwork = str((cover_urls[0] as Dictionary).get("url", ""))

	return {
		"id": str(photo.get("id", "")),
		"title": str(photo.get("caption", "")),
		"artist": str(author.get("name", "")),
		"artwork": artwork,
		"duration": _to_int(photo.get("duration", 0)),
		"manifest": photo.get("manifest", {}),
		"platform": PLATFORM,
	}

func _ensure_array(value: Variant) -> Array:
	return value if value is Array else []

func _to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(value)
	return 0
