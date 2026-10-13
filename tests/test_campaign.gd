extends SceneTree
## Plays the last stretch of every level with the autopilot and chains them like the game does: what a level
## hands on (score, ships, power-ups) is the next level's start.
##   redot --headless --path . --script res://tests/test_campaign.gd
const STARTS := {1: 400, 2: 400, 3: 300, 4: 440, 5: 1040}
var _carry := {}
var _done := false


func _on_complete(carry: Dictionary) -> void:
	_carry = carry
	_done = true


func _initialize() -> void:
	var disks: DiskSet = DiskLocator.find()["disks"]
	var carry := {}
	for level in range(1, 6):
		var opts := {"difficulty": 2, "lives": 3}
		if not carry.is_empty():
			opts["carry"] = carry
		var g := Game.new()
		g.setup(disks, level, opts)
		_done = false
		g.level_complete.connect(_on_complete)
		root.add_child(g)
		await process_frame
		await process_frame
		print("level %d starts with score %d lives %d weapon %d speed %d" % [level, g._score, g._lives, g._ps.weapon, g._ps.speed])
		g.jump_to_col(STARTS[level])
		g._ps.weapon = 2
		g._ps.speed = 3
		Input.action_press("fire")
		var t := 0
		while not _done and t < 12000:
			g._invuln = 100
			g.py = 20 + (t / 40) % 180
			for e in g._enemies:
				if e.vm_slot >= 0 and e.x < 330 and e.y < 230:
					g.py = clampi(int(e.y) + e.hit_h / 2 - 12 + (t / 5) % 21, 3, 212)
					break
			g._physics_process(0.02)
			t += 1
		print("  level %d: %s after %d ticks, carry %s" % [level, "complete" if _done else "NOT complete", t, str(_carry)])
		carry = _carry
		root.remove_child(g)
		g.queue_free()
		await process_frame
		if not _done:
			break
	quit(0)
