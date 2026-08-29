extends RefCounted
class_name Levels

## Level ladder, ported directly from web/index.html's LEVEL_TABLE /
## levelConfig / starsForResult - same numbers, same formula past level 10,
## so difficulty progression matches the web version exactly.

const LEVEL_TABLE := [
	{"target": 550, "moves": 10},
	{"target": 750, "moves": 12},
	{"target": 950, "moves": 13},
	{"target": 1150, "moves": 14},
	{"target": 1350, "moves": 15},
	{"target": 1550, "moves": 16},
	{"target": 1750, "moves": 17},
	{"target": 1950, "moves": 18},
	{"target": 2150, "moves": 19},
	{"target": 2400, "moves": 20},
]

static func config(n: int) -> Dictionary:
	if n <= LEVEL_TABLE.size():
		return LEVEL_TABLE[n - 1]
	var extra: int = n - LEVEL_TABLE.size()
	return {"target": 2400 + extra * 300, "moves": min(20 + ceili(extra / 2.0), 30)}

## Stars are about how comfortably you won, not just whether you did.
static func stars_for_result(moves_left: int, total_moves: int) -> int:
	var spare: float = float(moves_left) / float(total_moves)
	if spare >= 0.5:
		return 3
	if spare >= 0.25:
		return 2
	return 1
