class_name DiskSet
extends RefCounted
## The two original Apidya disks as WHDLoad `Disk.1` / `Disk.2` images (decoded tracks back to back).
##
## Layout (reverse engineered from the game's loader, see docs):
##   Disk.1: track 0 = 0x1600 bytes (boot), track 1 = 0x1800 (stage-2 loader), tracks 2.. = 0x1A00 each
##   Disk.2: every track 0x1A00
##   Stage 2 contains a 22-entry file table at Disk.1 + 0x2AB6 (16 bytes each):
##     disk(1 / 0xFF=2) cyl side aux | dest.l | length.l | cache.l       track = cyl*2 + side

const TRACK_BYTES := 0x1A00
const TABLE_OFF := 0x1600 + 0x14B6
const FILE_COUNT := 22

var disk1 := PackedByteArray()
var disk2 := PackedByteArray()
var files: Array[Dictionary] = []
var _unpacked: Dictionary = {}
var source_path := ""


static func _find_ci(dir: String, lower_name: String) -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	for f in da.get_files():
		if f.to_lower() == lower_name:
			return dir.path_join(f)
	return ""


## Looks for Disk.1 / Disk.2 in `path` and a few typical sub folders. Returns "" on success or an error text.
func load_dir(path: String) -> String:
	var candidates: Array[String] = [path, path.path_join("data"), path.path_join("ApidyaKaiko/data"),
			path.path_join("ApidyaKaiko").path_join("data")]
	for c in candidates:
		var p1 := _find_ci(c, "disk.1")
		var p2 := _find_ci(c, "disk.2")
		if p1 != "" and p2 != "":
			disk1 = FileAccess.get_file_as_bytes(p1)
			disk2 = FileAccess.get_file_as_bytes(p2)
			source_path = c
			return _parse()
	return "Disk.1 and Disk.2 not found in '%s'" % path


func load_files(path1: String, path2: String) -> String:
	disk1 = FileAccess.get_file_as_bytes(path1)
	disk2 = FileAccess.get_file_as_bytes(path2)
	source_path = path1.get_base_dir()
	return _parse()


func _parse() -> String:
	if disk1.size() < 1000000 or disk2.size() < 1000000:
		return "Disk images look too small (expected ~1 MB each, WHDLoad Disk.N files)"
	if disk1[0] != 0x44 or disk1[1] != 0x4F or disk1[2] != 0x53:
		return "Disk.1 does not start with a DOS boot block"
	files.clear()
	_unpacked.clear()
	for i in FILE_COUNT:
		var o := TABLE_OFF + i * 16
		var disk := 1 if disk1[o] == 1 else 2
		var cyl: int = disk1[o + 1]
		var side: int = disk1[o + 2]
		files.append({
			"index": i, "disk": disk, "track": cyl * 2 + side, "aux": disk1[o + 3],
			"dest": BE.u32(disk1, o + 4), "length": BE.u32(disk1, o + 8),
		})
	# sanity: file 6 must be a TFMX module
	var f6 := get_raw(6)
	if f6.size() < 10 or f6.slice(0, 9).get_string_from_ascii() != "TFMX-SONG":
		return "Disk contents do not match the original Apidya release (file table check failed)"
	return ""


static func track_offset(disk: int, t: int) -> int:
	if disk == 1:
		if t == 0:
			return 0
		if t == 1:
			return 0x1600
		return 0x2E00 + (t - 2) * TRACK_BYTES
	return t * TRACK_BYTES


func get_raw(i: int) -> PackedByteArray:
	var f: Dictionary = files[i]
	var img := disk1 if f["disk"] == 1 else disk2
	var off := track_offset(f["disk"], f["track"])
	return img.slice(off, off + f["length"])


## File contents with the TPWM packer removed (cached).
func get_data(i: int) -> PackedByteArray:
	if _unpacked.has(i):
		return _unpacked[i]
	var raw := get_raw(i)
	var res := Tpwm.unpack(raw) if Tpwm.is_packed(raw) else raw
	_unpacked[i] = res
	return res
