class_name GDMusicTextUtils
extends RefCounted

static func strip_html_emphasis(text: String) -> String:
	var regex = RegEx.new()
	if regex.compile("</?em[^>]*>") != OK:
		return text
	return regex.sub(text, "", true)

static func decode_basic_html_entities(text: String) -> String:
	return text.xml_unescape()

static func extract_render_data_json(html: String) -> String:
	var start_marker = "<script id=\"__RENDER_DATA__\""
	var script_start = html.find(start_marker)
	if script_start == -1:
		return ""

	var tag_end = html.find(">", script_start)
	if tag_end == -1:
		return ""

	var close_tag = html.find("</script>", tag_end)
	if close_tag == -1:
		return ""

	return html.substr(tag_end + 1, close_tag - tag_end - 1).strip_edges()

static func unix_to_date_string(timestamp_sec: int) -> String:
	if timestamp_sec <= 0:
		return ""
	var parts = Time.get_datetime_dict_from_unix_time(timestamp_sec)
	return "%04d-%02d-%02d" % [
		int(parts.get("year", 0)),
		int(parts.get("month", 0)),
		int(parts.get("day", 0)),
	]

static func extract_next_data_json(html: String) -> String:
	var start_marker = "<script id=\"__NEXT_DATA__\""
	var script_start = html.find(start_marker)
	if script_start == -1:
		return ""

	var tag_end = html.find(">", script_start)
	if tag_end == -1:
		return ""

	var close_tag = html.find("</script>", tag_end)
	if close_tag == -1:
		return ""

	return html.substr(tag_end + 1, close_tag - tag_end - 1).strip_edges()

static func strip_tags(text: String) -> String:
	var regex = RegEx.new()
	if regex.compile("<[^>]+>") != OK:
		return text
	return regex.sub(text, "", true)

static func clean_html_text(text: String) -> String:
	return decode_basic_html_entities(strip_tags(text)).strip_edges()

static func strip_jsonp(text: String) -> String:
	var trimmed = text.strip_edges()
	var open_index = trimmed.find("(")
	var close_index = trimmed.rfind(")")
	if open_index >= 0 and close_index > open_index:
		var prefix = trimmed.substr(0, open_index)
		if prefix.contains("callback") or prefix.contains("Callback") or prefix.contains("json") or prefix.contains("MusicJson"):
			return trimmed.substr(open_index + 1, close_index - open_index - 1)
	return trimmed

static func extract_first_match(text: String, pattern: String) -> String:
	var regex = RegEx.new()
	if regex.compile(pattern) != OK:
		return ""
	var match = regex.search(text)
	if match == null or match.get_group_count() < 1:
		return ""
	return match.get_string(1)

static func normalize_protocol_url(url: Variant, protocol: String = "https") -> String:
	var text = str(url)
	if text.begins_with("//"):
		return "%s:%s" % [protocol, text]
	return text
