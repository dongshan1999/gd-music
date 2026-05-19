class_name GDMusicHashUtils
extends RefCounted

static func md5_hex(text: String) -> String:
	var context = HashingContext.new()
	var error = context.start(HashingContext.HASH_MD5)
	if error != OK:
		return ""
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()

static func sha256_hex(text: String) -> String:
	var bytes = sha256_bytes(text.to_utf8_buffer())
	return bytes.hex_encode()

static func sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var context = HashingContext.new()
	var error = context.start(HashingContext.HASH_SHA256)
	if error != OK:
		return PackedByteArray()
	context.update(data)
	return context.finish()

static func hmac_sha256_hex(key: String, message: String) -> String:
	const BLOCK_SIZE := 64
	var key_bytes = key.to_utf8_buffer()
	if key_bytes.size() > BLOCK_SIZE:
		key_bytes = sha256_bytes(key_bytes)

	var normalized_key = PackedByteArray()
	normalized_key.resize(BLOCK_SIZE)
	for index in range(BLOCK_SIZE):
		normalized_key[index] = 0
	for index in range(mini(key_bytes.size(), BLOCK_SIZE)):
		normalized_key[index] = key_bytes[index]

	var inner_pad = PackedByteArray()
	var outer_pad = PackedByteArray()
	inner_pad.resize(BLOCK_SIZE)
	outer_pad.resize(BLOCK_SIZE)
	for index in range(BLOCK_SIZE):
		inner_pad[index] = normalized_key[index] ^ 0x36
		outer_pad[index] = normalized_key[index] ^ 0x5C

	var inner_context = HashingContext.new()
	if inner_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	inner_context.update(inner_pad)
	inner_context.update(message.to_utf8_buffer())
	var inner_hash = inner_context.finish()

	var outer_context = HashingContext.new()
	if outer_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	outer_context.update(outer_pad)
	outer_context.update(inner_hash)
	return outer_context.finish().hex_encode()

static func random_hex(length: int = 12) -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var alphabet = "0123456789abcdef"
	var result = ""
	for _index in range(length):
		result += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return result
