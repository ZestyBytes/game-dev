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
	var cleared := b.clear_matches(runs)
	assert(cleared.size() >= 3)
	assert(b.grid[0][0] == -1)

	var result := b.collapse_and_refill()
	assert(not result["moves"].is_empty() or not result["spawns"].is_empty())
	for r in range(BoardLogic.SIZE):
		for c in range(BoardLogic.SIZE):
			assert(b.grid[r][c] != -1, "no empty cells should remain after refill")

	# is_adjacent / swap sanity.
	assert(b.is_adjacent(Vector2i(0, 0), Vector2i(0, 1)))
	assert(not b.is_adjacent(Vector2i(0, 0), Vector2i(1, 1)))
	var before: int = b.grid[0][0]
	b.swap(Vector2i(0, 0), Vector2i(0, 1))
	assert(b.grid[0][1] == before)

	print("OK: all board_logic smoke tests passed")
	quit()
