class_name Tpwm
extends RefCounted
## TPWM decruncher (the LZSS packer used by Apidya's loader, routine $7EE66 in the original).
##   'TPWM' + u32 BE length, then groups of [flag byte] + 8 items, flags MSB-first:
##   bit 0 -> literal byte, bit 1 -> match b1,b2: dist = (b1>>4)<<8 | b2, len = (b1&15)+3.

static func is_packed(src: PackedByteArray) -> bool:
	return src.size() >= 8 and src[0] == 0x54 and src[1] == 0x50 and src[2] == 0x57 and src[3] == 0x4D


static func unpack(src: PackedByteArray) -> PackedByteArray:
	if not is_packed(src):
		return src
	var n: int = (src[4] << 24) | (src[5] << 16) | (src[6] << 8) | src[7]
	var out := PackedByteArray()
	out.resize(n)
	var o := 0
	var p := 8
	var sl := src.size()
	while o < n and p < sl:
		var flags: int = src[p]
		p += 1
		for _i in 8:
			if o >= n or p >= sl:
				break
			if flags & 0x80:
				var b1: int = src[p]
				var b2: int = src[p + 1]
				p += 2
				var dist: int = ((b1 >> 4) << 8) | b2
				var cnt: int = (b1 & 0x0F) + 3
				for _k in cnt:
					if o >= n:
						break
					out[o] = out[o - dist] if (dist > 0 and o >= dist) else 0
					o += 1
			else:
				out[o] = src[p]
				p += 1
				o += 1
			flags = (flags << 1) & 0xFF
	return out
