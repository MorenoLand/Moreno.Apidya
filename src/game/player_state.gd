class_name PlayerState
extends RefCounted
## Power-up meter and weapon state of the original (RAM $7C20, $7BBE, $7C28 ...).
##
## Collecting a capsule advances the meter (1..8, then back to 1). Using it (second button, or
## automatically in "auto" mode) spends the highlighted slot:
##   1 speed up   2 bomb type   3 weapon A (spread)   4 weapon B (missiles)   5 weapon C (waves)
##   6 option pods   7 shield   8 speed down

const MAX_SPEED := 4
const MIN_SPEED := 2

enum Result { NONE, USED, DENIED }

var bar := 0         # $7C20 highlighted slot, 0 = nothing collected
var speed := 2       # $7BBE pixels per tick
var weapon := 0      # $7C28 current weapon family (0 = default wave shot, 1..3)
var w1 := 0          # $7C22 spread level 0..2
var w2 := 0          # $7C24 missile level 0..3
var w3 := 0          # $7C26 wave level 0..3
var pods := 0        # $7BCA 0 none, 1 one pod, -1 two pods
var bomb := 0        # $7C2C 0 none, 1 / -1 bomb variants
var shield := false  # bit 3 of $7C2F
var shield_hits := 0 # $7C58


func pickup() -> void:
	bar += 1
	if bar == 9:
		bar = 1


func reset_for_life() -> void:
	# the original keeps the upgrades when a life is lost; only the meter highlight is reset
	bar = 0


## Spends the highlighted slot ($16F8). Returns NONE / USED / DENIED.
func activate() -> int:
	match bar:
		0:
			return Result.NONE
		1:
			if speed >= MAX_SPEED:
				return Result.DENIED
			bar = 0
			speed += 1
			return Result.USED
		2:
			bar = 0
			bomb = -1 if bomb > 0 else 1
			return Result.USED
		3:
			if weapon == 1:
				if w1 == 2:
					return Result.DENIED
				bar = 0
				w1 += 1
			else:
				bar = 0
				weapon = 1
			return Result.USED
		4:
			if weapon == 2:
				if w2 == 3:
					return Result.DENIED
				bar = 0
				w2 += 1
			else:
				bar = 0
				weapon = 2
			return Result.USED
		5:
			if weapon == 3:
				if w3 == 3:
					return Result.DENIED
				bar = 0
				w3 += 1
			else:
				bar = 0
				weapon = 3
			return Result.USED
		6:
			if pods < 0:
				return Result.DENIED
			bar = 0
			pods = 1 if pods == 0 else -1
			return Result.USED
		7:
			bar = 0
			shield = true
			shield_hits += 5
			return Result.USED
		8:
			bar = 0
			if speed <= MIN_SPEED:
				return Result.DENIED
			speed -= 1
			return Result.USED
	return Result.NONE


## "auto" mode ($1BEC): true when the original would spend the slot by itself.
func auto_wants() -> bool:
	match bar:
		1:
			return speed < 3
		2:
			if bomb == 0:
				return true
			return bomb > 0 and pods != 0
		3:
			if weapon != 1:
				return false
			if w1 < 1:
				return true
			return pods != 0 and w1 < 2
		4:
			if weapon != 2 or pods == 0:
				return false
			if w2 < 2:
				return true
			return pods < 0 and w2 < 3
		5:
			if weapon != 3 or pods == 0:
				return false
			if w3 < 2:
				return true
			return pods < 0 and w3 < 3
		6:
			return pods >= 0
		7:
			return not shield or shield_hits <= 2
	return false
