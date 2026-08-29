extends SceneTree

## Real integration test: instances the actual scenes (not just the pure
## logic in test_headless.gd) and drives them through profile creation,
## a forced match, a full won round, and a lost round - asserting on
## observable state at each step, not just "no console errors".
##
## Run with:
## godot --headless --path . --script res://scripts/test_integration.gd
##
## WARNING: this test calls Save.save_data(), which writes to the SAME
## user://save.json a real play session uses (this Godot build has no
## --user-data-dir override). Back up and restore that file around any run:
##   save="$HOME/.local/share/godot/app_userdata/Gumdrop Cascade/save.json"
##   [ -f "$save" ] && cp "$save" "$save.bak"
##   godot --headless --path . --script res://scripts/test_integration.gd
##   [ -f "$save.bak" ] && mv "$save.bak" "$save" || rm -f "$save"

var main_scene: Control
var failures := 0
var Save: Node # the "Save" autoload isn't auto-injected as a global for a
                # SceneTree script (that sugar only applies to Node
                # scripts in the actual scene), so fetch it explicitly.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame # let autoloads' _ready() finish
	Save = root.get_node("Save")

	_test_profiles()
	await _test_forced_match_and_gem_tracking()
	await _test_win_round()
	await _test_lose_round()
	await _test_level_select_locking()

	if failures == 0:
		print("OK: all integration tests passed")
	else:
		print("FAILED: %d integration test(s) failed" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)

# ---------------------------------------------------------------------

func _test_profiles() -> void:
	print("-- profiles --")
	Save.profiles.clear()
	var id_a: String = Save.create_profile("Alice")
	var id_b: String = Save.create_profile("Bob")
	_check(Save.profiles.size() == 2, "two profiles created")
	_check(Save.active_profile_id == id_b, "creating a profile makes it active")
	Save.set_active(id_a)
	_check(Save.active_profile_name() == "Alice", "set_active switches the active profile")
	Save.delete_profile(id_b)
	_check(not Save.profiles.has(id_b), "delete_profile removes the profile")
	_check(Save.active_profile_id == id_a, "deleting a non-active profile leaves the active one alone")

func _make_main() -> Control:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var instance: Control = scene.instantiate()
	root.add_child(instance)
	return instance

func _free_main() -> void:
	main_scene.queue_free()
	await process_frame
	main_scene = null

func _test_forced_match_and_gem_tracking() -> void:
	print("-- forced match + gem position tracking --")
	Save.current_level = 1
	main_scene = _make_main()
	await process_frame
	await process_frame # @onready + first _layout_board

	var start_score: int = main_scene.score
	var start_moves: int = main_scene.moves_left

	# Force a guaranteed match: swapping (0,2)<->(1,2) will complete a
	# horizontal run of 3 at row 0.
	main_scene.board.grid[0][0] = 0
	main_scene.board.grid[0][1] = 0
	main_scene.board.grid[0][2] = 1
	main_scene.board.grid[1][2] = 0

	await main_scene._attempt_swap(Vector2i(0, 2), Vector2i(1, 2))

	_check(main_scene.score > start_score, "score increased after a forced match")
	_check(main_scene.moves_left == start_moves - 1, "moves_left decremented by exactly one move")

	# Regression check for the "clicking one cell highlights another" bug:
	# every gem's tracked grid_pos metadata must match the dict key it's
	# actually stored under, even after swaps/falls have moved it around.
	var mismatches := 0
	for pos in main_scene.gems.keys():
		var gem: Panel = main_scene.gems[pos]
		if gem.get_meta("grid_pos") != pos:
			mismatches += 1
	_check(mismatches == 0, "every gem's grid_pos metadata matches its dict position (click-mapping regression)")
	_check(main_scene.gems.size() == BoardLogic.SIZE * BoardLogic.SIZE, "board still has exactly 64 gems after a cascade")

	# An invalid (non-matching) swap should revert with no score/move cost.
	var pre_invalid_score: int = main_scene.score
	var pre_invalid_moves: int = main_scene.moves_left
	# Two cells almost certainly not equal after a fresh refill in different colors.
	var val_a: int = main_scene.board.grid[7][0]
	var val_b: int = main_scene.board.grid[7][1]
	if val_a == val_b:
		main_scene.board.grid[7][1] = (val_a + 1) % BoardLogic.CANDY_TYPES
	await main_scene._attempt_swap(Vector2i(7, 0), Vector2i(7, 1))
	_check(main_scene.score == pre_invalid_score, "invalid swap doesn't change score")
	_check(main_scene.moves_left == pre_invalid_moves, "invalid swap doesn't cost a move")

	await _free_main()

