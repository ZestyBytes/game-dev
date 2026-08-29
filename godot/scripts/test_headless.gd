extends SceneTree

## Headless smoke test for board_logic.gd - run with:
## godot --headless --script res://scripts/test_headless.gd
## Not part of the shipped game; exercises the pure logic without a window.

func _init() -> void:
	var b := BoardLogic.new_random()
	assert(not b.has_matches(), "fresh board should have no instant matches")
	assert(b.grid.size() == BoardLogic.SIZE)
	assert(b.grid[0].size() == BoardLogic.SIZE)

	# Force a guaranteed match: make a horizontal run of 3.
	b.grid[0][0] = 0
	b.grid[0][1] = 0
	b.grid[0][2] = 0
	var runs := b.find_matches()
	assert(runs.size() >= 1, "should detect the forced run")
	var result0 := b.clear_matches(runs)
	var cleared: Array = result0["cleared"]
	assert(cleared.size() >= 3)
	assert(b.grid[0][0] == -1)

	var result := b.collapse_and_refill()
	assert(not result["moves"].is_empty() or not result["spawns"].is_empty())
	for r in range(BoardLogic.SIZE):
		for c in range(BoardLogic.SIZE):
			assert(b.grid[r][c] != -1, "no empty cells should remain after refill")

	# A run of 4 should promote a bomb instead of clearing everything.
	var b2 := BoardLogic.new_random()
	b2.grid[3][0] = 2
	b2.grid[3][1] = 2
	b2.grid[3][2] = 2
	b2.grid[3][3] = 2
	var runs2 := b2.find_matches()
	var result2 := b2.clear_matches(runs2)
	var bombs: Dictionary = result2["bombs"]
	assert(bombs.size() == 1, "a run of 4 should create exactly one bomb")
	var bomb_pos: Vector2i = bombs.keys()[0]
	assert(BoardLogic.is_bomb(b2.grid[bomb_pos.x][bomb_pos.y]), "bomb cell should stay a bomb, not clear")
	assert(BoardLogic.bomb_color(b2.grid[bomb_pos.x][bomb_pos.y]) == 2)

	# Detonating the bomb should clear its whole row and column.
	var b3 := BoardLogic.new_random()
	b3.grid[2][2] = BoardLogic.BOMB_OFFSET + 1
	var fake_runs: Array = [{"cells": [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)], "horizontal": true}]
	var result3 := b3.clear_matches(fake_runs)
	var cleared3: Array = result3["cleared"]
	assert(cleared3.size() >= BoardLogic.SIZE * 2 - 2, "detonating a bomb should sweep its row + column")

	# is_adjacent / swap sanity.
	assert(b.is_adjacent(Vector2i(0, 0), Vector2i(0, 1)))
	assert(not b.is_adjacent(Vector2i(0, 0), Vector2i(1, 1)))
	var before: int = b.grid[0][0]
	b.swap(Vector2i(0, 0), Vector2i(0, 1))
	assert(b.grid[0][1] == before)

	print("OK: all board_logic smoke tests passed")
	quit()
