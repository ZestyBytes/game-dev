extends Control

## Renders the board, handles input, and drives scoring, the speed bonus
## timer, sound, and the round (moves/target/win-lose) loop. Grid drawing is
## done with plain Panel "gems" built at runtime rather than a
## hand-authored scene, since the layout is fully dynamic (square board,
## screen-size independent).

const CELL_COLORS := [
	Color("ff6f91"), # pink
	Color("ffa552"), # orange
	Color("ffe066"), # yellow
	Color("6bd88f"), # green
	Color("54b6ff"), # blue
	Color("b48cff"), # purple
]

const CELL_GAP := 4.0
const SWAP_TIME := 0.12
const FALL_TIME := 0.18
const CLEAR_TIME := 0.12

const BONUS_TIME_MAX := 6.0 # seconds of "fast" window before bonus decays
const START_MOVES := 20
const TARGET_SCORE := 1500

var board: BoardLogic
var gems := {} # Vector2i -> Panel
var bomb_marks := {} # Vector2i -> Label, only set for bomb cells
var board_rect: Control
var board_panel: Panel
var cell_size := 0.0
var busy := false
var round_over := false
var selected: Variant = null # Vector2i or null

var score := 0
var moves_left := START_MOVES
var combo_depth := 0
var bonus_time := BONUS_TIME_MAX

@onready var score_label: Label = %ScoreLabel
@onready var moves_label: Label = %MovesLabel
@onready var target_label: Label = %TargetLabel
@onready var bonus_bar: ProgressBar = %BonusBar
@onready var board_wrap: Control = %BoardWrap
@onready var overlay: Control = %RoundOverlay
@onready var overlay_label: Label = %RoundOverlayLabel
@onready var restart_button: Button = %RestartButton
@onready var sound: Sound = %Sound

func _ready() -> void:
	target_label.text = "Target: %d" % TARGET_SCORE
	restart_button.pressed.connect(_start_round)
	board_wrap.resized.connect(_layout_board)
	_start_round()

func _start_round() -> void:
	overlay.hide()
	round_over = false
	score = 0
	moves_left = START_MOVES
	combo_depth = 0
	bonus_time = BONUS_TIME_MAX
	score_label.text = "Score: 0"
	moves_label.text = "Moves: %d" % moves_left
	board = BoardLogic.new_random()
	for pos in gems.keys():
		gems[pos].queue_free()
	gems.clear()
	bomb_marks.clear()
	if board_rect == null:
		board_panel = Panel.new()
		board_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color("241d33")
		panel_style.set_corner_radius_all(20)
		panel_style.shadow_color = Color(0, 0, 0, 0.35)
		panel_style.shadow_size = 10
		board_panel.add_theme_stylebox_override("panel", panel_style)
		board_wrap.add_child(board_panel)

		board_rect = Control.new()
		# Top-left preset (all anchors 0) rather than full-rect: we size and
		# position this manually every layout pass to keep it a centered
		# square, so stretch-anchors here would just fight that and log a
		# "non-equal opposite anchors" warning when we set .size directly.
		board_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		board_wrap.add_child(board_rect)
	_build_gems()
	_layout_board()
	set_process(true)

func _process(delta: float) -> void:
	if not busy and not round_over:
		bonus_time = max(0.0, bonus_time - delta)
		bonus_bar.value = bonus_time / BONUS_TIME_MAX * 100.0

func _build_gems() -> void:
	for r in range(BoardLogic.SIZE):
		for c in range(BoardLogic.SIZE):
			_make_gem(Vector2i(r, c), board.grid[r][c])

func _make_gem(pos: Vector2i, value: int) -> Panel:
	var gem := Panel.new()
	gem.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var highlight := Panel.new()
	highlight.name = "Highlight"
	highlight.set_anchors_preset(Control.PRESET_TOP_LEFT)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.add_child(highlight)
	gem.mouse_filter = Control.MOUSE_FILTER_STOP
	gem.gui_input.connect(_on_gem_input.bind(pos))
	board_rect.add_child(gem)
	gems[pos] = gem
	_place_gem(gem, pos) # sizes it (and its highlight) before styling needs cell_size
	_style_gem(gem, value)
	return gem

