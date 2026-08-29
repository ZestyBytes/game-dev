extends Control

## Level-select screen: a scrollable list of levels with stars earned and
## best score, tap to play. The new main scene entry point.

const LEVEL_COUNT := 20 # how many level buttons to list; more unlock as you clear the last one

@onready var list: VBoxContainer = %LevelList
@onready var total_stars_label: Label = %TotalStarsLabel
@onready var player_label: Label = %PlayerLabel
@onready var switch_player_button: Button = %SwitchPlayerButton

func _ready() -> void:
	if Save.active_profile().is_empty():
		# Reached directly (e.g. F5 in the editor) with no profile chosen yet.
		get_tree().change_scene_to_file("res://scenes/ProfileSelect.tscn")
		return
	switch_player_button.pressed.connect(_switch_player)
	_rebuild()

func _rebuild() -> void:
	for child in list.get_children():
		child.queue_free()
	player_label.text = Save.active_profile_name()
	total_stars_label.text = "★ %d" % Save.total_stars()

	var unlocked := Save.highest_unlocked()
	for n in range(1, LEVEL_COUNT + 1):
		list.add_child(_make_level_row(n, n <= unlocked))

func _make_level_row(n: int, unlocked: bool) -> Control:
	var cfg: Dictionary = Levels.config(n)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a2140") if unlocked else Color("221c33")
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var label := Label.new()
	var stars: int = Save.level_stars().get(n, 0)
	var best: int = Save.best_scores().get(n, 0)
	if unlocked:
		var star_str := "★".repeat(stars) + "☆".repeat(3 - stars)
		var best_str := (" · best %d" % best) if best > 0 else ""
		label.text = "Level %d  —  target %d, %d moves\n%s%s" % [n, cfg["target"], cfg["moves"], star_str, best_str]
	else:
		label.text = "Level %d — locked (clear level %d first)" % [n, n - 1]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	var button := Button.new()
	button.text = "Play" if unlocked else "🔒"
	button.disabled = not unlocked
	button.pressed.connect(_play_level.bind(n))
	row.add_child(button)

	return panel

func _play_level(n: int) -> void:
	Save.current_level = n
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _switch_player() -> void:
	get_tree().change_scene_to_file("res://scenes/ProfileSelect.tscn")
