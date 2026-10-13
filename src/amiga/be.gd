class_name BE
extends RefCounted
## Big-endian helpers for Amiga data.

static func u8(b: PackedByteArray, o: int) -> int:
	return b[o]

static func s8(b: PackedByteArray, o: int) -> int:
	var v: int = b[o]
	return v - 256 if v >= 128 else v

static func u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]

static func s16(b: PackedByteArray, o: int) -> int:
	var v: int = (b[o] << 8) | b[o + 1]
	return v - 65536 if v >= 32768 else v

static func u32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