## A gem is a Panel (rounded rect, real corners) with a small lighter
## "Highlight" panel in its top-left corner for a glossy look - a cheap
## stand-in for the web version's faceted gem SVGs.
func _style_gem(gem: Panel, value: int) -> void:
	var color: int = value
	var is_bomb := BoardLogic.is_bomb(value)
	if is_bomb:
		color = BoardLogic.bomb_color(value)

	var base: Color = CELL_COLORS[color]
	var style := StyleBoxFlat.new()
	style.bg_color = base.lightened(0.4) if is_bomb else base
	style.set_corner_radius_all(int(cell_size * 0.28) if cell_size > 0 else 10)
	style.border_width_bottom = 3
	style.border_width_right = 3
	style.border_color = base.darkened(0.3)
	if is_bomb:
		style.shadow_color = base.lightened(0.7)
		style.shadow_size = 6
	gem.add_theme_stylebox_override("panel", style)

	var highlight: Panel = gem.get_node("Highlight")
	var hi_style := StyleBoxFlat.new()
	hi_style.bg_color = Color(1, 1, 1, 0.35)
	hi_style.set_corner_radius_all(int(cell_size * 0.5) if cell_size > 0 else 10)
	highlight.add_theme_stylebox_override("panel", hi_style)

	for child in gem.get_children():
		if child.name != "Highlight":
			child.queue_free()
	if is_bomb:
		var mark := Label.new()
		mark.text = "✦" # marks it as a row+column bomb
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", max(14, int(cell_size * 0.4)))
		gem.add_child(mark)
		bomb_marks[gem] = mark

func _layout_board() -> void:
	if board_wrap.size.x <= 0 or board_wrap.size.y <= 0:
		return
	var size: float = min(board_wrap.size.x, board_wrap.size.y)
	cell_size = (size - CELL_GAP * (BoardLogic.SIZE + 1)) / float(BoardLogic.SIZE)
	board_rect.size = Vector2(size, size)
	board_rect.position = (board_wrap.size - Vector2(size, size)) / 2.0
	board_panel.size = board_rect.size
	board_panel.position = board_rect.position
	for pos in gems.keys():
		_place_gem(gems[pos], pos)
		_style_gem(gems[pos], board.grid[pos.x][pos.y]) # corner radius scales with cell_size

func _place_gem(gem: Panel, pos: Vector2i) -> void:
	gem.position = _cell_pos(pos)
	gem.size = Vector2(cell_size, cell_size)
	var highlight: Panel = gem.get_node("Highlight")
	highlight.position = Vector2(cell_size * 0.12, cell_size * 0.1)
	highlight.size = Vector2(cell_size * 0.38, cell_size * 0.28)

func _on_gem_input(event: InputEvent, pos: Vector2i) -> void:
	if busy or round_over:
		return
	if event is InputEventScreenTouch and event.pressed or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		_handle_select(pos)

func _handle_select(pos: Vector2i) -> void:
	if selected == null:
		selected = pos
		gems[pos].modulate = Color(1.3, 1.3, 1.3)
		return
	var a: Vector2i = selected
	gems[a].modulate = Color.WHITE
	selected = null
	if a == pos:
		return
	if board.is_adjacent(a, pos):
		_attempt_swap(a, pos)
	else:
		selected = pos
		gems[pos].modulate = Color(1.3, 1.3, 1.3)

func _attempt_swap(a: Vector2i, b: Vector2i) -> void:
	busy = true
	board.swap(a, b)
	await _animate_swap(a, b)
	if board.has_matches():
		moves_left -= 1
		moves_label.text = "Moves: %d" % moves_left
		combo_depth = 0
		await _resolve_matches()
		bonus_time = BONUS_TIME_MAX # a successful move resets the fast window
		_check_round_end()
	else:
		sound.play_bonk()
		board.swap(a, b) # revert
		await _animate_swap(a, b)
	busy = false
	if not round_over:
		_check_stuck_board()

func _animate_swap(a: Vector2i, b: Vector2i) -> void:
	var ga: Panel = gems[a]
	var gb: Panel = gems[b]
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ga, "position", _cell_pos(b), SWAP_TIME)
	tw.tween_property(gb, "position", _cell_pos(a), SWAP_TIME)
	await tw.finished
	gems[a] = gb
	gems[b] = ga