func _test_win_round() -> void:
	print("-- winning a round --")
	Save.current_level = 1
	main_scene = _make_main()
	await process_frame
	await process_frame

	# Force the round right to the edge of winning on the next match.
	main_scene.score = main_scene.target_score - 5
	main_scene.moves_left = 5
	main_scene.board.grid[0][0] = 2
	main_scene.board.grid[0][1] = 2
	main_scene.board.grid[0][2] = 3
	main_scene.board.grid[1][2] = 2

	await main_scene._attempt_swap(Vector2i(0, 2), Vector2i(1, 2))

	_check(main_scene.score >= main_scene.target_score, "score reached the target")
	_check(main_scene.round_over, "round_over is set once the target is reached")
	_check(main_scene.overlay.visible, "win overlay is shown")
	_check(main_scene.next_level_button.visible, "next-level button is shown on a win")
	_check(Save.level_stars().get(1, 0) > 0, "winning records stars for the level")
	_check(Save.best_scores().get(1, 0) == main_scene.score, "winning records the best score for the level")
	_check(Save.highest_unlocked() == 2, "winning level 1 unlocks level 2")

	await _free_main()

func _test_lose_round() -> void:
	print("-- losing a round --")
	Save.current_level = 3 # an unwon level, so this doesn't disturb level 1/2's saved stars
	main_scene = _make_main()
	await process_frame
	await process_frame

	main_scene.score = 0
	main_scene.moves_left = 1
	# A guaranteed non-matching swap that still counts as a valid move: force
	# a match so the move is "spent", but keep score under target.
	main_scene.board.grid[0][0] = 4
	main_scene.board.grid[0][1] = 4
	main_scene.board.grid[0][2] = 5
	main_scene.board.grid[1][2] = 4

	await main_scene._attempt_swap(Vector2i(0, 2), Vector2i(1, 2))

	_check(main_scene.round_over, "round_over is set once moves run out")
	_check(main_scene.overlay.visible, "lose overlay is shown")
	_check(not main_scene.next_level_button.visible, "next-level button is hidden on a loss")
	_check(Save.level_stars().get(3, 0) == 0, "losing doesn't award stars")
	_check(Save.highest_unlocked() == 2, "losing level 3 doesn't unlock it (level 2 stays the frontier)")

	await _free_main()

func _test_level_select_locking() -> void:
	print("-- level select locking --")
	var scene: PackedScene = load("res://scenes/LevelSelect.tscn")
	var instance: Control = scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	var rows := instance.get_node("%LevelList").get_children()
	_check(rows.size() == instance.LEVEL_COUNT, "level select lists all configured levels")

	# Level 2 was unlocked by the earlier win test; level 3 should still be locked.
	# Each row (PanelContainer) has a single HBoxContainer child, whose
	# second child is the Play button - use structural position, not node
	# names, since dynamically-created nodes get internal generated names.
	var row2_button: Button = rows[1].get_child(0).get_child(1)
	var row3_button: Button = rows[2].get_child(0).get_child(1)
	_check(not row2_button.disabled, "level 2 is playable after winning level 1")
	_check(row3_button.disabled, "level 3 is still locked")

	instance.queue_free()
	await process_frame
