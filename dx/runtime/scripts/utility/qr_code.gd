class_name DX_QrCode
extends RefCounted

## 纯 GDScript 二维码编码器
## 规格：byte mode + 纠错等级 M + 版本 1-10 自动选择 + 8 种掩码按 penalty 择优
## 参考 ISO/IEC 18004 标准流程（对齐 Nayuki 的经典实现思路）。

# ---------------------------------------------------------------------------
# 常量表
# ---------------------------------------------------------------------------

# 纠错等级 M 的版本参数：
#   total  = 该版本总码字数（数据 + 纠错）
#   ec     = 每个纠错块的纠错码字数
#   groups = [[块数, 每块数据码字数], ...]
const VERSION_TABLE_M := {
	1: {"total": 26, "ec": 10, "groups": [[1, 16]]},
	2: {"total": 44, "ec": 16, "groups": [[1, 28]]},
	3: {"total": 70, "ec": 26, "groups": [[1, 44]]},
	4: {"total": 100, "ec": 18, "groups": [[2, 32]]},
	5: {"total": 134, "ec": 24, "groups": [[2, 43]]},
	6: {"total": 172, "ec": 16, "groups": [[4, 27]]},
	7: {"total": 196, "ec": 18, "groups": [[4, 31]]},
	8: {"total": 242, "ec": 22, "groups": [[2, 38], [2, 39]]},
	9: {"total": 292, "ec": 22, "groups": [[3, 36], [2, 37]]},
	10: {"total": 346, "ec": 26, "groups": [[4, 43], [1, 44]]},
}

# 版本 1-10 的对齐图案中心坐标（行/列共用同一组坐标）
const ALIGNMENT_POSITIONS := {
	1: [],
	2: [6, 18],
	3: [6, 22],
	4: [6, 26],
	5: [6, 30],
	6: [6, 34],
	7: [6, 22, 38],
	8: [6, 24, 42],
	9: [6, 26, 46],
	10: [6, 28, 50],
}

const MODE_BYTE := 0b0100
const ECC_LEVEL_M_BITS := 0b00
const FORMAT_XOR_MASK := 0x5412
const FORMAT_GENERATOR := 0x537
const VERSION_GENERATOR := 0x1F25

# GF(256) 指数/对数表，首次使用时惰性构建（静态缓存）
static var _gf_exp: PackedInt32Array = PackedInt32Array()
static var _gf_log: PackedInt32Array = PackedInt32Array()


# ---------------------------------------------------------------------------
# 公开 API
# ---------------------------------------------------------------------------

## 将文本编码为二维码矩阵。
## 返回 {"size": int, "modules": Array}，modules[y][x] 为 bool，true = 黑。
## 额外附带 version / mask / penalty，便于调试与验证。
static func encode(text: String) -> Dictionary:
	var data := text.to_utf8_buffer()

	var version := _choose_version(data.size())
	if version <= 0:
		push_error("DX_QrCode: 内容过长，版本 1-10 / 纠错 M 无法容纳 %d 字节" % data.size())
		return {}

	var codewords := _build_codewords(data, version)

	# 逐一尝试 8 种掩码，按 penalty 规则 1-4 取最低分
	var best_mask := 0
	var best_penalty := 0x7FFFFFFF
	var best_modules: Array = []
	for mask in 8:
		var modules := _build_matrix(version, codewords, mask)
		var penalty := _calculate_penalty(modules, modules.size())
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
			best_modules = modules

	return {
		"size": version * 4 + 17,
		"modules": best_modules,
		"version": version,
		"mask": best_mask,
		"penalty": best_penalty,
	}


