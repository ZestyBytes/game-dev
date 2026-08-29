extends Control

## Renders the board, handles input, and drives scoring / the speed bonus
## timer. Grid drawing is done with plain ColorRect "gems" built at runtime
## rather than a hand-authored scene, since the layout is fully dynamic
## (square board, screen-size independent).

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

var board: BoardLogic
var gems := {} # Vector2i -> ColorRect
var board_rect: Control
var cell_size := 0.0
var busy := false
var selected: Variant = null # Vector2i or null

var score := 0
var combo_depth := 0
var bonus_time := BONUS_TIME_MAX

@onready var score_label: Label = %ScoreLabel
@onready var bonus_bar: ProgressBar = %BonusBar
@onready var board_wrap: Control = %BoardWrap

func _ready() -> void:
	board = BoardLogic.new_random()
	board_rect = Control.new()
	board_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_wrap.add_child(board_rect)
	board_wrap.resized.connect(_layout_board)
	_build_gems()
	_layout_board()
	set_process(true)

func _process(delta: float) -> void:
	if not busy:
		bonus_time = max(0.0, bonus_time - delta)
		bonus_bar.value = bonus_time / BONUS_TIME_MAX * 100.0

func _build_gems() -> void:
	for r in range(BoardLogic.SIZE):
		for c in range(BoardLogic.SIZE):
			var gem := ColorRect.new()
			gem.color = CELL_COLORS[board.grid[r][c]]
			gem.mouse_filter = Control.MOUSE_FILTER_STOP
			gem.gui_input.connect(_on_gem_input.bind(Vector2i(r, c)))
			board_rect.add_child(gem)
			gems[Vector2i(r, c)] = gem

func _layout_board() -> void:
	var size: float = min(board_wrap.size.x, board_wrap.size.y)
	cell_size = (size - CELL_GAP * (BoardLogic.SIZE + 1)) / float(BoardLogic.SIZE)
	board_rect.custom_minimum_size = Vector2(size, size)
	board_rect.size = Vector2(size, size)
	for pos in gems.keys():
		_place_gem(gems[pos], pos)

func _place_gem(gem: ColorRect, pos: Vector2i) -> void:
	var x := CELL_GAP + pos.y * (cell_size + CELL_GAP)
	var y := CELL_GAP + pos.x * (cell_size + CELL_GAP)
	gem.position = Vector2(x, y)
	gem.size = Vector2(cell_size, cell_size)

func _on_gem_input(event: InputEvent, pos: Vector2i) -> void:
	if busy:
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
		combo_depth = 0
		await _resolve_matches()
		bonus_time = BONUS_TIME_MAX # a successful move resets the fast window
	else:
		board.swap(a, b) # revert
		await _animate_swap(a, b)
	busy = false
	_check_stuck_board()

func _animate_swap(a: Vector2i, b: Vector2i) -> void:
	var ga: ColorRect = gems[a]
	var gb: ColorRect = gems[b]
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
		var cleared := board.clear_matches(runs)
		_award_score(cleared.size())
		await _animate_clear(cleared)
		var result := board.collapse_and_refill()
		await _animate_fall(result["moves"], result["spawns"])

func _award_score(cleared_count: int) -> void:
	var base := cleared_count * 10
	var combo_mult := 1.0 + (combo_depth - 1) * 0.5
	var speed_mult := 1.0 + (bonus_time / BONUS_TIME_MAX) # up to 2x for a fast move
	var gained := int(round(base * combo_mult * speed_mult))
	score += gained
	score_label.text = "Score: %d" % score

func _animate_clear(cells: Array) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for pos in cells:
		var gem: ColorRect = gems[pos]
		tw.tween_property(gem, "scale", Vector2.ZERO, CLEAR_TIME)
	await tw.finished
	for pos in cells:
		gems[pos].queue_free()
		gems.erase(pos)

func _animate_fall(moves: Array, spawns: Array) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	for move in moves:
		var gem: ColorRect = gems[move["from"]]
		gems.erase(move["from"])
		gems[move["to"]] = gem
		tw.tween_property(gem, "position", _cell_pos(move["to"]), FALL_TIME)
	for spawn in spawns:
		var pos: Vector2i = spawn["to"]
		var gem := ColorRect.new()
		gem.color = CELL_COLORS[spawn["type"]]
		gem.mouse_filter = Control.MOUSE_FILTER_STOP
		gem.gui_input.connect(_on_gem_input.bind(pos))
		gem.scale = Vector2.ONE
		board_rect.add_child(gem)
		var start := _cell_pos(pos) - Vector2(0, cell_size * 2)
		gem.position = start
		gem.size = Vector2(cell_size, cell_size)
		gems[pos] = gem
		tw.tween_property(gem, "position", _cell_pos(pos), FALL_TIME)
	await tw.finished

func _check_stuck_board() -> void:
	if not board.has_any_move():
		_reshuffle()

func _reshuffle() -> void:
	busy = true
	board = BoardLogic.new_random()
	for pos in gems.keys():
		gems[pos].queue_free()
	gems.clear()
	_build_gems()
	_layout_board()
	busy = false
