class_name GDMusicHashUtils
extends RefCounted

static func hmac_sha1_base64(key: String, message: String) -> String:
	const BLOCK_SIZE := 64
	var key_bytes = key.to_utf8_buffer()
	if key_bytes.size() > BLOCK_SIZE:
		key_bytes = _sha1_bytes(key_bytes)

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
	if inner_context.start(HashingContext.HASH_SHA1) != OK:
		return ""
	inner_context.update(inner_pad)
	inner_context.update(message.to_utf8_buffer())
	var inner_hash = inner_context.finish()

	var outer_context = HashingContext.new()
	if outer_context.start(HashingContext.HASH_SHA1) != OK:
		return ""
	outer_context.update(outer_pad)
	outer_context.update(inner_hash)
	return Marshalls.raw_to_base64(outer_context.finish())

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

static func random_alnum(length: int = 16) -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var result = ""
	for _index in range(length):
		result += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return result

static func base64_to_utf8(text: String) -> String:
	if text.is_empty():
		return ""
	return Marshalls.base64_to_utf8(text)

static func base64url_to_raw(text: String) -> PackedByteArray:
	var normalized = text.replace("-", "+").replace("_", "/")
	var remainder = normalized.length() % 4
	if remainder != 0:
		normalized += "=".repeat(4 - remainder)
	return Marshalls.base64_to_raw(normalized)

static func hex_to_bytes(hex_text: String) -> PackedByteArray:
	var cleaned = hex_text.strip_edges()
	if cleaned.length() % 2 != 0:
		cleaned = "0%s" % cleaned
	var bytes = PackedByteArray()
	for index in range(0, cleaned.length(), 2):
		bytes.append(cleaned.substr(index, 2).hex_to_int())
	return bytes

static func aes_cbc_pkcs7_encrypt_base64(text: String, key: String, iv: String) -> String:
	var context = AESContext.new()
	var key_bytes = key.to_utf8_buffer()
	var iv_bytes = iv.to_utf8_buffer()
	var source = _pkcs7_pad(text.to_utf8_buffer(), 16)
	if context.start(AESContext.MODE_CBC_ENCRYPT, key_bytes, iv_bytes) != OK:
		return ""
	var encrypted = context.update(source)
	context.finish()
	return Marshalls.raw_to_base64(encrypted)

static func aes_ecb_pkcs7_decrypt_base64url_to_utf8(text: String, key_hex: String) -> String:
	var source = base64url_to_raw(text)
	if source.is_empty():
		return ""
	var context = AESContext.new()
	if context.start(AESContext.MODE_ECB_DECRYPT, hex_to_bytes(key_hex)) != OK:
		return ""
	var decrypted = context.update(source)
	context.finish()
	return _pkcs7_unpad(decrypted).get_string_from_utf8()

static func rsa_mod_pow_hex_padded(message_hex: String, exponent_hex: String, modulus_hex: String, width: int) -> String:
	var base = _bigint_from_hex(message_hex)
	var modulus = _bigint_from_hex(modulus_hex)
	var exponent = exponent_hex.hex_to_int()
	base = _bigint_mod(base, modulus)
	var result = [1]
	while exponent > 0:
		if exponent & 1:
			result = _bigint_mul_mod(result, base, modulus)
		exponent = exponent >> 1
		if exponent > 0:
			base = _bigint_mul_mod(base, base, modulus)
	var hex_result = _bigint_to_hex(result)
	if hex_result.length() < width:
		return "0".repeat(width - hex_result.length()) + hex_result
	return hex_result

static func _sha1_bytes(data: PackedByteArray) -> PackedByteArray:
	var context = HashingContext.new()
	if context.start(HashingContext.HASH_SHA1) != OK:
		return PackedByteArray()
	context.update(data)
	return context.finish()

static func _pkcs7_pad(data: PackedByteArray, block_size: int) -> PackedByteArray:
	var result = PackedByteArray(data)
	var pad = block_size - (result.size() % block_size)
	if pad == 0:
		pad = block_size
	for _index in range(pad):
		result.append(pad)
	return result

