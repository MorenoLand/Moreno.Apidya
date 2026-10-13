class_name AudioManager
extends Node
## Plays the game's music and sound effects by running the original TFMX replay code (see TfmxPlayer)
## on a worker thread and streaming its output to an AudioStreamGenerator.
##
## Usage: var am := AudioManager.new(); add_child(am); am.start(disks, level); am.song(0); am.sfx(6)

const QUEUE_TICKS := 4          # ~80 ms of audio rendered ahead

var enabled := true             # sound effects
var music_on := true
var _song := 0
var _player: TfmxPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _queue: Array[PackedVector2Array] = []
var _cmds: Array = []
var _running := false
var _asp: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _mix_rate := 44100


func start(disks: DiskSet, level: int, mix_rate: int = 44100) -> bool:
	stop()
	if not LevelDefs.MUSIC.has(level):
		return false
	var m: Dictionary = LevelDefs.MUSIC[level]
	_player = TfmxPlayer.new()
	if not _player.setup(disks, m["file"], m["mdat"], m["smpl"], mix_rate):
		push_warning("Audio disabled: " + _player.error)
		_player = null
		return false
	_mix_rate = mix_rate
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = mix_rate
	gen.buffer_length = 0.25
	_asp = AudioStreamPlayer.new()
	_asp.stream = gen
	add_child(_asp)
	_asp.play()
	_playback = _asp.get_stream_playback() as AudioStreamGeneratorPlayback
	_running = true
	_thread = Thread.new()
	_thread.start(_worker)
	return true


func stop() -> void:
	_running = false
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _asp != null:
		_asp.stop()
		_asp.queue_free()
		_asp = null
	_playback = null
	_player = null
	_queue.clear()
	_cmds.clear()


func _exit_tree() -> void:
	stop()


# ---- commands (applied by the worker between replay ticks) -------------------------------------
func song(n: int) -> void:
	_song = n
	if music_on:
		_post(["song", n])


## The original's M key: the music stops, or the current song starts again.
func set_music(on: bool) -> void:
	if on == music_on:
		return
	music_on = on
	_post(["song", _song if on else -1])


func sfx(n: int) -> void:
	if enabled:
		_post(["sfx", n])


func fade(command: int) -> void:
	_post(["fade", command])


func _post(c: Array) -> void:
	if _player == null:
		return
	_mutex.lock()
	_cmds.append(c)
	_mutex.unlock()


# ---- worker thread -------------------------------------------------------------------------------
func _worker() -> void:
	while _running:
		_mutex.lock()
		var cmds := _cmds
		_cmds = []
		var need := _queue.size() < QUEUE_TICKS
		_mutex.unlock()
		for c in cmds:
			match c[0]:
				"song": _player.start_song(c[1])
				"sfx": _player.play_sfx(c[1])
				"fade": _player.fade(c[1])
		if need:
			var buf := _player.render_tick()
			_mutex.lock()
			_queue.append(buf)
			_mutex.unlock()
		else:
			OS.delay_msec(3)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var spt := _player.samples_per_tick if _player != null else 882
	while _playback.get_frames_available() >= spt:
		_mutex.lock()
		var buf: PackedVector2Array = _queue.pop_front() if not _queue.is_empty() else PackedVector2Array()
		_mutex.unlock()
		if buf.is_empty():
			break
		_playback.push_buffer(buf)
