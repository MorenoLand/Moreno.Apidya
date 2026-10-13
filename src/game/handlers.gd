class_name Handlers
extends RefCounted
## Behaviours of the original's "native handler" enemies (types 4 and 5). Every level file of the game
## carries its own copy of these routines (at different addresses); they are ported per level
## (HandlersL1 ...) and looked up by the routine address found in the wave data.

static func lookup(level_no: int, addr: int) -> Callable:
	match level_no:
		1:
			return HandlersL1.get_handler(addr)
	return Callable()


# ---- shared tails of the original's enemy updater --------------------------------------------------
## `bra $3E30` with D5 / D6: follow the path script, draw (unless `no_draw`), standard fire.
static func tail_path(g: Game, e: Enemy, no_draw: bool = false, phase: int = 0) -> void:
	e.phase = phase
	e.follow_path()
	if no_draw:
		e.no_draw = true
	elif not e.dead:
		e._fire_std(g)


## `bra $3E90 / $3ED8`: draw the current frame without moving.
static func tail_draw(e: Enemy, phase: int = 0) -> void:
	e.phase = phase


static func s8(v: int) -> int:
	return v - 256 if v >= 128 else v


static func bpl(v: int) -> bool:
	return (v & 0xFF) < 128
