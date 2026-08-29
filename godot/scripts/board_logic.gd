extends RefCounted
class_name BoardLogic

## Pure grid logic for the match-3 board: no nodes, no drawing, so it can be
## unit-tested and reused by the renderer. Mirrors the rules from the
## original web version (web/index.html): 8x8 grid, match-3+, cascades.

const SIZE := 8
const CANDY_TYPES := 6

var grid: Array = [] # grid[row][col] = candy type (int), -1 = empty

static func new_random() -> BoardLogic:
	var b := BoardLogic.new()
	b.grid = []
	for r in range(SIZE):
		var row := []
		for c in range(SIZE):
			row.append(b._non_matching_candy(row, b.grid, r, c))
		b.grid.append(row)
	return b

func _non_matching_candy(row: Array, g: Array, r: int, c: int) -> int:
	# Pick a candy type that doesn't create an instant match-3 at (r, c),
	# so the board starts in a stable, playable state. `row` is the
	# in-progress row being filled (not yet appended to `g`).
	var bad := []
	if c >= 2 and row[c - 1] == row[c - 2]:
		bad.append(row[c - 1])
	if r >= 2 and g[r - 1][c] == g[r - 2][c]:
		bad.append(g[r - 1][c])
	var choices := []
	for t in range(CANDY_TYPES):
		if not bad.has(t):
			choices.append(t)
	return choices[randi() % choices.size()]

func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var dr: int = abs(a.x - b.x)
	var dc: int = abs(a.y - b.y)
	return (dr + dc) == 1

func swap(a: Vector2i, b: Vector2i) -> void:
	var tmp: int = grid[a.x][a.y]
	grid[a.x][a.y] = grid[b.x][b.y]
	grid[b.x][b.y] = tmp

## Returns an array of match "runs", each a Dictionary with keys:
## cells (Array[Vector2i]), horizontal (bool).
func find_matches() -> Array:
	var runs := []
	# Horizontal
	for r in range(SIZE):
		var c := 0
		while c < SIZE:
			var t = grid[r][c]
			var start := c
			while c < SIZE and grid[r][c] == t:
				c += 1
			if c - start >= 3:
				var cells := []
				for cc in range(start, c):
					cells.append(Vector2i(r, cc))
				runs.append({"cells": cells, "horizontal": true})
	# Vertical
	for c in range(SIZE):
		var r := 0
		while r < SIZE:
			var t = grid[r][c]
			var start := r
			while r < SIZE and grid[r][c] == t:
				r += 1
			if r - start >= 3:
				var cells := []
				for rr in range(start, r):
					cells.append(Vector2i(rr, c))
				runs.append({"cells": cells, "horizontal": false})
	return runs

func has_matches() -> bool:
	return find_matches().size() > 0

## Clears matched cells (sets to -1) and returns the flat set of unique
## cleared positions, for scoring.
func clear_matches(runs: Array) -> Array:
	var seen := {}
	for run in runs:
		for cell in run["cells"]:
			seen[cell] = true
	for cell in seen.keys():
		grid[cell.x][cell.y] = -1
	return seen.keys()

## Applies gravity (candies fall into empty cells below them) and refills
## empty cells at the top with new random candies. Returns an array of
## {from: Vector2i, to: Vector2i} moves for animating the fall, plus new
## spawns as {to: Vector2i, type: int}.
func collapse_and_refill() -> Dictionary:
	var moves := []
	var spawns := []
	for c in range(SIZE):
		var write_r := SIZE - 1
		for r in range(SIZE - 1, -1, -1):
			if grid[r][c] != -1:
				if r != write_r:
					moves.append({"from": Vector2i(r, c), "to": Vector2i(write_r, c)})
					grid[write_r][c] = grid[r][c]
					grid[r][c] = -1
				write_r -= 1
		for r in range(write_r, -1, -1):
			var t := randi() % CANDY_TYPES
			grid[r][c] = t
			spawns.append({"to": Vector2i(r, c), "type": t})
	return {"moves": moves, "spawns": spawns}

## True if any adjacent swap on the board would create a match - used to
## detect a stuck board that needs reshuffling.
func has_any_move() -> bool:
	for r in range(SIZE):
		for c in range(SIZE):
			var dirs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0)]
			for d in dirs:
				var a := Vector2i(r, c)
				var b: Vector2i = a + d
				if b.x >= SIZE or b.y >= SIZE:
					continue
				swap(a, b)
				var found := has_matches()
				swap(a, b) # swap back
				if found:
					return true
	return false
