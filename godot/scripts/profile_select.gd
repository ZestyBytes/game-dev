extends Control

## "Who's playing?" screen: pick an existing profile or create a new one.
## The real entry point of the game (ported from the web version's
## overlay-profiles flow) - LevelSelect and Main both assume Save has an
## active profile by the time they load.

@onready var list: VBoxContainer = %ProfileList
@onready var name_edit: LineEdit = %NameEdit
@onready var create_button: Button = %CreateButton

func _ready() -> void:
	create_button.pressed.connect(_create_profile)
	name_edit.text_submitted.connect(func(_text): _create_profile())
	_rebuild()

func _rebuild() -> void:
	for child in list.get_children():
		child.queue_free()
	for id in Save.profiles.keys():
		list.add_child(_make_profile_row(id))

func _make_profile_row(id: String) -> Control:
	var profile: Dictionary = Save.profiles[id]
	var total_stars := 0
	for v in profile["level_stars"].values():
		total_stars += v

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a2140")
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
	label.text = "%s   ★ %d" % [profile["name"], total_stars]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.pressed.connect(_select_profile.bind(id))
	row.add_child(play_button)

	var delete_button := Button.new()
	delete_button.text = "✕"
	delete_button.tooltip_text = "Delete profile"
	delete_button.pressed.connect(_delete_profile.bind(id))
	row.add_child(delete_button)

	return panel

func _select_profile(id: String) -> void:
	Save.set_active(id)
	get_tree().change_scene_to_file("res://scenes/LevelSelect.tscn")

func _delete_profile(id: String) -> void:
	Save.delete_profile(id)
	_rebuild()

func _create_profile() -> void:
	var name := name_edit.text.strip_edges()
	if name.is_empty():
		return
	name_edit.text = ""
	var id := Save.create_profile(name)
	_select_profile(id)
