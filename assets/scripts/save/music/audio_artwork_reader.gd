class_name AudioArtworkReader
extends RefCounted

## 从音频文件的元数据块里读出内嵌封面图。
##
## 只负责「找图」：不解码音频、不依赖任何编解码扩展，因此 mp3 / flac / m4a / ogg
## 的音轨都能读到封面。要求传入真实文件路径（需要 seek 跳过音频数据）；
## Android 的 saf-tree:// 这类虚拟路径必须先由调用方物化成缓存文件。

## 单张封面的大小上限，超过就放弃（防止把异常大的标签写进内存）。
const MAX_ARTWORK_BYTES := 8 * 1024 * 1024
## 解析 ID3 标签时一次性读入的最大字节数。
const MAX_ID3_TAG_BYTES := 24 * 1024 * 1024
## 在 ogg 流里搜索注释头的最大范围。
const MAX_OGG_SCAN_BYTES := 256 * 1024

## 读取内嵌封面，返回 {"mime": String, "data": PackedByteArray}；
## 没有内嵌封面或文件不可读时返回空字典。
static func read_embedded_artwork(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var result: Dictionary = {}
	var header := file.get_buffer(12)
	if header.size() >= 10 and _ascii(header, 0, 3) == "ID3":
		file.seek(0)
		result = _read_id3(file)
	elif header.size() >= 4 and _ascii(header, 0, 4) == "fLaC":
		file.seek(0)
		result = _read_flac(file)
	elif header.size() >= 12 and _ascii(header, 4, 4) == "ftyp":
		file.seek(0)
		result = _read_mp4(file)
	elif header.size() >= 4 and _ascii(header, 0, 4) == "OggS":
		file.seek(0)
		result = _read_ogg(file)
	elif header.size() >= 12 and _ascii(header, 0, 4) == "RIFF":
		file.seek(0)
		result = _read_wav(file)

	file.close()
	return _finalize(result)


## 把结果补全成带 mime 的字典；识别不了图片类型就丢掉。
static func _finalize(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var data: PackedByteArray = raw.get("data", PackedByteArray())
	if data.is_empty() or data.size() > MAX_ARTWORK_BYTES:
		return {}
	var mime := str(raw.get("mime", "")).strip_edges().to_lower()
	if mime.is_empty() or mime == "image/" or mime == "image":
		mime = _sniff_mime(data)
	if mime.is_empty():
		return {}
	return {"mime": mime, "data": data}


## 按文件头判断图片类型。
static func _sniff_mime(data: PackedByteArray) -> String:
	if data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		return "image/jpeg"
	if data.size() >= 8 and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		return "image/png"
	if data.size() >= 12 and _ascii(data, 0, 4) == "RIFF" and _ascii(data, 8, 4) == "WEBP":
		return "image/webp"
	if data.size() >= 6 and (_ascii(data, 0, 3) == "GIF"):
		return "image/gif"
	return ""


## 取 ASCII 字符串，越界时返回空串。
static func _ascii(buffer: PackedByteArray, offset: int, length: int) -> String:
	if offset < 0 or length <= 0 or offset + length > buffer.size():
		return ""
	return buffer.slice(offset, offset + length).get_string_from_ascii()


## 读大端 4 字节整数（ID3 标签外的尺寸字段用）。
static func _uint32_be(buffer: PackedByteArray, offset: int) -> int:
	if offset + 4 > buffer.size():
		return -1
	return (buffer[offset] << 24) | (buffer[offset + 1] << 16) | (buffer[offset + 2] << 8) | buffer[offset + 3]


## 读 ID3 的 syncsafe 整数（每字节最高位恒为 0）。
static func _syncsafe(buffer: PackedByteArray, offset: int) -> int:
	if offset + 4 > buffer.size():
		return -1
	return (
		((buffer[offset] & 0x7F) << 21)
		| ((buffer[offset + 1] & 0x7F) << 14)
		| ((buffer[offset + 2] & 0x7F) << 7)
		| (buffer[offset + 3] & 0x7F)
	)


## 兼容旧版 ID3v2.3 的非 syncsafe 帧长度。
static func _frame_size(buffer: PackedByteArray, offset: int, major: int) -> int:
	if major >= 4:
		return _syncsafe(buffer, offset)
	return _uint32_be(buffer, offset)


## 解除 ID3 的 unsynchronisation 编码（0xFF 0x00 还原成 0xFF）。
static func _deunsync(buffer: PackedByteArray) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(buffer.size())
	var write_index := 0
	var index := 0
	while index < buffer.size():
		output[write_index] = buffer[index]
		write_index += 1
		if buffer[index] == 0xFF and index + 1 < buffer.size() and buffer[index + 1] == 0x00:
			index += 2
			continue
		index += 1
	output.resize(write_index)
	return output


# ---------------------------------------------------------------------------
# ID3v2（mp3 / 部分 wav）
# ---------------------------------------------------------------------------

static func _read_id3(file: FileAccess) -> Dictionary:
	var header := file.get_buffer(10)
	if header.size() < 10:
		return {}
	var major := header[3]
	var flags := header[5]
	var tag_size := _syncsafe(header, 6)
	if tag_size <= 0:
		return {}

	var tag_length := mini(tag_size, MAX_ID3_TAG_BYTES)
	var body := file.get_buffer(tag_length)
	if body.is_empty():
		return {}
	if (flags & 0x80) != 0:
		body = _deunsync(body)

	var offset := 0
	# 跳过扩展头（v2.3 是 4 字节自身长度 + 数据，v2.4 是 syncsafe 长度）。
	if (flags & 0x40) != 0 and body.size() >= 4:
		offset = _syncsafe(body, 0) if major >= 4 else (4 + _uint32_be(body, 0))
		if offset <= 0:
			offset = 0

	var header_length := 6 if major <= 2 else 10
	while offset + header_length <= body.size():
		var frame_id := _ascii(body, offset, 3 if major <= 2 else 4)
		if frame_id.is_empty() or frame_id[0] == "\n" or frame_id[0].unicode_at(0) == 0:
			break
		var frame_size := 0
		if major <= 2:
			frame_size = (body[offset + 3] << 16) | (body[offset + 4] << 8) | body[offset + 5]
		else:
			frame_size = _frame_size(body, offset + 4, major)
		if frame_size <= 0:
			break
		var body_start := offset + header_length
		var body_end := mini(body_start + frame_size, body.size())
		if body_end <= body_start:
			break
		if frame_id == "APIC" or frame_id == "PIC":
			return _parse_id3_apic(body, body_start, body_end, frame_id == "PIC")
		offset = body_end

	return {}


## 解析 APIC/PIC 帧：编码字节 + mime + 图片类型 + 描述 + 图片数据。
static func _parse_id3_apic(buffer: PackedByteArray, start: int, body_end: int, is_v22: bool) -> Dictionary:
	var position := start
	if position >= body_end:
		return {}
	var encoding := buffer[position]
	position += 1

	var mime := ""
	if is_v22:
		if position + 3 > body_end:
			return {}
		var image_format := _ascii(buffer, position, 3).to_upper()
		position += 3
		if image_format == "PNG":
			mime = "image/png"
		elif image_format == "JPG":
			mime = "image/jpeg"
	else:
		var mime_start := position
		while position < body_end and buffer[position] != 0:
			position += 1
		mime = _ascii(buffer, mime_start, position - mime_start).to_lower()
		position += 1

	# 图片类型 1 字节。
	position += 1
	if position >= body_end:
		return {}

	# 描述文本以空字节结尾；UTF-16 编码要看 2 字节对齐的连续两个 0。
	if encoding == 1 or encoding == 2:
		while position + 1 < body_end:
			if buffer[position] == 0 and buffer[position + 1] == 0:
				position += 2
				break
			position += 2
	else:
		while position < body_end and buffer[position] != 0:
			position += 1
		position += 1

	var data := buffer.slice(position, body_end)
	return {"mime": mime, "data": data}


# ---------------------------------------------------------------------------
# FLAC
# ---------------------------------------------------------------------------

static func _read_flac(file: FileAccess) -> Dictionary:
	file.seek(4)
	var file_length := file.get_length()
	var guard := 0
	while file.get_position() + 4 <= file_length and guard < 64:
		guard += 1
		var block_header := file.get_buffer(4)
		if block_header.size() < 4:
			break
		var is_last := (block_header[0] & 0x80) != 0
		var block_type := block_header[0] & 0x7F
		var block_size := (block_header[1] << 16) | (block_header[2] << 8) | block_header[3]
		if block_size < 0:
			break
		if block_type == 6:
			var body := file.get_buffer(block_size)
			return _parse_flac_picture(body)
		file.seek(file.get_position() + block_size)
		if is_last:
			break
	return {}


## FLAC/Vorbis 的 PICTURE 结构，也复用于 ogg 的 METADATA_BLOCK_PICTURE。
static func _parse_flac_picture(buffer: PackedByteArray) -> Dictionary:
	var position := 0
	# 4 字节图片类型。
	position += 4
	if position + 4 > buffer.size():
		return {}
	var mime_length := _uint32_be(buffer, position)
	position += 4
	if mime_length < 0 or position + mime_length > buffer.size():
		return {}
	var mime := _ascii(buffer, position, mime_length).to_lower()
	position += mime_length
	if position + 4 > buffer.size():
		return {}
	var description_length := _uint32_be(buffer, position)
	position += 4
	if description_length < 0 or position + description_length > buffer.size():
		return {}
	position += description_length
	# 宽、高、色深、索引色数，共 16 字节。
	position += 16
	if position + 4 > buffer.size():
		return {}
	var data_length := _uint32_be(buffer, position)
	position += 4
	if data_length <= 0:
		return {}
	var data_end := mini(position + data_length, buffer.size())
	if data_end <= position:
		return {}
	return {"mime": mime, "data": buffer.slice(position, data_end)}


# ---------------------------------------------------------------------------
# MP4 / M4A
# ---------------------------------------------------------------------------

static func _read_mp4(file: FileAccess) -> Dictionary:
	return _walk_mp4(file, 0, file.get_length(), 0)


## 递归遍历 mp4 的 atom 树，找到 moov/udta/meta/ilst 下的 covr。
static func _walk_mp4(file: FileAccess, start: int, end: int, depth: int) -> Dictionary:
	if depth > 8 or start < 0 or end <= start:
		return {}
	var position := start
	while position + 8 <= end:
		file.seek(position)
		var atom_header := file.get_buffer(8)
		if atom_header.size() < 8:
			break
		var atom_size := _uint32_be(atom_header, 0)
		var atom_type := _ascii(atom_header, 4, 4)
		var header_size := 8
		if atom_size == 1:
			var large := file.get_buffer(8)
			if large.size() < 8:
				break
			atom_size = _uint32_be(large, 4)
			header_size = 16
		elif atom_size == 0:
			atom_size = end - position
		if atom_size <= 0 or position + atom_size > end:
			break

		var body_start := position + header_size
		var body_end := position + atom_size

		if atom_type == "covr":
			var result := _read_mp4_covr(file, body_start, body_end)
			if not result.is_empty():
				return result
		elif atom_type == "meta":
			# meta 在子 atom 前多 4 字节（version + flags）。
			var result := _walk_mp4(file, body_start + 4, body_end, depth + 1)
			if not result.is_empty():
				return result
		elif atom_type == "moov" or atom_type == "udta" or atom_type == "ilst" or atom_type == "trak" or atom_type == "mdia":
			var result := _walk_mp4(file, body_start, body_end, depth + 1)
			if not result.is_empty():
				return result
		position = body_end
	return {}


## covr 内部是一个或多个 data 子 atom，取第一个能识别的。
static func _read_mp4_covr(file: FileAccess, start: int, end: int) -> Dictionary:
	var position := start
	while position + 16 <= end:
		file.seek(position)
		var atom_header := file.get_buffer(8)
		if atom_header.size() < 8:
			break
		var atom_size := _uint32_be(atom_header, 0)
		var atom_type := _ascii(atom_header, 4, 4)
		if atom_size < 16 or position + atom_size > end:
			break
		if atom_type == "data":
			var data_header := file.get_buffer(8)
			if data_header.size() < 8:
				break
			var data_type := _uint32_be(data_header, 0) & 0x00FFFFFF
			var payload_length := atom_size - 16
			if payload_length > 0 and payload_length <= MAX_ARTWORK_BYTES:
				var payload := file.get_buffer(payload_length)
				if not payload.is_empty():
					var mime := ""
					if data_type == 14:
						mime = "image/png"
					elif data_type == 13:
						mime = "image/jpeg"
					return {"mime": mime, "data": payload}
		position += atom_size
	return {}


# ---------------------------------------------------------------------------
# Ogg / Opus（Vorbis comment 里的 METADATA_BLOCK_PICTURE）
# ---------------------------------------------------------------------------

static func _read_ogg(file: FileAccess) -> Dictionary:
	var scan_length := mini(MAX_OGG_SCAN_BYTES, file.get_length())
	var buffer := file.get_buffer(scan_length)
	if buffer.is_empty():
		return {}

	var marker_end := -1
	for marker in ["\u0003vorbis", "OpusTags"]:
		var marker_index := _find_bytes(buffer, marker.to_ascii_buffer())
		if marker_index >= 0:
			marker_end = marker_index + marker.to_ascii_buffer().size()
			break
	if marker_end < 0:
		return {}

	var position := marker_end
	if position + 4 > buffer.size():
		return {}
	var vendor_length := buffer[position] | (buffer[position + 1] << 8) | (buffer[position + 2] << 16) | (buffer[position + 3] << 24)
	position += 4 + vendor_length
	if position + 4 > buffer.size():
		return {}
	var comment_count := (
		buffer[position]
		| (buffer[position + 1] << 8)
		| (buffer[position + 2] << 16)
		| (buffer[position + 3] << 24)
	)
	position += 4

	for _index in range(clampi(comment_count, 0, 256)):
		if position + 4 > buffer.size():
			break
		var comment_length := (
			buffer[position]
			| (buffer[position + 1] << 8)
			| (buffer[position + 2] << 16)
			| (buffer[position + 3] << 24)
		)
		position += 4
		if comment_length <= 0 or position + comment_length > buffer.size():
			break
		var comment := _ascii(buffer, position, comment_length)
		position += comment_length
		var separator := comment.find("=")
		if separator <= 0:
			continue
		var key := comment.substr(0, separator).to_upper()
		if key != "METADATA_BLOCK_PICTURE":
			continue
		var encoded := comment.substr(separator + 1).strip_edges()
		var decoded := Marshalls.base64_to_raw(encoded)
		if decoded.is_empty():
			continue
		var picture := _parse_flac_picture(decoded)
		if not picture.is_empty():
			return picture
	return {}


## 在字节数组里找一段子序列。
static func _find_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or needle.size() > haystack.size():
		return -1
	var limit := haystack.size() - needle.size()
	for index in range(limit + 1):
		var matched := true
		for offset in range(needle.size()):
			if haystack[index + offset] != needle[offset]:
				matched = false
				break
		if matched:
			return index
	return -1


# ---------------------------------------------------------------------------
# WAV（RIFF 里的 id3 块）
# ---------------------------------------------------------------------------

static func _read_wav(file: FileAccess) -> Dictionary:
	file.seek(12)
	var file_length := file.get_length()
	var guard := 0
	while file.get_position() + 8 <= file_length and guard < 128:
		guard += 1
		var chunk_header := file.get_buffer(8)
		if chunk_header.size() < 8:
			break
		var chunk_id := _ascii(chunk_header, 0, 4).to_lower()
		var chunk_size := (
			chunk_header[4]
			| (chunk_header[5] << 8)
			| (chunk_header[6] << 16)
			| (chunk_header[7] << 24)
		)
		if chunk_size < 0:
			break
		if chunk_id == "id3 " or chunk_id == "id32":
			var body := file.get_buffer(mini(chunk_size, MAX_ID3_TAG_BYTES))
			if body.size() >= 10 and _ascii(body, 0, 3) == "ID3":
				# 把整个块当成一个独立文件解析 ID3。
				var temporary := PackedByteArray()
				temporary.append_array(body)
				return _read_id3_from_buffer(temporary)
			return {}
		# chunk 按偶数字节对齐。
		var aligned := chunk_size + (chunk_size % 2)
		file.seek(file.get_position() + aligned)
	return {}


## 复用 ID3 解析逻辑，但数据来自内存而非文件流。
static func _read_id3_from_buffer(body: PackedByteArray) -> Dictionary:
	if body.size() < 10:
		return {}
	var major := body[3]
	var flags := body[5]
	var tag_size := _syncsafe(body, 6)
	if tag_size <= 0:
		return {}
	var tag := body.slice(10, mini(10 + tag_size, body.size()))
	if (flags & 0x80) != 0:
		tag = _deunsync(tag)

	var offset := 0
	var header_length := 6 if major <= 2 else 10
	while offset + header_length <= tag.size():
		var frame_id := _ascii(tag, offset, 3 if major <= 2 else 4)
		if frame_id.is_empty():
			break
		var frame_size := 0
		if major <= 2:
			frame_size = (tag[offset + 3] << 16) | (tag[offset + 4] << 8) | tag[offset + 5]
		else:
			frame_size = _frame_size(tag, offset + 4, major)
		if frame_size <= 0:
			break
		var body_start := offset + header_length
		var body_end := mini(body_start + frame_size, tag.size())
		if body_end <= body_start:
			break
		if frame_id == "APIC" or frame_id == "PIC":
			return _parse_id3_apic(tag, body_start, body_end, frame_id == "PIC")
		offset = body_end
	return {}