static func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data
	var pad = int(data[data.size() - 1])
	if pad <= 0 or pad > 16 or pad > data.size():
		return data
	for index in range(data.size() - pad, data.size()):
		if int(data[index]) != pad:
			return data
	var result = PackedByteArray()
	for index in range(data.size() - pad):
		result.append(data[index])
	return result

static func _bigint_from_hex(hex_text: String) -> Array:
	var cleaned = hex_text.strip_edges().to_lower()
	var result: Array = []
	for index in range(cleaned.length(), 0, -4):
		var start = maxi(0, index - 4)
		result.append(cleaned.substr(start, index - start).hex_to_int())
	return _bigint_trim(result)

static func _bigint_to_hex(value: Array) -> String:
	var trimmed = _bigint_trim(value)
	if trimmed.is_empty():
		return "0"
	var parts: Array[String] = []
	for index in range(trimmed.size() - 1, -1, -1):
		var part = "%x" % int(trimmed[index])
		if index != trimmed.size() - 1:
			part = "0".repeat(4 - part.length()) + part
		parts.append(part)
	return "".join(parts)

static func _bigint_trim(value: Array) -> Array:
	var result = value.duplicate()
	while result.size() > 0 and int(result[result.size() - 1]) == 0:
		result.pop_back()
	return result

static func _bigint_compare(left: Array, right: Array) -> int:
	var a = _bigint_trim(left)
	var b = _bigint_trim(right)
	if a.size() != b.size():
		return 1 if a.size() > b.size() else -1
	for index in range(a.size() - 1, -1, -1):
		if int(a[index]) == int(b[index]):
			continue
		return 1 if int(a[index]) > int(b[index]) else -1
	return 0

static func _bigint_add(left: Array, right: Array) -> Array:
	var size = maxi(left.size(), right.size())
	var result: Array = []
	var carry = 0
	for index in range(size):
		var sum = carry
		if index < left.size():
			sum += int(left[index])
		if index < right.size():
			sum += int(right[index])
		result.append(sum & 0xffff)
		carry = sum >> 16
	if carry > 0:
		result.append(carry)
	return _bigint_trim(result)

static func _bigint_subtract(left: Array, right: Array) -> Array:
	var result: Array = []
	var borrow = 0
	for index in range(left.size()):
		var value = int(left[index]) - borrow
		if index < right.size():
			value -= int(right[index])
		if value < 0:
			value += 0x10000
			borrow = 1
		else:
			borrow = 0
		result.append(value)
	return _bigint_trim(result)

static func _bigint_mod(value: Array, modulus: Array) -> Array:
	var result = _bigint_trim(value)
	while _bigint_compare(result, modulus) >= 0:
		var shift = maxi(0, result.size() - modulus.size())
		var shifted: Array = []
		for _index in range(shift):
			shifted.append(0)
		shifted.append_array(modulus)
		if _bigint_compare(result, shifted) < 0 and shift > 0:
			shifted.pop_front()
		result = _bigint_subtract(result, shifted)
	return result

static func _bigint_add_mod(left: Array, right: Array, modulus: Array) -> Array:
	var result = _bigint_add(left, right)
	if _bigint_compare(result, modulus) >= 0:
		result = _bigint_subtract(result, modulus)
	return result

static func _bigint_double_mod(value: Array, modulus: Array) -> Array:
	return _bigint_add_mod(value, value, modulus)

static func _bigint_bit_length(value: Array) -> int:
	var trimmed = _bigint_trim(value)
	if trimmed.is_empty():
		return 0
	var top = int(trimmed[trimmed.size() - 1])
	var bits = (trimmed.size() - 1) * 16
	while top > 0:
		bits += 1
		top = top >> 1
	return bits

static func _bigint_get_bit(value: Array, bit: int) -> bool:
	var limb = bit / 16
	if limb >= value.size():
		return false
	return (int(value[limb]) & (1 << (bit % 16))) != 0

static func _bigint_mul_mod(left: Array, right: Array, modulus: Array) -> Array:
	var result: Array = []
	var addend = _bigint_mod(left, modulus)
	var bit_count = _bigint_bit_length(right)
	for bit in range(bit_count):
		if _bigint_get_bit(right, bit):
			result = _bigint_add_mod(result, addend, modulus)
		addend = _bigint_double_mod(addend, modulus)
	return result