func _cell_pos(pos: Vector2i) -> Vector2:
	return Vector2(CELL_GAP + pos.y * (cell_size + CELL_GAP), CELL_GAP + pos.x * (cell_size + CELL_GAP))

func _resolve_matches() -> void:
	while true:
		var runs := board.find_matches()
		if runs.is_empty():
			break
		combo_depth += 1
		var result := board.clear_matches(runs)
		var cleared: Array = result["cleared"]
		var bombs: Dictionary = result["bombs"]
		var gained := _award_score(cleared.size())
		sound.play_match(combo_depth)
		_spawn_score_popup(cleared, gained)
		await _animate_clear(cleared, bombs)
		var fall := board.collapse_and_refill()
		await _animate_fall(fall["moves"], fall["spawns"])

func _award_score(cleared_count: int) -> int:
	var base := cleared_count * 10
	var combo_mult := 1.0 + (combo_depth - 1) * 0.5
	var speed_mult := 1.0 + (bonus_time / BONUS_TIME_MAX) # up to 2x for a fast move
	var gained := int(round(base * combo_mult * speed_mult))
	score += gained
	score_label.text = "Score: %d" % score
	return gained

## A floating "+N" label at the centroid of the cells that just cleared,
## rising and fading out - stands in for the web version's score popups.
func _spawn_score_popup(cells: Array, gained: int) -> void:
	if cells.is_empty():
		return
	var centroid := Vector2.ZERO
	for pos in cells:
		centroid += _cell_pos(pos)
	centroid /= cells.size()
	centroid += Vector2(cell_size, cell_size) / 2.0

	var label := Label.new()
	label.text = "+%d" % gained
	label.add_theme_font_size_override("font_size", max(16, int(cell_size * 0.45)))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.position = centroid - Vector2(20, 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_rect.add_child(label)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - cell_size * 0.8, 0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.15)
	tw.chain().tween_callback(label.queue_free)

func _animate_clear(cells: Array, bombs: Dictionary) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for pos in cells:
		var gem: Panel = gems[pos]
		tw.tween_property(gem, "scale", Vector2.ZERO, CLEAR_TIME)
	await tw.finished
	for pos in cells:
		var gem: Panel = gems[pos]
		bomb_marks.erase(gem)
		gem.queue_free()
		gems.erase(pos)
	# Cells promoted to bombs stay on the board - just restyle them in place.
	for pos in bombs.keys():
		var gem: Panel = gems[pos]
		for child in gem.get_children():
			child.queue_free()
		_style_gem(gem, board.grid[pos.x][pos.y])

func _animate_fall(moves: Array, spawns: Array) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for move in moves:
		var gem: Panel = gems[move["from"]]
		gems.erase(move["from"])
		gems[move["to"]] = gem
		tw.tween_property(gem, "position", _cell_pos(move["to"]), FALL_TIME)
	for spawn in spawns:
		var pos: Vector2i = spawn["to"]
		var gem := _make_gem(pos, spawn["type"])
		gem.scale = Vector2.ONE
		var start := _cell_pos(pos) - Vector2(0, cell_size * 2)
		gem.position = start
		gem.size = Vector2(cell_size, cell_size)
		tw.tween_property(gem, "position", _cell_pos(pos), FALL_TIME)
	await tw.finished

func _check_round_end() -> void:
	if score >= TARGET_SCORE:
		_end_round(true)
	elif moves_left <= 0:
		_end_round(false)

func _end_round(won: bool) -> void:
	round_over = true
	overlay_label.text = ("You win! Score: %d" % score) if won else ("Out of moves. Score: %d" % score)
	sound.play_round_end(won)
	overlay.show()

func _check_stuck_board() -> void:
	if not board.has_any_move():
		_reshuffle()

func _reshuffle() -> void:
	busy = true
	board = BoardLogic.new_random()
	for pos in gems.keys():
		gems[pos].queue_free()
	gems.clear()
	bomb_marks.clear()
	_build_gems()
	_layout_board()
	busy = false
