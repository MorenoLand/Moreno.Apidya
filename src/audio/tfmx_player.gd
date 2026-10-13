class_name TfmxPlayer
extends RefCounted
## Runs the game's own TFMX 7V replay routine (stored on disk 1, file 1, resident at $4DE00) inside
## the 68000 interpreter and renders its output through the Paula model. Music and sound effects
## are therefore exactly what the original produces; nothing is re-implemented or approximated.
##
## Entry points of the replay code (offsets from $4DE00):
##   $24 tick (50 Hz)   $2C start song (D0 = song, -1 = stop)   $34 init (D0 = module, D1 = sample base)
##   $48 fade / volume  $5C play sound effect (D0 = effect)

const CODE_FILE := 1
const TICK := 0x4DE24
const START_SONG := 0x4DE2C
const INIT := 0x4DE34
const FADE := 0x4DE48
const SFX := 0x4DE5C
const RAM_SIZE := 0x80000
const STACK := 0x4C880

var cpu: M68K
var paula: Paula
var rate := 44100
var samples_per_tick := 882
var ok := false
var error := ""


## `module_file` = disk file index of the TFMX module, `mdat` / `smpl` = addresses the game's level
## code passes to the init routine (see LevelDefs.MUSIC).
func setup(disks: DiskSet, module_file: int, mdat: int, smpl: int, mix_rate: int = 44100) -> bool:
	rate = mix_rate
	samples_per_tick = rate / 50
	var mem := PackedByteArray()
	mem.resize(RAM_SIZE)
	_blit(mem, disks.get_raw(CODE_FILE), disks.files[CODE_FILE]["dest"])
	_blit(mem, disks.get_data(module_file), disks.files[module_file]["dest"])
	cpu = M68K.new(mem)
	paula = Paula.new()
	paula.cpu = cpu
	cpu.io = paula
	paula.set_rate(float(rate))
	cpu.a[7] = STACK
	cpu.set_sr(0x2000)
	cpu.d[0] = mdat
	cpu.d[1] = smpl
	cpu.call_sub(INIT)
	ok = not cpu.failed
	error = cpu.last_error
	return ok


static func _blit(mem: PackedByteArray, src: PackedByteArray, dest: int) -> void:
	var n := mini(src.size(), mem.size() - dest)
	for i in n:
		mem[dest + i] = src[i]


func start_song(song: int) -> void:
	if not ok:
		return
	cpu.d[0] = song & 0xFFFFFFFF
	cpu.call_sub(START_SONG)


func play_sfx(effect: int) -> void:
	if not ok:
		return
	cpu.d[0] = effect
	cpu.call_sub(SFX)


## Fade command as used by the game: low byte = target volume (0..64), byte 2 = speed (0 = immediate).
func fade(command: int) -> void:
	if not ok:
		return
	cpu.d[0] = command
	cpu.call_sub(FADE)


## Runs one 50 Hz replay tick and returns that tick's audio (samples_per_tick stereo frames).
func render_tick() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(samples_per_tick)
	if ok:
		cpu.call_sub(TICK)
		ok = not cpu.failed
		paula.render(samples_per_tick, out, 0)
	return out