## 生成可直接 save_png() 的 Image：白底黑块，四周带 quiet zone。
static func encode_image(text: String, pixels_per_module: int = 6, quiet_zone: int = 4) -> Image:
	var code := encode(text)
	if code.is_empty():
		return null

	var size: int = code["size"]
	var modules: Array = code["modules"]
	var ppm := maxi(1, pixels_per_module)
	var qz := maxi(0, quiet_zone)
	var dim := (size + qz * 2) * ppm

	var img := Image.create(dim, dim, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in size:
		for x in size:
			if modules[y][x]:
				img.fill_rect(Rect2i((x + qz) * ppm, (y + qz) * ppm, ppm, ppm), Color.BLACK)
	return img


# ---------------------------------------------------------------------------
# 版本选择 / 码字构造
# ---------------------------------------------------------------------------

## 选择能容纳数据的最小版本（1-10）。返回 0 表示放不下。
static func _choose_version(byte_count: int) -> int:
	for version in range(1, 11):
		var data_codewords: int = _data_codeword_count(version)
		# byte mode 的字符计数指示符：版本 1-9 为 8 位，版本 10 起为 16 位
		var count_bits := 8 if version < 10 else 16
		var needed := 4 + count_bits + byte_count * 8
		if needed <= data_codewords * 8:
			return version
	return 0


## 取某版本在纠错等级 M 下的数据码字总数。
static func _data_codeword_count(version: int) -> int:
	var total := 0
	for group in VERSION_TABLE_M[version]["groups"]:
		total += int(group[0]) * int(group[1])
	return total


## 构造最终交织后的完整码字序列（数据 + 纠错）。
static func _build_codewords(data: PackedByteArray, version: int) -> PackedByteArray:
	_ensure_gf()

	var info: Dictionary = VERSION_TABLE_M[version]
	var ec_len: int = info["ec"]
	var groups: Array = info["groups"]
	var capacity: int = _data_codeword_count(version)
	var capacity_bits := capacity * 8

	# 1) 比特流：模式指示符 + 字符计数 + 数据
	var bits := PackedInt32Array()
	_append_bits(bits, MODE_BYTE, 4)
	_append_bits(bits, data.size(), 8 if version < 10 else 16)
	for byte in data:
		_append_bits(bits, byte, 8)

	# 2) 终止符（最多 4 个 0）、补齐到字节边界
	var terminator := mini(4, capacity_bits - bits.size())
	for i in terminator:
		bits.append(0)
	while bits.size() % 8 != 0:
		bits.append(0)

	# 3) 交替填充 0xEC / 0x11 直到数据区填满
	var pad_bytes := [0xEC, 0x11]
	var pad_index := 0
	while bits.size() < capacity_bits:
		_append_bits(bits, pad_bytes[pad_index % 2], 8)
		pad_index += 1

	# 4) 比特流 -> 数据码字
	var data_codewords := PackedByteArray()
	data_codewords.resize(capacity)
	for i in capacity:
		var value := 0
		for j in 8:
			value = (value << 1) | bits[i * 8 + j]
		data_codewords[i] = value

	# 5) 分块并计算每块的 RS 纠错码字
	var blocks: Array = []
	var ecc_blocks: Array = []
	var generator := _rs_generator(ec_len)
	var offset := 0
	for group in groups:
		var block_count: int = int(group[0])
		var block_len: int = int(group[1])
		for k in block_count:
			var block := data_codewords.slice(offset, offset + block_len)
			offset += block_len
			blocks.append(block)
			ecc_blocks.append(_rs_remainder(block, generator, ec_len))

	# 6) 按标准交织：先列式取数据码字，再列式取纠错码字
	var result := PackedByteArray()
	var max_block_len := 0
	for block in blocks:
		max_block_len = maxi(max_block_len, block.size())
	for i in max_block_len:
		for block in blocks:
			if i < block.size():
				result.append(block[i])
	for i in ec_len:
		for ecc in ecc_blocks:
			result.append(ecc[i])

	assert(result.size() == int(info["total"]))
	return result


static func _append_bits(bits: PackedInt32Array, value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


# ---------------------------------------------------------------------------
# GF(256) 与 Reed-Solomon
# ---------------------------------------------------------------------------

static func _ensure_gf() -> void:
	if _gf_exp.size() == 512:
		return
	_gf_exp.resize(512)
	_gf_log.resize(256)
	var x := 1
	for i in 255:
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_gf_exp[i] = _gf_exp[i - 255]


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _gf_exp[_gf_log[a] + _gf_log[b]]


## 生成多项式 (x - α^0)(x - α^1)...(x - α^(degree-1))
static func _rs_generator(degree: int) -> PackedInt32Array:
	var poly := PackedInt32Array([1])
	for i in degree:
		var factor := _gf_exp[i]
		var next := PackedInt32Array()
		next.resize(poly.size() + 1)
		next.fill(0)
		for j in poly.size():
			# 乘以 (x + factor)：系数数组按最高次项在前
			next[j] ^= poly[j]
			next[j + 1] ^= _gf_mul(poly[j], factor)
		poly = next
	return poly


## 计算数据块的 RS 余式（即纠错码字）。
static func _rs_remainder(data: PackedByteArray, generator: PackedInt32Array, ec_len: int) -> PackedByteArray:
	var remainder := PackedInt32Array()
	remainder.resize(ec_len)
	remainder.fill(0)
	for byte in data:
		var factor := byte ^ remainder[0]
		for i in range(ec_len - 1):
			remainder[i] = remainder[i + 1]
		remainder[ec_len - 1] = 0
		if factor != 0:
			for i in ec_len:
				remainder[i] ^= _gf_mul(generator[i + 1], factor)

	var result := PackedByteArray()
	result.resize(ec_len)
	for i in ec_len:
		result[i] = remainder[i]
	return result


# ---------------------------------------------------------------------------
# 矩阵构造
# ---------------------------------------------------------------------------

## 构造某个掩码下的完整矩阵（含功能图案、数据、格式信息、版本信息）。
static func _build_matrix(version: int, codewords: PackedByteArray, mask: int) -> Array:
	var size := version * 4 + 17
	var modules := _make_grid(size)
	var is_function := _make_grid(size)

	# 1) 定时图案（整行/整列，之后会被定位图案与对齐图案覆盖）
	for i in size:
		_set_function(modules, is_function, 6, i, i % 2 == 0)
		_set_function(modules, is_function, i, 6, i % 2 == 0)

	# 2) 三个定位图案（含分隔符，用切比雪夫距离 dist = 0..4）
	_draw_finder(modules, is_function, size, 3, 3)
	_draw_finder(modules, is_function, size, size - 4, 3)
	_draw_finder(modules, is_function, size, 3, size - 4)

	# 3) 对齐图案
	_draw_alignment_patterns(modules, is_function, version, size)

	# 4) 预留格式信息区 + 固定暗模块
	_reserve_format_areas(modules, is_function, size)

	# 5) 版本信息（版本 >= 7 才有）
	if version >= 7:
		_write_version_info(modules, is_function, version, size)

	# 6) 数据比特按 Z 字形放置
	_place_data(modules, is_function, size, codewords)

	# 7) 施加掩码（只作用于非功能模块）
	for y in size:
		for x in size:
			if not is_function[y][x] and _mask_bit(y, x, mask):
				modules[y][x] = not modules[y][x]

	# 8) 最后写入格式信息（其内容随掩码变化）
	_write_format_info(modules, is_function, size, mask)

	return modules


static func _make_grid(size: int) -> Array:
	var grid: Array = []
	grid.resize(size)
	for y in size:
		var row: Array = []
		row.resize(size)
		row.fill(false)
		grid[y] = row
	return grid


## 写功能模块并标记为功能区域。
static func _set_function(modules: Array, is_function: Array, y: int, x: int, dark: bool) -> void:
	modules[y][x] = dark
	is_function[y][x] = true


static func _reserve(is_function: Array, y: int, x: int) -> void:
	is_function[y][x] = true


static func _draw_finder(modules: Array, is_function: Array, size: int, center_x: int, center_y: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x: int = center_x + dx
			var y: int = center_y + dy
			if x < 0 or x >= size or y < 0 or y >= size:
				continue
			var dist: int = maxi(absi(dx), absi(dy))
			# dist 0/1/3 为黑，dist 2 为白环，dist 4 为分隔符（白）
			_set_function(modules, is_function, y, x, dist != 2 and dist != 4)


static func _draw_alignment_patterns(modules: Array, is_function: Array, version: int, size: int) -> void:
	var positions: Array = ALIGNMENT_POSITIONS[version]
	var count := positions.size()
	for i in count:
		for j in count:
			# 跳过与三个定位图案重叠的角落
			if (i == 0 and j == 0) or (i == 0 and j == count - 1) or (i == count - 1 and j == 0):
				continue
			var center_y: int = positions[i]
			var center_x: int = positions[j]
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var dist: int = maxi(absi(dx), absi(dy))
					_set_function(modules, is_function, center_y + dy, center_x + dx, dist != 1)


static func _reserve_format_areas(modules: Array, is_function: Array, size: int) -> void:
	# 左上角：列 8 的 0-5、7、8；行 8 的 0-5、7、8（(8,8) 共用）
	for i in 6:
		_reserve(is_function, i, 8)
		_reserve(is_function, 8, i)
	_reserve(is_function, 7, 8)
	_reserve(is_function, 8, 7)
	_reserve(is_function, 8, 8)
	# 右上角：行 8，列 size-8 .. size-1
	for i in 8:
		_reserve(is_function, 8, size - 1 - i)
	# 左下角：列 8，行 size-7 .. size-1
	for i in range(8, 15):
		_reserve(is_function, size - 15 + i, 8)
	# 固定暗模块
	_set_function(modules, is_function, size - 8, 8, true)


static func _write_version_info(modules: Array, is_function: Array, version: int, size: int) -> void:
	# 6 位版本号 + BCH(18,6) 校验
	var remainder := version
	for i in 12:
		remainder = (remainder << 1) ^ ((remainder >> 11) * VERSION_GENERATOR)
	var bits := (version << 12) | remainder

	for i in 18:
		var dark := ((bits >> i) & 1) != 0
		var a := size - 11 + i % 3
		var b := i / 3
		# 左下角 3x6 与右上角 6x3（互为转置）
		_set_function(modules, is_function, b, a, dark)
		_set_function(modules, is_function, a, b, dark)


static func _place_data(modules: Array, is_function: Array, size: int, codewords: PackedByteArray) -> void:
	var total_bits := codewords.size() * 8
	var bit_index := 0
	var right := size - 1
	while right >= 1:
		# 第 6 列是定时图案列，整列跳过
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x: int = right - j
				var upward := ((right + 1) & 2) == 0
				var y: int = (size - 1 - vert) if upward else vert
				if is_function[y][x]:
					continue
				if bit_index < total_bits:
					var byte_index := bit_index >> 3
					var bit_value := (codewords[byte_index] >> (7 - (bit_index & 7))) & 1
					modules[y][x] = bit_value == 1
					bit_index += 1
		right -= 2


static func _write_format_info(modules: Array, is_function: Array, size: int, mask: int) -> void:
	# 5 位格式数据（2 位纠错等级 + 3 位掩码），M 级对应 0b00
	var data := (ECC_LEVEL_M_BITS << 3) | mask
	var remainder := data
	for i in 10:
		remainder = (remainder << 1) ^ ((remainder >> 9) * FORMAT_GENERATOR)
	var bits := ((data << 10) | remainder) ^ FORMAT_XOR_MASK

	# 第一份：左上角
	for i in 6:
		_set_function(modules, is_function, i, 8, ((bits >> i) & 1) != 0)
	_set_function(modules, is_function, 7, 8, ((bits >> 6) & 1) != 0)
	_set_function(modules, is_function, 8, 8, ((bits >> 7) & 1) != 0)
	_set_function(modules, is_function, 8, 7, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_function(modules, is_function, 8, 14 - i, ((bits >> i) & 1) != 0)

	# 第二份：右上角 + 左下角
	for i in 8:
		_set_function(modules, is_function, 8, size - 1 - i, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_function(modules, is_function, size - 15 + i, 8, ((bits >> i) & 1) != 0)


static func _mask_bit(y: int, x: int, mask: int) -> bool:
	match mask:
		0:
			return (y + x) % 2 == 0
		1:
			return y % 2 == 0
		2:
			return x % 3 == 0
		3:
			return (y + x) % 3 == 0
		4:
			return (y / 2 + x / 3) % 2 == 0
		5:
			return (y * x) % 2 + (y * x) % 3 == 0
		6:
			return ((y * x) % 2 + (y * x) % 3) % 2 == 0
		7:
			return ((y + x) % 2 + (y * x) % 3) % 2 == 0
	return false


# ---------------------------------------------------------------------------
# 掩码 penalty（规则 1-4）
# ---------------------------------------------------------------------------

static func _calculate_penalty(modules: Array, size: int) -> int:
	var penalty := 0

	# 规则 1：行/列中连续同色模块数 >= 5，扣 3 + (长度 - 5)
	for y in size:
		var run := 1
		for x in range(1, size):
			if modules[y][x] == modules[y][x - 1]:
				run += 1
			else:
				if run >= 5:
					penalty += 3 + (run - 5)
				run = 1
		if run >= 5:
			penalty += 3 + (run - 5)

	for x in size:
		var run := 1
		for y in range(1, size):
			if modules[y][x] == modules[y - 1][x]:
				run += 1
			else:
				if run >= 5:
					penalty += 3 + (run - 5)
				run = 1
		if run >= 5:
			penalty += 3 + (run - 5)

	# 规则 2：2x2 同色块，每个扣 3
	for y in range(size - 1):
		for x in range(size - 1):
			var color: bool = modules[y][x]
			if color == modules[y][x + 1] and color == modules[y + 1][x] and color == modules[y + 1][x + 1]:
				penalty += 3

	# 规则 3：出现 1:1:3:1:1 且一侧带 4 个浅色模块的图案，每个扣 40
	var pattern_a := [true, false, true, true, true, false, true, false, false, false, false]
	var pattern_b := [false, false, false, false, true, false, true, true, true, false, true]

	for y in size:
		for x in range(size - 10):
			var match_a := true
			var match_b := true
			for k in 11:
				var value: bool = modules[y][x + k]
				if value != pattern_a[k]:
					match_a = false
				if value != pattern_b[k]:
					match_b = false
			if match_a:
				penalty += 40
			if match_b:
				penalty += 40

	for x in size:
		for y in range(size - 10):
			var match_a := true
			var match_b := true
			for k in 11:
				var value: bool = modules[y + k][x]
				if value != pattern_a[k]:
					match_a = false
				if value != pattern_b[k]:
					match_b = false
			if match_a:
				penalty += 40
			if match_b:
				penalty += 40

	# 规则 4：深色模块比例偏离 50% 的每 5% 扣 10
	var dark := 0
	for y in size:
		for x in size:
			if modules[y][x]:
				dark += 1
	var ratio := absf(dark * 100.0 / (size * size) - 50.0)
	penalty += int(ratio / 5.0) * 10

	return penalty
