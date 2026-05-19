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
